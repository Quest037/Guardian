import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Spacing and widths for mission setup / roster prep.
/// Tune here when adding sim battery, pre-place coordinates, staging waypoints, or other per-slot controls.
private enum MissionRunPrepLayout {
    static let setupScrollPaddingH: CGFloat = 10
    static let setupScrollPaddingV: CGFloat = 10
    static let setupBlockSpacing: CGFloat = 10
    static let taskCardPadding: CGFloat = 22
    static let taskCardInnerSpacing: CGFloat = 18
    static let tasksOuterSpacing: CGFloat = 22
    /// Former default ~200pt; +50% for wider prep columns.
    static let rosterGridMinWidth: CGFloat = 300
    static let rosterGridSpacing: CGFloat = 18
    static let scheduleCardPadding: CGFloat = 20
    static let scheduleCardSpacing: CGFloat = 16
    static let rosterSlotPadding: CGFloat = 10
    static let rosterSlotStackSpacing: CGFloat = 10
    static let rosterSlotIconSize: CGFloat = 44
    static let rosterSlotIconRowSpacing: CGFloat = 14
    static let rosterTitleStackSpacing: CGFloat = 3
    /// Wingman / reserve visual indent under a primary (matches Missions roster nesting).
    static let rosterSlotWingmanIndent: CGFloat = 14
    static let rosterSlotCornerRadius: CGFloat = 14
    static let rosterSlotMinHeight: CGFloat = 100
    static let taskCardCornerRadius: CGFloat = 12
    /// Below this width, Timing tab stacks Schedule and Tasks vertically.
    static let timingScheduleTasksStackBreakpoint: CGFloat = 720
    /// Below this width, Rosters tab stacks map above the accordion.
    static let rostersMapAccordionStackBreakpoint: CGFloat = 780
}

/// Matches the golden-angle route line hue in `OSMMapView` so route lines and progress bars align visually.
private enum MissionTaskMapColor {
    static func hueDegrees(forTaskIndex index: Int) -> Double {
        (Double(index) * 137.508).truncatingRemainder(dividingBy: 360)
    }

    static func swiftUIColor(forTaskIndex index: Int) -> Color {
        Color(hue: hueDegrees(forTaskIndex: index) / 360, saturation: 0.88, brightness: 0.62)
    }
}

struct MissionControlView: View {
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var controlStore: MissionControlStore
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var generalSettings: GeneralSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedRunID: UUID?
    @State private var showingAddRunSheet = false

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Group {
            if let run = selectedRun {
                MissionRunDetailView(
                    run: run,
                    missionStore: missionStore,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    controlStore: controlStore,
                    generalSettings: generalSettings,
                    defaultLiveMapStyle: generalSettings.defaultMapTileStyle,
                    onBack: { selectedRunID = nil },
                    onUpdate: { controlStore.updateRun($0) },
                    onStart: { run in
                        controlStore.updateRun(run)
                        let mission = missionStore.missions.first { $0.id == run.missionId }
                        controlStore.startRun(
                            id: run.id,
                            mission: mission,
                            fleetLink: fleetLink,
                            sitl: sitl,
                            missionsProvider: { missionStore.missions }
                        )
                    },
                    onDelete: { controlStore.deleteRun(id: $0) }
                )
            } else {
                missionRunGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundBase)
        .sheet(isPresented: $showingAddRunSheet) {
            AddMissionRunSheet(
                missionStore: missionStore,
                onCreateRun: { mission in
                    let run = controlStore.createRun(from: mission)
                    selectedRunID = run.id
                }
            )
        }
    }

    /// Same layout as Vehicles (`VehiclesView.centeredEmptyStateBlock`): icon 44pt medium gray, title 20pt semibold white, subtitle 14pt gray, max 480pt, padding 32, centered in the pane.
    private func centeredEmptyStateBlock(
        systemImage: String,
        title: String,
        @ViewBuilder subtitle: () -> Text
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                subtitle()
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            .padding(32)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedRun: MissionRunEnvironment? {
        guard let selectedRunID else { return nil }
        return controlStore.runs.first(where: { $0.id == selectedRunID })
    }

    private var missionRunGrid: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mission Runs")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button("Add Run") {
                    showingAddRunSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(theme.backgroundRaised)

            if controlStore.runs.isEmpty {
                centeredEmptyStateBlock(
                    systemImage: "slider.horizontal.3",
                    title: "No mission running",
                    subtitle: {
                        Text("Add a run from a mission template to begin.")
                    }
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(controlStore.runs) { run in
                            Button {
                                selectedRunID = run.id
                            } label: {
                                MissionRunCard(
                                    run: run,
                                    isSelected: selectedRunID == run.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .background(theme.backgroundBase)
            }
        }
    }
}

private struct MissionRunStatusBadge: View {
    let status: MissionRunStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.system(size: 10, weight: .heavy))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch status {
        case .running:
            return GuardianSemanticColors.successBackground
        case .setup:
            return GuardianSemanticColors.warningBackground
        case .paused, .completed:
            return GuardianSemanticColors.neutralBadgeBackground
        }
    }

    private var foreground: Color {
        switch status {
        case .running:
            return GuardianSemanticColors.successForeground
        case .setup:
            return GuardianSemanticColors.warningForeground
        case .paused, .completed:
            return GuardianSemanticColors.neutralBadgeForeground
        }
    }
}

private struct MissionRunCard: View {
    let run: MissionRunEnvironment
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(run.missionName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textPrimary)
                    .lineLimit(1)
                Spacer()
                MissionRunStatusBadge(status: run.status)
            }

            HStack(spacing: 8) {
                Image(systemName: scheduleIconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textTertiary)
                Text(scheduleSummaryText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if run.pendingGracefulCycleStop {
                    Text("Stopping after cycle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GuardianSemanticColors.warningForeground)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(GuardianSemanticColors.warningBackground)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 8) {
                statPill(label: "Slots", value: "\(run.assignments.count)")
                statPill(label: "Assigned", value: "\(assignedSlots)")
                statPill(label: "Unassigned", value: "\(unassignedSlots)")
            }

            if let progressLabel {
                VStack(alignment: .leading, spacing: 5) {
                    Text(progressLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GuardianDynamicColors.textTertiary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(GuardianDynamicColors.borderSubtle)
                            Capsule()
                                .fill(progressFillColor)
                                .frame(width: geo.size.width * progressFraction)
                        }
                    }
                    .frame(height: 5)
                }
            }

            Divider()
                .overlay(GuardianDynamicColors.borderSubtle)

            Text(timelineSummaryText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(GuardianDynamicColors.textTertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? GuardianDynamicColors.backgroundElevated : GuardianDynamicColors.backgroundRaised)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected
                        ? Color.blue.opacity(0.7)
                        : GuardianDynamicColors.borderSubtle,
                    lineWidth: isSelected ? 1.6 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var scheduleIconName: String { "calendar.badge.clock" }

    private var scheduleSummaryText: String {
        if let start = run.oneOffStartAt {
            return "Starts \(start.formatted(date: .omitted, time: .shortened))"
        }
        return "Starts after preflight"
    }

    private var assignedSlots: Int {
        run.assignments.filter(\.hasFleetOrLegacyAssignment).count
    }

    private var unassignedSlots: Int {
        max(0, run.assignments.count - assignedSlots)
    }

    private var progressLabel: String? {
        guard let cycles = run.reportCyclesCompleted else { return nil }
        return "\(cycles) mission cycle\(cycles == 1 ? "" : "s")"
    }

    private var progressFraction: CGFloat {
        guard run.reportCyclesCompleted != nil else { return 0 }
        return 1
    }

    private var progressFillColor: Color {
        switch run.status {
        case .running:
            return GuardianSemanticColors.successForeground.opacity(0.95)
        case .setup:
            return GuardianDynamicColors.textSecondary.opacity(0.85)
        case .paused:
            return GuardianDynamicColors.textSecondary.opacity(0.9)
        case .completed:
            return GuardianSemanticColors.infoForeground.opacity(0.95)
        }
    }

    private var timelineSummaryText: String {
        switch run.status {
        case .setup:
            return "Created \(run.createdAt.formatted(date: .abbreviated, time: .shortened))"
        case .running, .paused:
            if let startedAt = run.startedAt {
                return "Started \(startedAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Created \(run.createdAt.formatted(date: .abbreviated, time: .shortened))"
        case .completed:
            let completedText = run.completedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown"
            if let startedAt = run.startedAt, let completedAt = run.completedAt {
                let duration = completedAt.timeIntervalSince(startedAt)
                let mins = Int(max(0, duration) / 60)
                return "Completed \(completedText) · \(mins)m"
            }
            return "Completed \(completedText)"
        }
    }

    @ViewBuilder
    private func statPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(GuardianDynamicColors.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// Roster slot card: role + vehicle from fleet picker (Vehicles tab inventory).
private struct MissionControlRosterSlotCard: View {
    let title: String
    let subtitle: String
    /// Class for bundled ``SimulationDevices`` art: roster slot expectation when empty; linked fleet ``FleetVehicleModel`` type when assigned (unless sim-specific basenames apply).
    let vehicleClassForBundledDeviceArt: FleetVehicleType
    /// Slot has a fleet or legacy device binding (chrome, buttons).
    let isAttached: Bool
    /// Extra line under titles (live mode summary, etc.); omits generic sim preset names like “Multirotor”.
    let assignedVehicleDetail: String?
    /// MAVLink bridge battery summary when a fleet vehicle is assigned (`nil` if unassigned).
    let rosterBatterySummary: FleetVehicleOperationalModel.BatterySummary?
    /// `nil` when unassigned or legacy free-text only; `false` = live MAVLink, `true` = built-in sim.
    let assignedFleetIsSimulation: Bool?
    /// ArduPilot / PX4 badge when a fleet vehicle is bound (matches Vehicles grid).
    let autopilotStack: FleetAutopilotStack?
    let simulationImageBasenames: [String]?
    /// Shown under the type glyph when a vehicle is assigned (two-word lifecycle line).
    let lifecycleStatus: VehicleLifecycleStatus?
    /// ``FleetVehicleModel/displayShortID`` when linked (e.g. `UAV-C:1`); `nil` if unresolved.
    let fleetDisplayShortID: String?
    let isSelectedForSetupMap: Bool
    let onSelectForSetupMap: () -> Void
    let onChooseVehicle: () -> Void
    let onRemoveVehicle: () -> Void
    let onInfo: (() -> Void)?

    var body: some View {
        Group {
            if isAttached {
                attachedRosterCardBody
            } else {
                emptyRosterCardBody
            }
        }
        .frame(minHeight: MissionRunPrepLayout.rosterSlotMinHeight, alignment: .topLeading)
        .padding(MissionRunPrepLayout.rosterSlotPadding)
        .background(GuardianDynamicColors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.rosterSlotCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MissionRunPrepLayout.rosterSlotCornerRadius)
                .strokeBorder(
                    isSelectedForSetupMap ? Color.blue.opacity(0.92) : (isAttached ? Color.green.opacity(0.7) : GuardianDynamicColors.borderSubtle),
                    lineWidth: isSelectedForSetupMap ? 2 : (isAttached ? 2 : 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: isAttached ? 4 : 1, y: isAttached ? 1 : 0)
        .contentShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.rosterSlotCornerRadius))
        .onTapGesture {
            onSelectForSetupMap()
        }
    }

    private var emptyRosterCardBody: some View {
        HStack(alignment: .center, spacing: MissionRunPrepLayout.rosterSlotIconRowSpacing) {
            iconTile
                .frame(width: MissionRunPrepLayout.rosterSlotIconSize, height: MissionRunPrepLayout.rosterSlotIconSize)

            VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterTitleStackSpacing) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onChooseVehicle) {
                Text("Choose")
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.bordered)
            .tint(.blue)
            .controlSize(.small)
        }
    }

    private var attachedRosterCardBody: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterSlotStackSpacing) {
            HStack(alignment: .center, spacing: MissionRunPrepLayout.rosterSlotIconRowSpacing) {
                iconTile
                    .frame(width: MissionRunPrepLayout.rosterSlotIconSize, height: MissionRunPrepLayout.rosterSlotIconSize)

                VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterTitleStackSpacing) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GuardianDynamicColors.textPrimary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(GuardianDynamicColors.textSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let stack = autopilotStack {
                    HStack(spacing: 6) {
                        FleetAutopilotStackBadge(stack: stack)
                        if let isSim = assignedFleetIsSimulation {
                            FleetLiveSimBadge(isSimulation: isSim)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 10) {
                    Text(fleetDisplayShortID ?? "—")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GuardianDynamicColors.textPrimary.opacity(0.9))
                        .lineLimit(1)
                        .layoutPriority(1)
                        .help(
                            fleetDisplayShortID.map { "Fleet vehicle: \($0)" }
                                ?? "Fleet vehicle identifier not resolved yet"
                        )

                    if let lifecycleStatus {
                        Text(lifecycleStatus.compactTwoWordStatus)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(lifecycleStatus.color.uiColor.opacity(0.95))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("—")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(GuardianDynamicColors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    rosterSetupBatteryCompact
                }

                if let detail = assignedVehicleDetail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(GuardianDynamicColors.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                Button(action: onChooseVehicle) {
                    Text("Change")
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(.blue)
                .controlSize(.small)

                if let onInfo {
                    Button("Info", action: onInfo)
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer(minLength: 0)

                Button(action: onRemoveVehicle) {
                    Text("Remove")
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
        }
    }

    private var rosterSetupBatteryCompact: some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: rosterBatterySymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(rosterBatteryIconTint)
            Text(rosterBatteryPercentText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(GuardianDynamicColors.textPrimary.opacity(0.94))
                .lineLimit(1)
        }
        .help(rosterBatteryHoverText)
    }

    private var rosterBatteryPercentText: String {
        guard let p = rosterBatterySummary?.percent0to100 else { return "—" }
        return "\(Int(round(p)))%"
    }

    private var rosterBatterySymbol: String {
        if rosterBatterySummary?.isCharging == true {
            return "battery.100.bolt"
        }
        return "battery.100"
    }

    private var rosterBatteryIconTint: Color {
        guard let p = rosterBatterySummary?.percent0to100 else {
            return Color.gray.opacity(0.55)
        }
        if p < 10 {
            return Color.red.opacity(0.92)
        }
        if p < 80 {
            return Color.yellow.opacity(0.95)
        }
        return GuardianSemanticColors.successForeground
    }

    private var rosterBatteryHoverText: String {
        let pct = rosterBatteryPercentText
        let v = rosterBatterySummary?.voltageV.map { String(format: "%.1f V", $0) } ?? "—"
        let a = rosterBatterySummary?.currentA.map { String(format: "%.1f A", $0) } ?? "—"
        return "Battery \(pct), \(v), \(a)"
    }

    private var slotLeadingThumbnailBasenames: [String] {
        if let names = simulationImageBasenames, !names.isEmpty { return names }
        return vehicleClassForBundledDeviceArt.defaultSimulationDeviceImageBasenames
    }

    private var slotLeadingGlyph: some View {
        SimulationDeviceThumbnail(imageBasenames: slotLeadingThumbnailBasenames)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(3)
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.12, blue: 0.14),
                            Color(red: 0.05, green: 0.07, blue: 0.09),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            slotLeadingGlyph
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private enum LiveConsoleMediaTab: Hashable {
    case camera
    case map
}

private enum MissionRunSetupTab: String, CaseIterable, Identifiable, Hashable {
    case timing
    case rosters
    case rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timing: return "Timing"
        case .rosters: return "Rosters"
        case .rules: return "Rules"
        }
    }
}

private struct LiveOverviewMapSignature: Equatable {
    let missionID: UUID?
    let homeCoord: RouteCoordinate?
    let allTasksCoords: [[RouteCoordinate]]
    let markers: [MapVehicleMarker]
}

private struct SetupStagingMapSignature: Equatable {
    let missionID: UUID?
    let homeCoord: RouteCoordinate?
    let allTasksCoords: [[RouteCoordinate]]
    let markers: [MapVehicleMarker]
}

private struct MissionRunDetailView: View {
    @State var run: MissionRunEnvironment
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var controlStore: MissionControlStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    @EnvironmentObject private var sidebarOverlay: SidebarOverlay
    let onBack: () -> Void
    let onUpdate: (MissionRunEnvironment) -> Void
    let onStart: (MissionRunEnvironment) -> Void
    let onDelete: (UUID) -> Void

    @State private var confirmDeleteRun = false
    @State private var setupSelectedAssignmentId: UUID?
    /// Shared model for both the Setup staging map and the Live overview map —
    /// owns the tile style, recenter nonce, and the per-tab content that gets
    /// pushed in via `.task(id:)`.
    @StateObject private var mapModel: GuardianMapModel
    /// Paladin log card: default is reduced height; extended is taller.
    @State private var paladinLogExtended = false
    @State private var liveConsoleMediaTab: LiveConsoleMediaTab = .map
    @ObservedObject private var paladinLogTemplates: PaladinLogTemplateRegistry
    @State private var startPreflightPresented = false
    @State private var rosterInfoSheetTitle: String?
    @State private var rosterInfoVehicleID: String?
    @State private var rosterInfoSitlSessionUUID: String?
    /// Deferred one-off schedule: minutes to add when using **Go** on the running countdown banner.
    @State private var scheduledStartPostponeMinutes: Int = 5
    @State private var confirmSkipScheduledMissionStart = false
    @State private var confirmSkipScheduledMissionMessage = ""
    /// Initial task mission start deferral: minutes to add when using **Go** in the Progress card.
    @State private var taskStartDeferralPostponeMinutes: Int = 5
    @State private var confirmSkipTaskStartDeferral = false
    @State private var confirmSkipTaskStartDeferralTaskID: UUID?
    @State private var confirmSkipTaskStartDeferralMessage = ""
    @State private var setupMainTab: MissionRunSetupTab = .timing
    @State private var rosterSetupExpandedTaskIDs: Set<UUID> = []
    @State private var rosterSetupLegacyMissionRosterExpanded: Bool = true
    init(
        run: MissionRunEnvironment,
        missionStore: MissionStore,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        controlStore: MissionControlStore,
        generalSettings: GeneralSettingsStore,
        defaultLiveMapStyle: MapTileStyle,
        onBack: @escaping () -> Void,
        onUpdate: @escaping (MissionRunEnvironment) -> Void,
        onStart: @escaping (MissionRunEnvironment) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        _run = State(initialValue: run)
        self.missionStore = missionStore
        self.fleetLink = fleetLink
        self.sitl = sitl
        self.controlStore = controlStore
        self.generalSettings = generalSettings
        self.onBack = onBack
        self.onUpdate = onUpdate
        self.onStart = onStart
        self.onDelete = onDelete
        _confirmDeleteRun = State(initialValue: false)
        _setupSelectedAssignmentId = State(initialValue: nil)
        _mapModel = StateObject(
            wrappedValue: GuardianMapModel(
                mapStyle: defaultLiveMapStyle,
                preserveView: true
            )
        )
        _paladinLogTemplates = ObservedObject(wrappedValue: PaladinLogTemplateRegistry.shared)
    }

    private var rosterPickerSpring: Animation {
        .spring(response: 0.36, dampingFraction: 0.88)
    }

    private func presentMissionRosterVehiclePicker(assignmentId: UUID) {
        let anim = rosterPickerSpring
        sidebarOverlay.present(
            title: nil,
            preferredWidth: 420,
            scrimTapDismisses: true,
            animation: anim
        ) {
            MissionRosterVehiclePickerSidebar(
                vehicles: buildMissionPickableVehicles(fleetLink: fleetLink, sitl: sitl),
                rowIsEnabled: { rosterPickDisabledReason($0, assignmentId: assignmentId) == nil },
                rowDisabledReason: { rosterPickDisabledReason($0, assignmentId: assignmentId) },
                onSelect: { v in
                    applyFleetVehicle(v, assignmentId: assignmentId)
                    sidebarOverlay.dismiss(animation: anim)
                },
                onClose: {
                    sidebarOverlay.dismiss(animation: anim)
                }
            )
        }
    }

    private func syncRunFromStore() {
        if let r = controlStore.runs.first(where: { $0.id == run.id }) {
            run = r
        }
    }

    /// Vertical rule between adjacent controls. `Divider()` in an `HStack` stretches to the full row height; a fixed `Rectangle` does not.
    private func compactVerticalControlSeparator() -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 16)
    }

    private func refreshVehicleVoiceNarrativeFromTelemetry() {
        syncRunFromStore()
        guard run.status == .running || run.status == .paused else { return }
        let mission = missionStore.missions.first { $0.id == run.missionId }
        run.systems.logging.ingestVehicleTelemetryNarrative(
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    private func applyStopImmediate() {
        run.attachServices(fleetLink: fleetLink, sitl: sitl)
        run.systems.scheduling.abortNow()
        onUpdate(run)
        syncRunFromStore()
    }

    private func applyStopAfterCycle() {
        run.systems.scheduling.abortAfterCycle()
        onUpdate(run)
        syncRunFromStore()
    }

    private func applyRevokeAbortAfterCycle() {
        run.systems.scheduling.revokeAbortAfterCycle()
        onUpdate(run)
        syncRunFromStore()
    }

    private func applyResetToSetup() {
        controlStore.resetRunToSetup(id: run.id)
        syncRunFromStore()
    }

    private func isSimulationVehicleID(_ vehicleID: String) -> Bool {
        sitl.instances.contains { inst in
            let sid = inst.stackInstanceIndex + 1
            let resolved = fleetLink.vehicleID(forSystemID: sid) ?? "sysid:\(sid)"
            return resolved == vehicleID
        }
    }

    private var assignedSimulationVehicleIDs: [String] {
        Array(
            Set(
                run.assignments.compactMap { assignment in
                    guard let vid = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
                          isSimulationVehicleID(vid)
                    else { return nil }
                    return vid
                }
            )
        )
    }

    /// Mission Control Running owns SIM battery drain policy for this run:
    /// running => drain on, otherwise off.
    private func syncSimBatteryDrainForRunStatus() {
        let enableDrain = (run.status == .running)
        for vehicleID in assignedSimulationVehicleIDs {
            fleetLink.setSimBatteryDrainEnabled(
                vehicleID: vehicleID,
                enabled: enableDrain,
                rate: generalSettings.defaultSimBatteryDrainRate,
                source: "missionControl.runStatus.\(run.status.rawValue)",
                onResult: nil
            )
        }
    }

    private var resolvedMission: Mission? {
        missionStore.missions.first { $0.id == run.missionId }
    }

    private var liveMavlinkTaskContext: (task: RoutePath, missionItemCount: Int)? {
        guard let mission = resolvedMission else { return nil }
        return run.systems.projections.mavlinkMissionProgressContext(mission: mission)
    }

    private var liveMavlinkVehicleID: String? {
        guard let mission = resolvedMission, let ctx = liveMavlinkTaskContext else { return nil }
        let assignment =
            run.assignments.first(where: { $0.taskId == ctx.task.id })
            ?? {
                let enabled = mission.routeMacro.tasks.filter(\.enabled)
                if enabled.count == 1, enabled.first?.id == ctx.task.id {
                    return run.assignments.first(where: { $0.taskId == nil }) ?? run.assignments.first
                }
                return run.assignments.first
            }()
        guard let assignment else { return nil }
        return resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl)
    }

    private var liveMavlinkHub: FleetHubVehicleTelemetry? {
        guard let id = liveMavlinkVehicleID else { return nil }
        return fleetLink.hubTelemetry(forVehicleID: id)
    }

    /// Drives SwiftUI refresh when MAVSDK mission progress updates (not always the same as global `hubTelemetry`).
    private var liveMissionProgressPulseDate: Date? {
        liveMavlinkHub?.lastUpdate
    }

    private var allRosterFilled: Bool {
        run.assignments.allSatisfy(\.hasFleetOrLegacyAssignment)
    }

    private func canStart(referenceNow: Date) -> Bool {
        guard allRosterFilled else { return false }
        if run.oneOffStartAt != nil, run.oneOffScheduledTimeTooFarInPast(referenceNow: referenceNow) {
            return false
        }
        return true
    }

    @ViewBuilder
    private func runSetupActionButtons(referenceNow: Date) -> some View {
        HStack(spacing: 10) {
            Button("Start Run") {
                startPreflightPresented = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(!canStart(referenceNow: referenceNow))

            Button("Delete Run") {
                confirmDeleteRun = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 16) {
                        HStack(spacing: 12) {
                            Button {
                                onBack()
                            } label: {
                                Image(systemName: "arrow.left")
                                    .appIconGlyph()
                            }
                            .buttonStyle(.bordered)
                            .uniformIconButton()

                            Text(run.missionName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(GuardianDynamicColors.textPrimary)
                                .lineLimit(1)

                            if run.status == .setup {
                                Picker("Mission setup", selection: $setupMainTab) {
                                    ForEach(MissionRunSetupTab.allCases) { tab in
                                        Text(tab.title).tag(tab)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(maxWidth: 380)
                                .accessibilityLabel("Mission setup section")
                            }
                        }

                        Spacer(minLength: 8)

                        HStack(spacing: 10) {
                            if run.status == .setup {
                                if run.oneOffStartAt != nil {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        runSetupActionButtons(referenceNow: context.date)
                                    }
                                } else {
                                    runSetupActionButtons(referenceNow: Date())
                                }
                            } else if run.status == .running || run.status == .paused {
                                Menu {
                                    Button("Immediate", role: .destructive) {
                                        applyStopImmediate()
                                    }
                                    Button("After current cycle", role: .destructive) {
                                        applyStopAfterCycle()
                                    }
                                } label: {
                                    Text("Stop run")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .menuStyle(.button)
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.regular)
                            } else if run.status == .completed {
                                Button("Back to setup") {
                                    applyResetToSetup()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .controlSize(.regular)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(GuardianDynamicColors.backgroundRaised)

                    if run.pendingGracefulCycleStop, run.status == .running || run.status == .paused {
                        gracefulStopPendingBanner
                    }
                    if run.status == .running, run.oneOffDeferredExecution != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if let deferred = run.oneOffDeferredExecution {
                                oneOffDeferredExecutionBanner(
                                    deferred: deferred,
                                    now: context.date,
                                    postponeMinutes: $scheduledStartPostponeMinutes,
                                    onPostpone: {
                                        run.systems.scheduling.postponeDeferredOneOffExecutionByMinutes(scheduledStartPostponeMinutes) {
                                            onStart(run)
                                        }
                                        syncRunFromStore()
                                        onUpdate(run)
                                    },
                                    onRequestStartNow: {
                                        if let def = run.oneOffDeferredExecution {
                                            let rough = humanizedRoughTimeUntilScheduledStart(
                                                executeAt: def.executeAt,
                                                from: Date()
                                            )
                                            confirmSkipScheduledMissionMessage =
                                                "This mission is scheduled to start in \(rough). Are you sure you want to start it now?"
                                            confirmSkipScheduledMissionStart = true
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .confirmationDialog(
                    "Start mission now?",
                    isPresented: $confirmSkipScheduledMissionStart,
                    titleVisibility: .visible
                ) {
                    Button("Start now") {
                        run.systems.scheduling.beginDeferredOneOffImmediately()
                        onStart(run)
                        syncRunFromStore()
                        onUpdate(run)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(confirmSkipScheduledMissionMessage)
                }
                .confirmationDialog(
                    "Start this task now?",
                    isPresented: $confirmSkipTaskStartDeferral,
                    titleVisibility: .visible
                ) {
                    Button("Start now") {
                        if let taskID = confirmSkipTaskStartDeferralTaskID {
                            run.systems.scheduling.skipMissionTaskStartDeferral(
                                taskID: taskID,
                                onStartNow: { onStart(run) }
                            )
                        }
                        confirmSkipTaskStartDeferralTaskID = nil
                        syncRunFromStore()
                        onUpdate(run)
                    }
                    Button("Cancel", role: .cancel) {
                        confirmSkipTaskStartDeferralTaskID = nil
                    }
                } message: {
                    Text(confirmSkipTaskStartDeferralMessage)
                }

                if run.status == .setup {
                    Group {
                        if setupMainTab == .rosters {
                            setupRostersTabContent
                                .padding(.horizontal, MissionRunPrepLayout.setupScrollPaddingH)
                                .padding(.vertical, MissionRunPrepLayout.setupScrollPaddingV)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: MissionRunPrepLayout.setupBlockSpacing) {
                                    switch setupMainTab {
                                    case .timing:
                                        setupTimingTabContent
                                    case .rules:
                                        setupRulesTabContent
                                    case .rosters:
                                        EmptyView()
                                    }
                                }
                                .padding(.horizontal, MissionRunPrepLayout.setupScrollPaddingH)
                                .padding(.vertical, MissionRunPrepLayout.setupScrollPaddingV)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if run.status == .completed {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            missionCompletedReportCards
                            completedPaladinLogExportSection
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView {
                        missionLiveConsole
                            .padding(.horizontal, 24)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: fleetLink.hubTelemetry?.lastUpdate) { _ in
                        refreshVehicleVoiceNarrativeFromTelemetry()
                    }
                    .onChange(of: liveMissionProgressPulseDate) { _ in
                        refreshVehicleVoiceNarrativeFromTelemetry()
                    }
                    .onAppear {
                        refreshVehicleVoiceNarrativeFromTelemetry()
                    }
                }
            }
        .background(GuardianDynamicColors.backgroundBase)
        .confirmationDialog(
            "Delete “\(run.missionName)”?",
            isPresented: $confirmDeleteRun,
            titleVisibility: .visible
        ) {
            Button("Delete Run", role: .destructive) {
                let id = run.id
                onDelete(id)
                onBack()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the run from Mission Control. The mission template is not deleted.")
        }
        .sheet(isPresented: $startPreflightPresented) {
            MissionRunStartPreflightSheet(
                run: run,
                fleetLink: fleetLink,
                sitl: sitl,
                controlStore: controlStore,
                onSuccess: {
                    if let mission = resolvedMission {
                        let fleet = buildMissionPickableVehicles(fleetLink: fleetLink, sitl: sitl)
                        controlStore.compileMissionControlPlan(
                            run: run,
                            mission: mission,
                            fleetVehicles: fleet
                        )
                    }
                    run.status = .running
                    let deferOneOff: Bool = {
                        guard let t = run.oneOffStartAt else { return false }
                        return t.timeIntervalSince(Date()) > MissionRunEnvironment.oneOffScheduleTimeTolerance
                    }()
                    if deferOneOff, let executeAt = run.oneOffStartAt {
                        controlStore.updateRun(run)
                        run.systems.scheduling.scheduleDeferredOneOffExecution(executeAt: executeAt) {
                            onStart(run)
                        }
                    } else {
                        onStart(run)
                    }
                    syncRunFromStore()
                },
                onAbandonWithoutStart: {}
            )
        }
        .sheet(isPresented: rosterTelemetryInfoSheetPresented) {
            VehicleTelemetryInfoSheet(
                title: rosterInfoSheetTitle ?? "Vehicle telemetry",
                vehicleID: rosterInfoVehicleID,
                sitlSessionUUID: rosterInfoSitlSessionUUID,
                model: rosterInfoVehicleID.flatMap { fleetLink.vehicleModel(forVehicleID: $0) },
                hub: rosterInfoVehicleID.flatMap { fleetLink.hubTelemetry(forVehicleID: $0) } ?? fleetLink.hubTelemetry
            )
        }
        .onAppear {
            syncRunFromStore()
            mapModel.recenter()
            syncSimBatteryDrainForRunStatus()
            if run.status == .setup {
                pruneStaleRosterFleetAssignmentsIfNeeded()
            }
        }
        .onChange(of: setupMapBoundsSignature) { _ in
            mapModel.recenter()
        }
        .onChange(of: sitlRosterPruneSignature) { _ in
            if run.status == .setup {
                pruneStaleRosterFleetAssignmentsIfNeeded()
            }
        }
        .onChange(of: fleetRosterPruneSignature) { _ in
            if run.status == .setup {
                pruneStaleRosterFleetAssignmentsIfNeeded()
            }
        }
        .onChange(of: run.status) { new in
            syncSimBatteryDrainForRunStatus()
            if new == .setup {
                pruneStaleRosterFleetAssignmentsIfNeeded()
            } else {
                sidebarOverlay.dismiss()
            }
        }
        .onChange(of: setupMainTab) { newTab in
            sidebarOverlay.dismiss()
            if newTab == .rosters, rosterSetupExpandedTaskIDs.isEmpty, let mission = resolvedMission {
                rosterSetupExpandedTaskIDs = Set(mission.routeMacro.tasks.map(\.id))
            }
        }
        .onChange(of: run.assignments) { _ in
            syncSimBatteryDrainForRunStatus()
        }
        .onDisappear {
            sidebarOverlay.dismiss()
            for vehicleID in assignedSimulationVehicleIDs {
                fleetLink.setSimBatteryDrainEnabled(
                    vehicleID: vehicleID,
                    enabled: false,
                    rate: generalSettings.defaultSimBatteryDrainRate,
                    source: "missionControl.viewDisappear",
                    onResult: nil
                )
            }
            onUpdate(run)
        }
    }

    private var rosterTelemetryInfoSheetPresented: Binding<Bool> {
        Binding(
            get: { rosterInfoVehicleID != nil },
            set: { presented in
                guard !presented else { return }
                rosterInfoSheetTitle = nil
                rosterInfoVehicleID = nil
                rosterInfoSitlSessionUUID = nil
            }
        )
    }

    /// SITL instances + aliveness — roster slots drop removed sims.
    private var sitlRosterPruneSignature: String {
        sitl.instances
            .map { "\($0.id.uuidString)|\($0.isAlive)" }
            .sorted()
            .joined(separator: ";")
    }

    /// Fleet vehicle keys + lifecycle stages — roster drops stopped / failed sessions.
    private var fleetRosterPruneSignature: String {
        let keys = fleetLink.vehicleModelsByVehicleID.keys.sorted().joined(separator: ",")
        let stages = fleetLink.vehicleStatusByVehicleID
            .map { "\($0.key):\($0.value.stage.rawValue)" }
            .sorted()
            .joined(separator: ";")
        return "\(keys)|\(stages)"
    }

    private func presentRosterTelemetrySheet(for assignment: MissionRunAssignment) {
        guard let vehicleID = telemetryVehicleID(for: assignment) else { return }
        if let key = assignment.attachedFleetVehicleToken,
           let token = FleetMissionVehicleToken(storageKey: key),
           case .sitl(let uuid) = token,
           let inst = sitl.instances.first(where: { $0.id == uuid })
        {
            rosterInfoSheetTitle = "\(inst.preset.displayName) telemetry"
            rosterInfoVehicleID = vehicleID
            rosterInfoSitlSessionUUID = inst.id.uuidString
        } else {
            rosterInfoSheetTitle = "Live vehicle telemetry"
            rosterInfoVehicleID = vehicleID
            rosterInfoSitlSessionUUID = nil
        }
    }

    /// Clears fleet binding when the vehicle no longer exists in Vehicles or is stopped/failed.
    private func pruneStaleRosterFleetAssignmentsIfNeeded() {
        guard run.status == .setup else { return }
        var changed = false
        for assignment in run.assignments {
            guard assignment.attachedFleetVehicleToken != nil else { continue }
            guard let token = FleetMissionVehicleToken(storageKey: assignment.attachedFleetVehicleToken!) else { continue }

            if case .sitl(let uuid) = token {
                guard sitl.instances.contains(where: { $0.id == uuid }) else {
                    clearFleetVehicle(assignmentId: assignment.id)
                    changed = true
                    continue
                }
            }

            guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl) else {
                clearFleetVehicle(assignmentId: assignment.id)
                changed = true
                continue
            }

            if let stage = fleetLink.vehicleStatus(forVehicleID: vehicleID)?.stage,
               stage == .stopped || stage == .failed
            {
                clearFleetVehicle(assignmentId: assignment.id)
                changed = true
            }
        }
        if changed {
            onUpdate(run)
        }
    }

    private func rosterAutopilotStack(for assignment: MissionRunAssignment) -> FleetAutopilotStack? {
        guard assignment.attachedFleetVehicleToken != nil else { return nil }
        if let vid = telemetryVehicleID(for: assignment),
           let snap = fleetLink.vehicleModel(forVehicleID: vid)?.collections.telemetrySnapshot
        {
            return snap.autopilotStack
        }
        if let key = assignment.attachedFleetVehicleToken,
           let token = FleetMissionVehicleToken(storageKey: key),
           case .sitl(let uuid) = token,
           let inst = sitl.instances.first(where: { $0.id == uuid })
        {
            return FleetAutopilotStack(simulationPlatform: inst.platform)
        }
        return .unknown
    }

    private func rosterLifecycleStatus(for assignment: MissionRunAssignment) -> VehicleLifecycleStatus? {
        guard assignment.attachedFleetVehicleToken != nil else { return nil }
        guard let vid = telemetryVehicleID(for: assignment) else { return nil }
        return fleetLink.vehicleModel(forVehicleID: vid)?.collections.lifecycleStatus
            ?? fleetLink.vehicleStatus(forVehicleID: vid)
    }

    private var gracefulStopPendingBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GuardianSemanticColors.warningForeground)
            Text(
                "Finishing the current run — when it completes, this mission stops. No further loop or continuous cycles will be scheduled."
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(GuardianDynamicColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Keep running") {
                applyRevokeAbortAfterCycle()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.small)
            .help("Cancel the pending stop-after-cycle and clear the queued abort batch.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianSemanticColors.warningBackground.opacity(0.5))
    }

    private func humanizedRoughTimeUntilScheduledStart(executeAt: Date, from now: Date) -> String {
        let secs = max(1, Int(ceil(executeAt.timeIntervalSince(now))))
        if secs < 90 {
            return secs == 1 ? "about 1 second" : "about \(secs) seconds"
        }
        let minutes = (secs + 59) / 60
        if minutes < 120 {
            return minutes == 1 ? "about 1 minute" : "about \(minutes) minutes"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        if remMin == 0 {
            return hours == 1 ? "about 1 hour" : "about \(hours) hours"
        }
        return "about \(hours) h \(remMin) min"
    }

    private func oneOffDeferredExecutionBanner(
        deferred: MissionOneOffDeferredExecution,
        now: Date,
        postponeMinutes: Binding<Int>,
        onPostpone: @escaping () -> Void,
        onRequestStartNow: @escaping () -> Void
    ) -> some View {
        let remaining = max(0, deferred.executeAt.timeIntervalSince(now))
        let total = max(deferred.executeAt.timeIntervalSince(deferred.countdownStartedAt), 0.001)
        let progress = 1 - min(1, max(0, remaining / total))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.cyan.opacity(0.92))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scheduled mission start")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(
                        "Execution begins \(deferred.executeAt.guardianScheduleOnAtPhrase) — in \(formattedOneOffCountdown(seconds: remaining))."
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(alignment: .center, spacing: 8) {
                    Picker("Delay", selection: postponeMinutes) {
                        ForEach(1...30, id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 88, alignment: .leading)
                    Button("Go") {
                        onPostpone()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                    compactVerticalControlSeparator()
                        .padding(.horizontal, 6)
                    Button("Start") {
                        onRequestStartNow()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                }
                .fixedSize(horizontal: true, vertical: true)
                .padding(.top, 1)
            }
            ProgressView(value: progress)
                .tint(Color.cyan.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.14))
    }

    private func formattedOneOffCountdown(seconds: TimeInterval) -> String {
        let s = max(0, Int(ceil(seconds)))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }

    private let liveConsoleCardFill = GuardianDynamicColors.backgroundElevated
    private let liveConsoleCardStroke = GuardianDynamicColors.borderSubtle
    /// Map + camera row: 50% taller than the previous 220pt baseline.
    private let liveConsoleMapCameraRowMinHeight: CGFloat = 330

    /// Running / paused: tabbed camera/map (70%) + progress card (30%), then vehicles and Paladin log.
    private var missionLiveConsole: some View {
        VStack(spacing: 12) {
            missionLiveTopSplitRow
            missionLiveVehicleStatusRow
            missionLiveLogPlaceholder
        }
    }

    /// Segmented camera vs map on the left (~70% width), run progress card on the right (~30%).
    private var missionLiveTopSplitRow: some View {
        let mediaH = liveConsoleMapCameraRowMinHeight
        let tabGap: CGFloat = 8
        let tabBarHeight: CGFloat = 24
        let rowTotal = tabBarHeight + tabGap + mediaH
        let hGap: CGFloat = 12

        return GeometryReader { geo in
            let totalW = geo.size.width
            let usableW = max(0, totalW - hGap)
            let leftW = usableW * 0.7
            let rightW = usableW * 0.3

            HStack(alignment: .top, spacing: hGap) {
                VStack(alignment: .leading, spacing: tabGap) {
                    Picker("Camera or map", selection: $liveConsoleMediaTab) {
                        Text("Camera").tag(LiveConsoleMediaTab.camera)
                        Text("Map").tag(LiveConsoleMediaTab.map)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(height: tabBarHeight)
                    .accessibilityLabel("Camera or map")

                    Group {
                        switch liveConsoleMediaTab {
                        case .camera:
                            missionLiveCameraPlaceholder
                        case .map:
                            missionLiveOverviewMap
                        }
                    }
                    .frame(width: leftW, height: mediaH)
                }
                .frame(width: leftW, height: rowTotal, alignment: .topLeading)

                missionLiveProgressSideCard
                    .frame(width: rightW, height: rowTotal, alignment: .topLeading)
            }
            .frame(width: totalW, height: rowTotal, alignment: .topLeading)
        }
        .frame(height: rowTotal)
        .frame(maxWidth: .infinity)
    }

    private var missionLiveProgressSideCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Progress")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                if let mission = resolvedMission {
                    if run.status == .running,
                       !run.taskStartDeferralByTaskID.isEmpty
                    {
                        TimelineView(.periodic(from: .now, by: 0.25)) { context in
                            missionLiveTaskProgressList(mission: mission, now: context.date)
                        }
                    } else {
                        missionLiveTaskProgressList(mission: mission, now: Date())
                    }
                } else {
                    Text("No mission template")
                        .font(.system(size: 11))
                        .foregroundStyle(GuardianDynamicColors.textSecondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(liveConsoleCardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func missionLiveTaskProgressList(mission: Mission, now: Date) -> some View {
        ForEach(mission.routeMacro.tasks.indices, id: \.self) { index in
            let task = mission.routeMacro.tasks[index]
            missionLiveTaskProgressRow(task: task, taskIndex: index, mission: mission, now: now)
        }
    }

    private func missionLiveTaskProgressRow(task: RoutePath, taskIndex: Int, mission: Mission, now: Date) -> some View {
        let mavlinkTaskId = liveMavlinkTaskContext?.task.id
        let hub = liveMavlinkHub
        let tint = MissionTaskMapColor.swiftUIColor(forTaskIndex: taskIndex)
        let taskStartDef = run.taskStartDeferralByTaskID[task.id]
        let inTaskStartDeferral = task.enabled
            && run.status == .running
            && (taskStartDef.map { now < $0.startAt } ?? false)

        let missionFraction = missionLiveTaskFraction(task: task, mavlinkTaskId: mavlinkTaskId, hub: hub)
        let barFraction: Double
        let barTint: Color
        if inTaskStartDeferral, let def = taskStartDef {
            let remaining = def.startAt.timeIntervalSince(now)
            let elapsed = def.totalDelay - max(0, remaining)
            barFraction = def.totalDelay > 0 ? min(1, max(0, elapsed / def.totalDelay)) : 1
            barTint = Color.cyan.opacity(0.78)
        } else {
            barFraction = missionFraction
            barTint = task.enabled ? tint : Color.gray.opacity(0.35)
        }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(task.enabled ? GuardianDynamicColors.textPrimary : GuardianDynamicColors.textSecondary)
                Spacer(minLength: 6)
                Group {
                    if inTaskStartDeferral, let taskStartDef {
                        Text(formattedTaskStartDeferralStatus(
                            remaining: max(0, taskStartDef.startAt.timeIntervalSince(now)),
                            totalDelay: taskStartDef.totalDelay
                        ))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.cyan.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    } else if task.id == mavlinkTaskId, let hub, let tot = hub.missionProgressTotal, tot > 0, let cur = hub.missionProgressCurrent {
                        Text("\(cur)/\(tot)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(GuardianDynamicColors.textSecondary)
                    } else if !task.enabled {
                        Text("Off")
                            .font(.system(size: 10))
                            .foregroundStyle(GuardianDynamicColors.textSecondary)
                    } else {
                        Text("—")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(GuardianDynamicColors.textSecondary.opacity(0.45))
                    }
                }
            }
            missionLiveAnimatedProgressBar(
                fraction: barFraction,
                tint: barTint
            )

            if inTaskStartDeferral, let taskStartDefForControls = taskStartDef {
                HStack(alignment: .center, spacing: 8) {
                    Picker("Delay", selection: $taskStartDeferralPostponeMinutes) {
                        ForEach(1...30, id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 72, alignment: .leading)
                    .controlSize(.small)
                    Button("Go") {
                        run.systems.scheduling.extendMissionTaskStartDeferralByMinutes(
                            taskID: task.id,
                            additionalMinutes: taskStartDeferralPostponeMinutes,
                            onStartNow: { onStart(run) }
                        )
                        syncRunFromStore()
                        onUpdate(run)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan.opacity(0.8))
                    .controlSize(.small)
                    compactVerticalControlSeparator()
                        .padding(.horizontal, 6)
                    Button("Start") {
                        let rough = humanizedRoughTimeUntilScheduledStart(
                            executeAt: taskStartDefForControls.startAt,
                            from: now
                        )
                        confirmSkipTaskStartDeferralTaskID = task.id
                        confirmSkipTaskStartDeferralMessage =
                            "This task’s MAVLink mission is scheduled to start in \(rough). Start it immediately?"
                        confirmSkipTaskStartDeferral = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan.opacity(0.88))
                    .controlSize(.small)
                }
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 2)
            }
        }
    }

    /// Live progress caption while a task awaits its initial MAVLink mission start (see ``MissionTaskStartDeferral``).
    private func formattedTaskStartDeferralStatus(remaining: TimeInterval, totalDelay: TimeInterval) -> String {
        if totalDelay < 1 {
            return remaining > 0.08 ? "Starting mission…" : "Starting mission…"
        }
        if remaining <= 0 {
            return "Starting mission…"
        }
        let secs = max(1, Int(ceil(remaining)))
        let m = secs / 60
        let s = secs % 60
        let clock = String(format: "%d:%02d", m, s)
        return "\(clock) until mission start"
    }

    private func missionLiveTaskFraction(task: RoutePath, mavlinkTaskId: UUID?, hub: FleetHubVehicleTelemetry?) -> Double {
        guard task.enabled, task.id == mavlinkTaskId, let hub, let tot = hub.missionProgressTotal, tot > 0,
              let cur = hub.missionProgressCurrent
        else { return 0 }
        let t = Double(tot)
        let c = Double(cur)
        if c >= t { return 1 }
        return min(1, max(0, c / t))
    }

    private func missionLiveAnimatedProgressBar(fraction: Double, tint: Color) -> some View {
        GeometryReader { geo in
            let w = max(0, min(1, fraction)) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: w)
                    .animation(.easeInOut(duration: 0.35), value: fraction)
            }
        }
        .frame(height: 7)
    }

    private var missionLiveCameraPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(liveConsoleCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(liveConsoleCardStroke, lineWidth: 1)
            )
    }

    /// Same Leaflet/OSM stack and bbox logic as Missions route tab: home marker and route polylines from the mission template.
    private var missionLiveOverviewMap: some View {
        Group {
            if resolvedMission != nil {
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
                            }
                        case .stopFollowingVehicle:
                            mapModel.followedVehicleMarkerID = nil
                        case .centerMarker, .deleteWaypoint:
                            break
                        }
                    }
                )
                .task(id: liveOverviewMapSignature) {
                    if let mission = resolvedMission {
                        mapModel.home = mission.routeMacro.home
                        mapModel.allTasksCoords = mission.routeMacro.tasks.map { $0.waypoints.map(\.coord) }
                    } else {
                        mapModel.home = nil
                        mapModel.allTasksCoords = []
                    }
                    mapModel.selectedTaskWaypoints = []
                    mapModel.selectedWaypointIndex = nil
                    mapModel.vehicleMarkers = missionLiveVehicleMarkers
                    if let followID = mapModel.followedVehicleMarkerID,
                       !missionLiveVehicleMarkers.contains(where: { $0.id == followID }) {
                        mapModel.followedVehicleMarkerID = nil
                    }
                    mapModel.headingPreview = nil
                    mapModel.cameraPreview = nil
                    mapModel.isEditingTask = false
                }
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(liveConsoleCardFill)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(liveConsoleCardStroke, lineWidth: 1)
        )
    }

    /// Equatable signature of every input that feeds the live overview map's
    /// shared model state. Captures the actual home, route, and marker data so the
    /// `.task` re-runs whenever any vehicle drifts, the mission is edited,
    /// etc. — not just when counts change.
    private var liveOverviewMapSignature: LiveOverviewMapSignature {
        LiveOverviewMapSignature(
            missionID: resolvedMission?.id,
            homeCoord: resolvedMission?.routeMacro.home?.coord,
            allTasksCoords: resolvedMission?.routeMacro.tasks.map { $0.waypoints.map(\.coord) } ?? [],
            markers: missionLiveVehicleMarkers
        )
    }

    private var missionLiveVehicleMarkers: [MapVehicleMarker] {
        run.assignments.compactMap { assignment in
            guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
                  let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                  let lat = hub.latitudeDeg,
                  let lon = hub.longitudeDeg,
                  assignment.attachedFleetVehicleToken != nil
            else { return nil }
            let colorHex = fleetLink.mapColorHex(forVehicleID: vehicleID)
            let heading = hub.headingDeg ?? hub.yawDeg
            return MapVehicleMarker(
                id: assignment.id.uuidString,
                lat: lat,
                lon: lon,
                label: assignment.slotName,
                colorHex: colorHex,
                selected: false,
                draggable: false,
                headingDeg: heading
            )
        }
    }

    private var missionLiveVehicleStatusRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if run.assignments.isEmpty {
                    MissionLiveVehicleHealthCard(
                        slotTitle: "—",
                        rosterSubtitle: "—",
                        vehicleID: nil,
                        simulationImageBasenames: nil,
                        vehicleClassForBundledDeviceArt: .unknown,
                        vehicleModel: fleetLink.primaryVehicleOperationalModel()
                    )
                } else {
                    ForEach(run.assignments) { assignment in
                        let device = resolvedMission.flatMap { m in
                            m.rosterDevices.first { $0.id == assignment.rosterDeviceId }
                        }
                        let vehicleID = telemetryVehicleID(for: assignment)
                        let rosterDeviceClass = device?.vehicleClass ?? .unknown
                        let deviceArtVehicleClass: FleetVehicleType = {
                            if let vid = vehicleID, let model = fleetLink.vehicleModel(forVehicleID: vid) {
                                return model.data.vehicleType
                            }
                            return rosterDeviceClass
                        }()
                        MissionLiveVehicleHealthCard(
                            slotTitle: assignment.slotName,
                            rosterSubtitle: rosterRoleSubtitle(device),
                            vehicleID: vehicleID,
                            simulationImageBasenames: simulationImageBasenamesForAssignment(assignment, sitl: sitl),
                            vehicleClassForBundledDeviceArt: deviceArtVehicleClass,
                            vehicleModel: vehicleID.map { fleetLink.vehicleOperationalModel(forVehicleID: $0) }
                                ?? FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil)
                        )
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 175)
    }

    private var missionLiveLogPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text("Paladin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textPrimary)

                if let compiledPlan = run.compiledPlan {
                    let phaseStyle = GuardianSemanticColors.paladinPhaseBadgeStyle(for: run.sessionPhase)
                    HStack(spacing: 6) {
                        Text(run.sessionPhase.rawValue.capitalized)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(phaseStyle.foreground)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(phaseStyle.background)
                            .clipShape(Capsule())
                        Text(paladinCondensedHeaderMetadata(plan: compiledPlan))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(GuardianDynamicColors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 8)

                Button(paladinLogExtended ? "Compact" : "Expand") {
                    paladinLogExtended.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(paladinLogExtended ? "Use reduced log height" : "Use extended log height")

                Button("Copy log") {
                    copyPaladinLiveLogToPasteboard()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(run.events.isEmpty)
            }

            if !run.events.isEmpty {
                Divider().opacity(0.18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(run.events.suffix(80)) { event in
                            paladinLogEventRow(event: event)
                        }
                    }
                }
            } else {
                Text("No mission log entries for this run yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            }
        }
        .padding(12)
        .frame(
            minHeight: paladinLogExtended ? 420 : 280,
            idealHeight: paladinLogExtended ? 520 : 360,
            maxHeight: paladinLogExtended ? 720 : 480
        )
        .animation(.easeInOut(duration: 0.2), value: paladinLogExtended)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(liveConsoleCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(liveConsoleCardStroke, lineWidth: 1)
        )
    }

    private func paladinCondensedHeaderMetadata(plan: MissionControlPlan) -> String {
        "\(plan.taskTopology.rawValue) · \(plan.teamTopology.rawValue) · \(plan.roleTracks.count) trk"
    }

    private func paladinCondensedHeaderLine(phase: MissionRunSessionPhase, plan: MissionControlPlan) -> String {
        "\(phase.rawValue) · \(paladinCondensedHeaderMetadata(plan: plan))"
    }

    private func paladinLiveLogPlainText(
        events: [MissionRunEvent],
        phase: MissionRunSessionPhase,
        plan: MissionControlPlan?
    ) -> String {
        let header = plan.map { "Paladin - \(paladinCondensedHeaderLine(phase: phase, plan: $0))" } ?? "Mission log"
        let body = events.map { $0.plainTextLine() }
        return ([header] + body).joined(separator: "\n")
    }

    private func paladinColorFromMapHex(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let n = UInt32(s, radix: 16) else {
            return Color(red: 0.55, green: 0.55, blue: 0.58)
        }
        let r = Double((n >> 16) & 0xFF) / 255
        let g = Double((n >> 8) & 0xFF) / 255
        let b = Double(n & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    private func paladinLogSeverityBorderColor(_ level: MissionRunEventLevel) -> Color {
        switch level {
        case .info: return Color.white.opacity(0.22)
        case .warning: return Color.orange.opacity(0.9)
        case .error: return Color.red.opacity(0.9)
        }
    }

    @ViewBuilder
    private func paladinLogEventRow(event: MissionRunEvent) -> some View {
        let mission = resolvedMission
        let routeTint: Color? = {
            guard let pid = event.taskID, let mission else { return nil }
            if let idx = mission.routeMacro.tasks.firstIndex(where: { $0.id == pid }) {
                return MissionTaskMapColor.swiftUIColor(forTaskIndex: idx)
            }
            return nil
        }()
        let routeTextColor = routeTint ?? Color.gray.opacity(0.85)
        let speakerColor: Color = {
            switch event.speaker {
            case .missionControl:
                return GuardianDynamicColors.textPrimary
            case .paladin:
                return GuardianDynamicColors.textPrimary
            case .vehicleSlot(let slot):
                guard let a = run.assignments.first(where: { $0.slotName == slot }),
                      let vid = resolvedFleetStreamVehicleID(assignment: a, fleetLink: fleetLink, sitl: sitl)
                else { return Color.gray.opacity(0.9) }
                return paladinColorFromMapHex(fleetLink.mapColorHex(forVehicleID: vid))
            }
        }()
        let bodyColor: Color = {
            switch event.level {
            case .info: return Color.gray.opacity(0.92)
            case .warning: return Color.orange.opacity(0.88)
            case .error: return Color.red.opacity(0.9)
            }
        }()

        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(paladinLogSeverityBorderColor(event.level))
                .frame(width: 3)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let pl = event.taskLabel {
                    Text("[\(pl)]")
                        .foregroundStyle(routeTextColor)
                }
                switch event.speaker {
                case .missionControl:
                    Text("[MissionControl]")
                        .foregroundStyle(speakerColor)
                case .paladin:
                    Text("[Paladin]")
                        .foregroundStyle(speakerColor)
                case .vehicleSlot(let s):
                    Text("[\(s)]")
                        .foregroundStyle(speakerColor)
                }
                Text(verbatim: " \(paladinLogTemplates.resolveDisplayBody(for: event))")
                    .foregroundStyle(bodyColor)
            }
            .font(.system(size: 11, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
            .padding(.vertical, 2)
        }
    }

    private func copyPaladinLiveLogToPasteboard() {
        guard !run.events.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(
            paladinLiveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan),
            forType: .string
        )
    }

    private var missionCompletedReportCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mission report")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(GuardianDynamicColors.textPrimary)
                Spacer()
                MissionRunStatusBadge(status: .completed)
            }

            completedOutcomeCard
            completedScheduleCyclesCard
            completedTimelineCard
            completedRosterCard
            completedPaladinHealthCard
        }
    }

    private var completedOutcomeCard: some View {
        let accent = completedOutcomeAccent
        return completedReportCardChrome(title: "Outcome", accent: accent) {
            Text(completedOutcomeTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
            Text(completedOutcomeDetail)
                .font(.system(size: 13))
                .foregroundStyle(GuardianDynamicColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var completedOutcomeAccent: Color {
        switch run.completionKind {
        case .oneOffAutopilotFinished:
            return Color.green.opacity(0.75)
        case .operatorStoppedAfterCycle:
            return Color.blue.opacity(0.8)
        case .operatorStoppedImmediate:
            return Color.orange.opacity(0.85)
        case .none:
            return Color.gray.opacity(0.55)
        }
    }

    private var completedOutcomeTitle: String {
        switch run.completionKind {
        case .operatorStoppedImmediate:
            return "Stopped by operator"
        case .operatorStoppedAfterCycle:
            return "Stopped after current cycle"
        case .oneOffAutopilotFinished:
            return "Mission finished"
        case .none:
            return "Run completed"
        }
    }

    private var completedOutcomeDetail: String {
        switch run.completionKind {
        case .operatorStoppedImmediate:
            return "The run was ended immediately (vehicles were commanded home / RTL where applicable)."
        case .operatorStoppedAfterCycle:
            return "The active mission cycle was allowed to finish, then the run ended."
        case .oneOffAutopilotFinished:
            return "The mission cycle completed and the run ended."
        case .none:
            return "This run is marked complete. Older runs may not store a detailed outcome."
        }
    }

    private var completedScheduleCyclesCard: some View {
        completedReportCardChrome(title: "Timing & cycles", accent: Color.white.opacity(0.2)) {
            if let t = run.oneOffStartAt {
                labeledReportRow("Planned start", t.formatted(date: .abbreviated, time: .shortened))
            } else {
                labeledReportRow("Planned start", "When started (no deferred start)")
            }
            let cycles = run.reportCyclesCompleted ?? 0
            labeledReportRow(
                "Mission cycles completed",
                "\(cycles)"
            )
        }
    }

    private var completedTimelineCard: some View {
        completedReportCardChrome(title: "Timeline", accent: Color.white.opacity(0.2)) {
            labeledReportRow("Created", run.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let s = run.startedAt {
                labeledReportRow("Started", s.formatted(date: .abbreviated, time: .shortened))
            } else {
                labeledReportRow("Started", "—")
            }
            if let e = run.completedAt {
                labeledReportRow("Completed", e.formatted(date: .abbreviated, time: .shortened))
            }
            if let dur = completedRunDurationFormatted {
                labeledReportRow("Elapsed (start → complete)", dur)
            }
        }
    }

    private var completedRunDurationFormatted: String? {
        guard let s = run.startedAt, let e = run.completedAt else { return nil }
        let sec = max(0, e.timeIntervalSince(s))
        if sec < 60 { return String(format: "%.0f s", sec) }
        let m = Int(sec / 60)
        if m < 60 { return "\(m) min" }
        let h = m / 60
        let rm = m % 60
        return "\(h) h \(rm) min"
    }

    private var completedRosterCard: some View {
        completedReportCardChrome(title: "Roster", accent: Color.white.opacity(0.2)) {
            if run.assignments.isEmpty {
                Text("No roster slots.")
                    .font(.system(size: 13))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(run.assignments) { a in
                        let bound = a.attachedFleetVehicleToken != nil || !a.attachedDevice.isEmpty
                        Text("• \(a.slotName)\(bound ? "" : " — unassigned")")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(GuardianDynamicColors.textSecondary)
                    }
                }
            }
        }
    }

    private var completedPaladinHealthCard: some View {
        let errs = completedPaladinErrorCount
        let warns = completedPaladinWarningCount
        let accent: Color = errs > 0 ? Color.red.opacity(0.8) : (warns > 0 ? Color.orange.opacity(0.8) : Color.green.opacity(0.65))
        return completedReportCardChrome(title: "Paladin log health", accent: accent) {
            if run.events.isEmpty {
                Text("No mission log entries are stored for this run.")
                    .font(.system(size: 13))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            } else {
                let events = run.events.count
                labeledReportRow("Events recorded", "\(events)")
                labeledReportRow("Warnings", "\(warns)")
                labeledReportRow("Errors", "\(errs)")
                if errs == 0, warns == 0 {
                    Text("No warnings or errors in the Paladin log.")
                        .font(.system(size: 12))
                        .foregroundStyle(GuardianDynamicColors.textTertiary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var completedPaladinErrorCount: Int {
        run.events.filter { $0.level == .error }.count
    }

    private var completedPaladinWarningCount: Int {
        run.events.filter { $0.level == .warning }.count
    }

    private var completedPaladinLogExportSection: some View {
        let text = paladinLiveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Paladin log")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textPrimary)
                Spacer()
                Button("Copy") {
                    copyCompletedPaladinLog()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(text.isEmpty)

                Button("Save…") {
                    saveCompletedPaladinLog()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(text.isEmpty)

                Button("Print…") {
                    printCompletedPaladinLog()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(text.isEmpty)
            }

            if text.isEmpty {
                Text("No mission log entries for this run.")
                    .font(.system(size: 13))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(GuardianDynamicColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 220, idealHeight: 320, maxHeight: 480)
                .padding(10)
                .background(GuardianDynamicColors.backgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(GuardianDynamicColors.borderSubtle, lineWidth: 1)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func completedReportCardChrome<Content: View>(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textPrimary)
                content()
            }
            .padding(.leading, 12)
            .padding(.vertical, 12)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func labeledReportRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(GuardianDynamicColors.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func copyCompletedPaladinLog() {
        guard !run.events.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(
            paladinLiveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan),
            forType: .string
        )
    }

    private func saveCompletedPaladinLog() {
        guard !run.events.isEmpty else { return }
        let text = paladinLiveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.title = "Save Paladin log"
        let safeName = run.missionName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(safeName)-paladin-log.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Best-effort export; avoid crashing the UI.
            }
        }
    }

    private func printCompletedPaladinLog() {
        guard !run.events.isEmpty else { return }
        let text = paladinLiveLogPlainText(events: run.events, phase: run.sessionPhase, plan: run.compiledPlan)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 2000))
        tv.string = text
        tv.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        tv.isEditable = false
        tv.drawsBackground = false
        let op = NSPrintOperation(view: tv, printInfo: NSPrintInfo.shared)
        op.jobTitle = "\(run.missionName) — Paladin log"
        op.run()
    }

    private var setupScheduleCard: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.scheduleCardSpacing) {
            Text("Schedule")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
            scheduleSetupScheduleTabContent
        }
        .padding(MissionRunPrepLayout.scheduleCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.taskCardCornerRadius))
    }

    private var setupTasksDelaysCard: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.scheduleCardSpacing) {
            Text("Tasks")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
            scheduleSetupTasksTabContent
        }
        .padding(MissionRunPrepLayout.scheduleCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.taskCardCornerRadius))
    }

    private var setupTimingTabContent: some View {
        GeometryReader { geo in
            let stackVertically = geo.size.width < MissionRunPrepLayout.timingScheduleTasksStackBreakpoint
            Group {
                if stackVertically {
                    VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterGridSpacing) {
                        setupScheduleCard
                        setupTasksDelaysCard
                    }
                } else {
                    HStack(alignment: .top, spacing: MissionRunPrepLayout.rosterGridSpacing) {
                        setupScheduleCard
                        setupTasksDelaysCard
                    }
                }
            }
            .frame(width: geo.size.width, alignment: .topLeading)
        }
        .frame(minHeight: 200)
    }

    private var setupRostersTabContent: some View {
        GeometryReader { geo in
            let stackVertically = geo.size.width < MissionRunPrepLayout.rostersMapAccordionStackBreakpoint
            let totalH = geo.size.height
            let totalW = geo.size.width
            let rowGap: CGFloat = 14
            let mapW = stackVertically ? totalW : max(0, (totalW - rowGap) * 0.7)
            let accW = stackVertically ? totalW : max(0, (totalW - rowGap) * 0.3)
            Group {
                if stackVertically {
                    VStack(alignment: .leading, spacing: rowGap) {
                        rostersStagingMapBare
                            .frame(width: mapW, height: max(200, (totalH - rowGap) * 0.52), alignment: .topLeading)
                        rostersAccordionColumn
                            .frame(width: accW, height: max(160, (totalH - rowGap) * 0.48 - rowGap), alignment: .topLeading)
                    }
                } else {
                    HStack(alignment: .top, spacing: rowGap) {
                        rostersStagingMapBare
                            .frame(width: mapW, height: totalH, alignment: .topLeading)
                        rostersAccordionColumn
                            .frame(width: accW, height: totalH, alignment: .topLeading)
                    }
                }
            }
            .frame(width: totalW, height: totalH, alignment: .topLeading)
        }
    }

    private var rostersAccordionColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if run.assignments.isEmpty {
                    Text("No roster slots on this mission template.")
                        .foregroundStyle(GuardianDynamicColors.textSecondary)
                } else if let mission = resolvedMission {
                    ForEach(mission.routeMacro.tasks) { task in
                        taskRosterAccordionSection(task: task, mission: mission)
                    }
                    legacyRostersAccordionSection(mission: mission)
                } else {
                    missionMissingTemplateRosterFallback
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func missionRunAssignmentBelongsToTask(
        _ assignment: MissionRunAssignment,
        task: MissionTask,
        mission: Mission
    ) -> Bool {
        if assignment.taskId == task.id { return true }
        if assignment.taskId == nil {
            let enabled = mission.routeMacro.tasks.filter(\.enabled)
            if enabled.count == 1, enabled.first?.id == task.id { return true }
        }
        return false
    }

    /// Same ordering as ``MissionsView/taskRosterDisplayRows``: primaries in roster order, then each primary’s wingmen and reserves.
    private func missionRunTaskRosterOrderedSlots(task: MissionTask, mission: Mission) -> [(assignmentIndex: Int, indent: Int)] {
        let ids = task.rosterDeviceIds
        func device(for rosterId: UUID) -> RosterDevice? {
            mission.rosterDevices.first { $0.id == rosterId }
        }
        func slot(for rosterId: UUID, indent: Int) -> (assignmentIndex: Int, indent: Int)? {
            guard let idx = run.assignments.firstIndex(where: {
                $0.rosterDeviceId == rosterId && missionRunAssignmentBelongsToTask($0, task: task, mission: mission)
            }) else { return nil }
            return (idx, indent)
        }
        var emitted = Set<UUID>()
        var rows: [(assignmentIndex: Int, indent: Int)] = []
        let primaryIds = ids.filter { device(for: $0)?.slot == .primary }
        for pid in primaryIds {
            guard device(for: pid)?.slot == .primary else { continue }
            if let r = slot(for: pid, indent: 0) {
                rows.append(r)
                emitted.insert(pid)
            }
            let wingmanIds = ids.filter {
                guard let d = device(for: $0), d.slot == .wingman, d.leaderRosterDeviceId == pid else { return false }
                return true
            }
            let reserveIds = ids.filter {
                guard let d = device(for: $0), d.slot == .reserve, d.leaderRosterDeviceId == pid else { return false }
                return true
            }
            for wid in wingmanIds {
                if let r = slot(for: wid, indent: 1) {
                    rows.append(r)
                    emitted.insert(wid)
                }
            }
            for rid in reserveIds {
                if let r = slot(for: rid, indent: 1) {
                    rows.append(r)
                    emitted.insert(rid)
                }
            }
        }
        for id in ids where !emitted.contains(id) {
            let d = device(for: id)
            let indent = (d?.slot == .wingman || d?.slot == .reserve) ? 1 : 0
            if let r = slot(for: id, indent: indent) {
                rows.append(r)
                emitted.insert(id)
            }
        }
        return rows
    }

    private func missionRunLegacyRosterOrderedSlots(mission: Mission) -> [(assignmentIndex: Int, indent: Int)] {
        let indices = legacyUnassignedIndices
        let devicesById = Dictionary(uniqueKeysWithValues: mission.rosterDevices.map { ($0.id, $0) })
        let order = mission.rosterDevices.map(\.id)
        let sorted = indices.sorted {
            let da = run.assignments[$0].rosterDeviceId
            let db = run.assignments[$1].rosterDeviceId
            let ia = order.firstIndex(of: da) ?? Int.max
            let ib = order.firstIndex(of: db) ?? Int.max
            return ia < ib
        }
        return sorted.map { idx in
            let rid = run.assignments[idx].rosterDeviceId
            let d = devicesById[rid]
            let indent = (d?.slot == .wingman || d?.slot == .reserve) ? 1 : 0
            return (idx, indent)
        }
    }

    private func mcRosterAccordionHeaderChrome(
        title: String,
        filled: Int,
        total: Int,
        isExpanded: Bool,
        enabled: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textSecondary)
                .frame(width: 14, alignment: .center)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(filled)/\(total) filled")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GuardianDynamicColors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(enabled ? 1 : 0.55)
    }

    @ViewBuilder
    private func taskRosterAccordionSection(task: MissionTask, mission: Mission) -> some View {
        let expanded = rosterSetupExpandedTaskIDs.contains(task.id)
        let indices = run.assignments.indices.filter { missionRunAssignmentBelongsToTask(run.assignments[$0], task: task, mission: mission) }
        let filled = indices.filter { run.assignments[$0].hasFleetOrLegacyAssignment }.count
        let rows = missionRunTaskRosterOrderedSlots(task: task, mission: mission)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if expanded {
                    rosterSetupExpandedTaskIDs.remove(task.id)
                } else {
                    rosterSetupExpandedTaskIDs.insert(task.id)
                }
            } label: {
                mcRosterAccordionHeaderChrome(
                    title: task.name,
                    filled: filled,
                    total: indices.count,
                    isExpanded: expanded,
                    enabled: task.enabled
                )
            }
            .buttonStyle(.plain)

            if expanded {
                rostersOrderedSlotsList(rows: rows, mission: mission)
            }
        }
    }

    @ViewBuilder
    private func rostersOrderedSlotsList(rows: [(assignmentIndex: Int, indent: Int)], mission: Mission?) -> some View {
        if rows.isEmpty {
            Text("No roster slots linked to this task. Link devices to the task in Missions → Roster.")
                .font(.system(size: 12))
                .foregroundStyle(GuardianDynamicColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: MissionRunPrepLayout.rosterGridSpacing) {
                ForEach(rows, id: \.assignmentIndex) { row in
                    rosterSlotCard(assignmentIndex: row.assignmentIndex, mission: mission)
                        .padding(.leading, CGFloat(row.indent) * MissionRunPrepLayout.rosterSlotWingmanIndent)
                }
            }
        }
    }

    @ViewBuilder
    private func legacyRostersAccordionSection(mission: Mission) -> some View {
        let indices = legacyUnassignedIndices
        if !indices.isEmpty {
            let expanded = rosterSetupLegacyMissionRosterExpanded
            let filled = indices.filter { run.assignments[$0].hasFleetOrLegacyAssignment }.count
            let rows = missionRunLegacyRosterOrderedSlots(mission: mission)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    rosterSetupLegacyMissionRosterExpanded.toggle()
                } label: {
                    mcRosterAccordionHeaderChrome(
                        title: "Mission roster",
                        filled: filled,
                        total: indices.count,
                        isExpanded: expanded,
                        enabled: true
                    )
                }
                .buttonStyle(.plain)

                if rosterSetupLegacyMissionRosterExpanded {
                    rostersOrderedSlotsList(rows: rows, mission: mission)
                }
            }
        }
    }

    private var setupRulesTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rules of engagement")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
            Text(
                "Paladin and Mission Control resolve these dispositions when an action is requested during a run. Unlisted actions default to autonomous."
            )
            .font(.system(size: 12))
            .foregroundStyle(GuardianDynamicColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(MissionRunEngagementAction.allCases.indices, id: \.self) { idx in
                    let action = MissionRunEngagementAction.allCases[idx]
                    if idx > 0 {
                        Divider()
                            .overlay(GuardianDynamicColors.borderSubtle)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(action.setupLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(GuardianDynamicColors.textPrimary)
                        Spacer(minLength: 12)
                        Picker("", selection: engagementDispositionBinding(for: action)) {
                            ForEach(MissionRunEngagementDisposition.allCases, id: \.self) { disposition in
                                Text(disposition.setupMenuLabel).tag(disposition)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: 160, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(MissionRunPrepLayout.scheduleCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GuardianDynamicColors.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.taskCardCornerRadius))
        }
    }

    private func engagementDispositionBinding(for action: MissionRunEngagementAction) -> Binding<MissionRunEngagementDisposition> {
        Binding(
            get: {
                run.resolvedEngagementDisposition(for: action)
            },
            set: { newDisposition in
                var rules = run.policies.engagement
                var map = rules.perAction
                if newDisposition == .autonomous {
                    map.removeValue(forKey: action)
                } else {
                    map[action] = MissionRunEngagementRule(disposition: newDisposition)
                }
                rules.perAction = map
                run.policies.engagement = rules
                onUpdate(run)
            }
        )
    }

    /// Effective minutes: run override if present, otherwise the mission task’s ``MissionTask/startDelay``.
    private func taskStartDelayBinding(for task: MissionTask) -> Binding<Int> {
        Binding(
            get: {
                if let o = run.taskStartDelays.first(where: { $0.taskId == task.id }) {
                    return o.startDelayMinutes
                }
                return resolvedMission?.routeMacro.tasks.first(where: { $0.id == task.id })?.startDelay ?? task.startDelay
            },
            set: { newValue in
                let clamped = min(59, max(0, newValue))
                let templateMinutes = resolvedMission?.routeMacro.tasks.first(where: { $0.id == task.id })?.startDelay ?? task.startDelay
                var list = run.taskStartDelays
                list.removeAll { $0.taskId == task.id }
                if clamped != templateMinutes {
                    list.append(TaskStartDelay(taskId: task.id, startDelayMinutes: clamped))
                }
                run.taskStartDelays = list
                onUpdate(run)
            }
        )
    }

    private var mcSetupTaskFieldLabelFont: Font { .system(size: 13) }

    private func missionControlTaskStartDelayFieldRow(task: MissionTask) -> some View {
        let binding = taskStartDelayBinding(for: task)
        return HStack(alignment: .center, spacing: 10) {
            Text(task.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(task.enabled ? GuardianDynamicColors.textPrimary : GuardianDynamicColors.textSecondary.opacity(0.72))
                .lineLimit(2)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Stepper(value: binding, in: 0...59) {
                    Text(String(binding.wrappedValue))
                        .font(mcSetupTaskFieldLabelFont)
                        .monospacedDigit()
                        .foregroundStyle(GuardianDynamicColors.textPrimary)
                        .frame(minWidth: 28, alignment: .trailing)
                }
                Text("mins")
                    .font(mcSetupTaskFieldLabelFont)
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            }
            .fixedSize()
        }
        .opacity(task.enabled ? 1 : 0.55)
    }

    private var scheduleSetupTasksTabContent: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.scheduleCardSpacing) {
            Text("Manage task start delays")
                .font(.system(size: 12))
                .foregroundStyle(GuardianDynamicColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let mission = resolvedMission {
                ForEach(mission.routeMacro.tasks) { task in
                    missionControlTaskStartDelayFieldRow(task: task)
                }
            } else {
                Text("Mission template unavailable for this run.")
                    .font(.system(size: 12))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            }
        }
    }

    private var scheduleSetupScheduleTabContent: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.scheduleCardSpacing) {
            Toggle(
                "Start immediately",
                isOn: Binding(
                    get: { run.oneOffStartAt == nil },
                    set: { immediate in
                        if immediate {
                            run.oneOffStartAt = nil
                        } else if run.oneOffStartAt == nil {
                            run.oneOffStartAt = scheduleDefaultDeferredStartDate()
                        }
                        onUpdate(run)
                    }
                )
            )
            .tint(.blue)

            if run.oneOffStartAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        DatePicker(
                            "Start date & time",
                            selection: Binding(
                                get: { run.oneOffStartAt ?? Date() },
                                set: { run.oneOffStartAt = $0; onUpdate(run) }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        if run.oneOffScheduledTimeTooFarInPast(referenceNow: context.date) {
                            Text("That time is in the past. Move it forward or enable “Start immediately”.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.orange.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func scheduleDefaultDeferredStartDate() -> Date {
        Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
    }

    /// Rosters tab only: map fills its slot—no card chrome so horizontal gutters match the accordion column.
    private var rostersStagingMapBare: some View {
        GuardianMapView(
            model: mapModel,
            onMapClick: { lat, lon in
                applySetupMapClick(lat: lat, lon: lon)
            },
            onVehicleMarkerMoved: { markerID, lat, lon in
                applySetupMarkerDrag(markerID: markerID, lat: lat, lon: lon)
            }
        )
        .task(id: setupStagingMapSignature) {
            if let mission = resolvedMission {
                mapModel.home = mission.routeMacro.home
                mapModel.allTasksCoords = mission.routeMacro.tasks.map { $0.waypoints.map(\.coord) }
            } else {
                mapModel.home = nil
                mapModel.allTasksCoords = []
            }
            mapModel.selectedTaskWaypoints = []
            mapModel.selectedWaypointIndex = nil
            mapModel.vehicleMarkers = setupVehicleMarkers
            mapModel.headingPreview = nil
            mapModel.cameraPreview = nil
            mapModel.isEditingTask = false
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(GuardianDynamicColors.borderSubtle, lineWidth: 1)
        )
    }

    /// Equatable signature of all setup-staging-map inputs (mission home,
    /// route tasks, and every vehicle marker). Pushed into `mapModel` whenever any
    /// underlying coordinate or marker drag changes.
    private var setupStagingMapSignature: SetupStagingMapSignature {
        SetupStagingMapSignature(
            missionID: resolvedMission?.id,
            homeCoord: resolvedMission?.routeMacro.home?.coord,
            allTasksCoords: resolvedMission?.routeMacro.tasks.map { $0.waypoints.map(\.coord) } ?? [],
            markers: setupVehicleMarkers
        )
    }

    private var setupVehicleMarkers: [MapVehicleMarker] {
        run.assignments.compactMap { assignment in
            guard let tokenKey = assignment.attachedFleetVehicleToken,
                  let token = FleetMissionVehicleToken(storageKey: tokenKey)
            else { return nil }
            let selected = assignment.id == setupSelectedAssignmentId
            let label = "\(assignment.slotName)"
            switch token {
            case .sitl(let uuid):
                guard let inst = sitl.instances.first(where: { $0.id == uuid }) else { return nil }
                let systemID = inst.stackInstanceIndex + 1
                let vehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
                let colorHex = fleetLink.mapColorHex(forVehicleID: vehicleID)
                if let override = assignment.simStartOverrideCoord {
                    return MapVehicleMarker(
                        id: assignment.id.uuidString,
                        lat: override.lat,
                        lon: override.lon,
                        label: "\(label) (SIM start)",
                        colorHex: colorHex,
                        selected: selected,
                        draggable: selected,
                        headingDeg: nil
                    )
                }
                guard let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                      let lat = hub.latitudeDeg,
                      let lon = hub.longitudeDeg else { return nil }
                let heading = hub.headingDeg ?? hub.yawDeg
                return MapVehicleMarker(
                    id: assignment.id.uuidString,
                    lat: lat,
                    lon: lon,
                    label: "\(label) (SIM live)",
                    colorHex: colorHex,
                    selected: selected,
                    draggable: selected,
                    headingDeg: heading
                )
            case .live:
                guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
                      let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                      let lat = hub.latitudeDeg,
                      let lon = hub.longitudeDeg
                else { return nil }
                let heading = hub.headingDeg ?? hub.yawDeg
                return MapVehicleMarker(
                    id: assignment.id.uuidString,
                    lat: lat,
                    lon: lon,
                    label: "\(label) (Live)",
                    colorHex: fleetLink.mapColorHex(forVehicleID: vehicleID),
                    selected: selected,
                    draggable: false,
                    headingDeg: heading
                )
            }
        }
    }

    private func applySetupMapClick(lat: Double, lon: Double) {
        guard let aid = setupSelectedAssignmentId,
              let idx = run.assignments.firstIndex(where: { $0.id == aid }),
              let tokenKey = run.assignments[idx].attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: tokenKey)
        else { return }
        guard case .sitl = token else { return }
        run.assignments[idx].simStartOverrideCoord = RouteCoordinate(lat: lat, lon: lon)
    }

    private func applySetupMarkerDrag(markerID: String, lat: Double, lon: Double) {
        guard let aid = UUID(uuidString: markerID),
              let idx = run.assignments.firstIndex(where: { $0.id == aid }),
              let tokenKey = run.assignments[idx].attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: tokenKey)
        else { return }
        guard case .sitl = token else { return }
        setupSelectedAssignmentId = aid
        run.assignments[idx].simStartOverrideCoord = RouteCoordinate(lat: lat, lon: lon)
    }

    private var setupMapBoundsSignature: String {
        run.assignments
            .compactMap { assignment -> String? in
                guard let token = assignment.attachedFleetVehicleToken else { return nil }
                return "\(assignment.id.uuidString)|\(token)"
            }
            .sorted()
            .joined(separator: ";")
    }

    private var legacyUnassignedIndices: [Int] {
        run.assignments.indices.filter { run.assignments[$0].taskId == nil }
    }

    private var missionMissingTemplateRosterFallback: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.taskCardInnerSpacing) {
            Text("Roster")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
            Text("Mission template not found — roster slots are frozen from when the run was created.")
                .font(.system(size: 12))
                .foregroundStyle(GuardianDynamicColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: MissionRunPrepLayout.rosterGridMinWidth),
                        spacing: MissionRunPrepLayout.rosterGridSpacing,
                        alignment: .top
                    ),
                ],
                spacing: MissionRunPrepLayout.rosterGridSpacing
            ) {
                ForEach(run.assignments.indices, id: \.self) { idx in
                    rosterSlotCard(assignmentIndex: idx, mission: nil)
                }
            }
        }
        .padding(MissionRunPrepLayout.taskCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.taskCardCornerRadius))
    }

    private func rosterSlotCard(assignmentIndex: Int, mission: Mission?) -> some View {
        let a = run.assignments[assignmentIndex]
        let device = mission.flatMap { m in m.rosterDevices.first { $0.id == a.rosterDeviceId } }
        let detailLine = resolvedRosterVehicleSecondaryLine(assignment: a, fleetLink: fleetLink, sitl: sitl)
        let basenames = simulationImageBasenamesForAssignment(a, sitl: sitl)
        let assignmentId = a.id
        let slotFilled = a.hasFleetOrLegacyAssignment
        let batterySummary: FleetVehicleOperationalModel.BatterySummary? = {
            guard let vid = telemetryVehicleID(for: a) else { return nil }
            return fleetLink.vehicleOperationalModel(forVehicleID: vid).battery
        }()
        let infoVehicleID = telemetryVehicleID(for: a)
        let rosterDeviceClass = device?.vehicleClass ?? .unknown
        let fleetDisplayShortID: String? = {
            guard slotFilled, let vid = telemetryVehicleID(for: a) else { return nil }
            if let model = fleetLink.vehicleModel(forVehicleID: vid) {
                return model.displayShortID
            }
            if let key = a.attachedFleetVehicleToken,
               let token = FleetMissionVehicleToken(storageKey: key),
               case .sitl(let uuid) = token,
               let inst = sitl.instances.first(where: { $0.id == uuid })
            {
                let systemID = inst.stackInstanceIndex + 1
                return "\(inst.preset.fleetVehicleType.classCode):\(systemID)"
            }
            let prefix = "sysid:"
            if vid.hasPrefix(prefix), let n = Int(vid.dropFirst(prefix.count)) {
                return "\(rosterDeviceClass.classCode):\(n)"
            }
            return nil
        }()
        let deviceArtVehicleClass: FleetVehicleType = {
            guard slotFilled,
                  let vid = telemetryVehicleID(for: a),
                  let model = fleetLink.vehicleModel(forVehicleID: vid)
            else { return rosterDeviceClass }
            return model.data.vehicleType
        }()
        return MissionControlRosterSlotCard(
            title: a.slotName,
            subtitle: rosterRoleSubtitle(device),
            vehicleClassForBundledDeviceArt: deviceArtVehicleClass,
            isAttached: slotFilled,
            assignedVehicleDetail: detailLine,
            rosterBatterySummary: batterySummary,
            assignedFleetIsSimulation: rosterAssignmentFleetIsSimulation(a),
            autopilotStack: rosterAutopilotStack(for: a),
            simulationImageBasenames: basenames,
            lifecycleStatus: rosterLifecycleStatus(for: a),
            fleetDisplayShortID: fleetDisplayShortID,
            isSelectedForSetupMap: setupSelectedAssignmentId == assignmentId,
            onSelectForSetupMap: {
                setupSelectedAssignmentId = assignmentId
            },
            onChooseVehicle: {
                setupSelectedAssignmentId = assignmentId
                presentMissionRosterVehiclePicker(assignmentId: assignmentId)
            },
            onRemoveVehicle: {
                clearFleetVehicle(assignmentId: assignmentId)
            },
            onInfo: infoVehicleID == nil
                ? nil
                : {
                    presentRosterTelemetrySheet(for: a)
                }
        )
    }

    private func rosterRoleSubtitle(_ device: RosterDevice?) -> String {
        guard let device else { return "—" }
        return "\(device.slot.rawValue) · \(device.role.rawValue)"
    }

    /// `nil` when there is no fleet token (unassigned or legacy typed label only).
    private func rosterAssignmentFleetIsSimulation(_ assignment: MissionRunAssignment) -> Bool? {
        guard let key = assignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: key)
        else { return nil }
        switch token {
        case .live: return false
        case .sitl: return true
        }
    }

    private func applyFleetVehicle(_ vehicle: MissionPickableFleetVehicle, assignmentId: UUID) {
        guard let idx = run.assignments.firstIndex(where: { $0.id == assignmentId }) else { return }
        run.assignments[idx].attachedFleetVehicleToken = vehicle.token.storageKey
        run.assignments[idx].attachedDevice = vehicle.title
        if !vehicle.isSimulation {
            run.assignments[idx].simStartOverrideCoord = nil
        }
    }

    private func clearFleetVehicle(assignmentId: UUID) {
        guard let idx = run.assignments.firstIndex(where: { $0.id == assignmentId }) else { return }
        run.assignments[idx].attachedFleetVehicleToken = nil
        run.assignments[idx].attachedDevice = ""
        run.assignments[idx].simStartOverrideCoord = nil
    }

    private func rosterPickDisabledReason(_ vehicle: MissionPickableFleetVehicle, assignmentId: UUID) -> String? {
        let key = vehicle.token.storageKey
        if run.assignments.first(where: { $0.id == assignmentId })?.attachedFleetVehicleToken == key {
            return nil
        }
        if controlStore.isFleetVehicleLockedByOtherLiveMission(tokenKey: key, excludingRunId: run.id) {
            return "In use by another live mission"
        }
        if controlStore.isFleetVehicleUsedOnOtherSlotInRun(tokenKey: key, run: run, assignmentId: assignmentId) {
            return "Already assigned in this mission"
        }
        return nil
    }

    /// Bridge vehicle stream key for a roster assignment (`sysid:<id>` for SITL).
    private func telemetryVehicleID(for assignment: MissionRunAssignment) -> String? {
        resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl)
    }
}

/// One vehicle column in Mission Control: vehicle-type thumbnail + slot title / roster role subtitle, battery/GPS, MAVSDK health. Top-trailing reserved for a future cog menu.
private struct MissionLiveVehicleHealthCard: View {
    let slotTitle: String
    /// Same text as roster slot subtitle (`roleType` · position hint, or "—").
    let rosterSubtitle: String
    let vehicleID: String?
    let simulationImageBasenames: [String]?
    /// Bundled device art when ``simulationImageBasenames`` is nil (live link / unknown sim art).
    let vehicleClassForBundledDeviceArt: FleetVehicleType
    let vehicleModel: FleetVehicleOperationalModel

    private let cardFill = GuardianDynamicColors.backgroundElevated
    private let cardStrokeNeutral = GuardianDynamicColors.borderSubtle

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    vehicleTypeThumbnail
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(slotTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GuardianDynamicColors.textPrimary)
                            .lineLimit(1)
                        Text(rosterSubtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(GuardianDynamicColors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if let vehicleID {
                    Text(displayVehicleID(vehicleID))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(GuardianDynamicColors.textTertiary)
                        .lineLimit(1)
                        .help("Bridge vehicle key: \(vehicleID)")
                }

                if vehicleModel.telemetryAgeS != nil {
                    Divider().opacity(0.22)
                    Spacer(minLength: 0)
                    batteryGpsMovementRow
                } else {
                    Spacer(minLength: 0)
                    Text("No telemetry")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GuardianDynamicColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .padding(.trailing, 26)

            Color.clear
                .frame(width: 28, height: 28)
                .padding(.top, 6)
                .padding(.trailing, 6)
                .accessibilityLabel("Vehicle actions, coming soon")
        }
        .frame(width: 216, height: 175)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(lifecycleBorderColor, lineWidth: 1.6)
        )
    }

    private var liveThumbnailBasenames: [String] {
        if let names = simulationImageBasenames, !names.isEmpty { return names }
        return vehicleClassForBundledDeviceArt.defaultSimulationDeviceImageBasenames
    }

    private var vehicleTypeThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.12, blue: 0.14),
                            Color(red: 0.05, green: 0.07, blue: 0.09),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            SimulationDeviceThumbnail(imageBasenames: liveThumbnailBasenames)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var batteryGpsMovementRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 6) {
                    Image(systemName: batterySymbol)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(batteryIconTint(percent: vehicleModel.battery.percent0to100))
                        .help(batteryHoverText)
                    Text(batteryPercentText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GuardianDynamicColors.textPrimary.opacity(0.94))
                        .lineLimit(1)
                }
                Text(vehicleModel.battery.trendText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(vehicleModel.battery.etaText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(GuardianDynamicColors.borderSubtle.opacity(0.9))
                .frame(width: 1, height: 58)

            VStack(alignment: .trailing, spacing: 4) {
                Text(vehicleModel.gps.titleText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GuardianDynamicColors.textPrimary.opacity(0.92))
                    .lineLimit(1)
                Text(vehicleModel.movement.titleText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func batteryIconTint(percent: Double?) -> Color {
        guard let p = percent else {
            return Color.gray.opacity(0.55)
        }
        if p < 10 {
            return Color.red.opacity(0.92)
        }
        if p < 80 {
            return Color.yellow.opacity(0.95)
        }
        return GuardianSemanticColors.successForeground
    }

    private var batteryPercentText: String {
        guard let p = vehicleModel.battery.percent0to100 else { return "—" }
        return "\(Int(round(p)))%"
    }

    private var batterySymbol: String {
        if vehicleModel.battery.isCharging {
            return "battery.100.bolt"
        }
        return "battery.100"
    }

    private var batteryHoverText: String {
        let pct = batteryPercentText
        let v = vehicleModel.battery.voltageV.map { String(format: "%.1f V", $0) } ?? "—"
        let a = vehicleModel.battery.currentA.map { String(format: "%.1f A", $0) } ?? "—"
        let eta = vehicleModel.battery.etaText
        return "Battery \(pct), \(v), \(a), \(eta)"
    }

    private var lifecycleBorderColor: Color {
        if let lifecycleStatus = vehicleModel.lifecycleStatus {
            return lifecycleStatus.color.uiColor.opacity(0.72)
        }
        return cardStrokeNeutral
    }

    private func displayVehicleID(_ raw: String) -> String {
        if raw.hasPrefix("sysid:") {
            return String(raw.dropFirst("sysid:".count))
        }
        return raw
    }
}

private struct AddMissionRunSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var missionStore: MissionStore
    let onCreateRun: (Mission) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Modal(
            title: "Select Mission",
            headerActions: {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: 12) {
                    if missionStore.missions.isEmpty {
                        Text("No mission templates available.")
                            .foregroundStyle(theme.textSecondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(missionStore.missions) { mission in
                                    Button {
                                        onCreateRun(mission)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(mission.name)
                                                    .foregroundStyle(theme.textPrimary)
                                                Text(mission.description.isEmpty ? "No description" : mission.description)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(theme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Image(systemName: "plus.circle.fill")
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(theme.backgroundRaised)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        )
        .frame(width: 520, height: 420)
    }
}
