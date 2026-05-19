import AppKit
import SwiftUI

private enum FormationsSidePanelTab: String, CaseIterable, Identifiable {
    case controls = "Controls"
    case sims = "Sims"
    case logs = "Logs"

    var id: String { rawValue }
}

private enum TrainingSidePanelTab: String, CaseIterable, Identifiable {
    case controls = "Controls"
    case logs = "Logs"
    case skill = "Skill"

    var id: String { rawValue }
}

/// Simulate panel: **Vehicle** mode (skill training, default) and **Formation** mode (spacing sandbox).
struct TrainingPanelView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var missionControl: MissionControlStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    @ObservedObject var gazebo: GazeboService
    var requiresGazeboRunWorld: Bool = false
    @StateObject private var playground = FormationsPlaygroundController()
    @StateObject private var training = TrainingPanelController()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.guardianAppProduct) private var appProduct
    @EnvironmentObject private var toastCenter: ToastCenter
    @EnvironmentObject private var applicationLifecycle: GuardianApplicationLifecycle

    @State private var panelMode: TrainingPanelMode = .vehicle
    @State private var sidePanelTab: FormationsSidePanelTab = .controls
    @State private var trainingSidePanelTab: TrainingSidePanelTab = .controls
    @State private var calibrationContext: FormationsCalibrationContext?
    @State private var showTelemetryTrace = false

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var formationControlsLocked: Bool {
        playground.isBusy || playground.phase != .idle
    }

    private var vehicleControlsLocked: Bool {
        training.isBusy
            || training.phase == .teaching
            || training.phase == .spawning
            || training.phase == .connecting
            || training.phase == .preflight
    }

    /// Target-slot map edit toggle is off-limits while a teaching run is active (or spawn/preflight is busy).
    private var trainingTargetSlotMapEditLocked: Bool {
        vehicleControlsLocked || training.phase == .teaching
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let mapWidth = geo.size.width * 0.7
                HStack(spacing: 0) {
                    trainingMainColumn
                        .frame(width: mapWidth, height: geo.size.height, alignment: .top)

                    Rectangle()
                        .fill(theme.borderSubtle)
                        .frame(width: 1)
                        .frame(height: geo.size.height)

                    sidePanel
                        .frame(width: geo.size.width - mapWidth - 1, height: geo.size.height, alignment: .top)
                }
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
        .onAppear {
            training.clampVehicleClassToTrainingPanelOptions()
            attachControllersForCurrentMode()
            refreshActiveMap()
        }
        .onDisappear {
            training.leavePanel()
            playground.leavePanel()
        }
        .onChange(of: generalSettings.simSpawnDefaults) { defaults in
            training.attach(
                fleetLink: fleetLink,
                sitl: sitl,
                spawnDefaults: defaults,
                simulationPlatform: generalSettings.defaultSimulationPlatform,
                gazebo: gazebo,
                requiresGazeboRunWorld: requiresGazeboRunWorld,
                toastCenter: toastCenter
            )
            training.spawnDefaultsDidChange()
            playground.attach(
                fleetLink: fleetLink,
                sitl: sitl,
                spawnDefaults: defaults,
                simulationPlatform: generalSettings.defaultSimulationPlatform
            )
            if panelMode == .vehicle {
                refreshTrainingMap()
            } else {
                refreshMapHome()
            }
        }
        .onChange(of: generalSettings.defaultSimulationPlatform) { platform in
            playground.attach(
                fleetLink: fleetLink,
                sitl: sitl,
                spawnDefaults: generalSettings.simSpawnDefaults,
                simulationPlatform: platform
            )
        }
        .onChange(of: playground.formation) { _ in
            guard panelMode == .formation else { return }
            playground.formationSettingsDidChange(fleetLink: fleetLink)
            if playground.isSlotGroupMapEditEnabled {
                syncFormationSlotMapEditChrome()
            } else {
                syncMapContent()
            }
        }
        .onChange(of: playground.shape) { _ in
            guard panelMode == .formation else { return }
            playground.formationSettingsDidChange(fleetLink: fleetLink)
            if playground.isSlotGroupMapEditEnabled {
                syncFormationSlotMapEditChrome()
            } else {
                syncMapContent()
            }
        }
        .onChange(of: training.taskKind) { _ in
            guard panelMode == .vehicle else { return }
            training.taskKindDidChange()
            training.trainingTaskOrVehicleDidChange()
            training.loadPromotedSkill()
        }
        .onChange(of: training.targetSlot) { _ in
            guard panelMode == .vehicle else { return }
            training.scheduleNav2PlanPathRefresh()
            refreshTrainingMap()
        }
        .onChange(of: training.nav2PlannedPath) { _ in
            guard panelMode == .vehicle else { return }
            refreshTrainingMap()
        }
        .onChange(of: training.selectedEnvironmentID) { _ in
            training.environmentSelectionDidChange()
        }
        .onChange(of: training.vehicleClass) { _ in
            training.trainingTaskOrVehicleDidChange()
            guard panelMode == .vehicle else { return }
            training.scheduleNav2PlanPathRefresh()
        }
        .onChange(of: fleetLink.nav2TrainingStackReady) { _ in
            guard panelMode == .vehicle else { return }
            training.scheduleNav2PlanPathRefresh()
        }
        .onChange(of: training.isTargetSlotMapEditEnabled) { _ in
            guard panelMode == .vehicle else { return }
            refreshTrainingMap()
        }
        .onReceive(fleetLink.$hubFleetTelemetryTick) { _ in
            guard applicationLifecycle.isApplicationActive else { return }
            if panelMode == .vehicle {
                training.refreshSimulatorSlot(fleetLink: fleetLink)
                syncTrainingMapMarkers()
            } else {
                playground.refreshConnectedSimCount(fleetLink: fleetLink)
                syncMapMarkers()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .guardianApplicationDidBecomeActive)) { _ in
            if panelMode == .vehicle {
                training.refreshSimulatorSlot(fleetLink: fleetLink)
                refreshTrainingMap()
            } else {
                playground.refreshConnectedSimCount(fleetLink: fleetLink)
                refreshActiveMap()
            }
        }
        .onChange(of: sidePanelTab) { tab in
            if tab == .sims {
                playground.refreshConnectedSimCount(fleetLink: fleetLink)
            }
        }
    }

    private func attachControllersForCurrentMode() {
        training.attach(
            fleetLink: fleetLink,
            sitl: sitl,
            spawnDefaults: generalSettings.simSpawnDefaults,
            simulationPlatform: generalSettings.defaultSimulationPlatform,
            gazebo: gazebo,
            requiresGazeboRunWorld: requiresGazeboRunWorld,
            toastCenter: toastCenter
        )
        playground.attach(
            fleetLink: fleetLink,
            sitl: sitl,
            spawnDefaults: generalSettings.simSpawnDefaults,
            simulationPlatform: generalSettings.defaultSimulationPlatform
        )
        if panelMode == .vehicle {
            playground.leavePanel()
            training.syncFromFleetOnAppear(fleetLink: fleetLink)
            training.loadPromotedSkill()
            training.scheduleNav2PlanPathRefresh()
            refreshTrainingMap()
        } else {
            training.leavePanel()
            playground.syncFromFleetOnAppear(fleetLink: fleetLink)
        }
    }

    private func handlePanelModeChange(_ mode: TrainingPanelMode) {
        switch mode {
        case .vehicle:
            playground.leavePanel()
            training.syncFromFleetOnAppear(fleetLink: fleetLink)
            training.loadPromotedSkill()
        case .formation:
            training.leavePanel()
            playground.syncFromFleetOnAppear(fleetLink: fleetLink)
            GuardianGazeboWebViewerPolicy.showOfflineToastIfNeeded(
                productIncludesGazebo: appProduct.includesGazeboSimulation,
                toastCenter: toastCenter
            )
        }
        refreshActiveMap()
    }

    private func refreshActiveMap() {
        if panelMode == .vehicle {
            refreshTrainingMap()
        } else {
            refreshMapHome()
            fitMapToPlayground()
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
        if panelMode == .vehicle, training.usesGazeboTrainingViewport {
            trainingGazeboViewport
        } else {
            mapColumn
        }
    }

    private var trainingGazeboViewport: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.md) {
            Text("Gazebo simulation")
                .font(GuardianTypography.font(.sectionHeadingSemibold))
                .foregroundStyle(theme.textPrimary)
            Text(
                gazebo.runtimeAvailable
                    ? "The training world runs in the Gazebo simulator window. An embedded 3D view will replace this panel in a later release."
                    : "Gazebo is not available in this build. Run make gazebo-runtime after installing Gazebo Harmonic, then rebuild."
            )
            .font(GuardianTypography.Scale.body.font())
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if let env = training.selectedEnvironment {
                Text(env.manifest.displayName)
                    .font(GuardianTypography.Scale.caption.font(weight: .medium))
                    .foregroundStyle(theme.textPrimary)
            }

            if let gazeboStatus = training.gazeboWorldStatusText {
                Text(gazeboStatus)
                    .font(GuardianTypography.Scale.caption.font())
                    .foregroundStyle(theme.textTertiary)
            }

            if let err = gazebo.lastError, training.activeGazeboWorldID == nil, training.simulatorSlot != nil {
                Text(err)
                    .font(GuardianTypography.Scale.caption.font())
                    .foregroundStyle(GuardianSemanticColors.dangerForeground)
            }

            Spacer()
        }
        .padding(GuardianSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.backgroundRaised)
    }

    private var mapColumn: some View {
        GuardianMapView(
            model: mapModel,
            toolbar: GuardianMapToolbarOptions(
                mapResetAction: { model in
                    if panelMode == .vehicle {
                        fitTrainingMap(mapModel: model)
                    } else {
                        fitMapToPlayground(mapModel: model)
                    }
                }
            ),
            onFormationSlotGroupCenterMoved: { lat, lon in
                if panelMode == .vehicle {
                    training.moveTargetSlotCenter(latitudeDeg: lat, longitudeDeg: lon)
                    syncTrainingTargetSlotMapEdit()
                } else {
                    playground.previewFormationSlotGroupCenter(lat: lat, lon: lon)
                    syncFormationSlotMapEditChrome()
                }
            },
            onFormationSlotGroupHeadingMoved: { headingDeg in
                if panelMode == .vehicle {
                    training.setTargetSlotHeading(headingDeg: headingDeg)
                    syncTrainingTargetSlotMapEdit()
                } else {
                    playground.previewFormationSlotGroupHeading(headingDeg: headingDeg)
                    syncFormationSlotMapEditChrome()
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var sidePanel: some View {
        VStack(spacing: 0) {
            panelModePicker
                .padding(.horizontal, GuardianSpacing.md)
                .padding(.top, GuardianSpacing.sm)
                .padding(.bottom, GuardianSpacing.xsTight)

            if panelMode == .vehicle {
                vehicleSidePanelToolbar
            } else {
                sidePanelToolbar
            }

            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)

            Group {
                if panelMode == .vehicle {
                    switch trainingSidePanelTab {
                    case .controls:
                        vehicleControlsTab
                    case .logs:
                        vehicleLogsTab
                    case .skill:
                        vehicleSkillTab
                    }
                } else {
                    switch sidePanelTab {
                    case .controls:
                        controlsTab
                    case .sims:
                        simsTab
                    case .logs:
                        logsTab
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if panelMode == .vehicle, fleetLink.isDebugEnabled {
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
                Text(training.trainingPathOverlayDebugLine)
                    .font(GuardianTypography.font(.denseCaption12Medium))
                    .foregroundStyle(theme.textSecondary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, GuardianSpacing.md)
            .padding(.vertical, GuardianSpacing.sm)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(training.trainingPathOverlayDebugLine)
    }

    private var panelModePicker: some View {
        Picker("Panel mode", selection: $panelMode) {
            ForEach(TrainingPanelMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: panelMode) { mode in
            handlePanelModeChange(mode)
        }
    }

    private var sidePanelToolbar: some View {
        HStack(spacing: GuardianSpacing.sm) {
            HStack(spacing: GuardianSpacing.sm) {
                Picker("Panel", selection: $sidePanelTab) {
                    ForEach(FormationsSidePanelTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: GuardianSpacing.sm)

            if !playground.slots.isEmpty {
                GuardianThemedButton(
                    accent: .primary,
                    surface: .solid,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !playground.isBusy,
                    contentSizing: .squareToolbarCell,
                    action: {
                        Task {
                            sidePanelTab = .logs
                            await playground.applyFormationControl()
                            syncMapContent()
                        }
                    },
                    label: {
                        Image(systemName: "arrow.clockwise")
                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                    }
                )
                .help("Reform squad")
                .guardianPointerOnHover()
            }
            GuardianThemedButton(
                accent: .primary,
                surface: .solid,
                size: .small,
                shape: .cornered,
                isEnabled: !playground.isBusy && fleetLink.isSimulateEnabled,
                contentSizing: .squareToolbarCell,
                action: {
                    Task {
                        await playground.spawnPlaygroundSims(missionControl: missionControl)
                        syncMapMarkers()
                        fitMapToPlayground()
                        if !playground.slots.isEmpty {
                            sidePanelTab = .sims
                        }
                    }
                },
                label: {
                    Image(systemName: playground.isBusy ? "hourglass" : "wand.and.stars")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                }
            )
            .help(spawnButtonHelp)
            .guardianPointerOnHover()
            if !playground.slots.isEmpty {
                GuardianThemedButton(
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !playground.isBusy,
                    contentSizing: .squareToolbarCell,
                    action: {
                        playground.stopPlaygroundSquad()
                        syncMapMarkers()
                    },
                    label: {
                        Image(systemName: "trash")
                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                    }
                )
                .help("Stop squad")
                .guardianPointerOnHover()
            }
        }
        .padding(.horizontal, GuardianSpacing.md)
        .padding(.vertical, GuardianSpacing.sm)
    }

    private var spawnButtonHelp: String {
        if playground.isBusy { return "Working…" }
        if playground.phase == .following { return "Respawn squad" }
        return "Spawn simulators"
    }

    private var controlsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                if !fleetLink.isSimulateEnabled {
                    Text("Turn on Simulate in the top bar to spawn vehicles.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(playground.statusText)
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(
                        playground.phase == .following ? theme.textSecondary : theme.textTertiary
                    )
                    .fixedSize(horizontal: false, vertical: true)

                formationControl(
                    title: "Vehicle class",
                    help: "SITL type for every simulator in the squad."
                ) {
                    Picker("Vehicle class", selection: $playground.vehicleClass) {
                        ForEach(FormationsPlaygroundVehicleClass.allCases) { kind in
                            Text(kind.displayTitle).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .disabled(formationControlsLocked)
                }

                formationControl(
                    title: "Simulators",
                    help: "One primary plus wingmen (1–10)."
                ) {
                    HStack(spacing: GuardianSpacing.sm) {
                        Text("\(playground.simCount)")
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(theme.textPrimary)
                            .monospacedDigit()
                            .frame(minWidth: 28, alignment: .trailing)
                        Stepper(
                            "Simulator count",
                            value: $playground.simCount,
                            in: 1...10,
                            step: 1
                        )
                        .labelsHidden()
                        .disabled(formationControlsLocked)
                    }
                }

                formationControl(
                    title: "Formation",
                    help: "Convoy, chevron, or arrowhead. Change while following to re-stream slots."
                ) {
                    Picker("Formation", selection: $playground.formation) {
                        ForEach(MissionSquadFormationKind.allCases) { kind in
                            Text(kind.displayTitle).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .disabled(playground.isBusy)
                }

                formationControl(
                    title: "Spacing",
                    help: "Tight, normal, or loose pack for every formation."
                ) {
                    Picker("Spacing", selection: $playground.shape) {
                        ForEach(MissionSquadFormationShape.allCases) { value in
                            Text(value.displayTitle).tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .disabled(playground.isBusy)
                }

                formationControl(
                    title: "Adjust slots on map",
                    help: "Gold outlines are a preview — drag the diamond or circle handle to move and rotate them. Red slots stay on the live formation until you turn this off, then simulators move to the preview."
                ) {
                    Toggle(
                        isOn: Binding(
                            get: { playground.isSlotGroupMapEditEnabled },
                            set: { enabled in
                                Task {
                                    await playground.setSlotGroupMapEditEnabled(
                                        enabled,
                                        fleetLink: fleetLink
                                    )
                                    if enabled {
                                        syncFormationSlotMapEditChrome()
                                    } else {
                                        syncMapContent()
                                    }
                                }
                            }
                        )
                    ) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Adjust slots on map")
                    .disabled(playground.isBusy || playground.slots.isEmpty)
                }

                Text(
                    "Spawns the same SITLs as Vehicles (they stay when you leave this tab). Preflight requires live telemetry, then streamed OFFBOARD/GUIDED setpoints move the squad into formation — not teleport."
                )
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, GuardianSpacing.md)
            .padding(.vertical, GuardianSpacing.cardBodyInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logsTab: some View {
        VStack(spacing: 0) {
            logsTabHeader
            ScrollView {
                VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                    if playground.logLines.isEmpty {
                        Text("Formation follow logs appear here after you apply or reform. Each simulator reports position, slot distance, and stuck recovery.")
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(playground.logLines) { line in
                            formationLogRow(line)
                        }
                    }
                }
                .padding(.horizontal, GuardianSpacing.md)
                .padding(.vertical, GuardianSpacing.cardBodyInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            telemetryTraceSection
        }
    }

    private var telemetryTraceSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)

            Button {
                withAnimation(GuardianMotion.confirmPresent) {
                    showTelemetryTrace.toggle()
                }
            } label: {
                HStack(spacing: GuardianSpacing.xs) {
                    Image(systemName: showTelemetryTrace ? "chevron.down" : "chevron.right")
                        .font(GuardianTypography.font(.denseCaption10Regular))
                        .foregroundStyle(theme.textTertiary)
                    Text("Telemetry trace")
                        .font(GuardianTypography.font(.denseCaption12Medium))
                        .foregroundStyle(theme.textSecondary)
                    Text("debug")
                        .font(GuardianTypography.font(.denseCaption10Regular))
                        .foregroundStyle(theme.textTertiary)
                    Spacer(minLength: GuardianSpacing.xs)
                    if playground.hasTelemetryTrace {
                        Text("\(playground.telemetryTraceSampleCount)")
                            .font(GuardianTypography.font(.telemetryMono10Semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(.horizontal, GuardianSpacing.md)
                .padding(.vertical, GuardianSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(GuardianPointerPlainButtonStyle())
            .guardianPointerOnHover()
            .help("Position and heading changes vs formation slots — for MRE tuning analysis")

            if showTelemetryTrace {
                VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                    HStack(spacing: GuardianSpacing.sm) {
                        Text("Records start pose, movement, slot target, and primary heading each tick something changes.")
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        GuardianNeutralBorderedButton(
                            systemImage: "doc.on.doc",
                            help: "Copy telemetry trace (plain text + JSONL)",
                            action: { copyTelemetryTraceToPasteboard() }
                        )
                        .disabled(!playground.hasTelemetryTrace)
                        .guardianPointerOnHover()
                    }

                    if playground.hasTelemetryTrace {
                        ScrollView {
                            Text(playground.telemetryTraceClipboardExport())
                                .font(GuardianTypography.font(.telemetryMono10Semibold))
                                .foregroundStyle(theme.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                    } else {
                        Text("Apply or reform formation to start recording. Samples appear when position, heading, slot, or movement changes.")
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, GuardianSpacing.md)
                .padding(.bottom, GuardianSpacing.cardBodyInset)
            }
        }
    }

    private func copyTelemetryTraceToPasteboard() {
        let text = playground.telemetryTraceClipboardExport()
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        toastCenter.show("Telemetry trace copied", style: .success, duration: 2)
    }

    private var logsTabHeader: some View {
        HStack(spacing: GuardianSpacing.sm) {
            Text("Formation logs")
                .font(GuardianTypography.font(.sectionHeadingSemibold))
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: GuardianSpacing.xs)
            GuardianNeutralBorderedButton(
                systemImage: "doc.on.doc",
                help: "Copy all formation log lines to the clipboard",
                action: { copyFormationLogsToPasteboard() }
            )
            .disabled(playground.logLines.isEmpty)
            .guardianPointerOnHover()
        }
        .padding(.horizontal, GuardianSpacing.md)
        .padding(.top, GuardianSpacing.cardBodyInset)
        .padding(.bottom, GuardianSpacing.xs)
    }

    private func copyFormationLogsToPasteboard() {
        let text = FormationsPlaygroundLogExport.plainText(from: playground.logLines)
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        toastCenter.show("Formation logs copied", style: .success, duration: 2)
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

    private var simsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                if playground.slots.isEmpty {
                    Text("No simulators in the squad yet. Spawn from Controls.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(playground.slots.enumerated()), id: \.element.id) { index, slot in
                        simSlotCard(index: index, slot: slot)
                    }
                }
            }
            .padding(.horizontal, GuardianSpacing.md)
            .padding(.vertical, GuardianSpacing.cardBodyInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func simSlotCard(index: Int, slot: FormationsPlaygroundSlotState) -> some View {
        GuardianSimulatorSlotCardView(
            title: index == 0 ? "Primary" : "Wingman \(index)",
            slot: slot,
            fleetLink: fleetLink,
            sitl: sitl,
            showRetry: playground.shouldOfferSimulatorRetry(slot: slot),
            retryButtonTitle: playground.retryButtonTitle(for: slot),
            showReplace: playground.canReplaceSlot(slot),
            cardActionsLocked: playground.cardActionsLocked,
            onInspect: { vehicleID, fallback in
                calibrationContext = FormationsCalibrationContext(
                    vehicleID: vehicleID,
                    fallback: fallback
                )
            },
            onRetry: {
                Task { @MainActor in
                    await playground.retrySimulatorConnection(
                        slotID: slot.id,
                        missionControl: missionControl
                    )
                    syncMapContent()
                }
            },
            onReplace: {
                Task { @MainActor in
                    await playground.replaceSlot(
                        slotID: slot.id,
                        missionControl: missionControl
                    )
                    syncMapContent()
                }
            }
        )
    }

    @ViewBuilder
    private func formationControl<Content: View>(
        title: String,
        help: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text(title)
                .font(GuardianTypography.font(.disclosureRowTitle))
                .foregroundStyle(theme.textPrimary)
            Text(help)
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                control()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
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
        geometry.formationSlotGroupMapEdit = playground.buildFormationSlotGroupMapEdit(fleetLink: fleetLink)
        mapModel.applyMapContent(
            routeGeometry: geometry,
            vehicleMarkers: playground.buildAllMapMarkers(fleetLink: fleetLink)
        )
    }

    private func syncMapContent() {
        playground.refreshConnectedSimCount(fleetLink: fleetLink)
        var geometry = mapModel.routeGeometry
        geometry.formationSlotGroupMapEdit = playground.buildFormationSlotGroupMapEdit(fleetLink: fleetLink)
        mapModel.applyMapContent(
            routeGeometry: geometry,
            vehicleMarkers: playground.buildAllMapMarkers(fleetLink: fleetLink)
        )
    }

    private func syncMapMarkers() {
        playground.refreshConnectedSimCount(fleetLink: fleetLink)
        mapModel.applyVehicleMarkersOnly(playground.buildAllMapMarkers(fleetLink: fleetLink))
    }

    /// Full map publish for slot-edit chrome (handles + clones). Avoid during an active drag — rebuilds Leaflet handles.
    private func syncFormationSlotMapEditChrome() {
        playground.refreshConnectedSimCount(fleetLink: fleetLink)
        var geometry = mapModel.routeGeometry
        geometry.formationSlotGroupMapEdit = playground.buildFormationSlotGroupMapEdit(fleetLink: fleetLink)
        mapModel.applyMapContent(
            routeGeometry: geometry,
            vehicleMarkers: playground.buildAllMapMarkers(fleetLink: fleetLink)
        )
    }

    private func fitMapToPlayground(mapModel: GuardianMapModel? = nil) {
        syncMapContent()
        let model = mapModel ?? self.mapModel
        model.fitToVisible(
            points: playground.formationMapFitPoints(fleetLink: fleetLink),
            style: .formationContent
        )
    }

    // MARK: - Vehicle mode (skill training)

    private var vehicleSidePanelToolbar: some View {
        HStack(spacing: GuardianSpacing.sm) {
            Picker("Panel", selection: $trainingSidePanelTab) {
                ForEach(TrainingSidePanelTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: GuardianSpacing.sm)

            if training.vehicleID != nil {
                GuardianThemedButton(
                    accent: .primary,
                    surface: .solid,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !training.cardActionsLocked,
                    contentSizing: .squareToolbarCell,
                    action: {
                        Task { await training.resetEpisode() }
                    },
                    label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                    }
                )
                .help("Reset to task start pose")
                .guardianPointerOnHover()
            }
            GuardianThemedButton(
                accent: .primary,
                surface: .solid,
                size: .small,
                shape: .cornered,
                isEnabled: !training.cardActionsLocked && fleetLink.isSimulateEnabled,
                contentSizing: .squareToolbarCell,
                action: {
                    Task { @MainActor in
                        await training.spawnTrainingSim(missionControl: missionControl)
                        refreshTrainingMap()
                    }
                },
                label: {
                    Image(systemName: training.cardActionsLocked ? "hourglass" : "wand.and.stars")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                }
            )
            .help(vehicleSpawnButtonHelp)
            .guardianPointerOnHover()

            if training.vehicleID != nil {
                GuardianThemedButton(
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !training.cardActionsLocked,
                    contentSizing: .squareToolbarCell,
                    action: {
                        Task { @MainActor in
                            await training.stopSimulator()
                            refreshTrainingMap()
                        }
                    },
                    label: {
                        Image(systemName: "trash")
                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                    }
                )
                .help("Stop simulator")
                .guardianPointerOnHover()
            }
        }
        .padding(.horizontal, GuardianSpacing.md)
        .padding(.vertical, GuardianSpacing.sm)
    }

    private var vehicleSpawnButtonHelp: String {
        if !fleetLink.isSimulateEnabled {
            return "Turn on Simulate in the top bar before spawning."
        }
        if training.vehicleID != nil {
            return "Respawn training simulator"
        }
        return "Spawn training simulator"
    }

    private var vehicleControlsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                if !fleetLink.isSimulateEnabled {
                    Text("Turn on Simulate in the top bar to train on simulators.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textSecondary)
                }

                Text(training.statusText)
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let slot = training.simulatorSlot {
                    GuardianSimulatorSlotCardView(
                        title: "Training vehicle",
                        slot: slot,
                        fleetLink: fleetLink,
                        sitl: sitl,
                        showRetry: training.shouldOfferSimulatorRetry(slot: slot),
                        retryButtonTitle: training.retryButtonTitle(for: slot),
                        showReplace: training.canReplaceSlot(slot),
                        cardActionsLocked: training.cardActionsLocked,
                        onInspect: { vehicleID, fallback in
                            calibrationContext = FormationsCalibrationContext(
                                vehicleID: vehicleID,
                                fallback: fallback
                            )
                        },
                        onRetry: {
                            Task { @MainActor in
                                await training.retrySimulatorConnection(missionControl: missionControl)
                                refreshTrainingMap()
                            }
                        },
                        onReplace: {
                            Task { @MainActor in
                                await training.replaceSimulator(missionControl: missionControl)
                                refreshTrainingMap()
                            }
                        }
                    )
                }

                trainingRow(title: "Vehicle class", help: "SITL type for training.") {
                    Picker("Vehicle class", selection: $training.vehicleClass) {
                        ForEach(TrainingVehicleClass.trainingPanelSelectableCases) { kind in
                            Text(kind.displayTitle).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(vehicleControlsLocked)
                }

                trainingRow(title: "Task", help: training.taskKind.summary) {
                    Picker("Task", selection: $training.taskKind) {
                        ForEach(TrainingTaskKind.allCases) { task in
                            Text(task.displayTitle).tag(task)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(vehicleControlsLocked)
                }

                trainingRow(
                    title: "Environment",
                    help: training.selectedEnvironment?.manifest.description
                        ?? "Gazebo world package for training spawn."
                ) {
                    if training.availableEnvironments.isEmpty {
                        Text("No environments installed.")
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textSecondary)
                    } else {
                        Picker("Environment", selection: $training.selectedEnvironmentID) {
                            ForEach(training.availableEnvironments, id: \.id) { env in
                                Text(env.manifest.displayName).tag(env.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(vehicleControlsLocked)
                    }
                }

                if !training.usesGazeboTrainingViewport {
                    trainingRow(
                        title: "Adjust target slot on map",
                        help: "Drag the gold diamond to move the slot. Drag the handle on the circle to set heading. Changing the task does not move the slot."
                    ) {
                        Toggle(
                            isOn: Binding(
                                get: { training.isTargetSlotMapEditEnabled },
                                set: { enabled in
                                    training.setTargetSlotMapEditEnabled(enabled)
                                    if enabled {
                                        syncTrainingTargetSlotMapEdit()
                                    } else {
                                        refreshTrainingMap()
                                    }
                                }
                            )
                        ) {
                            EmptyView()
                        }
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("Adjust target slot on map")
                        .disabled(trainingTargetSlotMapEditLocked)
                    }
                }

                vehicleForbiddenControlsSection
            }
            .padding(10)
        }
    }

    private var vehicleForbiddenControlsSection: some View {
        let supported = Array(
            Utilities.training.supportedAxes(vehicleType: training.vehicleClass.fleetVehicleType)
        ).sorted { $0.displayTitle < $1.displayTitle }
        return VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text("Forbidden controls")
                .font(GuardianTypography.font(.disclosureRowTitle))
                .foregroundStyle(theme.textPrimary)
            Text("Turn on a control to forbid it during autonomous teaching. All controls are allowed until you mark one forbidden.")
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(supported, id: \.self) { axis in
                Toggle(
                    axis.displayTitle,
                    isOn: Binding(
                        get: { training.forbiddenAxes.contains(axis) },
                        set: { on in
                            if on {
                                training.forbiddenAxes.insert(axis)
                            } else {
                                training.forbiddenAxes.remove(axis)
                            }
                        }
                    )
                )
                .disabled(vehicleControlsLocked)
            }
        }
    }

    private var vehicleLogsTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                if training.logLines.isEmpty {
                    Text("Teaching logs appear here.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                } else {
                    ForEach(training.logLines) { line in
                        Text(line.message)
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(10)
        }
    }

    private var vehicleSkillTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                if let skill = training.promotedSkill {
                    Text("Promoted skill")
                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                    Text(skill.summary)
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textSecondary)
                    Text(
                        String(
                            format: "Score: %.1f m, heading %.0f°",
                            skill.score.positionErrorM,
                            skill.score.headingErrorDeg
                        )
                    )
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    Text("\(skill.segments.count) segments")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                    ForEach(Array(skill.segments.enumerated()), id: \.offset) { index, segment in
                        Text(vehicleSegmentDescription(segment, index: index))
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Toggle("Auto-export brain pack on promote", isOn: $training.autoExportBrainOnPromote)
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textSecondary)

                    if training.promotedSkill != nil {
                        if panelMode == .formation {
                            Text("Formation rehearsal metadata (shape, spacing, sim count) is included in the brain pack squad profile.")
                                .font(GuardianTypography.font(.denseFootnoteRegular))
                                .foregroundStyle(theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if training.exportPlannerHintsSnapshot() != nil {
                            Text("Nav2 or Aerostack2 lab overlays (path source, layout, environment) are included in planner hints.")
                                .font(GuardianTypography.font(.denseFootnoteRegular))
                                .foregroundStyle(theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                        GuardianPrimaryProminentButton(title: "Export brain pack…") {
                            training.exportPromotedBrainPack(squadProfile: brainExportSquadProfile())
                        }
                        if training.lastExportedBrainId != nil {
                            GuardianThemedButton(
                                title: "Export new version…",
                                accent: .primary,
                                surface: .outline
                            ) {
                                training.exportPromotedBrainPackNewVersion(squadProfile: brainExportSquadProfile())
                            }
                        }
                    }
                    .padding(.top, GuardianSpacing.sm)
                } else {
                    Text("No promoted skill for this task and vehicle class yet. Run autonomous teaching.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(10)
        }
        .onAppear { training.loadPromotedSkill() }
    }

    @ViewBuilder
    private func trainingRow<Content: View>(
        title: String,
        help: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text(title)
                .font(GuardianTypography.font(.disclosureRowTitle))
                .foregroundStyle(theme.textPrimary)
            Text(help)
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            control()
        }
    }

    private func vehicleSegmentDescription(_ segment: TrainingControlSegment, index: Int) -> String {
        var parts: [String] = []
        if abs(segment.bodyForwardMS) > 0.02 { parts.append(String(format: "fwd %.2f m/s", segment.bodyForwardMS)) }
        if abs(segment.bodyRightMS) > 0.02 { parts.append(String(format: "right %.2f m/s", segment.bodyRightMS)) }
        if abs(segment.yawspeedDegS) > 0.5 { parts.append(String(format: "yaw %.0f°/s", segment.yawspeedDegS)) }
        if parts.isEmpty { parts.append("hold") }
        return "\(index + 1). \(parts.joined(separator: ", ")) · \(String(format: "%.1f", segment.durationS)) s"
    }

    private func refreshTrainingMap() {
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
        geometry.formationSlotGroupMapEdit = training.buildTargetSlotMapEdit()
        if training.nav2PlannedPath.count >= 2 {
            geometry.debugOverlayPolylines = [training.nav2PlannedPath]
        }
        mapModel.applyMapContent(routeGeometry: geometry, vehicleMarkers: buildTrainingMapMarkers())
        fitTrainingMap()
    }

    private func syncTrainingTargetSlotMapEdit() {
        var geometry = mapModel.routeGeometry
        geometry.preserveView = true
        geometry.formationSlotGroupMapEdit = training.buildTargetSlotMapEdit()
        if training.nav2PlannedPath.count >= 2 {
            geometry.debugOverlayPolylines = [training.nav2PlannedPath]
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
        guard let layout = training.taskLayout else { return [] }
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
        if let vid = training.vehicleID,
           let hub = fleetLink.hubTelemetry(forVehicleID: vid),
           let lat = hub.latitudeDeg,
           let lon = hub.longitudeDeg {
            let vType = fleetLink.vehicleModel(forVehicleID: vid)?.data.vehicleType
                ?? training.vehicleClass.fleetVehicleType
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
        guard let layout = training.taskLayout else { return }
        var points: [(Double, Double)] = [
            (layout.start.latitudeDeg, layout.start.longitudeDeg),
            (layout.goal.latitudeDeg, layout.goal.longitudeDeg),
        ]
        if let vid = training.vehicleID,
           let hub = fleetLink.hubTelemetry(forVehicleID: vid),
           let lat = hub.latitudeDeg,
           let lon = hub.longitudeDeg {
            points.append((lat, lon))
        }
        let model = mapModel ?? self.mapModel
        model.fitToVisible(points: points, style: .formationContent)
    }

    private func brainExportSquadProfile() -> GuardianBrainPackSquadProfile? {
        guard panelMode == .formation else { return nil }
        let vehicleClass: TrainingVehicleClass = switch playground.vehicleClass {
        case .uavCopter: .uavCopter
        case .ugvWheeled: .ugvWheeled
        case .ugvTracked: .ugvTracked
        }
        return GuardianBrainPackBuilder.squadProfile(
            formation: playground.formation,
            shape: playground.shape,
            vehicleClass: vehicleClass,
            simCount: playground.simCount
        )
    }
}
