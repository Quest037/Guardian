import AppKit
import SwiftUI

/// Unified Training lab: idle side rail (shared panel views) · running full-width viewport + drawers.
struct TrainingLabPanelView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var missionControl: MissionControlStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    @ObservedObject var gazebo: GazeboService
    var requiresGazeboRunWorld: Bool = false
    @StateObject private var lab = TrainingLabController()
    @StateObject private var roster = TrainingLabRosterController()
    @StateObject private var viewportCamera = GazeboWebViewportCameraBridge()
    @StateObject private var viewportZones = GazeboWebViewportZoneBridge()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.guardianAppProduct) private var appProduct
    @EnvironmentObject private var toastCenter: ToastCenter
    @EnvironmentObject private var applicationLifecycle: GuardianApplicationLifecycle
    @EnvironmentObject private var appDrawer: AppDrawer

    @State private var idleRailTab: TrainingLabPanelTab = .map
    @State private var calibrationContext: FormationsCalibrationContext?
    @State private var addVehicleSimulationPlatform: SimulationPlatform = .ardupilot

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var usesFormationMapLayout: Bool {
        roster.usesMultiVehicleFormation
    }

    private var isSessionRunning: Bool {
        lab.teaching.phase == .teaching || lab.formation.phase == .following
    }

    private var mapIsSelected: Bool {
        lab.teaching.selectedEnvironment != nil
    }

    /// Vehicles rail may spawn only after the map viewport is ready (Gazebo `.live`, or 2D map when selected).
    private var mapIsReadyForVehicles: Bool {
        guard mapIsSelected else { return false }
        if lab.teaching.usesGazeboTrainingViewport {
            return isTrainingViewportCameraLive
        }
        return true
    }

    private var labControlsLocked: Bool {
        isSessionRunning
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                trainingLabSubBar
                GeometryReader { geo in
                    if isSessionRunning {
                        trainingMainColumn
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    } else {
                        let mapWidth = geo.size.width * TrainingLabLayout.viewportWidthFraction
                        HStack(spacing: 0) {
                            trainingMainColumn
                                .frame(width: mapWidth, height: geo.size.height, alignment: .top)

                            Rectangle()
                                .fill(theme.borderSubtle)
                                .frame(width: 1)
                                .frame(height: geo.size.height)

                            trainingLabSideRail
                                .frame(width: geo.size.width - mapWidth - 1, height: geo.size.height, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.backgroundBase)

            if let ctx = calibrationContext {
                VehicleInspectorHostOverlay(onDismiss: { calibrationContext = nil }) {
                    VehicleCalibrationModal(
                        fleetLink: fleetLink,
                        controlStore: missionControl,
                        sitl: sitl,
                        vehicleID: ctx.vehicleID,
                        fallback: ctx.fallback,
                        onClose: { calibrationContext = nil }
                    )
                    .environmentObject(toastCenter)
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(GuardianMotion.confirmPresent, value: calibrationContext?.id)
        .background { trainingLabKeyboardShortcutButtons }
        .modifier(TrainingLabEscapeStopModifier(
            isEnabled: isSessionRunning,
            drawerPresented: appDrawer.presented != nil,
            onStop: stopSessionAndReset
        ))
        .onAppear {
            lab.teaching.clampVehicleClassToTrainingPanelOptions()
            attachBothControllers()
            refreshActiveMap()
            Task { await ensureTrainingGazeboWorldLoadedIfNeeded() }
        }
        .onDisappear {
            appDrawer.dismiss()
            lab.teaching.leavePanel()
            lab.formation.leavePanel()
        }
        .onChange(of: isSessionRunning) { running in
            if running {
                appDrawer.dismiss()
            }
        }
        .onChange(of: generalSettings.simSpawnDefaults) { defaults in
            lab.attach(
                fleetLink: fleetLink,
                sitl: sitl,
                spawnDefaults: defaults,
                simulationPlatform: generalSettings.defaultSimulationPlatform,
                gazebo: gazebo,
                requiresGazeboRunWorld: requiresGazeboRunWorld,
                toastCenter: toastCenter
            )
            lab.teaching.spawnDefaultsDidChange()
            refreshActiveMap()
        }
        .onChange(of: generalSettings.defaultSimulationPlatform) { platform in
            lab.attach(
                fleetLink: fleetLink,
                sitl: sitl,
                spawnDefaults: generalSettings.simSpawnDefaults,
                simulationPlatform: platform,
                gazebo: gazebo,
                requiresGazeboRunWorld: requiresGazeboRunWorld,
                toastCenter: toastCenter
            )
            roster.attach(
                lab: lab,
                fleetLink: fleetLink,
                missionControl: missionControl,
                simulationPlatform: platform
            )
            lab.bindRoster(roster)
        }
        .onChange(of: lab.formation.formation) { _ in
            guard usesFormationMapLayout else { return }
            lab.formation.formationSettingsDidChange(fleetLink: fleetLink)
            if lab.formation.isSlotGroupMapEditEnabled {
                syncFormationSlotMapEditChrome()
            } else {
                syncMapContent()
            }
        }
        .onChange(of: lab.formation.spacing) { _ in
            guard usesFormationMapLayout else { return }
            lab.formation.formationSettingsDidChange(fleetLink: fleetLink)
            if lab.formation.isSlotGroupMapEditEnabled {
                syncFormationSlotMapEditChrome()
            } else {
                syncMapContent()
            }
        }
        .onChange(of: lab.teaching.taskKind) { _ in
            lab.teaching.taskKindDidChange()
            lab.teaching.trainingTaskOrVehicleDidChange()
            lab.teaching.loadPromotedSkill()
        }
        .onChange(of: lab.teaching.targetSlot) { _ in
            lab.teaching.scheduleNav2PlanPathRefresh()
            refreshTrainingMap()
        }
        .onChange(of: lab.teaching.nav2PlannedPath) { _ in
            refreshTrainingMap()
        }
        .onChange(of: lab.teaching.selectedEnvironmentID) { _ in
            lab.teaching.environmentSelectionDidChange()
            pushTrainingViewportZones()
        }
        .onChange(of: isTrainingViewportCameraLive) { live in
            if live { pushTrainingViewportZones() }
        }
        .onChange(of: lab.teaching.vehicleClass) { _ in
            lab.teaching.trainingTaskOrVehicleDidChange()
            lab.teaching.scheduleNav2PlanPathRefresh()
        }
        .onChange(of: fleetLink.nav2TrainingStackReady) { _ in
            lab.teaching.scheduleNav2PlanPathRefresh()
        }
        .onChange(of: lab.teaching.isTargetSlotMapEditEnabled) { _ in
            refreshTrainingMap()
        }
        .onReceive(fleetLink.$hubFleetTelemetryTick) { _ in
            guard applicationLifecycle.isApplicationActive else { return }
            roster.refreshSlotStatesFromFleet()
            if usesFormationMapLayout {
                lab.formation.refreshConnectedSimCount(fleetLink: fleetLink)
                syncMapMarkers()
            } else {
                lab.teaching.refreshSimulatorSlot(fleetLink: fleetLink)
                syncTrainingMapMarkers()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .guardianApplicationDidBecomeActive)) { _ in
            if usesFormationMapLayout {
                lab.formation.refreshConnectedSimCount(fleetLink: fleetLink)
                refreshActiveMap()
            } else {
                lab.teaching.refreshSimulatorSlot(fleetLink: fleetLink)
                refreshTrainingMap()
            }
        }
    }

    /// Restores the embedded `.run` world when a map is already selected (e.g. returning to the tab).
    private func ensureTrainingGazeboWorldLoadedIfNeeded() async {
        guard let envID = lab.teaching.selectedEnvironmentID, mapIsSelected, lab.teaching.usesGazeboTrainingViewport else { return }
        lab.teaching.reconcileActiveGazeboRunWorldIfNeeded()
        if let worldID = lab.teaching.activeGazeboWorldID, gazebo.isWorldAlive(id: worldID) { return }
        await lab.teaching.selectEnvironmentAndLoadGazeboWorld(environmentID: envID)
        pushTrainingViewportZones()
    }

    private func pushTrainingViewportZones() {
        guard let manifest = lab.teaching.selectedEnvironment?.manifest else {
            viewportZones.syncFromManifest(nil)
            return
        }
        viewportZones.pushEditorState(
            placementActive: false,
            tapToEditEnabled: false,
            placementKind: .start,
            zones: WorldBuilderZoneManifestSupport.zones(from: manifest),
            obstacles: manifest.obstacles,
            mapHalfExtentM: trainingGroundHalfExtentM
        )
    }

    private func presentAddVehicleDrawer(wingmanToSquadID: UUID? = nil) {
        guard mapIsReadyForVehicles else {
            toastCenter.show("Wait for the map to finish loading.", style: .info, duration: 2.5)
            return
        }
        addVehicleSimulationPlatform = generalSettings.defaultSimulationPlatform
        appDrawer.present(title: nil, preferredWidth: 352) {
            TrainingLabAddVehicleDrawerContent(
                roster: roster,
                fleetLink: fleetLink,
                simulationPlatform: $addVehicleSimulationPlatform,
                vehicleClassForTier: lab.teaching.vehicleClass.fleetVehicleType,
                controlsLocked: labControlsLocked,
                wingmanToSquadID: wingmanToSquadID,
                onAdded: { appDrawer.dismiss() }
            )
        }
    }

    private func presentSquadSettingsDrawer(squadID: UUID, squadIndex: Int) {
        appDrawer.present(title: nil, preferredWidth: 360) {
            TrainingLabSquadSettingsDrawerContent(
                roster: roster,
                squadID: squadID,
                squadIndex: squadIndex,
                controlsLocked: labControlsLocked
            )
        }
    }

    private func attachBothControllers() {
        lab.attach(
            fleetLink: fleetLink,
            sitl: sitl,
            spawnDefaults: generalSettings.simSpawnDefaults,
            simulationPlatform: generalSettings.defaultSimulationPlatform,
            gazebo: gazebo,
            requiresGazeboRunWorld: requiresGazeboRunWorld,
            toastCenter: toastCenter
        )
        roster.attach(
            lab: lab,
            fleetLink: fleetLink,
            missionControl: missionControl,
            simulationPlatform: generalSettings.defaultSimulationPlatform
        )
        lab.bindRoster(roster)
        lab.teaching.syncFromFleetOnAppear(fleetLink: fleetLink)
        lab.teaching.loadPromotedSkill()
        lab.teaching.scheduleNav2PlanPathRefresh()
        lab.formation.syncFromFleetOnAppear(fleetLink: fleetLink)
        GuardianGazeboWebViewerPolicy.showOfflineToastIfNeeded(
            productIncludesGazebo: appProduct.includesGazeboSimulation,
            toastCenter: toastCenter
        )
        refreshActiveMap()
    }

    private func refreshActiveMap() {
        if usesFormationMapLayout {
            refreshMapHome()
            fitMapToPlayground()
        } else {
            refreshTrainingMap()
        }
    }

    @StateObject private var mapModel = GuardianMapModel()

    private struct FormationsCalibrationContext: Identifiable {
        var id: String { vehicleID }
        let vehicleID: String
        let fallback: FleetVehicleModel?
    }

    @ViewBuilder
    private var trainingMainColumn: some View {
        if lab.teaching.usesGazeboTrainingViewport {
            trainingEmbeddedViewportColumn
        } else {
            mapColumn
        }
    }

    // MARK: - Embedded Gazebo viewport (Training `.run`)

    private var trainingFloorSize: TrainingEnvironmentFloorSize {
        guard let pkg = lab.teaching.selectedEnvironment else { return .small }
        return TrainingEnvironmentFloorSize.resolved(from: pkg.manifest.floorSize)
    }

    private var trainingGroundHalfExtentM: Double {
        trainingFloorSize.floorSideM / 2
    }

    private var trainingOrbitMinDistanceM: Double {
        trainingFloorSize.orbitMinDistanceM
    }

    private var isTrainingViewportCameraLive: Bool {
        guard let viewport = gazebo.embeddedViewport else { return false }
        return gazebo.isEmbeddedViewportLive(worldID: viewport.worldID)
    }

    private var trainingEmbeddedViewport: GazeboEmbeddedViewportState? {
        guard let viewport = gazebo.embeddedViewport,
              gazebo.isEmbeddedViewportLive(worldID: viewport.worldID)
                || viewport.worldID == lab.teaching.activeGazeboWorldID
        else { return nil }
        return viewport
    }

    private var showsTrainingEmbeddedViewportSpinner: Bool {
        guard mapIsSelected else { return false }
        guard let viewport = gazebo.embeddedViewport else {
            return lab.teaching.activeGazeboWorldID != nil || lab.teaching.gazeboWorldStatusText != nil
        }
        return !gazebo.isEmbeddedViewportLive(worldID: viewport.worldID)
    }

    private var trainingEmbeddedViewportColumn: some View {
        Group {
            if !mapIsSelected {
                trainingEmptyViewportPrompt
            } else if !gazebo.runtimeAvailable {
                trainingRuntimeMissingViewport
                    .padding(GuardianSpacing.lg)
            } else {
                trainingEmbeddedViewportStack
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var trainingEmbeddedViewportStack: some View {
        ZStack {
            Group {
                if let viewport = trainingEmbeddedViewport {
                    GazeboWebViewportView(
                        websocketPort: viewport.websocketPort,
                        gazeboWorldName: viewport.gazeboWorldName,
                        phase: viewport.phase,
                        cameraBridge: viewportCamera,
                        cameraCommandTick: viewportCamera.tick,
                        zoneBridge: viewportZones,
                        zoneCommandTick: viewportZones.tick,
                        showsCameraDebugHUD: fleetLink.isDebugEnabled,
                        groundHalfExtentM: trainingGroundHalfExtentM,
                        orbitMinDistanceM: trainingOrbitMinDistanceM
                    )
                    .id(viewport.worldID)
                } else {
                    Color.black
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsTrainingEmbeddedViewportSpinner {
                trainingViewportLoadingOverlay
            }

            if let err = gazebo.lastError,
               lab.teaching.activeGazeboWorldID == nil,
               !showsTrainingEmbeddedViewportSpinner {
                trainingViewportErrorOverlay(err)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
            if fleetLink.isDebugEnabled {
                WorldBuilderMapDebugOverlay(
                    lines: lab.teaching.mapDebugLines,
                    theme: theme,
                    accessibilityLabel: "Training map debug log"
                )
            }
        }
        .onChange(of: gazebo.embeddedViewport) { viewport in
            lab.teaching.reconcileActiveGazeboRunWorldIfNeeded()
            lab.teaching.noteEmbeddedViewport(viewport)
        }
        .onChange(of: fleetLink.isDebugEnabled) { enabled in
            if enabled {
                lab.teaching.logMap("Debug overlay enabled")
                lab.teaching.noteEmbeddedViewport(gazebo.embeddedViewport)
            }
        }
    }

    private var trainingViewportLoadingOverlay: some View {
        ZStack {
            theme.backgroundRaised.opacity(0.92)
            VStack(spacing: GuardianSpacing.md) {
                ProgressView()
                    .controlSize(.regular)
                Text(lab.teaching.gazeboWorldStatusText ?? "Loading scene…")
                    .font(GuardianTypography.Scale.body.font())
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(GuardianSpacing.lg)
        }
    }

    private func trainingViewportErrorOverlay(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(GuardianTypography.Scale.caption.font())
                .foregroundStyle(GuardianSemanticColors.dangerForeground)
                .multilineTextAlignment(.center)
                .padding(GuardianSpacing.lg)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundRaised.opacity(0.88))
    }

    private var trainingRuntimeMissingViewport: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            Text("Gazebo is not available")
                .font(GuardianTypography.font(.sectionHeadingSemibold))
                .foregroundStyle(theme.textPrimary)
            Text("Run make gazebo-runtime after installing Gazebo Harmonic, then rebuild.")
                .font(GuardianTypography.Scale.body.font())
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var trainingEmptyViewportPrompt: some View {
        GuardianEmptyState(
            systemImage: "map",
            title: "No map selected",
            detail: "Choose a built training map from the Map tab. The world loads here when selected.",
            primaryTitle: nil,
            primaryAction: nil,
            secondaryTitle: "Open Map",
            secondaryAction: {
                if isSessionRunning {
                    presentTrainingLabDrawer(.map)
                } else {
                    idleRailTab = .map
                }
            }
        )
    }

    private var mapColumn: some View {
        GuardianMapView(
            model: mapModel,
            toolbar: GuardianMapToolbarOptions(
                mapResetAction: { model in
                    if usesFormationMapLayout {
                        fitMapToPlayground(mapModel: model)
                    } else {
                        fitTrainingMap(mapModel: model)
                    }
                }
            ),
            onFormationSlotGroupCenterMoved: { lat, lon in
                if usesFormationMapLayout {
                    lab.formation.previewFormationSlotGroupCenter(lat: lat, lon: lon)
                    syncFormationSlotMapEditChrome()
                } else {
                    lab.teaching.moveTargetSlotCenter(latitudeDeg: lat, longitudeDeg: lon)
                    syncTrainingTargetSlotMapEdit()
                }
            },
            onFormationSlotGroupHeadingMoved: { headingDeg in
                if usesFormationMapLayout {
                    lab.formation.previewFormationSlotGroupHeading(headingDeg: headingDeg)
                    syncFormationSlotMapEditChrome()
                } else {
                    lab.teaching.setTargetSlotHeading(headingDeg: headingDeg)
                    syncTrainingTargetSlotMapEdit()
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var trainingLabSideRail: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $idleRailTab) {
                ForEach(TrainingLabPanelTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, GuardianSpacing.md)
            .padding(.top, GuardianSpacing.sm)
            .padding(.bottom, GuardianSpacing.xsTight)

            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)

            trainingLabPanelContent(for: idleRailTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if !usesFormationMapLayout, fleetLink.isDebugEnabled {
                trainingPathOverlayDebugRail
            }
        }
        .background(theme.backgroundBase)
    }

    private var trainingPathOverlayDebugRail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)
            HStack(spacing: GuardianSpacing.xs) {
                Text("debug")
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textTertiary)
                Text(lab.teaching.trainingPathOverlayDebugLine)
                    .font(GuardianTypography.font(.denseCaption12Medium))
                    .foregroundStyle(theme.textSecondary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, GuardianSpacing.md)
            .padding(.vertical, GuardianSpacing.sm)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lab.teaching.trainingPathOverlayDebugLine)
    }

    // MARK: - Training lab sub-bar & drawers

    private var trainingLabSubBar: some View {
        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                Text(lab.teaching.selectedEnvironment?.manifest.displayName ?? "No map selected")
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                    .foregroundStyle(mapIsSelected ? theme.textPrimary : theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 220, alignment: .leading)

                if mapIsSelected, lab.teaching.usesGazeboTrainingViewport {
                    trainingViewportCameraControls
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            if roster.squads.count > 1 {
                TrainingLabLearningSquadPicker(
                    roster: roster,
                    controlsLocked: labControlsLocked
                )
            }

            Spacer(minLength: GuardianSpacing.sm)

            if isSessionRunning {
                trainingLabDrawerTriggers
            } else {
                trainingLabRunButton
            }
        }
        .padding(.horizontal, GuardianSpacing.md)
        .padding(.vertical, GuardianSpacing.sm)
        .background(theme.backgroundRaised)
    }

    private var trainingViewportCameraControls: some View {
        HStack(spacing: GuardianSpacing.xs) {
            subBarIconButton(
                systemImage: "view.3d",
                accessibilityLabel: "Oblique view preset",
                isEnabled: isTrainingViewportCameraLive,
                action: { viewportCamera.trigger(.defaultView) }
            )
            subBarIconButton(
                systemImage: "view.2d",
                accessibilityLabel: "Top-down view preset",
                isEnabled: isTrainingViewportCameraLive,
                action: { viewportCamera.trigger(.birdseye) }
            )
        }
    }

    private var trainingLabRunButton: some View {
        GuardianPrimaryProminentButton(title: "Run") {
            startSession()
        }
        .disabled(!canStartSession)
        .keyboardShortcut(TrainingLabKeyboardShortcuts.run)
    }

    private var trainingLabDrawerTriggers: some View {
        HStack(spacing: GuardianSpacing.xs) {
            ForEach(TrainingLabPanelTab.allCases) { tab in
                subBarIconButton(
                    systemImage: tab.systemImage,
                    accessibilityLabel: tab.rawValue,
                    isEnabled: tab != .vehicles || mapIsReadyForVehicles,
                    action: { presentTrainingLabDrawer(tab) }
                )
                .help(trainingLabDrawerTabHelp(tab))
            }
            subBarIconButton(
                systemImage: "stop.fill",
                accessibilityLabel: "Stop",
                accent: .danger,
                surface: .outline,
                action: { stopSessionAndReset() }
            )
            .help("Stop session (Escape)")
        }
    }

    @ViewBuilder
    private func trainingLabPanelContent(for tab: TrainingLabPanelTab) -> some View {
        switch tab {
        case .map:
            TrainingLabMapPanelContent(
                training: lab.teaching,
                packages: lab.teaching.availableEnvironments,
                controlsLocked: labControlsLocked,
                onSelectEnvironmentID: { id in
                    Task {
                        await lab.teaching.selectEnvironmentAndLoadGazeboWorld(environmentID: id)
                        pushTrainingViewportZones()
                        refreshActiveMap()
                    }
                }
            )
        case .vehicles:
            if mapIsSelected {
                TrainingLabVehiclesPanelContent(
                    roster: roster,
                    playground: lab.formation,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    missionControl: missionControl,
                    mapReadyForVehicles: mapIsReadyForVehicles,
                    controlsLocked: labControlsLocked,
                    onPresentAddVehicle: { presentAddVehicleDrawer() },
                    onPresentSquadSettings: { squadID, squadIndex in
                        presentSquadSettingsDrawer(squadID: squadID, squadIndex: squadIndex)
                    },
                    onOpenCalibration: { vehicleID, fallback in
                        calibrationContext = FormationsCalibrationContext(
                            vehicleID: vehicleID,
                            fallback: fallback
                        )
                    }
                )
            } else {
                trainingLabGateEmptyState(
                    message: "Select a map before configuring vehicles."
                )
            }
        case .training:
            trainingLabPanel
        case .logs:
            logsLabPanel
        }
    }

    private func trainingLabDrawerTabHelp(_ tab: TrainingLabPanelTab) -> String {
        guard tab == .vehicles else { return tab.rawValue }
        if !mapIsSelected { return "Choose a training map first." }
        if !mapIsReadyForVehicles { return "Wait for the map to finish loading." }
        return tab.rawValue
    }

    private var trainingLabKeyboardShortcutButtons: some View {
        Group {
            if isSessionRunning {
                ForEach(TrainingLabPanelTab.allCases) { tab in
                    Button(tab.drawerTitle) {
                        presentTrainingLabDrawer(tab)
                    }
                    .keyboardShortcut(TrainingLabKeyboardShortcuts.panelTab(tab))
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
                }
            } else {
                ForEach(TrainingLabPanelTab.allCases) { tab in
                    Button(tab.rawValue) {
                        selectIdleRailTab(tab)
                    }
                    .keyboardShortcut(TrainingLabKeyboardShortcuts.panelTab(tab))
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private func selectIdleRailTab(_ tab: TrainingLabPanelTab) {
        if tab == .vehicles, !mapIsSelected {
            toastCenter.show("Choose a training map first.", style: .info, duration: 2.5)
            return
        }
        if tab == .vehicles, !mapIsReadyForVehicles {
            toastCenter.show("Wait for the map to finish loading.", style: .info, duration: 2.5)
            return
        }
        idleRailTab = tab
    }

    private func presentTrainingLabDrawer(_ tab: TrainingLabPanelTab) {
        if tab == .vehicles, !mapIsSelected {
            toastCenter.show("Choose a training map first.", style: .info, duration: 2.5)
            return
        }
        if tab == .vehicles, !mapIsReadyForVehicles {
            toastCenter.show("Wait for the map to finish loading.", style: .info, duration: 2.5)
            return
        }
        appDrawer.present(title: tab.drawerTitle, preferredWidth: TrainingLabLayout.runningDrawerWidth) {
            trainingLabPanelContent(for: tab)
        }
    }

    private func subBarIconButton(
        systemImage: String,
        accessibilityLabel: String,
        accent: GuardianThemeAccent = .neutral,
        surface: GuardianChromeSurface = .outline,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        GuardianThemedButton(
            accent: accent,
            surface: surface,
            size: .small,
            shape: .cornered,
            isEnabled: isEnabled,
            contentSizing: .squareToolbarCell,
            action: action,
            label: {
                Image(systemName: systemImage)
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
            }
        )
        .accessibilityLabel(accessibilityLabel)
        .guardianPointerOnHover()
    }

    private func trainingLabGateEmptyState(message: String) -> some View {
        ScrollView {
            Text(message)
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textTertiary)
                .padding(GuardianSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var canStartSession: Bool {
        guard mapIsSelected else { return false }
        let slots = roster.allSlotStates
        guard !slots.isEmpty else { return false }
        return slots.allSatisfy(\.linkReady) && slots.allSatisfy { $0.preflightPassed == true }
    }

    private func startSession() {
        guard canStartSession else { return }
        Task {
            await lab.buildMap(roster: roster)
            roster.syncTrainingFromLearningSquad()
            if roster.learningSquadUsesFormation {
                idleRailTab = .logs
                lab.applyFormationPolicyForRun(from: roster)
                await lab.applyFormationControl()
                syncMapContent()
            } else {
                lab.teaching.startAutonomousTeaching()
                idleRailTab = .logs
            }
        }
    }

    private func stopSessionAndReset() {
        lab.teaching.cancelTeaching()
        Task {
            await lab.stopActiveFormationSession()
            await lab.resetMap(roster: roster)
        }
    }

    private var trainingLabPanel: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logsLabPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                if !lab.teaching.logLines.isEmpty {
                    Text("Teaching")
                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                        .foregroundStyle(theme.textPrimary)
                    ForEach(lab.teaching.logLines) { line in
                        Text(line.message)
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled)
                    }
                }
                if !lab.formation.logLines.isEmpty {
                    Text("Formation")
                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.top, lab.teaching.logLines.isEmpty ? 0 : GuardianSpacing.sm)
                    ForEach(lab.formation.logLines) { line in
                        formationLogRow(line)
                    }
                }
                if lab.teaching.logLines.isEmpty && lab.formation.logLines.isEmpty {
                    Text("Logs appear here during spawn, teaching, and formation runs.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(GuardianSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formationLogRow(_ line: FormationsPlaygroundLogLine) -> some View {
        let stateColor: Color = switch line.state {
        case .inPosition: GuardianSemanticColors.successForeground
        case .movingToPosition: GuardianSemanticColors.infoForeground
        case .stuck: GuardianSemanticColors.warningForeground
        case .noTelemetry: theme.textTertiary
        case .idle: theme.textSecondary
        }
        return VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xs) {
                Text(line.vehicleLabel)
                    .font(GuardianTypography.font(.denseCaption12Medium))
                    .foregroundStyle(theme.textPrimary)
                Text(line.timestamp, style: .time)
                    .font(GuardianTypography.font(.telemetryMono10Semibold))
                    .foregroundStyle(theme.textTertiary)
                Spacer(minLength: 0)
                Text(line.state.rawValue)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(stateColor)
            }
            Text(line.message)
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(GuardianSpacing.sm)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func refreshMapHome() {
        let defaults = generalSettings.simSpawnDefaults
        let home = RouteHome(
            coord: RouteCoordinate(lat: defaults.latitudeDeg, lon: defaults.longitudeDeg),
            altitude: RouteAltitude(value: defaults.altitudeM, unit: .m, reference: .agl),
            heading: defaults.headingDeg,
            radiusMeters: 8,
            dockAllowed: true,
            fallbackOnly: false
        )
        var geometry = GuardianRouteMapGeometry.empty
        geometry.home = home
        geometry.preserveView = true
        geometry.formationSlotGroupMapEdit = lab.formation.buildFormationSlotGroupMapEdit(fleetLink: fleetLink)
        mapModel.applyMapContent(
            routeGeometry: geometry,
            vehicleMarkers: lab.formation.buildAllMapMarkers(fleetLink: fleetLink)
        )
    }

    private func syncMapContent() {
        lab.formation.refreshConnectedSimCount(fleetLink: fleetLink)
        var geometry = mapModel.routeGeometry
        geometry.formationSlotGroupMapEdit = lab.formation.buildFormationSlotGroupMapEdit(fleetLink: fleetLink)
        mapModel.applyMapContent(
            routeGeometry: geometry,
            vehicleMarkers: lab.formation.buildAllMapMarkers(fleetLink: fleetLink)
        )
    }

    private func syncMapMarkers() {
        lab.formation.refreshConnectedSimCount(fleetLink: fleetLink)
        mapModel.applyVehicleMarkersOnly(lab.formation.buildAllMapMarkers(fleetLink: fleetLink))
    }

    /// Full map publish for slot-edit chrome (handles + clones). Avoid during an active drag — rebuilds Leaflet handles.
    private func syncFormationSlotMapEditChrome() {
        lab.formation.refreshConnectedSimCount(fleetLink: fleetLink)
        var geometry = mapModel.routeGeometry
        geometry.formationSlotGroupMapEdit = lab.formation.buildFormationSlotGroupMapEdit(fleetLink: fleetLink)
        mapModel.applyMapContent(
            routeGeometry: geometry,
            vehicleMarkers: lab.formation.buildAllMapMarkers(fleetLink: fleetLink)
        )
    }

    private func fitMapToPlayground(mapModel: GuardianMapModel? = nil) {
        syncMapContent()
        let model = mapModel ?? self.mapModel
        model.fitToVisible(
            points: lab.formation.formationMapFitPoints(fleetLink: fleetLink),
            style: .formationContent
        )
    }

    private func refreshTrainingMap() {
        guard !lab.teaching.usesGazeboTrainingViewport else { return }
        let defaults = generalSettings.simSpawnDefaults
        let home = RouteHome(
            coord: RouteCoordinate(lat: defaults.latitudeDeg, lon: defaults.longitudeDeg),
            altitude: RouteAltitude(value: defaults.altitudeM, unit: .m, reference: .agl),
            heading: defaults.headingDeg,
            radiusMeters: 8,
            dockAllowed: true,
            fallbackOnly: false
        )
        var geometry = GuardianRouteMapGeometry.empty
        geometry.home = home
        geometry.preserveView = true
        geometry.formationSlotGroupMapEdit = lab.teaching.buildTargetSlotMapEdit()
        if lab.teaching.nav2PlannedPath.count >= 2 {
            geometry.debugOverlayPolylines = [lab.teaching.nav2PlannedPath]
        }
        mapModel.applyMapContent(routeGeometry: geometry, vehicleMarkers: buildTrainingMapMarkers())
        fitTrainingMap()
    }

    private func syncTrainingTargetSlotMapEdit() {
        var geometry = mapModel.routeGeometry
        geometry.preserveView = true
        geometry.formationSlotGroupMapEdit = lab.teaching.buildTargetSlotMapEdit()
        if lab.teaching.nav2PlannedPath.count >= 2 {
            geometry.debugOverlayPolylines = [lab.teaching.nav2PlannedPath]
        } else {
            geometry.debugOverlayPolylines = []
        }
        mapModel.applyMapContent(
            routeGeometry: geometry,
            vehicleMarkers: buildTrainingMapMarkers()
        )
    }

    private func syncTrainingMapMarkers() {
        syncTrainingTargetSlotMapEdit()
    }

    private func buildTrainingMapMarkers() -> [MapVehicleMarker] {
        guard let layout = lab.teaching.taskLayout else { return [] }
        var markers: [MapVehicleMarker] = [
            MapVehicleMarker(
                id: "training:start",
                lat: layout.start.latitudeDeg,
                lon: layout.start.longitudeDeg,
                label: "Start",
                colorHex: "#4A90D9",
                glyphKind: .formationSlotTarget,
                imageDataURL: nil,
                showLabel: true,
                selected: false,
                draggable: false,
                headingDeg: layout.start.headingDeg,
                accessibilityTitle: "Task start"
            ),
            MapVehicleMarker(
                id: "training:targetSlot",
                lat: layout.goal.latitudeDeg,
                lon: layout.goal.longitudeDeg,
                label: "Target slot",
                colorHex: "#2ECC71",
                glyphKind: .trainingSlotGoal,
                imageDataURL: nil,
                showLabel: true,
                selected: false,
                draggable: false,
                headingDeg: layout.goal.headingDeg,
                accessibilityTitle: "Target slot — yellow edge is heading"
            ),
        ]
        if let vid = lab.teaching.vehicleID,
           let hub = fleetLink.hubTelemetry(forVehicleID: vid),
           let lat = hub.latitudeDeg,
           let lon = hub.longitudeDeg {
            let vType = fleetLink.vehicleModel(forVehicleID: vid)?.data.vehicleType
                ?? lab.teaching.vehicleClass.fleetVehicleType
            markers.append(
                MapVehicleMarker(
                    id: vid,
                    lat: lat,
                    lon: lon,
                    label: "Sim",
                    colorHex: "#E67E22",
                    glyphKind: GuardianMapVehicleGlyphKind.forFleetVehicleType(vType),
                    imageDataURL: nil,
                    showLabel: true,
                    selected: true,
                    draggable: false,
                    headingDeg: MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: hub)
                )
            )
        }
        return markers
    }

    private func fitTrainingMap(mapModel: GuardianMapModel? = nil) {
        guard let layout = lab.teaching.taskLayout else { return }
        var points: [(Double, Double)] = [
            (layout.start.latitudeDeg, layout.start.longitudeDeg),
            (layout.goal.latitudeDeg, layout.goal.longitudeDeg),
        ]
        if let vid = lab.teaching.vehicleID,
           let hub = fleetLink.hubTelemetry(forVehicleID: vid),
           let lat = hub.latitudeDeg,
           let lon = hub.longitudeDeg {
            points.append((lat, lon))
        }
        let model = mapModel ?? self.mapModel
        model.fitToVisible(points: points, style: .formationContent)
    }

}

private struct TrainingLabEscapeStopModifier: ViewModifier {
    let isEnabled: Bool
    let drawerPresented: Bool
    let onStop: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.escape) {
                    guard isEnabled, !drawerPresented else { return .ignored }
                    onStop()
                    return .handled
                }
        } else {
            content
        }
    }
}
