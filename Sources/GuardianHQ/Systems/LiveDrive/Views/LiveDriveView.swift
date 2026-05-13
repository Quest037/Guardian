import AppKit
import SwiftUI

struct LiveDriveView: View {
    @ObservedObject var store: LiveDriveStore
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var missionControlStore: MissionControlStore
    @ObservedObject var manualControlSettings: ManualControlSettingsStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @EnvironmentObject private var appDrawer: AppDrawer
    @EnvironmentObject private var operatorPromptCenter: OperatorPromptCenter
    @EnvironmentObject private var operatorPromptReviewFocus: OperatorPromptReviewFocusController
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var mapModel = GuardianMapModel(preserveView: true)
    @State private var vehiclePickerVisible = false
    @State private var mediaTab: LiveDriveMediaTab = .map
    @State private var sessionStartInFlight = false
    @State private var sessionStatusText: String?
    @State private var sessionStatusIsError = false
    /// Arm/test preflight before starting a freestyle or mission Live Drive session.
    @State private var preflightPurpose: LiveDrivePreflightPurpose?
    @State private var lastKeyboardCommandText: String?
    @State private var lastKeyboardCommandFailed = false
    /// Edge-tracked held axis actions (W/A/S/D/Q/E/K/L). Discrete actions
    /// (toggleArm/engage/terminate) are NOT tracked here — they fire on keyDown only.
    @State private var heldActions: Set<ManualControlAction> = []
    /// Selected input device — drives plugin choice in `ManualControlStream`.
    /// Keyboard → `Offboard.setVelocityBody` (predictable body-frame velocity).
    /// Controller → `ManualControl.setManualControlInput` (raw stick passthrough).
    /// Right now only `.keyboard` is wired; controller integration ships with
    /// the GameController/IOHID work tracked in TODO.md.
    @State private var inputSource: LiveDriveInputSource = .keyboard
    @State private var streamActive = false
    @State private var simControlsSidebarVisible = false
    /// Bottom prompts (same template as Mission Control run) — call ``GuardianBottomPromptCenter/present(_:style:onDismiss:)`` from Live Drive flows.
    @StateObject private var bottomPromptCenter = GuardianBottomPromptCenter()
    /// Prevents overlapping drill-in handlers while an active session is being ended for a vehicle switch.
    @State private var liveDriveDrillInSessionEndInFlight = false
    /// After framing the live-mission map once per bridged vehicle, avoid resetting zoom on every hub tick.
    @State private var liveDriveLiveMissionMapZoomAppliedVehicleKey: String?

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var liveDriveSidebarAnimation: Animation {
        GuardianMotion.drawerSlide
    }

    /// Drives ``OperatorPromptCenter/setLiveDrivePromptPanelHostContext`` when session, vehicle, or MC‑R drill-in run id changes.
    private var liveDriveOperatorPromptHostSignature: String {
        let vid = store.activeSessionRecord?.vehicleID ?? store.activeVehicleID ?? ""
        let activeSession = store.hasActiveSession && !vid.isEmpty
        let pendingRun = operatorPromptReviewFocus.pendingLiveDriveMissionRunID?.uuidString ?? ""
        let engagedRun = (!vid.isEmpty
            ? missionControlStore.activeMissionRunIDEngagingVehicle(vehicleID: vid, fleetLink: fleetLink, sitl: sitl)
            : nil)?.uuidString ?? ""
        return "\(activeSession)|\(vid)|\(pendingRun)|\(engagedRun)"
    }

    /// MC‑R / Decisions drill-in: ``onChange`` does not run when ``pendingLiveDriveVehicleID`` was set before this view mounted (e.g. tab switch from Mission Control).
    private func applyPendingLiveDriveVehicleDrillInFromFocus() {
        guard let pendingVid = operatorPromptReviewFocus.pendingLiveDriveVehicleID, !pendingVid.isEmpty else { return }
        guard !liveDriveDrillInSessionEndInFlight else { return }

        if store.hasActiveSession {
            let sessionVid = store.activeSessionRecord?.vehicleID ?? store.activeControlledVehicleID ?? ""
            guard !sessionVid.isEmpty else { return }
            if sessionVid == pendingVid {
                store.selectVehicle(pendingVid)
                operatorPromptReviewFocus.consumeLiveDriveFocus()
                return
            }
            liveDriveDrillInSessionEndInFlight = true
            Task { @MainActor in
                defer { liveDriveDrillInSessionEndInFlight = false }
                await endActiveLiveDriveSessionForDrillInVehicleSwitch(
                    sessionVehicleID: sessionVid,
                    pendingVehicleID: pendingVid
                )
            }
            return
        }

        store.selectVehicle(pendingVid)
        operatorPromptReviewFocus.consumeLiveDriveFocus()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                subBar

                GeometryReader { geo in
                    let spacing: CGFloat = GuardianSpacing.cardBodyInset
                    let outerPadding: CGFloat = GuardianSpacing.lg
                    let totalW = geo.size.width
                    let totalH = geo.size.height
                    let contentW = max(0, totalW - (outerPadding * 2))
                    let contentH = max(0, totalH - (outerPadding * 2))
                    // Left column is 70% of content area width (explicit requirement).
                    let leftW = contentW * 0.7
                    // Right column consumes remaining width after gutter.
                    let rightW = max(0, contentW - leftW - spacing)
                    // Left column vertical split is 70/30 (with gutter accounted for).
                    let mediaH = max(220, (contentH - spacing) * 0.7)
                    let telemetryH = max(120, (contentH - spacing) * 0.3)

                    HStack(alignment: .top, spacing: spacing) {
                        VStack(spacing: spacing) {
                            mediaCard
                                .frame(maxWidth: .infinity)
                                .frame(height: mediaH)
                            telemetryCard
                                .frame(height: telemetryH)
                        }
                        .frame(width: leftW)

                        logCard
                            .frame(width: rightW, height: contentH)
                    }
                    .padding(outerPadding)
                    .frame(width: totalW, height: totalH, alignment: .topLeading)
                }
            }
            .background(
                KeyboardEventMonitor(
                    isEnabled: keyboardControlsEnabled,
                    onKeyDown: { event in handleKeyboardKeyDown(event) },
                    onKeyUp: { event in handleKeyboardKeyUp(event) }
                )
            )
            // Safety net: if the user switches apps / windows while a key is held, the
            // `keyUp` event never reaches us. Without this, the vehicle would keep streaming
            // forward velocity in the background. Resigning key window flushes the held set,
            // and the next stream tick pushes a zero setpoint (vehicle decelerates to hover).
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                handleWindowResignKey()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.backgroundBase)
            .onChange(of: appDrawer.presentationRevision) { _ in
                if appDrawer.presented == nil {
                    vehiclePickerVisible = false
                    simControlsSidebarVisible = false
                }
            }
            .onDisappear {
                appDrawer.dismiss()
                bottomPromptCenter.dismiss()
                operatorPromptCenter.setLiveDrivePromptPanelHostContext(isActive: false, missionRunID: nil, vehicleID: nil)
            }
            .sheet(item: $preflightPurpose) { purpose in
                if let vehicle = selectedPickableVehicle,
                   let vehicleID = selectedVehicleID {
                    VehiclePreflightSheet(
                        vehicleTitle: vehicle.title,
                        vehicleID: vehicleID,
                        fleetLink: fleetLink,
                        sitl: sitl,
                        controlStore: missionControlStore,
                        leaveArmed: true,
                        autoCloseOnPass: true,
                        allowDuringLiveMission: purpose == .mission,
                        onPassed: {
                            Task { @MainActor in
                                activateLiveDriveSessionAfterPreflight(kind: purpose.sessionKind)
                            }
                        }
                    )
                }
            }

            LiveDriveOperatorRecipePromptBanner()
                .zIndex(2.5)

            GuardianBottomPromptBanner(center: bottomPromptCenter)
                // Above any future in-window overlays in this ZStack (content → modal → prompt shell order).
                .zIndex(2)
        }
        .task(id: liveDriveOperatorPromptHostSignature) {
            let vid = store.activeSessionRecord?.vehicleID ?? store.activeVehicleID ?? ""
            guard !vid.isEmpty else {
                operatorPromptCenter.setLiveDrivePromptPanelHostContext(isActive: false, missionRunID: nil, vehicleID: nil)
                return
            }
            let engagedRun = missionControlStore.activeMissionRunIDEngagingVehicle(
                vehicleID: vid,
                fleetLink: fleetLink,
                sitl: sitl
            )
            let pendingRun = operatorPromptReviewFocus.pendingLiveDriveMissionRunID
            let missionRunID = pendingRun ?? engagedRun
            let onLiveMissionRoster = missionControlStore.isVehicleStreamUsedInLiveMission(
                vehicleID: vid,
                fleetLink: fleetLink,
                sitl: sitl
            )

            if store.hasActiveSession {
                operatorPromptCenter.setLiveDrivePromptPanelHostContext(
                    isActive: true,
                    missionRunID: missionRunID,
                    vehicleID: vid
                )
                return
            }

            if missionRunID != nil || onLiveMissionRoster {
                operatorPromptCenter.setLiveDrivePromptPanelHostContext(
                    isActive: true,
                    missionRunID: missionRunID,
                    vehicleID: vid
                )
            } else {
                operatorPromptCenter.setLiveDrivePromptPanelHostContext(isActive: false, missionRunID: nil, vehicleID: nil)
            }
        }
        .onAppear {
            applyPendingLiveDriveVehicleDrillInFromFocus()
        }
        .onChange(of: operatorPromptReviewFocus.pendingLiveDriveVehicleID) { _ in
            applyPendingLiveDriveVehicleDrillInFromFocus()
        }
        .onChange(of: store.activeVehicleID) { _ in
            liveDriveLiveMissionMapZoomAppliedVehicleKey = nil
        }
    }

    private var pickableVehicles: [MissionPickableFleetVehicle] {
        buildMissionPickableVehicles(fleetLink: fleetLink, sitl: sitl)
    }

    private var selectedVehicleID: String? {
        store.activeVehicleID
    }

    private var selectedHub: FleetHubVehicleTelemetry? {
        guard let id = selectedVehicleID else { return nil }
        return fleetLink.hubTelemetry(forVehicleID: id)
    }

    private var selectedVehicleMarker: [MapVehicleMarker] {
        guard let id = selectedVehicleID, let hub = selectedHub, let lat = hub.latitudeDeg, let lon = hub.longitudeDeg else { return [] }
        let imageDataURL = markerImageDataURL(forVehicleID: id)
        let slotLabel = liveMissionRosterContext?.slotName ?? ""
        return [
            MapVehicleMarker(
                id: id,
                lat: lat,
                lon: lon,
                label: slotLabel,
                colorHex: fleetLink.mapColorHex(forVehicleID: id),
                imageDataURL: imageDataURL,
                showLabel: !slotLabel.isEmpty,
                selected: true,
                draggable: false,
                headingDeg: hub.headingDeg
            ),
        ]
    }

    /// Equatable signature so `.task(id:)` only re-pushes the marker into the
    /// shared map model when the underlying lat/lon/heading changes.
    private var liveDriveMarkerSignature: LiveDriveMarkerSignature {
        LiveDriveMarkerSignature(
            vehicleID: selectedVehicleID,
            lat: selectedHub?.latitudeDeg,
            lon: selectedHub?.longitudeDeg,
            headingDeg: selectedHub?.headingDeg
        )
    }

    private var liveDriveActiveMissionRun: MissionRunEnvironment? {
        guard let vid = selectedVehicleID,
              let rid = missionControlStore.activeMissionRunIDEngagingVehicle(vehicleID: vid, fleetLink: fleetLink, sitl: sitl)
        else { return nil }
        return missionControlStore.runs.first { $0.id == rid }
    }

    /// Task id for the selected vehicle’s roster row, with single-enabled-task fallback when roster `taskId` is nil.
    private var liveDriveLiveMissionFocusedTaskID: UUID? {
        guard let vid = selectedVehicleID,
              let run = liveDriveActiveMissionRun,
              run.status == .running || run.status == .paused || run.status == .recovery
        else { return nil }
        guard let assignment = run.assignments.first(where: {
            resolvedFleetStreamVehicleID(assignment: $0, fleetLink: fleetLink, sitl: sitl) == vid
        }) else { return nil }
        if let tid = assignment.taskId { return tid }
        if let mission = run.template {
            let enabled = mission.routeMacro.tasks.filter(\.enabled)
            if enabled.count == 1 { return enabled.first?.id }
        }
        return nil
    }

    private var liveDriveLiveMissionMapSyncSignature: String {
        let tab = String(describing: mediaTab)
        guard vehicleIsInLiveMission,
              let run = liveDriveActiveMissionRun,
              let mission = run.template,
              let vid = selectedVehicleID
        else {
            let m = liveDriveMarkerSignature
            return "free|\(tab)|\(m.vehicleID ?? "")|\(String(describing: m.lat))|\(String(describing: m.lon))|\(String(describing: m.headingDeg))"
        }
        let focus = liveDriveLiveMissionFocusedTaskID?.uuidString ?? "none"
        let path = MissionControlLiveDriveMapOverlay.taskPathPayload(mission: mission, focusedTaskID: liveDriveLiveMissionFocusedTaskID)
        let pathKey = path.ids.map(\.uuidString).joined(separator: ",")
        let pts = MissionPoint.filteredForMissionControlLiveMap(run.runtimeMissionPoints, focusedTaskID: liveDriveLiveMissionFocusedTaskID)
            .map { "\($0.id.uuidString)|\(String(format: "%.5f", $0.coordinate.lat))|\(String(format: "%.5f", $0.coordinate.lon))|\($0.isClosed)" }
            .joined(separator: ";")
        let markers = MissionControlLiveDriveMapOverlay.vehicleMarkers(
            run: run,
            mission: mission,
            focusedTaskID: liveDriveLiveMissionFocusedTaskID,
            ldStreamVehicleID: vid,
            fleetLink: fleetLink,
            sitl: sitl
        )
        let veh = markers.map { "\($0.id)|\(String(format: "%.5f", $0.lat))|\(String(format: "%.5f", $0.lon))|\($0.headingDeg ?? 0)" }
            .joined(separator: "|")
        return "m|\(run.id.uuidString)|\(mission.id.uuidString)|\(focus)|\(pathKey)|\(pts)|\(veh)|\(tab)"
    }

    private func syncLiveDriveMapContentFromModel() {
        if vehicleIsInLiveMission,
           let run = liveDriveActiveMissionRun,
           let mission = run.template,
           let vid = selectedVehicleID {
            mapModel.routeGeometry = MissionControlLiveDriveMapOverlay.routeGeometry(
                mission: mission,
                run: run,
                focusedTaskID: liveDriveLiveMissionFocusedTaskID,
                selectedMissionPointID: nil
            )
            mapModel.vehicleMarkers = MissionControlLiveDriveMapOverlay.vehicleMarkers(
                run: run,
                mission: mission,
                focusedTaskID: liveDriveLiveMissionFocusedTaskID,
                ldStreamVehicleID: vid,
                fleetLink: fleetLink,
                sitl: sitl
            )
            if mediaTab == .map, liveDriveLiveMissionMapZoomAppliedVehicleKey != vid {
                fitLiveDriveMapToVisibleContent(mapModel)
                liveDriveLiveMissionMapZoomAppliedVehicleKey = vid
            }
            return
        }
        liveDriveLiveMissionMapZoomAppliedVehicleKey = nil
        mapModel.routeGeometry = .empty
        mapModel.vehicleMarkers = selectedVehicleMarker
    }

    /// Same bbox inputs as MC‑R ``MissionControlSetupView/fitLiveOverviewMapToVisibleMissionContent()`` (home, paths, runtime map points, live markers).
    private func fitLiveDriveMapToVisibleContent(_ model: GuardianMapModel) {
        if vehicleIsInLiveMission,
           let run = liveDriveActiveMissionRun,
           let mission = run.template,
           let vid = selectedVehicleID {
            let focus = liveDriveLiveMissionFocusedTaskID
            let pathPayload = MissionControlLiveDriveMapOverlay.taskPathPayload(mission: mission, focusedTaskID: focus)
            let markers = MissionControlLiveDriveMapOverlay.vehicleMarkers(
                run: run,
                mission: mission,
                focusedTaskID: focus,
                ldStreamVehicleID: vid,
                fleetLink: fleetLink,
                sitl: sitl
            )
            let vehicleLL = markers.map { ($0.lat, $0.lon) }
            let pts = MissionControlLiveMapFitCoordinates.liveOverviewMissionContentPoints(
                homeCoordinate: mission.routeMacro.home?.coord,
                taskPathCoordinates: pathPayload.coords,
                runtimeMissionPoints: run.runtimeMissionPoints,
                focusedTaskID: focus,
                vehicleMarkerLatLon: vehicleLL
            )
            guard !pts.isEmpty else {
                model.recenter()
                return
            }
            model.focusMapFitBounds(points: pts)
            return
        }
        let markerPts: [(Double, Double)] = model.vehicleMarkers.compactMap { m in
            guard MissionControlLiveMapFitCoordinates.isUsableWgs84ForMapFit(lat: m.lat, lon: m.lon) else { return nil }
            return (m.lat, m.lon)
        }
        guard !markerPts.isEmpty else {
            model.recenter()
            return
        }
        model.focusMapFitBounds(points: markerPts)
    }

    private func performReturnToMissionControl() {
        Task { @MainActor in
            guard let vid = selectedVehicleID,
                  let runID = missionControlStore.activeMissionRunIDEngagingVehicle(vehicleID: vid, fleetLink: fleetLink, sitl: sitl),
                  let run = missionControlStore.runs.first(where: { $0.id == runID })
            else {
                toastCenter.show("No live mission run is linked to this vehicle.", style: .warning)
                return
            }
            let assignment = run.assignments.first { resolvedFleetStreamVehicleID(assignment: $0, fleetLink: fleetLink, sitl: sitl) == vid }
            await clearLiveDriveVehicleIfIdle()
            operatorPromptReviewFocus.requestMissionControlReturnDrillIn(
                runID: runID,
                missionTaskID: assignment?.taskId,
                liveAssignmentID: assignment?.id
            )
        }
    }

    private var subBar: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: GuardianSpacing.xxs) {
                GuardianToolbarDualIconModeToggle(
                    selection: $mediaTab,
                    leftMode: .map,
                    leftSystemImage: "map.fill",
                    leftAccessibilityLabel: "Map",
                    rightMode: .camera,
                    rightSystemImage: "video.fill",
                    rightAccessibilityLabel: "Camera"
                )

                if selectedVehicleID != nil {
                    GuardianToolbarDualIconModeToggle(
                        selection: $inputSource,
                        leftMode: .keyboard,
                        leftSystemImage: LiveDriveInputSource.keyboard.pickerSystemImage,
                        leftAccessibilityLabel: "Keyboard",
                        rightMode: .controller,
                        rightSystemImage: LiveDriveInputSource.controller.pickerSystemImage,
                        rightAccessibilityLabel: "Controller",
                        isEnabled: !store.hasActiveSession
                    )
                    .help(store.hasActiveSession ? "End the session to change input device" : "Choose keyboard or controller")
                }
            }

            Spacer(minLength: GuardianSpacing.micro)

            if selectedVehicleID != nil {
                HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                    if let sessionStatusText {
                        Text(sessionStatusText)
                            .font(GuardianTypography.font(.inlineNoticeDetail))
                            .foregroundStyle(
                                sessionStatusIsError ? GuardianSemanticColors.warningStroke : theme.textSecondary
                            )
                            .lineLimit(1)
                    }
                    if let lastKeyboardCommandText {
                        Text(lastKeyboardCommandText)
                            .font(GuardianTypography.font(.inlineNoticeDetail))
                            .foregroundStyle(
                                lastKeyboardCommandFailed ? GuardianSemanticColors.warningStroke : theme.textSecondary
                            )
                            .lineLimit(1)
                    }

                    if !vehicleIsInLiveMission {
                        GuardianThemedButton(
                            title: "Clear Vehicle",
                            accent: .neutral,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            isEnabled: selectedVehicleID != nil && !store.hasActiveSession,
                            action: { Task { await clearLiveDriveVehicleIfIdle() } }
                        )
                        .guardianPointerOnHover()
                    }

                    if selectedVehicleID != nil && !vehicleIsInLiveMission {
                        Menu {
                            Button("Export completed sessions (JSON)…") {
                                if store.promptExportCompletedSessionsToJSON(activeVehicleIDForMeta: selectedVehicleID) {
                                    sessionStatusText = "Exported Live Drive session history."
                                    sessionStatusIsError = false
                                }
                            }
                            .disabled(store.completedSessions.isEmpty)
                        } label: {
                            GuardianNeutralOutlinedMenuTriggerLabel(title: "Sessions (\(store.completedSessions.count))")
                        }
                        .guardianStyledNeutralToolbarMenu()
                        .fixedSize(horizontal: true, vertical: false)
                        .guardianPointerOnHover()
                    }

                    if store.hasActiveSession {
                        let missionSession = store.activeSessionRecord?.kind == .mission
                        Menu {
                            ForEach(
                                endSessionActions(for: selectedVehicleClass, isLiveMissionSession: missionSession),
                                id: \.label
                            ) { action in
                                Button(action.label) {
                                    endLiveDriveSession(with: action.command, label: action.label)
                                }
                            }
                        } label: {
                            GuardianNeutralOutlinedMenuTriggerLabel(title: missionSession ? "End Mission" : "End Session")
                        }
                        .guardianStyledNeutralToolbarMenu()
                        .fixedSize(horizontal: true, vertical: false)
                        .guardianPointerOnHover()
                    } else {
                        HStack(spacing: GuardianSpacing.xs) {
                            GuardianThemedButton(
                                title: "Start Session",
                                accent: .primary,
                                surface: .solid,
                                size: .small,
                                shape: .cornered,
                                isEnabled: selectedVehicleID != nil && !sessionStartInFlight,
                                action: {
                                    if vehicleIsInLiveMission {
                                        startMissionSession()
                                    } else {
                                        startFreestyleSession()
                                    }
                                }
                            )
                            .guardianPointerOnHover()
                            if vehicleIsInLiveMission {
                                GuardianThemedButton(
                                    title: "Return to Mission",
                                    accent: .neutral,
                                    surface: .outline,
                                    size: .small,
                                    shape: .cornered,
                                    action: { performReturnToMissionControl() }
                                )
                                .guardianPointerOnHover()
                                .help("Open Mission Control on this live run.")
                            }
                        }
                    }

                    if let selectedVehicleID, !vehicleIsInLiveMission, isSimulationVehicle(vehicleID: selectedVehicleID) {
                        GuardianNeutralBorderedButton(
                            systemImage: "gearshape",
                            help: "SIM live settings",
                            action: {
                                if simControlsSidebarVisible {
                                    appDrawer.dismiss(animation: liveDriveSidebarAnimation)
                                    simControlsSidebarVisible = false
                                } else {
                                    vehiclePickerVisible = false
                                    simControlsSidebarVisible = true
                                    presentLiveDriveSimControlsSidebar()
                                }
                            }
                        )
                        .guardianPointerOnHover()
                    }
                }
            } else {
                Spacer(minLength: GuardianSpacing.micro)
                GuardianThemedButton(
                    accent: .neutral,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: {
                        if vehiclePickerVisible {
                            appDrawer.dismiss(animation: liveDriveSidebarAnimation)
                            vehiclePickerVisible = false
                        } else {
                            simControlsSidebarVisible = false
                            vehiclePickerVisible = true
                            presentLiveDriveVehiclePickerSidebar()
                        }
                    },
                    label: {
                        Label("Vehicle Picker", systemImage: "line.3.horizontal.decrease.circle")
                            .labelStyle(.titleAndIcon)
                    }
                )
            }
        }
        .padding(.leading, GuardianSpacing.xxs)
        .padding(.trailing, GuardianSpacing.md)
        .padding(.vertical, GuardianSpacing.denseGutter)
        .background(theme.backgroundRaised)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)
        }
    }

    /// Body only; title + close come from ``AppDrawer`` / ``AppDrawerChrome``.
    private var liveSimControlsSidebarBody: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.md) {
            simLiveSettingsLabeledRow(
                title: "SIM battery drain",
                help: "SIM pack depletion on the wire during Live Drive freestyle (PX4 SIM_BAT_DRAIN / ArduPilot SIM_BATT_CAP_AH). None turns drain off."
            ) {
                Picker("", selection: $generalSettings.liveDriveSimBatteryDrainRate) {
                    ForEach(SimBatteryDrainRate.missionRunPickerCases, id: \.self) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 160, alignment: .trailing)
                .accessibilityLabel("SIM battery drain during Live Drive freestyle")
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            applyLiveSimBatteryDrainSettings(recordSessionEvent: false, updateStatusLine: false)
        }
        .onChange(of: generalSettings.liveDriveSimBatteryDrainRate) { _ in
            applyLiveSimBatteryDrainSettings()
        }
    }

    private func simLiveSettingsLabeledRow<Content: View>(
        title: String,
        help: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: GuardianSpacing.md) {
            Text(title)
                .font(GuardianTypography.font(.formFieldLabel))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 118, alignment: .leading)
                .help(help)
            control()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    private func presentLiveDriveVehiclePickerSidebar() {
        appDrawer.present(
            title: nil,
            preferredWidth: 380,
            scrimTapDismisses: true,
            animation: liveDriveSidebarAnimation
        ) {
            LiveDriveVehiclePickerSidebar(
                vehicles: pickableVehicles,
                selectedVehicleID: selectedVehicleID,
                onSelect: { vehicle in
                    store.selectVehicle(resolvedVehicleID(for: vehicle))
                    appDrawer.dismiss(animation: liveDriveSidebarAnimation)
                    mapModel.recenter()
                },
                onClose: {
                    appDrawer.dismiss(animation: liveDriveSidebarAnimation)
                }
            )
        }
    }

    private func presentLiveDriveSimControlsSidebar() {
        appDrawer.present(
            title: "Settings",
            preferredWidth: 340,
            scrimTapDismisses: true,
            animation: liveDriveSidebarAnimation
        ) {
            liveSimControlsSidebarBody
                .padding(GuardianSpacing.cardBodyInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Live Drive **mission** path: narrow hub gate (HandOff §3) before arm preflight — §1 stabilize is still required upstream in MC‑R.
    private func liveDriveMissionTelemetryAllowsPreflightProbe() -> Bool {
        guard let vehicleID = selectedVehicleID else { return false }
        guard vehicleIsInLiveMission else { return true }
        let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
        let lifecycle = fleetLink.vehicleStatus(forVehicleID: vehicleID)
        let now = Date()
        let operational = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: lifecycle, now: now)
        let maxHubAge: TimeInterval = isSimulationVehicle(vehicleID: vehicleID)
            ? MissionControlReserveSwapInPreflightGates.maxHubAgeSecondsSimulation
            : MissionControlReserveSwapInPreflightGates.maxHubAgeSecondsLive
        let verdict = MissionRunEngageStabilizeTelemetryClassifier.evaluateLiveDriveMissionStartStabilizeGate(
            vehicleClass: selectedVehicleClass,
            hub: hub,
            operational: operational,
            now: now,
            maxHubAgeSeconds: maxHubAge
        )
        if case .stable = verdict { return true }
        let detail: String = {
            switch verdict {
            case .stable: return ""
            case .pending(let r), .fault(let r): return r
            }
        }()
        toastCenter.show(
            "Live Drive start blocked — stabilize the vehicle in Mission Control first. \(detail)",
            style: .warning
        )
        return false
    }

    private func startFreestyleSession() {
        guard selectedVehicleID != nil else { return }
        sessionStatusText = nil
        sessionStatusIsError = false
        preflightPurpose = .freestyle
    }

    /// Mission roster vehicle: telemetry gate, then arm preflight (``allowDuringLiveMission``) and the same control session as freestyle, recorded as `.mission`.
    private func startMissionSession() {
        guard selectedVehicleID != nil else { return }
        guard liveDriveMissionTelemetryAllowsPreflightProbe() else { return }
        sessionStatusText = nil
        sessionStatusIsError = false
        preflightPurpose = .mission
    }

    @MainActor
    private func activateLiveDriveSessionAfterPreflight(kind: LiveDriveSessionKind) {
        guard let vehicleID = selectedVehicleID else { return }

        Task { @MainActor in
            let record = buildLiveDriveSessionRecord(vehicleID: vehicleID, kind: kind)
            store.beginTrackedSession(record: record)
            fleetLink.setLiveDriveControlSessionVehicle(vehicleID)

            let isSim = isSimulationVehicle(vehicleID: vehicleID)
            if isSim {
                let drain = generalSettings.liveDriveSimBatteryDrainRate
                let enabled = drain != .none
                fleetLink.setSimBatteryDrainEnabled(
                    vehicleID: vehicleID,
                    enabled: enabled,
                    rate: enabled ? drain : .normal,
                    source: "liveDrive.sessionStart",
                    onResult: { result in
                        Task { @MainActor in
                            if case .failure(let err) = result {
                                sessionStatusText = "SIM battery drain not applied: \(err.message)"
                                sessionStatusIsError = true
                            }
                        }
                    }
                )
            }

            fleetLink.setCommandAuthorityGate(vehicleID: vehicleID, minimumCategory: .manualTakeover)
            heldActions.removeAll()
            let startingPhrase = kind == .mission ? "Mission session starting…" : "Freestyle session starting…"
            sessionStatusText = startingPhrase
            sessionStatusIsError = false

            let vehicleClass = selectedVehicleClass
            let needsTakeoff = (vehicleClass == .uav)
            let stack = selectedHub?.autopilotStack
                ?? selectedPickableVehicle?.autopilotStack
                ?? .unknown

            let mode: ManualControlStream.Mode = {
                if inputSource == .controller { return .manualControl }
                if stack == .px4 && vehicleClass == .ugv { return .px4GroundManual }
                return .bodyVelocity
            }()
            let profile = manualControlSettings.stepProfile(for: vehicleClass)

            let started = await fleetLink.startManualControlStream(
                vehicleID: vehicleID,
                mode: mode,
                autoTakeoff: needsTakeoff,
                profile: profile
            )
            streamActive = started
            if started {
                let prefix = needsTakeoff ? "airborne" : "active"
                let roleLabel = kind == .mission ? "Mission" : "Freestyle"
                sessionStatusText =
                    "Live Drive \(roleLabel) \(prefix) (\(inputSource.displayName) → \(mode.displayName))."
                sessionStatusIsError = false
                lastKeyboardCommandText = "Idle"
                lastKeyboardCommandFailed = false
                operatorPromptReviewFocus.consumePendingLiveDriveMissionRunDrillIn()
            } else {
                fleetLink.clearLiveDriveControlSessionVehicleIfMatches(vehicleID: vehicleID)
                missionControlStore.clearOperatorLiveDriveHandoffForClearedControlSessionVehicle(
                    vehicleID: vehicleID,
                    fleetLink: fleetLink,
                    sitl: sitl
                )
                store.discardActiveSessionRecording()
                operatorPromptReviewFocus.consumePendingLiveDriveMissionRunDrillIn()
                sessionStatusText = "Live Drive: streaming setup failed; vehicle held."
                sessionStatusIsError = true
            }
        }
    }

    private func buildLiveDriveSessionRecord(vehicleID: String, kind: LiveDriveSessionKind) -> LiveDriveSessionRecord {
        let isSim = isSimulationVehicle(vehicleID: vehicleID)
        let logStart = fleetLink.storedLogLines(forVehicleID: vehicleID).count
        let startTitle = kind == .mission ? "Mission session start" : "Freestyle session start"
        return LiveDriveSessionRecord(
            vehicleID: vehicleID,
            kind: kind,
            isSimulationVehicle: isSim,
            startedAt: Date(),
            endedAt: nil,
            events: [LiveDriveSessionEvent(title: startTitle, detail: nil)],
            sessionLogLines: [],
            logBufferStartIndex: logStart
        )
    }

    @MainActor
    private func awaitEndLiveDriveSessionForVehicle(
        vehicleID: String,
        vehicleClass: UniversalVehicleClass,
        command: FleetVehicleCommand,
        label: String,
        consumePendingMissionRunDrillIn: Bool
    ) async {
        let usedInLiveMission = missionControlStore.isVehicleStreamUsedInLiveMission(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl
        )

        heldActions.removeAll()
        streamActive = false
        lastKeyboardCommandText = nil

        await fleetLink.stopManualControlStream(vehicleID: vehicleID)
        let isSim = isSimulationVehicle(vehicleID: vehicleID)
        if isSim {
            fleetLink.setSimBatteryDrainEnabled(
                vehicleID: vehicleID,
                enabled: false,
                rate: .normal,
                source: "liveDrive.sessionEnd",
                onResult: nil
            )
        }

        store.appendActiveSessionEvent(
            LiveDriveSessionEvent(title: "Session end", detail: label)
        )

        let isSurfaceClass = [.ugv, .usv, .uuv].contains(vehicleClass)
        switch (isSurfaceClass, command) {
        case (true, .holdPosition):
            await fleetLink.awaitLiveDriveSurfaceParkHoldAndDisarm(vehicleID: vehicleID)
        case (true, .returnToLaunch):
            await fleetLink.awaitLiveDriveSurfaceRTLHomeAndPark(vehicleID: vehicleID)
        default:
            _ = fleetLink.executeVehicleCommand(
                vehicleID: vehicleID,
                command: command,
                source: "liveDrive.endSession",
                category: .manualTakeover
            )
        }
        fleetLink.setCommandAuthorityGate(vehicleID: vehicleID, minimumCategory: .missionControl)

        let logLinesNow = fleetLink.storedLogLines(forVehicleID: vehicleID)
        store.finalizeActiveSession(vehicleLogLinesSnapshot: logLinesNow)

        fleetLink.clearLiveDriveControlSessionVehicleIfMatches(vehicleID: vehicleID)

        missionControlStore.clearOperatorLiveDriveHandoffForClearedControlSessionVehicle(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl
        )
        if consumePendingMissionRunDrillIn {
            operatorPromptReviewFocus.consumePendingLiveDriveMissionRunDrillIn()
        }

        if usedInLiveMission {
            sessionStatusText = "Session ended (\(label)); Mission Control has authority — use Continue mission there when you want to resume."
        } else {
            sessionStatusText = "Session ended (\(label)); manual control released."
        }
        sessionStatusIsError = false
    }

    /// Ends the current control session using a **safe** class-aware default (Loiter for aerial handoff, Park for surface), then applies MC‑R drill-in selection. Does not clear ``pendingLiveDriveMissionRunID`` so the new handoff context stays intact.
    @MainActor
    private func endActiveLiveDriveSessionForDrillInVehicleSwitch(sessionVehicleID: String, pendingVehicleID: String) async {
        let vehicleClass = universalVehicleClass(forFleetVehicleID: sessionVehicleID)
        let isMissionSession = store.activeSessionRecord?.kind == .mission
        guard let end = liveDriveAutoEndSessionActionForVehicleSwitch(
            vehicleClass: vehicleClass,
            isLiveMissionSession: isMissionSession
        ) else { return }
        await awaitEndLiveDriveSessionForVehicle(
            vehicleID: sessionVehicleID,
            vehicleClass: vehicleClass,
            command: end.command,
            label: "\(end.label) (auto before handoff)",
            consumePendingMissionRunDrillIn: false
        )
        store.selectVehicle(pendingVehicleID)
        operatorPromptReviewFocus.consumeLiveDriveFocus()
    }

    @MainActor
    private func endLiveDriveSession(with command: FleetVehicleCommand, label: String) {
        guard let vehicleID = selectedVehicleID else { return }
        Task { @MainActor in
            await awaitEndLiveDriveSessionForVehicle(
                vehicleID: vehicleID,
                vehicleClass: selectedVehicleClass,
                command: command,
                label: label,
                consumePendingMissionRunDrillIn: true
            )
        }
    }

    @MainActor
    private func clearLiveDriveVehicleIfIdle() async {
        guard !store.hasActiveSession else { return }
        store.clearActiveVehicleIfIdle()
        operatorPromptReviewFocus.consumePendingLiveDriveMissionRunDrillIn()
    }

    private func isSimulationVehicle(vehicleID: String) -> Bool {
        sitl.instances.contains { inst in
            let sid = inst.stackInstanceIndex + 1
            let resolved = fleetLink.vehicleID(forSystemID: sid) ?? "sysid:\(sid)"
            return resolved == vehicleID
        }
    }

    private func applyLiveSimBatteryDrainSettings(
        recordSessionEvent: Bool = true,
        updateStatusLine: Bool = true
    ) {
        guard let vehicleID = selectedVehicleID, isSimulationVehicle(vehicleID: vehicleID) else { return }
        let rate = generalSettings.liveDriveSimBatteryDrainRate
        let enabled = rate != .none
        let wireRate = enabled ? rate : .normal
        fleetLink.setSimBatteryDrainEnabled(
            vehicleID: vehicleID,
            enabled: enabled,
            rate: wireRate,
            source: "liveDrive.simSidebar",
            onResult: { result in
                Task { @MainActor in
                    if case .failure(let err) = result {
                        sessionStatusText = "SIM battery drain: \(err.message)"
                        sessionStatusIsError = true
                    }
                }
            }
        )
        if updateStatusLine {
            sessionStatusText = enabled
                ? "SIM battery drain enabled (\(rate.displayName))."
                : "SIM battery drain disabled."
            sessionStatusIsError = false
        }
        if recordSessionEvent {
            store.appendActiveSessionEvent(
                LiveDriveSessionEvent(
                    title: "Battery drain",
                    detail: enabled ? "On (\(rate.displayName))" : "Off"
                )
            )
        }
    }

    private var mediaCard: some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianCardLayout.defaultBodyPadding
            ),
            media: {
                Group {
                    switch mediaTab {
                    case .map:
                        GuardianMapView(
                            model: mapModel,
                            toolbar: GuardianMapToolbarOptions(
                                mapResetAction: { m in
                                    fitLiveDriveMapToVisibleContent(m)
                                }
                            ),
                            contextMenuPolicy: GuardianMapContextMenuPolicy(
                                vehicleActions: [.followVehicle, .stopFollowingVehicle, .centerMarker],
                                waypointActions: [],
                                homeActions: []
                            ),
                            onContextAction: { event in
                                guard event.markerType == .vehicle else { return }
                                switch event.action {
                                case .followVehicle:
                                    if let markerID = event.markerID, !markerID.isEmpty {
                                        mapModel.followedVehicleMarkerID = markerID
                                        sessionStatusText = "Map follow enabled."
                                        sessionStatusIsError = false
                                    }
                                case .stopFollowingVehicle:
                                    mapModel.followedVehicleMarkerID = nil
                                    sessionStatusText = "Map follow disabled."
                                    sessionStatusIsError = false
                                case .centerMarker:
                                    fitLiveDriveMapToVisibleContent(mapModel)
                                case .deleteWaypoint, .deleteMissionPoint:
                                    break
                                }
                            }
                        )
                        .task(id: liveDriveLiveMissionMapSyncSignature) {
                            syncLiveDriveMapContentFromModel()
                            if let followID = mapModel.followedVehicleMarkerID,
                               !mapModel.vehicleMarkers.contains(where: { $0.id == followID }) {
                                mapModel.followedVehicleMarkerID = nil
                            }
                        }
                    case .camera:
                        ZStack {
                            theme.backgroundElevated
                            VStack(spacing: GuardianSpacing.xs) {
                                Image(systemName: "video")
                                    .font(GuardianTypography.font(.heroGlyph30Medium))
                                    .foregroundStyle(theme.textSecondary)
                                Text("Camera view placeholder")
                                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomLeading) {
                    if let label = lastKeyboardCommandText, store.hasActiveSession {
                        Text(label)
                            .font(GuardianTypography.font(.telemetryMono10Semibold))
                            .foregroundStyle(
                                lastKeyboardCommandFailed
                                    ? GuardianSemanticColors.warningForeground
                                    : theme.textPrimary
                            )
                            .padding(.horizontal, GuardianSpacing.xs)
                            .padding(.vertical, GuardianSpacing.xxs)
                            .background(theme.backgroundRaised.opacity(0.92))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
                            )
                            .padding(GuardianSpacing.xs)
                    }
                }
            }
        )
    }

    private var telemetryCard: some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .none,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianSpacing.sm
            ),
            header: {
                HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                    if let vehicle = selectedPickableVehicle {
                        HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                            telemetryVehicleBadge(for: vehicle)
                                .frame(width: 34, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: GuardianSpacing.hairlineStack) {
                                Text(telemetryHeaderName(for: vehicle))
                                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                                    .foregroundStyle(theme.textPrimary)
                                Text(telemetryHeaderSubtitle(for: vehicle))
                                    .font(GuardianTypography.font(.telemetryMono10Regular))
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    } else {
                        Text("Vehicle Health")
                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                            .foregroundStyle(theme.textPrimary)
                    }
                    Spacer(minLength: GuardianSpacing.xs)
                    if let hub = selectedHub {
                        HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                            telemetryPill("Mode", hub.flightMode.isEmpty ? "—" : hub.flightMode)
                            telemetryPill(
                                "Armed",
                                hub.isArmed ? "Yes" : "No",
                                accent: hub.isArmed
                                    ? GuardianSemanticColors.successBackground
                                    : theme.borderSubtle
                            )
                            telemetryPill("Battery", hub.batteryRemainingPercent.map { "\(Int(round($0)))%" } ?? "—")
                            telemetryPill("GPS", hub.gpsFixType ?? "—")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            body: {
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    if let hub = selectedHub {
                        HStack(alignment: .top, spacing: GuardianSpacing.denseGutter) {
                            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                                HStack(spacing: GuardianSpacing.xs) {
                                    telemetryPrimaryBox(
                                        "Altitude",
                                        displayAltitudeText(for: hub)
                                    )
                                    telemetryPrimaryBox(
                                        "Heading",
                                        hub.headingDeg.map { String(format: "%.0f°", $0) } ?? "—"
                                    )
                                }

                                HStack(spacing: GuardianSpacing.xs) {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(theme.borderSubtle.opacity(0.5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(theme.borderSubtle, lineWidth: 1)
                                        )
                                }
                                .frame(height: 42)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                                Text("Messages")
                                    .font(GuardianTypography.font(.formFieldLabel))
                                    .foregroundStyle(theme.textSecondary)
                                Text("No active messages.")
                                    .font(GuardianTypography.font(.telemetryMono11Regular))
                                    .foregroundStyle(theme.textTertiary)
                                    .lineLimit(3)
                            }
                            .padding(GuardianSpacing.xs)
                            .frame(width: 220, alignment: .topLeading)
                            .background(theme.backgroundElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
                            )
                        }
                    } else {
                        Text("Select a vehicle to view telemetry.")
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                .strokeBorder(telemetryCardBorderColor, lineWidth: 1.5)
        }
    }

    private var telemetryCardBorderColor: Color {
        guard let id = selectedVehicleID, let status = fleetLink.vehicleStatus(forVehicleID: id) else {
            return theme.borderSubtle
        }
        return status.color.uiColor.opacity(0.9)
    }

    private var selectedPickableVehicle: MissionPickableFleetVehicle? {
        guard let selectedVehicleID else { return nil }
        return pickableVehicles.first(where: { resolvedVehicleID(for: $0) == selectedVehicleID })
    }

    /// When selected vehicle is part of a live mission, prefer mission roster slot labeling.
    private var liveMissionRosterContext: (slotName: String, roleName: String?)? {
        guard let selectedVehicleID else { return nil }
        let activeRuns = missionControlStore.runs.filter { $0.status == .running || $0.status == .paused }
        for run in activeRuns {
            guard let assignment = run.assignments.first(where: {
                resolvedFleetStreamVehicleID(assignment: $0, fleetLink: fleetLink, sitl: sitl) == selectedVehicleID
            }) else { continue }
            let roleFromPlan = run.compiledPlan?.roleTracks
                .first(where: { $0.assignmentID == assignment.id })?
                .taskDisplayName
            return (assignment.slotName, roleFromPlan)
        }
        return nil
    }

    private func telemetryHeaderName(for vehicle: MissionPickableFleetVehicle) -> String {
        if let ctx = liveMissionRosterContext {
            return ctx.slotName
        }
        return vehicle.title
    }

    private func telemetryHeaderSubtitle(for vehicle: MissionPickableFleetVehicle) -> String {
        let idText = vehicle.vehicleShortID
        guard let ctx = liveMissionRosterContext else { return idText }
        if let role = ctx.roleName, !role.isEmpty {
            return "\(role) • \(idText)"
        }
        return idText
    }

    private var liveDriveMissionLogEvents: [MissionRunEvent] {
        guard let run = liveDriveActiveMissionRun,
              let mission = run.template,
              selectedVehicleID != nil
        else { return [] }
        let focus = liveDriveLiveMissionFocusedTaskID
        return run.eventsFilteredForLiveTaskLogFocus(focusedTaskID: focus, mission: mission)
    }

    private var liveDriveMissionLogTailAnchorID: UUID? {
        liveDriveMissionLogEvents.suffix(80).last?.id
    }

    /// Matches Mission Control Setup live log header: ``GuardianNeutralBorderedButton`` + `doc.on.doc` + disabled when empty.
    private var isLiveDriveLogCopyDisabled: Bool {
        guard let vehicleID = selectedVehicleID else { return true }
        if vehicleIsInLiveMission {
            return liveDriveMissionLogEvents.isEmpty
        }
        return fleetLink.combinedLogs(filteredVehicleIDs: [vehicleID]).isEmpty
    }

    private var logCard: some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianCardLayout.defaultBodyPadding
            ),
            header: {
                HStack(spacing: GuardianSpacing.denseGutter) {
                    Text(logHeaderTitle)
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if selectedVehicleID != nil {
                        GuardianNeutralBorderedButton(
                            systemImage: "doc.on.doc",
                            help: "Copy log",
                            action: { copyLiveDriveLogToPasteboard() }
                        )
                        .disabled(isLiveDriveLogCopyDisabled)
                        .guardianPointerOnHover()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            body: {
                Group {
                    if vehicleIsInLiveMission,
                       let run = liveDriveActiveMissionRun,
                       let mission = run.template {
                        liveDriveMissionLogsScroll(run: run, mission: mission)
                    } else {
                        ScrollView {
                            Text(liveDriveFleetVehicleLogBodyText)
                                .font(GuardianTypography.font(.telemetryMono11Regular))
                                .foregroundStyle(theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
        )
    }

    private var liveDriveFleetVehicleLogBodyText: String {
        guard let vehicleID = selectedVehicleID else { return "No vehicle selected." }
        let lines = fleetLink.combinedLogs(filteredVehicleIDs: [vehicleID])
        return lines.isEmpty ? "No vehicle log lines yet." : lines.joined(separator: "\n")
    }

    @ViewBuilder
    private func liveDriveMissionLogsScroll(run: MissionRunEnvironment, mission: Mission) -> some View {
        let events = liveDriveMissionLogEvents
        ScrollViewReader { proxy in
            ScrollView {
                if events.isEmpty {
                    Text("No mission log lines yet.")
                        .font(GuardianTypography.font(.telemetryMono11Regular))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                        ForEach(events.suffix(80)) { event in
                            MissionRunLiveLogEventRow(
                                event: event,
                                run: run,
                                mission: mission,
                                fleetLink: fleetLink,
                                sitl: sitl
                            )
                            .id(event.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.openURL, OpenURLAction { url in
                handleLiveDriveMissionLogURL(url, run: run)
            })
            .onAppear {
                if let id = liveDriveMissionLogTailAnchorID {
                    DispatchQueue.main.async {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: liveDriveMissionLogTailAnchorID) { id in
                guard let id else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private func handleLiveDriveMissionLogURL(_ url: URL, run: MissionRunEnvironment) -> OpenURLAction.Result {
        guard url.scheme == "guardian", url.host == "mcr" else { return .discarded }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return .discarded }
        switch parts[0] {
        case "task":
            operatorPromptReviewFocus.requestMissionControlReturnDrillIn(runID: run.id, missionTaskID: id)
            return .handled
        case "slot":
            let taskID = run.assignments.first(where: { $0.id == id })?.taskId
            operatorPromptReviewFocus.requestMissionControlReturnDrillIn(runID: run.id, missionTaskID: taskID)
            return .handled
        default:
            return .discarded
        }
    }

    private var logHeaderTitle: String {
        if selectedVehicleID == nil { return "Log" }
        return vehicleIsInLiveMission ? "Mission Logs" : "Vehicle Log"
    }

    private func copyLiveDriveLogToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(liveDriveLogExportString, forType: .string)
    }

    private var liveDriveLogExportString: String {
        guard let vehicleID = selectedVehicleID else { return "No vehicle selected." }
        if vehicleIsInLiveMission,
           let run = liveDriveActiveMissionRun,
           let mission = run.template {
            let events = liveDriveMissionLogEvents
            let header: String = {
                guard let plan = run.compiledPlan else { return "Mission log" }
                let meta = "\(plan.taskTopology.rawValue) · \(plan.teamTopology.rawValue) · \(plan.roleTracks.count) trk"
                return "Logs - \(run.sessionPhase.rawValue.capitalized) · \(meta)"
            }()
            let body = events.map { $0.plainTextLine(mission: mission, assignments: run.assignments) }
            return ([header] + body).joined(separator: "\n")
        }
        let lines = fleetLink.combinedLogs(filteredVehicleIDs: [vehicleID])
        return lines.isEmpty ? "No vehicle log lines yet." : lines.joined(separator: "\n")
    }

    private var vehicleIsInLiveMission: Bool {
        guard let id = selectedVehicleID else { return false }
        return missionControlStore.isVehicleStreamUsedInLiveMission(vehicleID: id, fleetLink: fleetLink, sitl: sitl)
    }

    private func resolvedVehicleID(for vehicle: MissionPickableFleetVehicle) -> String? {
        resolvedFleetStreamVehicleID(token: vehicle.token, fleetLink: fleetLink, sitl: sitl)
    }

    private func markerImageDataURL(forVehicleID vehicleID: String) -> String? {
        guard let vehicle = pickableVehicles.first(where: { resolvedVehicleID(for: $0) == vehicleID }),
              let names = vehicle.simulationImageBasenames,
              let image = SimulationDeviceBundleImage.nsImage(firstMatching: names),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }

    @ViewBuilder
    private func telemetryVehicleBadge(for vehicle: MissionPickableFleetVehicle) -> some View {
        if let names = vehicle.simulationImageBasenames, !names.isEmpty {
            SimulationDeviceThumbnail(imageBasenames: names)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.14, green: 0.18, blue: 0.22), Color(red: 0.08, green: 0.10, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary.opacity(0.45))
            }
        }
    }

    private func telemetryPill(_ label: String, _ value: String, accent: Color = Color.white.opacity(0.04)) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
            Text(label)
                .font(GuardianTypography.font(.denseCaption10Regular))
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(GuardianTypography.font(.telemetryMono12Semibold))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.vertical, GuardianSpacing.xsTight)
        .padding(.horizontal, GuardianSpacing.xs)
        .background(accent.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func telemetryPrimaryBox(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.titleStackTight) {
            Text(label)
                .font(GuardianTypography.font(.denseCaption10Semibold))
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(GuardianTypography.font(.hudCountdownRounded22Bold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, GuardianSpacing.xs)
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.borderSubtle.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        )
    }

    private var keyboardControlsEnabled: Bool {
        store.hasActiveSession && selectedVehicleID != nil
    }

    /// Edge-triggered key-down. Axis actions update the held set and push a fresh intent
    /// to the running `ManualControlStream`; discrete actions (toggleArm/engage/terminate)
    /// continue to fire as one-shot `executeVehicleCommand` requests.
    private func handleKeyboardKeyDown(_ event: NSEvent) -> Bool {
        guard keyboardControlsEnabled,
              let action = mappedAction(for: event),
              let vehicleID = selectedVehicleID
        else { return false }

        if action.isAxisInput {
            // macOS auto-repeats `keyDown` after the system repeat delay. We only care about
            // the leading edge — the held-key state stays sticky until `.keyUp` fires.
            if event.isARepeat || heldActions.contains(action) { return true }
            heldActions.insert(action)
            pushHeldIntentToStream(vehicleID: vehicleID)
            updateHeldKeyLabel()
            return true
        }

        let manual = ManualControlIntentCommand(
            intent: manualIntent(for: action),
            vehicleClass: selectedVehicleClass,
            stepProfile: manualControlSettings.stepProfile(for: selectedVehicleClass)
        )
        let source = "liveDrive.keyboard.\(action.rawValue)"
        _ = fleetLink.executeVehicleCommand(
            vehicleID: vehicleID,
            command: .manualControl(manual),
            source: source,
            category: .manualTakeover,
            onCommandOutcome: { outcome in
                switch outcome {
                case .succeeded, .succeededWithPayload:
                    lastKeyboardCommandText = "Keyboard: \(action.title)"
                    lastKeyboardCommandFailed = false
                case .failed(let detail):
                    lastKeyboardCommandText = "Keyboard \(action.title): \(detail)"
                    lastKeyboardCommandFailed = true
                }
            }
        )
        return true
    }

    /// Key-up edge for axis actions. Removes the action from the held set and pushes the
    /// recomputed intent. Discrete actions (toggleArm/engage/terminate) are key-down-only.
    private func handleKeyboardKeyUp(_ event: NSEvent) -> Bool {
        guard keyboardControlsEnabled,
              let action = mappedAction(for: event),
              action.isAxisInput,
              let vehicleID = selectedVehicleID
        else { return false }

        guard heldActions.remove(action) != nil else { return true }
        pushHeldIntentToStream(vehicleID: vehicleID)
        updateHeldKeyLabel()
        return true
    }

    /// Translate the current held-action set into a normalized `OperatorIntent` and push
    /// it to the running stream. Per-class axis blocking lives here (e.g. wheeled UGVs
    /// have no strafe and no vertical axis).
    private func pushHeldIntentToStream(vehicleID: String) {
        let intent = computeOperatorIntent(from: heldActions, vehicleClass: selectedVehicleClass)
        fleetLink.updateManualControlIntent(
            vehicleID: vehicleID,
            forward: intent.forward,
            right: intent.right,
            up: intent.up,
            yawRate: intent.yawRate
        )
    }

    /// Produce a `-1…1` per-axis intent from the held action set.
    /// Opposite keys cancel (W+S = 0); chord keys combine (W+D = forward-right diagonal).
    private func computeOperatorIntent(
        from actions: Set<ManualControlAction>,
        vehicleClass: UniversalVehicleClass
    ) -> ManualControlStream.OperatorIntent {
        var intent = ManualControlStream.OperatorIntent()
        if actions.contains(.moveForward) { intent.forward += 1 }
        if actions.contains(.moveBackward) { intent.forward -= 1 }
        if actions.contains(.moveRight) { intent.right += 1 }
        if actions.contains(.moveLeft) { intent.right -= 1 }
        if actions.contains(.yawRight) { intent.yawRate += 1 }
        if actions.contains(.yawLeft) { intent.yawRate -= 1 }
        if actions.contains(.ascend) { intent.up += 1 }
        if actions.contains(.descend) { intent.up -= 1 }

        switch vehicleClass {
        case .ugv, .usv:
            // Wheeled / surface vehicles are non-holonomic in the body frame and have no vertical axis.
            intent.right = 0
            intent.up = 0
        case .uav, .uuv, .unknown:
            break
        }
        return intent
    }

    private func handleWindowResignKey() {
        guard !heldActions.isEmpty, let vehicleID = selectedVehicleID else { return }
        heldActions.removeAll()
        pushHeldIntentToStream(vehicleID: vehicleID)
        updateHeldKeyLabel()
    }

    private func updateHeldKeyLabel() {
        if heldActions.isEmpty {
            lastKeyboardCommandText = streamActive ? "Idle" : nil
            lastKeyboardCommandFailed = false
            return
        }
        var parts: [String] = []
        if heldActions.contains(.moveForward) { parts.append("F") }
        if heldActions.contains(.moveBackward) { parts.append("B") }
        if heldActions.contains(.moveLeft) { parts.append("L") }
        if heldActions.contains(.moveRight) { parts.append("R") }
        if heldActions.contains(.yawLeft) { parts.append("Yaw L") }
        if heldActions.contains(.yawRight) { parts.append("Yaw R") }
        if heldActions.contains(.ascend) { parts.append("Up") }
        if heldActions.contains(.descend) { parts.append("Down") }
        lastKeyboardCommandText = "Streaming: " + parts.joined(separator: " + ")
        lastKeyboardCommandFailed = false
    }

    private func mappedAction(for event: NSEvent) -> ManualControlAction? {
        let token = keyToken(for: event)
        return ManualControlAction.allCases.first {
            manualControlSettings.key(for: $0).caseInsensitiveCompare(token) == .orderedSame
        }
    }

    private func keyToken(for event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "Space"
        case 36, 76: return "Return"
        case 51, 117: return "Delete"
        default:
            let s = event.charactersIgnoringModifiers ?? ""
            return String(s.prefix(1)).uppercased()
        }
    }

    private func manualIntent(for action: ManualControlAction) -> ManualControlIntent {
        switch action {
        case .moveForward: return .moveForward
        case .moveLeft: return .moveLeft
        case .moveBackward: return .moveBackward
        case .moveRight: return .moveRight
        case .yawLeft: return .yawLeft
        case .yawRight: return .yawRight
        case .ascend: return .ascend
        case .descend: return .descend
        case .toggleArm: return .toggleArm
        case .engage: return .engage
        case .terminate: return .terminate
        }
    }

    private func universalVehicleClass(forFleetVehicleID vehicleID: String) -> UniversalVehicleClass {
        if let vehicle = pickableVehicles.first(where: { resolvedVehicleID(for: $0) == vehicleID }) {
            switch vehicle.domain {
            case .aerial:
                return .uav
            case .ground:
                return .ugv
            case .marine:
                return (vehicle.title.lowercased().contains("underwater") || vehicle.title.lowercased().contains("uuv")) ? .uuv : .usv
            }
        }
        let mode = fleetLink.hubTelemetry(forVehicleID: vehicleID)?.flightMode.lowercased() ?? ""
        if mode.contains("sub") { return .uuv }
        if mode.contains("boat") || mode.contains("ship") { return .usv }
        if mode.contains("rover") || mode.contains("ground") { return .ugv }
        return .unknown
    }

    /// Safe default when auto-ending a session before a vehicle handoff (not the same as the operator menu order).
    private func liveDriveAutoEndSessionActionForVehicleSwitch(
        vehicleClass: UniversalVehicleClass,
        isLiveMissionSession: Bool
    ) -> LiveDriveEndAction? {
        if isLiveMissionSession {
            switch vehicleClass {
            case .uav:
                return LiveDriveEndAction(label: "Loiter", command: .holdPosition)
            case .ugv, .usv, .uuv:
                return LiveDriveEndAction(label: "Park", command: .holdPosition)
            case .unknown:
                return LiveDriveEndAction(label: "Loiter", command: .holdPosition)
            }
        }
        return endSessionActions(for: vehicleClass, isLiveMissionSession: false).first
    }

    /// Build **End Session** / **End Mission** menu rows. Mission sessions use a shorter surface / aerial list per product spec; freestyle keeps RTL / Idle where useful.
    private func endSessionActions(for vehicleClass: UniversalVehicleClass, isLiveMissionSession: Bool) -> [LiveDriveEndAction] {
        if isLiveMissionSession {
            switch vehicleClass {
            case .uav:
                return [
                    LiveDriveEndAction(label: "Return to Launch", command: .returnToLaunch),
                    LiveDriveEndAction(label: "Park", command: .land),
                    LiveDriveEndAction(label: "Loiter", command: .holdPosition),
                ]
            case .ugv, .usv, .uuv:
                return [LiveDriveEndAction(label: "Park", command: .holdPosition)]
            case .unknown:
                return [
                    LiveDriveEndAction(label: "Return to Launch", command: .returnToLaunch),
                    LiveDriveEndAction(label: "Park", command: .land),
                    LiveDriveEndAction(label: "Loiter", command: .holdPosition),
                ]
            }
        }
        switch vehicleClass {
        case .uav:
            return [
                LiveDriveEndAction(label: "Loiter", command: .holdPosition),
                LiveDriveEndAction(label: "RTL", command: .returnToLaunch),
                LiveDriveEndAction(label: "Land", command: .land),
            ]
        case .ugv, .usv, .uuv:
            return [
                LiveDriveEndAction(label: "Park", command: .holdPosition),
                LiveDriveEndAction(label: "RTL", command: .returnToLaunch),
                LiveDriveEndAction(label: "Idle", command: .idle),
            ]
        case .unknown:
            return [
                LiveDriveEndAction(label: "Loiter", command: .holdPosition),
                LiveDriveEndAction(label: "RTL", command: .returnToLaunch),
                LiveDriveEndAction(label: "Land", command: .land),
            ]
        }
    }

    private var selectedVehicleClass: UniversalVehicleClass {
        guard let id = selectedVehicleID else { return .unknown }
        return universalVehicleClass(forFleetVehicleID: id)
    }

    private func displayAltitudeText(for hub: FleetHubVehicleTelemetry) -> String {
        guard let rel = hub.relativeAltM else { return "—" }
        switch selectedVehicleClass {
        case .ugv, .usv:
            return String(format: "%.1f m", max(0, rel))
        default:
            return String(format: "%.1f m", rel)
        }
    }
}

/// Drives `VehiclePreflightSheet` → `activateLiveDriveSessionAfterPreflight(kind:)`.
private enum LiveDrivePreflightPurpose: String, Identifiable {
    case freestyle
    case mission

    var id: String { rawValue }

    var sessionKind: LiveDriveSessionKind {
        switch self {
        case .freestyle: return .freestyle
        case .mission: return .mission
        }
    }
}

private enum LiveDriveMediaTab: Hashable {
    case map
    case camera
}

/// One row in the LiveDrive End-Session menu. Pairs a UI-facing label (e.g. `"Park"`,
/// `"Idle"`) with the underlying ``FleetVehicleCommand`` to dispatch. Decoupled because
/// the same command (`.holdPosition`) takes a different label per vehicle class
/// ("Loiter" for UAV, "Park" for UGV/USV/UUV) — the autopilot doesn't care, but the UX
/// reads totally differently.
private struct LiveDriveEndAction {
    let label: String
    let command: FleetVehicleCommand
}

/// Currently-selected manual input device. Determines which MAVSDK plugin
/// `ManualControlStream` drives.
enum LiveDriveInputSource: String, Equatable, CaseIterable {
    /// Keyboard W/A/S/D + Q/E + K/L. Discrete keys are quantized into a body-velocity setpoint.
    case keyboard
    /// Wired or wireless gamepad / joystick. Analog stick values pass through unchanged.
    /// (Hardware integration is part of the controller TODO; selecting `.controller`
    /// today still works against a connected `GCExtendedGamepad` if one is bound.)
    case controller

    var displayName: String {
        switch self {
        case .keyboard: return "Keyboard"
        case .controller: return "Controller"
        }
    }

    var pickerSystemImage: String {
        switch self {
        case .keyboard: return "arrow.up.and.down.and.arrow.left.and.right"
        case .controller: return "gamecontroller.fill"
        }
    }
}

extension ManualControlStream.Mode {
    /// Short label for the LiveDrive subbar status pill.
    var displayName: String {
        switch self {
        case .bodyVelocity: return "Offboard/Body"
        case .px4GroundManual: return "PX4 Manual"
        case .manualControl: return "ManualControl"
        }
    }
}

private struct LiveDriveMarkerSignature: Equatable {
    let vehicleID: String?
    let lat: Double?
    let lon: Double?
    let headingDeg: Double?
}

private struct LiveDriveVehiclePickerSidebar: View {
    let vehicles: [MissionPickableFleetVehicle]
    let selectedVehicleID: String?
    let onSelect: (MissionPickableFleetVehicle) -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                Text("Select vehicle")
                    .font(GuardianTypography.font(.hudTitle16Bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: GuardianSpacing.xs)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(GuardianTypography.font(.heroGlyph18Medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .padding(.horizontal, GuardianSpacing.md)
            .padding(.vertical, GuardianSpacing.cardBodyInset)
            .background(theme.backgroundElevated)

            if vehicles.isEmpty {
                Spacer()
                Text("No vehicles available.")
                    .font(GuardianTypography.font(.denseSubsection13Regular))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: GuardianSpacing.denseGutter) {
                        ForEach(vehicles) { vehicle in
                            Button {
                                onSelect(vehicle)
                            } label: {
                                GuardianCard(
                                    configuration: GuardianCardConfiguration(
                                        border: .none,
                                        cornerRadius: GuardianCardLayout.cornerRadius,
                                        bodyPadding: GuardianCardLayout.defaultBodyPadding
                                    ),
                                    body: {
                                        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                                            ZStack(alignment: .topTrailing) {
                                                HStack(spacing: GuardianSpacing.cardBodyInset) {
                                                    vehicleThumbnail(vehicle)
                                                        .frame(width: 72, height: 56)
                                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                                    VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                                                        Text(vehicle.title)
                                                            .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                                                            .foregroundStyle(theme.textPrimary)
                                                            .multilineTextAlignment(.leading)
                                                        Text(vehicle.lifecycleStatus.mediumLabel)
                                                            .font(GuardianTypography.font(.formFieldLabel))
                                                            .foregroundStyle(vehicle.lifecycleStatus.color.uiColor.opacity(0.95))
                                                            .lineLimit(1)
                                                        Text(vehicle.vehicleShortID)
                                                            .font(GuardianTypography.font(.telemetryMono10Medium))
                                                            .foregroundStyle(theme.textSecondary)
                                                            .lineLimit(1)
                                                    }
                                                    Spacer(minLength: 0)
                                                }

                                                HStack(spacing: GuardianSpacing.xs) {
                                                    FleetAutopilotStackBadge(stack: vehicle.autopilotStack)
                                                    FleetLiveSimBadge(isSimulation: vehicle.isSimulation)
                                                    if isSelected(vehicle) {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundStyle(GuardianSemanticColors.infoForeground)
                                                    }
                                                }
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                                        .strokeBorder(vehicle.lifecycleStatus.color.uiColor.opacity(0.7), lineWidth: 1)
                                }
                            }
                            .buttonStyle(GuardianPointerPlainButtonStyle())
                        }
                    }
                    .padding(GuardianSpacing.md)
                }
            }
        }
    }

    private func isSelected(_ vehicle: MissionPickableFleetVehicle) -> Bool {
        guard let selectedVehicleID else { return false }
        let normalizedSelected = selectedVehicleID.replacingOccurrences(of: "sysid:", with: "")
        switch vehicle.token {
        case .live:
            return normalizedSelected == vehicle.vehicleIDText
        case .sitl:
            return normalizedSelected == vehicle.vehicleIDText
        }
    }

    @ViewBuilder
    private func vehicleThumbnail(_ vehicle: MissionPickableFleetVehicle) -> some View {
        if let names = vehicle.simulationImageBasenames, !names.isEmpty {
            SimulationDeviceThumbnail(imageBasenames: names)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.14, green: 0.18, blue: 0.22), Color(red: 0.08, green: 0.10, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(GuardianTypography.font(.heroGlyph28Medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.35))
            }
        }
    }

}
