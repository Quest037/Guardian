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
    @State private var liveSimBatteryDrainEnabled = true
    @State private var liveSimBatteryDrainRate: SimBatteryDrainRate = .normal

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                subBar

                GeometryReader { geo in
                    let spacing: CGFloat = 14
                    let outerPadding: CGFloat = 16
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

            if vehiclePickerVisible {
                theme.overlayScrim
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vehiclePickerVisible = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }

            if vehiclePickerVisible {
                LiveDriveVehiclePickerSidebar(
                    vehicles: pickableVehicles,
                    selectedVehicleID: selectedVehicleID,
                    onSelect: { vehicle in
                        store.selectVehicle(resolvedVehicleID(for: vehicle))
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vehiclePickerVisible = false
                        }
                        mapModel.recenter()
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vehiclePickerVisible = false
                        }
                    }
                )
                .frame(width: 380)
                .frame(maxHeight: .infinity)
                .background(theme.backgroundElevated)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(theme.borderSubtle)
                        .frame(width: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }

            if simControlsSidebarVisible {
                theme.overlayScrim
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            simControlsSidebarVisible = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(3)
            }

            if simControlsSidebarVisible {
                liveSimControlsSidebar
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
                    .background(theme.backgroundElevated)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(theme.borderSubtle)
                            .frame(width: 1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing))
                    .zIndex(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    onPassed: {
                        Task { @MainActor in
                            activateLiveDriveSessionAfterPreflight(kind: purpose.sessionKind)
                        }
                    }
                )
            }
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
        return [
            MapVehicleMarker(
                id: id,
                lat: lat,
                lon: lon,
                label: "",
                colorHex: fleetLink.mapColorHex(forVehicleID: id),
                imageDataURL: imageDataURL,
                showLabel: false,
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

    private var subBar: some View {
        HStack(spacing: 10) {
            
            Picker("", selection: $mediaTab) {
                Text("Map").tag(LiveDriveMediaTab.map)
                Text("Camera").tag(LiveDriveMediaTab.camera)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)

            if selectedVehicleID != nil {
                inputSourcePill
                Spacer(minLength: 2)

                if let sessionStatusText {
                    Text(sessionStatusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(sessionStatusIsError ? Color.orange.opacity(0.95) : .gray)
                        .lineLimit(1)
                }
                if let lastKeyboardCommandText {
                    Text(lastKeyboardCommandText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(lastKeyboardCommandFailed ? Color.orange.opacity(0.95) : .gray.opacity(0.92))
                        .lineLimit(1)
                }

                Button("Clear Vehicle") {
                    Task { await clearLiveDriveVehicleIfIdle() }
                }
                .buttonStyle(.bordered)
                .disabled(selectedVehicleID == nil || store.hasActiveSession)

                if selectedVehicleID != nil {
                    Menu("Sessions (\(store.completedSessions.count))") {
                        Button("Export completed sessions (JSON)…") {
                            if store.promptExportCompletedSessionsToJSON(activeVehicleIDForMeta: selectedVehicleID) {
                                sessionStatusText = "Exported Live Drive session history."
                                sessionStatusIsError = false
                            }
                        }
                        .disabled(store.completedSessions.isEmpty)
                    }
                    .buttonStyle(.bordered)
                }

                if store.hasActiveSession {
                    Menu("End Session") {
                        ForEach(endSessionActions(for: selectedVehicleClass), id: \.label) { action in
                            Button(action.label) {
                                endLiveDriveSession(with: action.command, label: action.label)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button("Start Session") {
                        if vehicleIsInLiveMission {
                            startMissionSession()
                        } else {
                            startFreestyleSession()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(selectedVehicleID == nil || sessionStartInFlight)
                }

                if let selectedVehicleID, isSimulationVehicle(vehicleID: selectedVehicleID) {
                    Button {
                        liveSimBatteryDrainRate = generalSettings.defaultSimBatteryDrainRate
                        withAnimation(.easeInOut(duration: 0.2)) {
                            simControlsSidebarVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .help("SIM live settings")
                }
            } else {
                Spacer(minLength: 2)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vehiclePickerVisible.toggle()
                    }
                } label: {
                    Label("Vehicle Picker", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
            }
            
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.backgroundRaised)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)
        }
    }

    /// Compact input-source toggle. Disabled mid-session because changing input device
    /// while streaming requires restarting the plugin (Offboard ↔ ManualControl).
    private var inputSourcePill: some View {
        Picker("", selection: $inputSource) {
            ForEach(LiveDriveInputSource.allCases, id: \.self) { source in
                Text(source.displayName).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 165)
        .disabled(store.hasActiveSession)
        .help(store.hasActiveSession ? "End the session to change input device" : "Choose keyboard or controller")
    }

    private var liveSimControlsSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SIM Live Settings")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        simControlsSidebarVisible = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }

            Text("Battery drain")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Toggle("Enable drain", isOn: $liveSimBatteryDrainEnabled)
                .toggleStyle(.switch)

            Picker("Drain rate", selection: $liveSimBatteryDrainRate) {
                ForEach(SimBatteryDrainRate.allCases) { rate in
                    Text(rate.displayName).tag(rate)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button("Apply") {
                applyLiveSimBatteryDrainSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(selectedVehicleID == nil)

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func startFreestyleSession() {
        guard selectedVehicleID != nil else { return }
        sessionStatusText = nil
        sessionStatusIsError = false
        preflightPurpose = .freestyle
    }

    /// Mission roster vehicle: same preflight + control session as freestyle, recorded as `.mission`.
    private func startMissionSession() {
        guard selectedVehicleID != nil else { return }
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
                fleetLink.setSimBatteryDrainEnabled(
                    vehicleID: vehicleID,
                    enabled: true,
                    rate: generalSettings.defaultSimBatteryDrainRate,
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
            } else {
                fleetLink.clearLiveDriveControlSessionVehicleIfMatches(vehicleID: vehicleID)
                store.discardActiveSessionRecording()
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
    private func endLiveDriveSession(with command: FleetVehicleCommand, label: String) {
        guard let vehicleID = selectedVehicleID else { return }
        let usedInLiveMission = missionControlStore.isVehicleStreamUsedInLiveMission(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl
        )

        // Drop held inputs immediately so the next stream tick (if any) sees a zero setpoint.
        heldActions.removeAll()
        streamActive = false
        lastKeyboardCommandText = nil

        Task { @MainActor in
            await fleetLink.stopManualControlStream(vehicleID: vehicleID)
            let isSim = isSimulationVehicle(vehicleID: vehicleID)
            if isSim {
                fleetLink.setSimBatteryDrainEnabled(
                    vehicleID: vehicleID,
                    enabled: false,
                    rate: generalSettings.defaultSimBatteryDrainRate,
                    source: "liveDrive.sessionEnd",
                    onResult: nil
                )
                // Intentionally NO snapshot restore on session end — that would throw away the work the
                // operator just did. Clearing the vehicle row also leaves the SIM where it is.
            }

            store.appendActiveSessionEvent(
                LiveDriveSessionEvent(title: "Session end", detail: label)
            )

            // Surface / ground classes get class-aware end-session sequences instead of the bare
            // command. Park (`.holdPosition`) becomes hold + disarm; RTL becomes RTL + wait-for-arrival
            // + HOLD + disarm so the vehicle ends "parked at home" rather than "still in RTL mode at
            // home with autopilot waiting for the next leg." UAVs keep the bare command path because
            // their RTL ends in LAND (autopilot-managed touchdown + auto-disarm) and Loiter must stay
            // armed mid-air.
            let isSurfaceClass = [.ugv, .usv, .uuv].contains(selectedVehicleClass)
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
            fleetLink.setCommandAuthorityGate(vehicleID: vehicleID, minimumCategory: .paladin)

            let logLinesNow = fleetLink.storedLogLines(forVehicleID: vehicleID)
            store.finalizeActiveSession(vehicleLogLinesSnapshot: logLinesNow)

            fleetLink.clearLiveDriveControlSessionVehicleIfMatches(vehicleID: vehicleID)

            if usedInLiveMission {
                sessionStatusText = "Session ended (\(label)); returned to mission authority."
            } else {
                sessionStatusText = "Session ended (\(label)); manual control released."
            }
            sessionStatusIsError = false
        }
    }

    @MainActor
    private func clearLiveDriveVehicleIfIdle() async {
        guard !store.hasActiveSession else { return }
        store.clearActiveVehicleIfIdle()
    }

    private func isSimulationVehicle(vehicleID: String) -> Bool {
        sitl.instances.contains { inst in
            let sid = inst.stackInstanceIndex + 1
            let resolved = fleetLink.vehicleID(forSystemID: sid) ?? "sysid:\(sid)"
            return resolved == vehicleID
        }
    }

    private func applyLiveSimBatteryDrainSettings() {
        guard let vehicleID = selectedVehicleID, isSimulationVehicle(vehicleID: vehicleID) else { return }
        fleetLink.setSimBatteryDrainEnabled(
            vehicleID: vehicleID,
            enabled: liveSimBatteryDrainEnabled,
            rate: liveSimBatteryDrainRate,
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
        sessionStatusText = liveSimBatteryDrainEnabled
            ? "SIM battery drain enabled (\(liveSimBatteryDrainRate.displayName))."
            : "SIM battery drain disabled."
        sessionStatusIsError = false
        store.appendActiveSessionEvent(
            LiveDriveSessionEvent(
                title: "Battery drain",
                detail: liveSimBatteryDrainEnabled
                    ? "On (\(liveSimBatteryDrainRate.displayName))"
                    : "Off"
            )
        )
    }

    private var mediaCard: some View {
        Group {
            switch mediaTab {
            case .map:
                GuardianMapView(
                    model: mapModel,
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
                            break
                        case .deleteWaypoint:
                            break
                        }
                    }
                )
                    .task(id: liveDriveMarkerSignature) {
                        mapModel.vehicleMarkers = selectedVehicleMarker
                        if let followID = mapModel.followedVehicleMarkerID,
                           !selectedVehicleMarker.contains(where: { $0.id == followID }) {
                            mapModel.followedVehicleMarkerID = nil
                        }
                    }
            case .camera:
                ZStack {
                    Color.black.opacity(0.35)
                    VStack(spacing: 8) {
                        Image(systemName: "video")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                        Text("Camera view placeholder")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let label = lastKeyboardCommandText, store.hasActiveSession {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lastKeyboardCommandFailed ? Color.orange.opacity(0.95) : Color.white.opacity(0.92))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var telemetryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if let vehicle = selectedPickableVehicle {
                    HStack(spacing: 10) {
                        telemetryVehicleBadge(for: vehicle)
                            .frame(width: 34, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(telemetryHeaderName(for: vehicle))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text(telemetryHeaderSubtitle(for: vehicle))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                } else {
                    Text("Vehicle health / telemetry")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                }
                Spacer(minLength: 8)
                if let hub = selectedHub {
                    HStack(spacing: 8) {
                        telemetryPill("Mode", hub.flightMode.isEmpty ? "—" : hub.flightMode)
                        telemetryPill(
                            "Armed",
                            hub.isArmed ? "Yes" : "No",
                            accent: hub.isArmed ? Color.green : Color.gray.opacity(0.7)
                        )
                        telemetryPill("Battery", hub.batteryRemainingPercent.map { "\(Int(round($0)))%" } ?? "—")
                        telemetryPill("GPS", hub.gpsFixType ?? "—")
                    }
                }
            }
            if let hub = selectedHub {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            telemetryPrimaryBox(
                                "Altitude",
                                displayAltitudeText(for: hub)
                            )
                            telemetryPrimaryBox(
                                "Heading",
                                hub.headingDeg.map { String(format: "%.0f°", $0) } ?? "—"
                            )
                        }

                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.borderSubtle.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                                )
                        }
                        .frame(height: 42)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Messages")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                        Text("No active messages.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(3)
                    }
                    .padding(8)
                    .frame(width: 220, alignment: .topLeading)
                    .background(theme.borderSubtle.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Text("Select a vehicle to view telemetry.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(telemetryCardBorderColor, lineWidth: 1.5)
        )
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
                .pathDisplayName
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

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(logHeaderTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                if selectedVehicleID != nil {
                    Button {
                        copyLiveDriveLogToPasteboard()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy log text to the clipboard")
                }
            }

            ScrollView {
                Text(logText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var logHeaderTitle: String {
        if selectedVehicleID == nil { return "Log" }
        return vehicleIsInLiveMission ? "Paladin Log" : "Vehicle Log"
    }

    private func copyLiveDriveLogToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
    }

    private var vehicleIsInLiveMission: Bool {
        guard let id = selectedVehicleID else { return false }
        return missionControlStore.isVehicleStreamUsedInLiveMission(vehicleID: id, fleetLink: fleetLink, sitl: sitl)
    }

    private var logText: String {
        guard let vehicleID = selectedVehicleID else { return "No vehicle selected." }
        if vehicleIsInLiveMission {
            let runs = missionControlStore.runs
                .filter { $0.status == .running || $0.status == .paused }
            let lines = runs.flatMap { run in
                run.events.map { $0.plainTextLine() }
            }
            return lines.isEmpty ? "No Paladin lines yet." : lines.joined(separator: "\n")
        }
        let lines = fleetLink.combinedLogs(filteredVehicleIDs: [vehicleID])
        return lines.isEmpty ? "No vehicle log lines yet." : lines.joined(separator: "\n")
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.45))
            }
        }
    }

    private func telemetryPill(_ label: String, _ value: String, accent: Color = Color.white.opacity(0.04)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(accent.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func telemetryPrimaryBox(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
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
            onPaladinCommandOutcome: { outcome in
                switch outcome {
                case .succeeded:
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

    /// Build the End-Session menu items for the given vehicle class.
    ///
    /// Class-aware because the safe / sensible "set the vehicle down" actions diverge:
    ///
    /// - **UAV** (copters / planes / VTOLs): Loiter (hold position in air), RTL (fly home),
    ///   Land (descend and disarm). `.land` is the canonical safe-end for an aerial vehicle.
    ///
    /// - **UGV / USV / UUV** (rovers / boats / subs): Park (`.holdPosition` — same autopilot
    ///   action-hold as UAV "Loiter", relabelled because "loiter" reads as "circle in the
    ///   air" and a stationary rover isn't loitering), RTL (drive / sail home), Idle
    ///   (`.idle` — switch to MANUAL stick-passthrough so the operator or Paladin can
    ///   re-take control instantly without re-engaging Offboard / GUIDED). Land is omitted
    ///   because nothing meaningful happens when a rover or boat receives `MAV_CMD_NAV_LAND`.
    ///
    /// - **unknown**: fall back to the UAV menu (it's the strict superset and includes
    ///   the safe Land option in case the vehicle turns out to be airborne).
    private func endSessionActions(for vehicleClass: UniversalVehicleClass) -> [LiveDriveEndAction] {
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
        if let vehicle = selectedPickableVehicle {
            switch vehicle.domain {
            case .aerial:
                return .uav
            case .ground:
                return .ugv
            case .marine:
                return (vehicle.title.lowercased().contains("underwater") || vehicle.title.lowercased().contains("uuv")) ? .uuv : .usv
            }
        }
        if let mode = selectedHub?.flightMode.lowercased() {
            if mode.contains("sub") { return .uuv }
            if mode.contains("boat") || mode.contains("ship") { return .usv }
            if mode.contains("rover") || mode.contains("ground") { return .ugv }
        }
        return .unknown
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

private enum LiveDriveMediaTab {
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
            HStack(alignment: .center, spacing: 12) {
                Text("Select vehicle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.backgroundElevated)

            if vehicles.isEmpty {
                Spacer()
                Text("No vehicles available.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(vehicles) { vehicle in
                            Button {
                                onSelect(vehicle)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    ZStack(alignment: .topTrailing) {
                                        HStack(spacing: 14) {
                                            vehicleThumbnail(vehicle)
                                                .frame(width: 72, height: 56)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(vehicle.title)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(theme.textPrimary)
                                                    .multilineTextAlignment(.leading)
                                                Text(vehicle.lifecycleStatus.mediumLabel)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(vehicle.lifecycleStatus.color.uiColor.opacity(0.95))
                                                    .lineLimit(1)
                                                Text(vehicle.vehicleShortID)
                                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                    .foregroundStyle(theme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }

                                        HStack(spacing: 8) {
                                            FleetAutopilotStackBadge(stack: vehicle.autopilotStack)
                                            FleetLiveSimBadge(isSimulation: vehicle.isSimulation)
                                            if isSelected(vehicle) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(theme.backgroundRaised)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(vehicle.lifecycleStatus.color.uiColor.opacity(0.7), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
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
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.35))
            }
        }
    }

}
