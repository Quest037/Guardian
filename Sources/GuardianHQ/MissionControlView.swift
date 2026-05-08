import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Spacing and widths for mission setup / roster prep.
/// Tune here when adding sim battery, pre-place coordinates, staging waypoints, or other per-slot controls.
private enum MissionRunPrepLayout {
    static let setupScrollPaddingH: CGFloat = 36
    static let setupScrollPaddingV: CGFloat = 28
    static let setupBlockSpacing: CGFloat = 22
    static let pathCardPadding: CGFloat = 22
    static let pathCardInnerSpacing: CGFloat = 18
    static let pathsOuterSpacing: CGFloat = 22
    /// Former default ~200pt; +50% for wider prep columns.
    static let rosterGridMinWidth: CGFloat = 300
    static let rosterGridSpacing: CGFloat = 18
    static let scheduleCardPadding: CGFloat = 20
    static let scheduleCardSpacing: CGFloat = 16
    static let rosterSlotPadding: CGFloat = 26
    static let rosterSlotStackSpacing: CGFloat = 20
    static let rosterSlotIconSize: CGFloat = 64
    static let rosterSlotIconRowSpacing: CGFloat = 14
    static let rosterTitleStackSpacing: CGFloat = 5
    static let rosterSlotCornerRadius: CGFloat = 14
    /// Baseline card body grew ~25% vs earlier layout (taller icon column + spacing).
    static let rosterSlotMinHeight: CGFloat = 220
    static let pathCardCornerRadius: CGFloat = 12
}

/// Matches `pathColor(index)` in `OSMMapView` (golden-angle hue on HSL) so route lines and progress bars align visually.
private enum MissionPathMapColor {
    static func hueDegrees(forPathIndex index: Int) -> Double {
        (Double(index) * 137.508).truncatingRemainder(dividingBy: 360)
    }

    static func swiftUIColor(forPathIndex index: Int) -> Color {
        Color(hue: hueDegrees(forPathIndex: index) / 360, saturation: 0.88, brightness: 0.62)
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

    /// Same layout as Vehicles (`DevicesView.centeredEmptyStateBlock`): icon 44pt medium gray, title 20pt semibold white, subtitle 14pt gray, max 480pt, padding 32, centered in the pane.
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

    private var selectedRun: MissionRun? {
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
    let run: MissionRun
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

    private var scheduleIconName: String {
        switch run.scheduleMode {
        case .oneOff:
            return "calendar.badge.clock"
        case .loop, .continuous:
            return "repeat"
        }
    }

    private var scheduleSummaryText: String {
        switch run.scheduleMode {
        case .oneOff:
            if let start = run.oneOffStartAt {
                return "One-off · starts \(start.formatted(date: .omitted, time: .shortened))"
            }
            return "One-off · starts after preflight"
        case .loop, .continuous:
            let repeatText = run.loopRepeatCount > 0 ? "target \(run.loopRepeatCount) cycles" : "unbounded cycles"
            return "Loop · every \(run.loopDelayMinutesClamped)m · \(repeatText)"
        }
    }

    private var assignedSlots: Int {
        run.assignments.filter(\.hasFleetOrLegacyAssignment).count
    }

    private var unassignedSlots: Int {
        max(0, run.assignments.count - assignedSlots)
    }

    private var progressLabel: String? {
        guard let cycles = run.reportAutopilotCyclesCompleted else { return nil }
        if run.loopRepeatCount > 0 {
            return "Cycles \(cycles)/\(run.loopRepeatCount)"
        }
        return "Cycles \(cycles)"
    }

    private var progressFraction: CGFloat {
        guard let cycles = run.reportAutopilotCyclesCompleted else { return 0 }
        guard run.loopRepeatCount > 0 else { return min(1, CGFloat(cycles) / 8) }
        return min(1, CGFloat(cycles) / CGFloat(max(1, run.loopRepeatCount)))
    }

    private var progressFillColor: Color {
        switch run.status {
        case .running:
            return GuardianSemanticColors.successForeground.opacity(0.95)
        case .setup:
            return GuardianSemanticColors.warningForeground.opacity(0.95)
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
    /// MAVLink `system_id` when resolved (`nil` if unknown).
    let vehicleSystemID: Int?
    let isSelectedForSetupMap: Bool
    let onSelectForSetupMap: () -> Void
    let onChooseVehicle: () -> Void
    let onRemoveVehicle: () -> Void
    let onInfo: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterSlotStackSpacing) {
            // Row 1: image | title / subtitle | stack + sim/live badges (vertical center)
            HStack(alignment: .center, spacing: MissionRunPrepLayout.rosterSlotIconRowSpacing) {
                iconTile
                    .frame(width: MissionRunPrepLayout.rosterSlotIconSize, height: MissionRunPrepLayout.rosterSlotIconSize)

                VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterTitleStackSpacing) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GuardianDynamicColors.textPrimary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(GuardianDynamicColors.textSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isAttached, let stack = autopilotStack {
                    HStack(spacing: 6) {
                        FleetAutopilotStackBadge(stack: stack)
                        if let isSim = assignedFleetIsSimulation {
                            FleetLiveSimBadge(isSimulation: isSim)
                        }
                    }
                }
            }

            // Row 2: lifecycle status (+ optional mode line) | battery (vertical center)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if isAttached, let lifecycleStatus {
                        Text(lifecycleStatus.compactTwoWordStatus)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(lifecycleStatus.color.uiColor.opacity(0.95))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if isAttached {
                        Text("—")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GuardianDynamicColors.textSecondary)
                    } else {
                        Text("No vehicle assigned")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GuardianDynamicColors.textSecondary)
                    }
                    if let detail = assignedVehicleDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(GuardianDynamicColors.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isAttached {
                    rosterSetupBatteryCompact
                }
            }

            // Row 3: vehicle system ID
            HStack(alignment: .center, spacing: 8) {
                Text("System ID")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                Text(vehicleSystemID.map { "\($0)" } ?? "—")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(GuardianDynamicColors.textPrimary.opacity(0.9))
                Spacer(minLength: 0)
            }

            // Row 4: actions (text only, vertical center)
            HStack(alignment: .center, spacing: 10) {
                Button(action: onChooseVehicle) {
                    Text(isAttached ? "Change" : "Choose")
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(.blue)
                .controlSize(.small)

                if isAttached, let onInfo {
                    Button("Info", action: onInfo)
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer(minLength: 0)

                if isAttached {
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
        .shadow(color: .black.opacity(0.25), radius: isAttached ? 6 : 2, y: isAttached ? 2 : 1)
        .contentShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.rosterSlotCornerRadius))
        .onTapGesture {
            onSelectForSetupMap()
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

    @ViewBuilder
    private var slotLeadingGlyph: some View {
        if let names = simulationImageBasenames, !names.isEmpty {
            SimulationDeviceThumbnail(imageBasenames: names)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(4)
        } else {
            Image(systemName: "fanblades")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan.opacity(0.9), .teal.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .symbolRenderingMode(.hierarchical)
        }
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

private struct LiveOverviewMapSignature: Equatable {
    let missionID: UUID?
    let homeCoord: RouteCoordinate?
    let pathCoords: [[RouteCoordinate]]
    let markers: [MapVehicleMarker]
}

private struct SetupStagingMapSignature: Equatable {
    let missionID: UUID?
    let homeCoord: RouteCoordinate?
    let pathCoords: [[RouteCoordinate]]
    let markers: [MapVehicleMarker]
}

private struct MissionRunDetailView: View {
    @State var run: MissionRun
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var controlStore: MissionControlStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    let onBack: () -> Void
    let onUpdate: (MissionRun) -> Void
    let onStart: (MissionRun) -> Void
    let onDelete: (UUID) -> Void

    @State private var confirmDeleteRun = false
    @State private var rosterPickerAssignmentId: UUID?
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
    @State private var confirmSkipScheduledPaladinStart = false
    @State private var confirmSkipScheduledPaladinMessage = ""
    /// Initial path mission start deferral: minutes to add when using **Go** in the Progress card.
    @State private var pathStartDeferralPostponeMinutes: Int = 5
    @State private var confirmSkipPathStartDeferral = false
    @State private var confirmSkipPathStartDeferralPathID: UUID?
    @State private var confirmSkipPathStartDeferralMessage = ""
    /// MC Setup Schedule card: **Schedule** vs **Paths** (per-path MAVLink mission start delays).
    @State private var scheduleSetupCardSegment: Int = 0
    /// Loop intermission (per path): minutes to add when using **Go** on the Progress card.
    @State private var pathLoopIntermissionPostponeMinutes: Int = 5
    @State private var confirmSkipPathLoopIntermission = false
    @State private var confirmSkipPathLoopIntermissionPathID: UUID?
    @State private var confirmSkipPathLoopIntermissionMessage = ""
    /// Running sub-bar controls sidebar (cog button).
    @State private var runControlsSidebarVisible = false

    init(
        run: MissionRun,
        missionStore: MissionStore,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        controlStore: MissionControlStore,
        generalSettings: GeneralSettingsStore,
        defaultLiveMapStyle: MapTileStyle,
        onBack: @escaping () -> Void,
        onUpdate: @escaping (MissionRun) -> Void,
        onStart: @escaping (MissionRun) -> Void,
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
        _rosterPickerAssignmentId = State(initialValue: nil)
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
        controlStore.ingestVehicleTelemetryNarrative(
            runID: run.id,
            run: run,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    private func applyStopImmediate() {
        controlStore.stopRunImmediate(id: run.id, fleetLink: fleetLink, sitl: sitl)
        syncRunFromStore()
    }

    private func applyStopAfterCycle() {
        controlStore.stopRunAfterCurrentCycle(id: run.id)
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

    private var runLoopEnabled: Bool {
        run.scheduleMode != .oneOff
    }

    private func setRunLoopEnabled(_ enabled: Bool) {
        run.scheduleMode = enabled ? .loop : .oneOff
        onUpdate(run)
        syncRunFromStore()
    }

    private var resolvedMission: Mission? {
        missionStore.missions.first { $0.id == run.missionId }
    }

    private var liveMavlinkPathContext: (path: RoutePath, missionItemCount: Int)? {
        guard let mission = resolvedMission else { return nil }
        return PaladinMavlinkMissionBuilder.mavlinkMissionProgressContext(run: run, mission: mission)
    }

    private var liveMavlinkVehicleID: String? {
        guard let mission = resolvedMission, let ctx = liveMavlinkPathContext else { return nil }
        let assignment =
            run.assignments.first(where: { $0.pathId == ctx.path.id })
            ?? {
                let enabled = mission.routeMacro.paths.filter(\.enabled)
                if enabled.count == 1, enabled.first?.id == ctx.path.id {
                    return run.assignments.first(where: { $0.pathId == nil }) ?? run.assignments.first
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
        if run.repeatsAutopilotMissionCycles {
            return run.loopIntervalMinutes >= 0 && run.loopIntervalMinutes <= 59
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
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
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
                        Spacer()

                        if run.status == .setup {
                            if run.oneOffStartAt != nil {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    runSetupActionButtons(referenceNow: context.date)
                                }
                            } else {
                                runSetupActionButtons(referenceNow: Date())
                            }
                        } else if run.status == .running || run.status == .paused {
                            HStack(spacing: 8) {
                                Menu {
                                    Button("Immediate", role: .destructive) {
                                        applyStopImmediate()
                                    }
                                    Button("Finish loop", role: .destructive) {
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

                                Button {
                                    withAnimation(rosterPickerSpring) {
                                        runControlsSidebarVisible.toggle()
                                    }
                                } label: {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .help("Run controls")
                            }
                        } else if run.status == .completed {
                            Button("Back to setup") {
                                applyResetToSetup()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .controlSize(.regular)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(GuardianDynamicColors.backgroundRaised)

                    if run.pendingGracefulCycleStop, run.status == .running || run.status == .paused {
                        gracefulStopPendingBanner
                    }
                    if run.status == .running, controlStore.oneOffDeferredExecution(for: run.id) != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if let deferred = controlStore.oneOffDeferredExecution(for: run.id) {
                                oneOffDeferredExecutionBanner(
                                    deferred: deferred,
                                    now: context.date,
                                    postponeMinutes: $scheduledStartPostponeMinutes,
                                    onPostpone: {
                                        controlStore.postponeDeferredOneOffExecutionByMinutes(
                                            runID: run.id,
                                            additionalMinutes: scheduledStartPostponeMinutes,
                                            fleetLink: fleetLink,
                                            sitl: sitl,
                                            missionProvider: { [missionStore] in
                                                missionStore.missions.first { $0.id == run.missionId }
                                            }
                                        )
                                        syncRunFromStore()
                                        onUpdate(run)
                                    },
                                    onRequestStartNow: {
                                        if let def = controlStore.oneOffDeferredExecution(for: run.id) {
                                            let rough = humanizedRoughTimeUntilScheduledStart(
                                                executeAt: def.executeAt,
                                                from: Date()
                                            )
                                            confirmSkipScheduledPaladinMessage =
                                                "This mission is scheduled to start in \(rough). Are you sure you want to start it now?"
                                            confirmSkipScheduledPaladinStart = true
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .confirmationDialog(
                    "Start Paladin now?",
                    isPresented: $confirmSkipScheduledPaladinStart,
                    titleVisibility: .visible
                ) {
                    Button("Start now") {
                        controlStore.beginDeferredOneOffPaladinImmediately(
                            runID: run.id,
                            fleetLink: fleetLink,
                            sitl: sitl,
                            missionProvider: { [missionStore] in
                                missionStore.missions.first { $0.id == run.missionId }
                            }
                        )
                        syncRunFromStore()
                        onUpdate(run)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(confirmSkipScheduledPaladinMessage)
                }
                .confirmationDialog(
                    "Start next loop now?",
                    isPresented: $confirmSkipPathLoopIntermission,
                    titleVisibility: .visible
                ) {
                    Button("Start now") {
                        if let pathID = confirmSkipPathLoopIntermissionPathID {
                            controlStore.skipMissionCycleIntermissionForPath(
                                runID: run.id,
                                pathID: pathID,
                                fleetLink: fleetLink,
                                sitl: sitl,
                                missionsProvider: { [missionStore] in missionStore.missions }
                            )
                        }
                        confirmSkipPathLoopIntermissionPathID = nil
                        syncRunFromStore()
                        onUpdate(run)
                    }
                    Button("Cancel", role: .cancel) {
                        confirmSkipPathLoopIntermissionPathID = nil
                    }
                } message: {
                    Text(confirmSkipPathLoopIntermissionMessage)
                }
                .confirmationDialog(
                    "Start this path now?",
                    isPresented: $confirmSkipPathStartDeferral,
                    titleVisibility: .visible
                ) {
                    Button("Start now") {
                        if let pathID = confirmSkipPathStartDeferralPathID {
                            controlStore.skipMissionPathStartDeferralForPath(
                                runID: run.id,
                                pathID: pathID,
                                fleetLink: fleetLink,
                                sitl: sitl,
                                missionsProvider: { [missionStore] in missionStore.missions }
                            )
                        }
                        confirmSkipPathStartDeferralPathID = nil
                        syncRunFromStore()
                        onUpdate(run)
                    }
                    Button("Cancel", role: .cancel) {
                        confirmSkipPathStartDeferralPathID = nil
                    }
                } message: {
                    Text(confirmSkipPathStartDeferralMessage)
                }

                if run.status == .setup {
                    ScrollView {
                        VStack(alignment: .leading, spacing: MissionRunPrepLayout.setupBlockSpacing) {
                            setupScheduleAndMapRow
                            rosterPathsSetupSection
                        }
                        .padding(.horizontal, MissionRunPrepLayout.setupScrollPaddingH)
                        .padding(.vertical, MissionRunPrepLayout.setupScrollPaddingV)
                        .frame(maxWidth: .infinity)
                    }
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

            if run.status == .setup, rosterPickerAssignmentId != nil {
                GuardianDynamicColors.backgroundBase.opacity(0.45)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(rosterPickerSpring) {
                            rosterPickerAssignmentId = nil
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
            if run.status == .setup, let aid = rosterPickerAssignmentId {
                MissionRosterVehiclePickerSidebar(
                    vehicles: buildMissionPickableVehicles(fleetLink: fleetLink, sitl: sitl),
                    rowIsEnabled: { rosterPickDisabledReason($0, assignmentId: aid) == nil },
                    rowDisabledReason: { rosterPickDisabledReason($0, assignmentId: aid) },
                    onSelect: { v in
                        applyFleetVehicle(v, assignmentId: aid)
                        withAnimation(rosterPickerSpring) {
                            rosterPickerAssignmentId = nil
                        }
                    },
                    onClose: {
                        withAnimation(rosterPickerSpring) {
                            rosterPickerAssignmentId = nil
                        }
                    }
                )
                .frame(width: 420)
                .frame(maxHeight: .infinity)
                .background(GuardianDynamicColors.backgroundElevated)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(GuardianDynamicColors.borderSubtle)
                        .frame(width: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }

            if (run.status == .running || run.status == .paused), runControlsSidebarVisible {
                GuardianDynamicColors.backgroundBase.opacity(0.45)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(rosterPickerSpring) {
                            runControlsSidebarVisible = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(3)
            }
            if (run.status == .running || run.status == .paused), runControlsSidebarVisible {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Run controls")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GuardianDynamicColors.textPrimary)
                        Spacer(minLength: 8)
                        Button {
                            withAnimation(rosterPickerSpring) {
                                runControlsSidebarVisible = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Loop schedule")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GuardianDynamicColors.textPrimary.opacity(0.95))

                        Divider().opacity(0.18)

                        Toggle(
                            isOn: Binding(
                                get: { runLoopEnabled },
                                set: { setRunLoopEnabled($0) }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Loop")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(GuardianDynamicColors.textPrimary)
                                Text("When off, the current cycle finishes and the run ends.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                            }
                        }
                        .toggleStyle(.switch)

                        Divider().opacity(0.18)

                        Group {
                            HStack(alignment: .center, spacing: 10) {
                                Text("Times")
                                Spacer(minLength: 8)
                                Text(run.loopRepeatCount == 0 ? "Unlimited" : "\(run.loopRepeatCount)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(runLoopEnabled ? GuardianDynamicColors.textPrimary : GuardianDynamicColors.textSecondary.opacity(0.8))
                                Stepper(
                                    "",
                                    value: Binding(
                                        get: { run.loopRepeatCount },
                                        set: {
                                            run.loopRepeatCount = min(999, max(0, $0))
                                            if run.scheduleMode != .oneOff {
                                                run.scheduleMode = .loop
                                            }
                                            onUpdate(run)
                                            syncRunFromStore()
                                        }
                                    ),
                                    in: 0...999
                                )
                                .labelsHidden()
                            }

                            HStack(alignment: .center, spacing: 10) {
                                Text("Delay between cycles")
                                Spacer(minLength: 8)
                                Text("\(run.loopDelayMinutesClamped) min")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(runLoopEnabled ? GuardianDynamicColors.textPrimary : GuardianDynamicColors.textSecondary.opacity(0.8))
                                Stepper(
                                    "",
                                    value: Binding(
                                        get: { run.loopIntervalMinutes },
                                        set: {
                                            run.loopIntervalMinutes = min(59, max(0, $0))
                                            if run.scheduleMode != .oneOff {
                                                run.scheduleMode = .loop
                                            }
                                            onUpdate(run)
                                            syncRunFromStore()
                                        }
                                    ),
                                    in: 0...59
                                )
                                .labelsHidden()
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(runLoopEnabled ? GuardianDynamicColors.textPrimary : GuardianDynamicColors.textSecondary)
                        .disabled(!runLoopEnabled)
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(width: 360)
                .frame(maxHeight: .infinity)
                .background(GuardianDynamicColors.backgroundElevated)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(GuardianDynamicColors.borderSubtle)
                        .frame(width: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing))
                .zIndex(4)
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
                        controlStore.compilePaladinSession(
                            run: run,
                            mission: mission,
                            fleetVehicles: fleet
                        )
                    }
                    run.status = .running
                    let deferOneOff: Bool = {
                        guard let t = run.oneOffStartAt else { return false }
                        return t.timeIntervalSince(Date()) > MissionRun.oneOffScheduleTimeTolerance
                    }()
                    if deferOneOff, let executeAt = run.oneOffStartAt {
                        controlStore.updateRun(run)
                        controlStore.scheduleDeferredOneOffPaladinExecution(
                            runID: run.id,
                            executeAt: executeAt,
                            fleetLink: fleetLink,
                            sitl: sitl,
                            missionProvider: { [missionStore] in
                                missionStore.missions.first { $0.id == run.missionId }
                            }
                        )
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
            }
        }
        .onChange(of: run.assignments) { _ in
            syncSimBatteryDrainForRunStatus()
        }
        .onDisappear {
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

    private func rosterVehicleSystemID(for assignment: MissionRunAssignment) -> Int? {
        guard let vid = telemetryVehicleID(for: assignment) else { return nil }
        if let sid = fleetLink.vehicleModel(forVehicleID: vid)?.data.systemID {
            return sid
        }
        let prefix = "sysid:"
        if vid.hasPrefix(prefix), let n = Int(vid.dropFirst(prefix.count)) {
            return n
        }
        return nil
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
                    Text("Scheduled Paladin start")
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
                HStack(alignment: .firstTextBaseline) {
                    Text("Progress")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GuardianDynamicColors.textSecondary)
                    Spacer(minLength: 8)
                    missionLiveScheduleCounter
                }
                if let mission = resolvedMission {
                    if run.status == .running,
                       controlStore.hasMissionCycleIntermission(for: run.id) || controlStore.hasMissionPathStartDeferral(for: run.id)
                    {
                        TimelineView(.periodic(from: .now, by: 0.25)) { context in
                            missionLivePathProgressList(mission: mission, now: context.date)
                        }
                    } else {
                        missionLivePathProgressList(mission: mission, now: Date())
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
    private var missionLiveScheduleCounter: some View {
        switch run.scheduleMode {
        case .oneOff:
            Text("—")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(GuardianDynamicColors.textTertiary)
        case .loop, .continuous:
            if run.loopRepeatCount > 0 {
                Text("Runs \(controlStore.completedAutopilotCycles(for: run.id))/\(run.loopRepeatCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            } else {
                Text("Runs \(controlStore.completedAutopilotCycles(for: run.id))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func missionLivePathProgressList(mission: Mission, now: Date) -> some View {
        ForEach(Array(mission.routeMacro.paths.enumerated()), id: \.element.id) { index, path in
            missionLivePathProgressRow(path: path, pathIndex: index, mission: mission, now: now)
        }
    }

    private func missionLivePathProgressRow(path: RoutePath, pathIndex: Int, mission: Mission, now: Date) -> some View {
        let mavlinkPathId = liveMavlinkPathContext?.path.id
        let hub = liveMavlinkHub
        let tint = MissionPathMapColor.swiftUIColor(forPathIndex: pathIndex)
        let pathStartDef = controlStore.missionPathStartDeferral(for: run.id, pathID: path.id)
        let inPathStartDeferral = path.enabled
            && run.status == .running
            && (pathStartDef.map { now < $0.startAt } ?? false)
        let inter = controlStore.missionCycleIntermission(for: run.id, pathID: path.id)
        let inIntermission = path.enabled
            && run.repeatsAutopilotMissionCycles
            && run.status == .running
            && !inPathStartDeferral
            && (inter.map { now < $0.restartAt } ?? false)

        let missionFraction = missionLivePathFraction(path: path, mavlinkPathId: mavlinkPathId, hub: hub)
        let barFraction: Double
        let barTint: Color
        if inPathStartDeferral, let def = pathStartDef {
            let remaining = def.startAt.timeIntervalSince(now)
            let elapsed = def.totalDelay - max(0, remaining)
            barFraction = def.totalDelay > 0 ? min(1, max(0, elapsed / def.totalDelay)) : 1
            barTint = Color.cyan.opacity(0.78)
        } else if inIntermission, let interUnwrapped = inter {
            let remaining = interUnwrapped.restartAt.timeIntervalSince(now)
            let elapsed = interUnwrapped.totalDelay - max(0, remaining)
            barFraction = interUnwrapped.totalDelay > 0 ? min(1, max(0, elapsed / interUnwrapped.totalDelay)) : 1
            barTint = Color.orange.opacity(0.85)
        } else {
            barFraction = missionFraction
            barTint = path.enabled ? tint : Color.gray.opacity(0.35)
        }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(path.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(path.enabled ? GuardianDynamicColors.textPrimary : GuardianDynamicColors.textSecondary)
                Spacer(minLength: 6)
                Group {
                    if inPathStartDeferral, let pathStartDef {
                        Text(formattedPathStartDeferralStatus(
                            remaining: max(0, pathStartDef.startAt.timeIntervalSince(now)),
                            totalDelay: pathStartDef.totalDelay
                        ))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.cyan.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    } else if inIntermission, let inter {
                        Text(formattedIntermissionStatus(
                            inter: inter,
                            remaining: max(0, inter.restartAt.timeIntervalSince(now))
                        ))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.orange.opacity(0.92))
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    } else if path.id == mavlinkPathId, let hub, let tot = hub.missionProgressTotal, tot > 0, let cur = hub.missionProgressCurrent {
                        Text("\(cur)/\(tot)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(GuardianDynamicColors.textSecondary)
                    } else if !path.enabled {
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

            if inPathStartDeferral, let pathStartDefForControls = pathStartDef {
                HStack(alignment: .center, spacing: 8) {
                    Picker("Delay", selection: $pathStartDeferralPostponeMinutes) {
                        ForEach(1...30, id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 72, alignment: .leading)
                    .controlSize(.small)
                    Button("Go") {
                        controlStore.extendMissionPathStartDeferralForPathByMinutes(
                            runID: run.id,
                            pathID: path.id,
                            additionalMinutes: pathStartDeferralPostponeMinutes,
                            fleetLink: fleetLink,
                            sitl: sitl,
                            missionsProvider: { [missionStore] in missionStore.missions }
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
                            executeAt: pathStartDefForControls.startAt,
                            from: now
                        )
                        confirmSkipPathStartDeferralPathID = path.id
                        confirmSkipPathStartDeferralMessage =
                            "This path mission is scheduled to start in \(rough). Start it immediately?"
                        confirmSkipPathStartDeferral = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan.opacity(0.88))
                    .controlSize(.small)
                }
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 2)
            }

            if !inPathStartDeferral, inIntermission, let interForControls = inter {
                HStack(alignment: .center, spacing: 8) {
                    Picker("Delay", selection: $pathLoopIntermissionPostponeMinutes) {
                        ForEach(1...30, id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 72, alignment: .leading)
                    .controlSize(.small)
                    Button("Go") {
                        controlStore.extendMissionCycleIntermissionForPathByMinutes(
                            runID: run.id,
                            pathID: path.id,
                            additionalMinutes: pathLoopIntermissionPostponeMinutes,
                            fleetLink: fleetLink,
                            sitl: sitl,
                            missionsProvider: { [missionStore] in missionStore.missions }
                        )
                        syncRunFromStore()
                        onUpdate(run)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange.opacity(0.85))
                    .controlSize(.small)
                    compactVerticalControlSeparator()
                        .padding(.horizontal, 6)
                    Button("Start") {
                        let rough = humanizedRoughTimeUntilScheduledStart(
                            executeAt: interForControls.restartAt,
                            from: now
                        )
                        confirmSkipPathLoopIntermissionPathID = path.id
                        confirmSkipPathLoopIntermissionMessage =
                            "This path’s next loop is scheduled in \(rough). Start it immediately?"
                        confirmSkipPathLoopIntermission = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange.opacity(0.92))
                    .controlSize(.small)
                }
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 2)
            }
        }
    }

    private func formattedIntermissionStatus(inter: MissionCycleIntermission, remaining: TimeInterval) -> String {
        if inter.totalDelay < 1 {
            return remaining > 0.08 ? "Restarting…" : "Starting…"
        }
        if remaining <= 0 {
            return "Restarting…"
        }
        let secs = max(1, Int(ceil(remaining)))
        let m = secs / 60
        let s = secs % 60
        let clock = String(format: "%d:%02d", m, s)
        return "\(clock) until restart"
    }

    /// Live progress caption while a path awaits its initial MAVLink mission start (see ``MissionPathStartDeferral``).
    private func formattedPathStartDeferralStatus(remaining: TimeInterval, totalDelay: TimeInterval) -> String {
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

    private func missionLivePathFraction(path: RoutePath, mavlinkPathId: UUID?, hub: FleetHubVehicleTelemetry?) -> Double {
        guard path.enabled, path.id == mavlinkPathId, let hub, let tot = hub.missionProgressTotal, tot > 0,
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

    /// Same Leaflet/OSM stack and bbox logic as Missions route tab: home marker + path polylines from the mission template.
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
                        mapModel.allPathsCoords = mission.routeMacro.paths.map { $0.waypoints.map(\.coord) }
                    } else {
                        mapModel.home = nil
                        mapModel.allPathsCoords = []
                    }
                    mapModel.selectedPathWaypoints = []
                    mapModel.selectedWaypointIndex = nil
                    mapModel.vehicleMarkers = missionLiveVehicleMarkers
                    if let followID = mapModel.followedVehicleMarkerID,
                       !missionLiveVehicleMarkers.contains(where: { $0.id == followID }) {
                        mapModel.followedVehicleMarkerID = nil
                    }
                    mapModel.headingPreview = nil
                    mapModel.cameraPreview = nil
                    mapModel.isEditingPath = false
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
    /// shared model state. Captures the actual home/path/marker data so the
    /// `.task` re-runs whenever any vehicle drifts, the mission is edited,
    /// etc. — not just when counts change.
    private var liveOverviewMapSignature: LiveOverviewMapSignature {
        LiveOverviewMapSignature(
            missionID: resolvedMission?.id,
            homeCoord: resolvedMission?.routeMacro.home?.coord,
            pathCoords: resolvedMission?.routeMacro.paths.map { $0.waypoints.map(\.coord) } ?? [],
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
                        vehicleModel: fleetLink.primaryVehicleOperationalModel()
                    )
                } else {
                    ForEach(run.assignments) { assignment in
                        let device = resolvedMission.flatMap { m in
                            m.rosterDevices.first { $0.id == assignment.rosterDeviceId }
                        }
                        let vehicleID = telemetryVehicleID(for: assignment)
                        MissionLiveVehicleHealthCard(
                            slotTitle: assignment.slotName,
                            rosterSubtitle: rosterRoleSubtitle(device),
                            vehicleID: vehicleID,
                            simulationImageBasenames: simulationImageBasenamesForAssignment(assignment, sitl: sitl),
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

                if let session = controlStore.paladinSessionsByRunID[run.id] {
                    let phaseStyle = GuardianSemanticColors.paladinPhaseBadgeStyle(for: session.phase)
                    HStack(spacing: 6) {
                        Text(session.phase.rawValue.capitalized)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(phaseStyle.foreground)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(phaseStyle.background)
                            .clipShape(Capsule())
                        Text(paladinCondensedHeaderMetadata(session: session))
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
                .disabled(controlStore.paladinSessionsByRunID[run.id] == nil)
            }

            if let session = controlStore.paladinSessionsByRunID[run.id] {
                Divider().opacity(0.18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(session.events.suffix(80)) { event in
                            paladinLogEventRow(event: event)
                        }
                    }
                }
            } else {
                Text("No Paladin session for this run yet.")
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

    private func paladinCondensedHeaderMetadata(session: PaladinSession) -> String {
        let p = session.plan
        return "\(p.pathTopology.rawValue) · \(p.teamTopology.rawValue) · \(p.roleTracks.count) trk"
    }

    private func paladinCondensedHeaderLine(session: PaladinSession) -> String {
        "\(session.phase.rawValue) · \(paladinCondensedHeaderMetadata(session: session))"
    }

    private func paladinLiveLogPlainText(session: PaladinSession) -> String {
        let header = "Paladin — \(paladinCondensedHeaderLine(session: session))"
        let body = session.events.map { $0.plainTextLine() }
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

    private func paladinLogSeverityBorderColor(_ level: PaladinEventLevel) -> Color {
        switch level {
        case .info: return Color.white.opacity(0.22)
        case .warning: return Color.orange.opacity(0.9)
        case .error: return Color.red.opacity(0.9)
        }
    }

    @ViewBuilder
    private func paladinLogEventRow(event: PaladinEvent) -> some View {
        let mission = resolvedMission
        let pathTint: Color? = {
            guard let pid = event.pathID, let mission else { return nil }
            if let idx = mission.routeMacro.paths.firstIndex(where: { $0.id == pid }) {
                return MissionPathMapColor.swiftUIColor(forPathIndex: idx)
            }
            return nil
        }()
        let pathTextColor = pathTint ?? Color.gray.opacity(0.85)
        let speakerColor: Color = {
            switch event.speaker {
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
                if let pl = event.pathLabel {
                    Text("[\(pl)]")
                        .foregroundStyle(pathTextColor)
                }
                switch event.speaker {
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
        guard let session = controlStore.paladinSessionsByRunID[run.id] else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paladinLiveLogPlainText(session: session), forType: .string)
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
        case .oneOffAutopilotFinished, .loopCompletedAllRepeats:
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
        case .loopCompletedAllRepeats:
            return "Loop schedule finished"
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
            return "The scheduled one-off mission cycle completed on the autopilot."
        case .loopCompletedAllRepeats:
            return "All configured loop iterations completed successfully."
        case .none:
            return "This run is marked complete. Older runs may not store a detailed outcome."
        }
    }

    private var completedScheduleCyclesCard: some View {
        completedReportCardChrome(title: "Schedule & cycles", accent: Color.white.opacity(0.2)) {
            labeledReportRow("Schedule mode", run.scheduleMode.rawValue)
            if run.scheduleMode == .loop {
                let limit = run.loopRepeatCount
                labeledReportRow(
                    "Loop target",
                    limit > 0 ? "\(limit) mission run(s)" : "Repeat until stopped"
                )
                let intervalLabel =
                    run.loopDelayMinutesClamped == 0
                    ? "Immediate (next cycle as soon as ready)"
                    : "Every \(run.loopDelayMinutesClamped) minute(s)"
                labeledReportRow("Between cycles", intervalLabel)
            }
            let plannedStart: String? = {
                if let t = run.oneOffStartAt {
                    return t.formatted(date: .abbreviated, time: .shortened)
                }
                if run.scheduleMode == .oneOff {
                    return "Immediate (when started)"
                }
                return nil
            }()
            if let plannedStart {
                labeledReportRow("Planned start", plannedStart)
            }
            let cycles = run.reportAutopilotCyclesCompleted ?? 0
            labeledReportRow(
                "Autopilot mission cycles completed",
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
            if controlStore.paladinSessionsByRunID[run.id] == nil {
                Text("No Paladin session is stored for this run.")
                    .font(.system(size: 13))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            } else {
                let events = controlStore.paladinSessionsByRunID[run.id]?.events.count ?? 0
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
        controlStore.paladinSessionsByRunID[run.id]?.events.filter { $0.level == .error }.count ?? 0
    }

    private var completedPaladinWarningCount: Int {
        controlStore.paladinSessionsByRunID[run.id]?.events.filter { $0.level == .warning }.count ?? 0
    }

    private var completedPaladinLogExportSection: some View {
        let session = controlStore.paladinSessionsByRunID[run.id]
        let text = session.map { paladinLiveLogPlainText(session: $0) } ?? ""
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
                .disabled(session == nil || text.isEmpty)

                Button("Save…") {
                    saveCompletedPaladinLog()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(session == nil || text.isEmpty)

                Button("Print…") {
                    printCompletedPaladinLog()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(session == nil || text.isEmpty)
            }

            if session == nil {
                Text("No Paladin session for this run.")
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
        guard let session = controlStore.paladinSessionsByRunID[run.id] else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paladinLiveLogPlainText(session: session), forType: .string)
    }

    private func saveCompletedPaladinLog() {
        guard let session = controlStore.paladinSessionsByRunID[run.id] else { return }
        let text = paladinLiveLogPlainText(session: session)
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
        guard let session = controlStore.paladinSessionsByRunID[run.id] else { return }
        let text = paladinLiveLogPlainText(session: session)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 2000))
        tv.string = text
        tv.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        tv.isEditable = false
        tv.drawsBackground = false
        let op = NSPrintOperation(view: tv, printInfo: NSPrintInfo.shared)
        op.jobTitle = "\(run.missionName) — Paladin log"
        op.run()
    }

    private var scheduleSetupCard: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.scheduleCardSpacing) {
            Picker("", selection: $scheduleSetupCardSegment) {
                Text("Schedule").tag(0)
                Text("Paths").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                if scheduleSetupCardSegment == 0 {
                    scheduleSetupScheduleTabContent
                } else {
                    scheduleSetupPathsTabContent
                }
            }
        }
        .padding(MissionRunPrepLayout.scheduleCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.pathCardCornerRadius))
    }

    /// Per-path binding: omit path from `run.pathStartDelays` when delay is zero.
    private func pathStartDelayBinding(pathId: UUID) -> Binding<Int> {
        Binding(
            get: {
                run.pathStartDelays.first { $0.pathId == pathId }?.startDelayMinutes ?? 0
            },
            set: { newValue in
                let clamped = min(59, max(0, newValue))
                var list = run.pathStartDelays
                list.removeAll { $0.pathId == pathId }
                if clamped > 0 {
                    list.append(PathStartDelay(pathId: pathId, startDelayMinutes: clamped))
                }
                run.pathStartDelays = list
                onUpdate(run)
            }
        )
    }

    private var scheduleSetupPathsTabContent: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.scheduleCardSpacing) {
            Text("Mission start delays")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textPrimary.opacity(0.92))
            Text(
                "After Paladin finishes staging at execution start, each path’s MAVLink mission upload/start waits this many minutes (0 = start with the run)."
            )
            .font(.system(size: 11))
            .foregroundStyle(GuardianDynamicColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if let mission = resolvedMission {
                ForEach(mission.routeMacro.paths) { path in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(path.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(path.enabled ? GuardianDynamicColors.textPrimary : GuardianDynamicColors.textSecondary.opacity(0.72))
                            .lineLimit(2)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Text("Delay")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.gray.opacity(0.85))
                        Picker("Delay", selection: pathStartDelayBinding(pathId: path.id)) {
                            ForEach(0...59, id: \.self) { m in
                                Text(m == 0 ? "0 min" : "\(m) min").tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 88, alignment: .trailing)
                        .labelsHidden()
                    }
                    .opacity(path.enabled ? 1 : 0.55)
                }
            } else {
                Text("Mission template unavailable for this run.")
                    .font(.system(size: 12))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            }
        }
    }

    private var scheduleSetupScheduleTabContent: some View {
        let loopOn = run.scheduleMode == .loop || run.scheduleMode == .continuous
        return VStack(alignment: .leading, spacing: MissionRunPrepLayout.scheduleCardSpacing) {
            Text("Timing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textPrimary.opacity(0.92))

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

            Toggle(
                "Loop",
                isOn: Binding(
                    get: { loopOn },
                    set: { enabled in
                        if enabled {
                            run.scheduleMode = .loop
                            run.loopIntervalMinutes = min(59, max(0, run.loopIntervalMinutes))
                            run.loopRepeatCount = min(9999, max(0, run.loopRepeatCount))
                        } else {
                            run.scheduleMode = .oneOff
                        }
                        onUpdate(run)
                    }
                )
            )
            .tint(.blue)

            if loopOn {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Times")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GuardianDynamicColors.textPrimary)
                    HStack(spacing: 6) {
                        StrictNumberField(
                            value: Binding(
                                get: { Double(run.loopRepeatCount) },
                                set: {
                                    run.loopRepeatCount = min(9999, max(0, Int($0.rounded())))
                                    onUpdate(run)
                                }
                            ),
                            step: 1,
                            min: 0,
                            max: 9999
                        )
                        .frame(width: 72)
                        Stepper(
                            "",
                            value: Binding(
                                get: { run.loopRepeatCount },
                                set: {
                                    run.loopRepeatCount = min(9999, max(0, $0))
                                    onUpdate(run)
                                }
                            ),
                            in: 0...9999,
                            step: 1
                        )
                        .labelsHidden()
                    }
                }
                Text("Mission cycles before the run completes (0 = repeat until you stop the run).")
                    .font(.system(size: 11))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Stepper(
                    "Delay between cycles: \(run.loopIntervalMinutes) min",
                    value: Binding(
                        get: { run.loopIntervalMinutes },
                        set: {
                            run.loopIntervalMinutes = min(59, max(0, $0))
                            onUpdate(run)
                        }
                    ),
                    in: 0...59
                )
                Text("Wait between autopilot mission cycles (0 = start the next cycle immediately).")
                    .font(.system(size: 11))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scheduleDefaultDeferredStartDate() -> Date {
        Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
    }

    private var setupScheduleAndMapRow: some View {
        GeometryReader { geo in
            let spacing = MissionRunPrepLayout.rosterGridSpacing
            let usableWidth = max(0, geo.size.width - spacing)
            let scheduleWidth = usableWidth * 0.33
            let mapWidth = usableWidth * 0.67
            HStack(alignment: .top, spacing: spacing) {
                scheduleSetupCard
                    .frame(width: scheduleWidth)
                setupVehicleStagingMapCard
                    .frame(width: mapWidth)
            }
        }
        .frame(minHeight: 370, maxHeight: 420)
    }

    private var rosterPathsSetupSection: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.pathsOuterSpacing) {
            if run.assignments.isEmpty {
                Text("No roster slots on this mission template.")
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
            } else if let mission = resolvedMission {
                ForEach(mission.routeMacro.paths) { path in
                    pathRosterCard(path: path, mission: mission)
                }
                legacyPathlessRosterCard(mission: mission)
            } else {
                missionMissingTemplateRosterFallback
            }
        }
    }

    private var setupVehicleStagingMapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vehicle staging map")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textPrimary)

            Text(stagingMapInstructionText)
                .font(.system(size: 12))
                .foregroundStyle(GuardianDynamicColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

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
                    mapModel.allPathsCoords = mission.routeMacro.paths.map { $0.waypoints.map(\.coord) }
                } else {
                    mapModel.home = nil
                    mapModel.allPathsCoords = []
                }
                mapModel.selectedPathWaypoints = []
                mapModel.selectedWaypointIndex = nil
                mapModel.vehicleMarkers = setupVehicleMarkers
                mapModel.headingPreview = nil
                mapModel.cameraPreview = nil
                mapModel.isEditingPath = false
            }
            .frame(minHeight: 260, maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(GuardianDynamicColors.borderSubtle, lineWidth: 1)
            )
        }
        .padding(MissionRunPrepLayout.pathCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.pathCardCornerRadius))
    }

    /// Equatable signature of all setup-staging-map inputs (mission home /
    /// paths + every vehicle marker). Pushed into `mapModel` whenever any
    /// underlying coordinate or marker drag changes.
    private var setupStagingMapSignature: SetupStagingMapSignature {
        SetupStagingMapSignature(
            missionID: resolvedMission?.id,
            homeCoord: resolvedMission?.routeMacro.home?.coord,
            pathCoords: resolvedMission?.routeMacro.paths.map { $0.waypoints.map(\.coord) } ?? [],
            markers: setupVehicleMarkers
        )
    }

    private var stagingMapInstructionText: String {
        guard let aid = setupSelectedAssignmentId,
              let assignment = run.assignments.first(where: { $0.id == aid }),
              let tokenKey = assignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: tokenKey)
        else {
            return "Select a roster slot and click map to set SIM start point. Live vehicles remain read-only."
        }
        switch token {
        case .sitl:
            return "Selected SIM slot: click map to set start position override before mission execution."
        case .live:
            return "Selected live vehicle: position is read-only and updates from telemetry."
        }
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
        run.assignments.indices.filter { run.assignments[$0].pathId == nil }
    }

    private func pathRosterCard(path: RoutePath, mission: Mission) -> some View {
        let indices = run.assignments.indices.filter { run.assignments[$0].pathId == path.id }
        return VStack(alignment: .leading, spacing: MissionRunPrepLayout.pathCardInnerSpacing) {
            Text(path.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GuardianDynamicColors.textPrimary)

            if indices.isEmpty {
                Text("No roster slots linked to this path. Link devices to the path in Missions → Roster.")
                    .font(.system(size: 12))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
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
                    ForEach(indices, id: \.self) { idx in
                        rosterSlotCard(assignmentIndex: idx, mission: mission)
                    }
                }
            }
        }
        .padding(MissionRunPrepLayout.pathCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.pathCardCornerRadius))
    }

    @ViewBuilder
    private func legacyPathlessRosterCard(mission: Mission) -> some View {
        let indices = legacyUnassignedIndices
        if !indices.isEmpty {
            VStack(alignment: .leading, spacing: MissionRunPrepLayout.pathCardInnerSpacing) {
                Text("Mission roster")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textPrimary)
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
                    ForEach(indices, id: \.self) { idx in
                        rosterSlotCard(assignmentIndex: idx, mission: mission)
                    }
                }
            }
            .padding(MissionRunPrepLayout.pathCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GuardianDynamicColors.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.pathCardCornerRadius))
        }
    }

    private var missionMissingTemplateRosterFallback: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.pathCardInnerSpacing) {
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
        .padding(MissionRunPrepLayout.pathCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.pathCardCornerRadius))
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
        let systemID = rosterVehicleSystemID(for: a)
        return MissionControlRosterSlotCard(
            title: a.slotName,
            subtitle: rosterRoleSubtitle(device),
            isAttached: slotFilled,
            assignedVehicleDetail: detailLine,
            rosterBatterySummary: batterySummary,
            assignedFleetIsSimulation: rosterAssignmentFleetIsSimulation(a),
            autopilotStack: rosterAutopilotStack(for: a),
            simulationImageBasenames: basenames,
            lifecycleStatus: rosterLifecycleStatus(for: a),
            vehicleSystemID: systemID,
            isSelectedForSetupMap: setupSelectedAssignmentId == assignmentId,
            onSelectForSetupMap: {
                setupSelectedAssignmentId = assignmentId
            },
            onChooseVehicle: {
                setupSelectedAssignmentId = assignmentId
                withAnimation(rosterPickerSpring) {
                    rosterPickerAssignmentId = assignmentId
                }
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
        let hint = device.positionHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if hint.isEmpty { return device.roleType }
        return "\(device.roleType) · \(hint)"
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
            if let names = simulationImageBasenames, !names.isEmpty {
                SimulationDeviceThumbnail(imageBasenames: names)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(3)
            } else {
                Image(systemName: "fanblades")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan.opacity(0.9), .teal.opacity(0.65)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
            }
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
        GuardianModalTemplate(
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
