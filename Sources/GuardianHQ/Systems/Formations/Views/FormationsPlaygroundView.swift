import AppKit
import SwiftUI

private enum FormationsSidePanelTab: String, CaseIterable, Identifiable {
    case controls = "Controls"
    case sims = "Sims"
    case logs = "Logs"

    var id: String { rawValue }
}

/// Formation sandbox (Simulate on): map at default SIM spawn + live OFFBOARD/GUIDED spacing.
struct FormationsPlaygroundView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var missionControl: MissionControlStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    @StateObject private var playground = FormationsPlaygroundController()

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var toastCenter: ToastCenter

    @State private var sidePanelTab: FormationsSidePanelTab = .controls
    @State private var calibrationContext: FormationsCalibrationContext?
    @State private var showTelemetryTrace = false

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var controlsLocked: Bool {
        playground.isBusy || playground.phase != .idle
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let mapWidth = geo.size.width * 0.7
                HStack(spacing: 0) {
                    mapColumn
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
            playground.attach(
                fleetLink: fleetLink,
                sitl: sitl,
                spawnDefaults: generalSettings.simSpawnDefaults,
                simulationPlatform: generalSettings.defaultSimulationPlatform
            )
            playground.syncFromFleetOnAppear(fleetLink: fleetLink)
            refreshMapHome()
            fitMapToPlayground()
        }
        .onDisappear {
            playground.leavePanel()
        }
        .onChange(of: generalSettings.simSpawnDefaults) { defaults in
            playground.attach(
                fleetLink: fleetLink,
                sitl: sitl,
                spawnDefaults: defaults,
                simulationPlatform: generalSettings.defaultSimulationPlatform
            )
            refreshMapHome()
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
            playground.formationSettingsDidChange(fleetLink: fleetLink)
            if playground.isSlotGroupMapEditEnabled {
                syncFormationSlotMapEditChrome()
            } else {
                syncMapContent()
            }
        }
        .onChange(of: playground.shape) { _ in
            playground.formationSettingsDidChange(fleetLink: fleetLink)
            if playground.isSlotGroupMapEditEnabled {
                syncFormationSlotMapEditChrome()
            } else {
                syncMapContent()
            }
        }
        .onReceive(fleetLink.$hubFleetTelemetryTick) { _ in
            playground.refreshConnectedSimCount(fleetLink: fleetLink)
            syncMapMarkers()
        }
        .onChange(of: sidePanelTab) { tab in
            if tab == .sims {
                playground.refreshConnectedSimCount(fleetLink: fleetLink)
            }
        }
    }

    @StateObject private var mapModel = GuardianMapModel()

    private struct FormationsCalibrationContext: Identifiable {
        var id: String { vehicleID }
        let vehicleID: String
        let fallback: FleetVehicleModel?
    }

    private var mapColumn: some View {
        GuardianMapView(
            model: mapModel,
            toolbar: GuardianMapToolbarOptions(
                mapResetAction: { model in
                    fitMapToPlayground(mapModel: model)
                }
            ),
            onFormationSlotGroupCenterMoved: { lat, lon in
                playground.previewFormationSlotGroupCenter(lat: lat, lon: lon)
                syncFormationSlotMapEditChrome()
            },
            onFormationSlotGroupHeadingMoved: { headingDeg in
                playground.previewFormationSlotGroupHeading(headingDeg: headingDeg)
                syncFormationSlotMapEditChrome()
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var sidePanel: some View {
        VStack(spacing: 0) {
            sidePanelToolbar

            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)

            Group {
                switch sidePanelTab {
                case .controls:
                    controlsTab
                case .sims:
                    simsTab
                case .logs:
                    logsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(theme.backgroundBase)
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
                    .disabled(controlsLocked)
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
                        .disabled(controlsLocked)
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
        let lifecycle = lifecycleStatus(for: slot)
        let preflight = preflightStatusPresentation(for: slot)
        let vehicleModel = slot.vehicleID.flatMap { fleetLink.vehicleModel(forVehicleID: $0) }
        let statusColor = lifecycle?.color.uiColor ?? theme.borderSubtle

        return VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xs) {
                Text(index == 0 ? "Primary" : "Wingman \(index)")
                    .font(GuardianTypography.font(.denseCaption12Medium))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: GuardianSpacing.xsTight)
                if let shortID = vehicleModel?.displayShortID, !shortID.isEmpty {
                    Text(shortID)
                        .font(GuardianTypography.font(.telemetryMono10Semibold))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
                if let lifecycle {
                    Text(lifecycle.compactTwoWordStatus)
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(lifecycle.color.uiColor.opacity(0.95))
                } else {
                    Text("Link connecting")
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(Color.yellow.opacity(0.95))
                }
                Spacer(minLength: 0)
                Text(preflight.twoWordLabel)
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(preflight.color.opacity(0.95))
            }

            if let detail = preflight.detailLine {
                Text(detail)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let lifecycle {
                Text(lifecycle.sentence)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            simSlotActionBar(
                slot: slot,
                vehicleModel: vehicleModel,
                lifecycle: lifecycle
            )
        }
        .padding(GuardianSpacing.sm)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                .strokeBorder(statusColor.opacity(0.55), lineWidth: 1)
        }
    }

    private func simSlotActionBar(
        slot: FormationsPlaygroundSlotState,
        vehicleModel: FleetVehicleModel?,
        lifecycle: VehicleLifecycleStatus?
    ) -> some View {
        let showRetry = playground.shouldOfferRetryPreflight(slot: slot, fleetLink: fleetLink)
        let showReplace = playground.canReplaceSlot(slot)
        let actionsEnabled = !playground.isBusy

        return HStack(spacing: GuardianSpacing.xs) {
            if let vehicleID = slot.vehicleID {
                GuardianThemedButton(
                    accent: .neutral,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: actionsEnabled,
                    contentSizing: .squareToolbarCell,
                    action: {
                        calibrationContext = FormationsCalibrationContext(
                            vehicleID: vehicleID,
                            fallback: vehicleModel
                        )
                    },
                    label: {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                    }
                )
                .help("Open Vehicle Inspector (calibration, preflight, telemetry)")
                .guardianPointerOnHover()
            }
            if showRetry {
                GuardianThemedButton(
                    title: "Retry",
                    accent: .primary,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: actionsEnabled,
                    action: {
                        Task {
                            await playground.retryPreflight(
                                slotID: slot.id,
                                missionControl: missionControl
                            )
                            syncMapContent()
                        }
                    }
                )
                .help("Run preflight again on this simulator")
                .guardianPointerOnHover()
            }
            if showReplace {
                GuardianThemedButton(
                    title: "Replace",
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: actionsEnabled,
                    action: {
                        Task {
                            await playground.replaceSlot(
                                slotID: slot.id,
                                missionControl: missionControl
                            )
                            syncMapContent()
                        }
                    }
                )
                .help(
                    slot.linkReady
                        ? "Stop this simulator and spawn a new one at this squad position"
                        : "Stop the stuck simulator and spawn a new one at this squad position"
                )
                .guardianPointerOnHover()
            }
            Spacer(minLength: 0)
        }
    }

    private struct PreflightStatusPresentation {
        let twoWordLabel: String
        let color: Color
        let detailLine: String?
    }

    private func preflightStatusPresentation(for slot: FormationsPlaygroundSlotState) -> PreflightStatusPresentation {
        guard slot.linkReady else {
            return PreflightStatusPresentation(
                twoWordLabel: "Not connected",
                color: GuardianSemanticColors.warningStroke,
                detailLine: "Use Replace to stop this SITL and spawn a new simulator."
            )
        }
        if let passed = slot.preflightPassed {
            if passed {
                return PreflightStatusPresentation(
                    twoWordLabel: "Preflight passed",
                    color: GuardianSemanticColors.successStroke,
                    detailLine: slot.preflightDetail
                )
            }
            return PreflightStatusPresentation(
                twoWordLabel: "Preflight failed",
                color: GuardianSemanticColors.dangerStroke,
                detailLine: slot.preflightDetail ?? "Preflight failed"
            )
        }
        return PreflightStatusPresentation(
            twoWordLabel: "Preflight pending",
            color: GuardianSemanticColors.warningStroke,
            detailLine: "Run spawn or Retry preflight"
        )
    }

    private func lifecycleStatus(for slot: FormationsPlaygroundSlotState) -> VehicleLifecycleStatus? {
        guard let inst = sitl.instances.first(where: { $0.id == slot.sitlSessionID }) else { return nil }
        let resolvedVehicleID = fleetLink.vehicleID(forSystemID: inst.mavlinkSystemID)
            ?? slot.vehicleID
            ?? inst.guardianVehicleStreamKey
        let model = fleetLink.vehicleModel(forVehicleID: resolvedVehicleID)
        if let code = inst.lastExitCode, !inst.isAlive {
            return VehicleLifecycleStatus(
                stage: .failed,
                sentenceOverride:
                    "The simulator exited with code \(code), so telemetry is unavailable until this vehicle is restarted."
            )
        }
        if let explicit = model?.collections.lifecycleStatus ?? fleetLink.vehicleStatus(forVehicleID: resolvedVehicleID) {
            return explicit
        }
        if model?.data.telemetry != nil {
            return VehicleLifecycleStatus(stage: .live)
        }
        if inst.isAlive {
            return VehicleLifecycleStatus(stage: .connecting)
        }
        return VehicleLifecycleStatus(stage: .stopped)
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
}
