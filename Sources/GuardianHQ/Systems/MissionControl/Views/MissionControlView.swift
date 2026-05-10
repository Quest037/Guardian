// MissionControlView.swift — MC: mission runs grid, add-run sheet, and entry into a run.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
                Spacer(minLength: 0)
                GuardianPrimaryProminentButton(title: "Add Run") {
                    showingAddRunSheet = true
                }
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
                                    mission: missionStore.missions.first { $0.id == run.missionId },
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

struct MissionRunStatusBadge: View {
    let status: MissionRunStatus
    /// When set, running/paused runs in abort wind-down use abort styling instead of the coarse status alone.
    var sessionPhase: MissionRunSessionPhase?

    init(status: MissionRunStatus, sessionPhase: MissionRunSessionPhase? = nil) {
        self.status = status
        self.sessionPhase = sessionPhase
    }

    private var isAbortWindDownActive: Bool {
        guard let sessionPhase else { return false }
        return (status == .running || status == .paused)
            && (sessionPhase == .aborting || sessionPhase == .aborted)
    }

    private var displayTitle: String {
        if isAbortWindDownActive {
            return sessionPhase == .aborted ? "Aborted" : "Aborting"
        }
        return status.rawValue.capitalized
    }

    var body: some View {
        Text(displayTitle)
            .font(.system(size: 10, weight: .heavy))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(Capsule())
    }

    private var background: Color {
        if isAbortWindDownActive { return GuardianSemanticColors.dangerBackground }
        switch status {
        case .running:
            return GuardianSemanticColors.successBackground
        case .setup:
            return GuardianSemanticColors.warningBackground
        case .recovery:
            return GuardianSemanticColors.infoBackground
        case .paused, .completed:
            return GuardianSemanticColors.neutralBadgeBackground
        }
    }

    private var foreground: Color {
        if isAbortWindDownActive { return GuardianSemanticColors.dangerForeground }
        switch status {
        case .running:
            return GuardianSemanticColors.successForeground
        case .setup:
            return GuardianSemanticColors.warningForeground
        case .recovery:
            return GuardianSemanticColors.infoForeground
        case .paused, .completed:
            return GuardianSemanticColors.neutralBadgeForeground
        }
    }
}

private func gracefulStopKindGridLabel(_ kind: MissionRunGracefulStopKind) -> String {
    switch kind {
    case .none: return ""
    case .abortAfterCycle: return "Abort after cycle"
    case .completeAfterCycle: return "Complete after cycle"
    }
}

private struct MissionRunCard: View {
    let run: MissionRunEnvironment
    /// Template whose mission-card JPEG is shown (same asset as Missions grid / Add Run).
    let mission: Mission?
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private static let runCardBannerHeight: CGFloat = 76
    private static let runCardBannerThumb: CGFloat = 58

    private var cardConfiguration: GuardianCardConfiguration {
        GuardianCardConfiguration(
            border: isSelected ? .none : .subtle,
            cornerRadius: GuardianCardLayout.cornerRadius,
            bodyPadding: 12
        )
    }

    var body: some View {
        GuardianCard(
            configuration: cardConfiguration,
            media: {
                runCardMissionThumbnail
            },
            body: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(run.missionName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        MissionRunStatusBadge(status: run.status, sessionPhase: run.sessionPhase)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: scheduleIconName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                        Text(scheduleSummaryText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if run.gracefulStopKind != .none {
                            Text(gracefulStopKindGridLabel(run.gracefulStopKind))
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
                                .foregroundStyle(theme.textTertiary)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(theme.borderSubtle)
                                    Capsule()
                                        .fill(progressFillColor)
                                        .frame(width: geo.size.width * progressFraction)
                                }
                            }
                            .frame(height: 5)
                        }
                    }

                    Rectangle()
                        .fill(theme.borderSubtle)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)

                    Text(timelineSummaryText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: cardConfiguration.cornerRadius, style: .continuous)
                    .strokeBorder(GuardianSemanticColors.infoForeground.opacity(0.55), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var runCardMissionThumbnail: some View {
        if let mission {
            MissionCardThumbnailView(
                mission: mission,
                gridBannerBarHeight: Self.runCardBannerHeight,
                gridThumbnailSide: Self.runCardBannerThumb
            )
        } else {
            ZStack {
                Color(red: 0x12 / 255, green: 0x15 / 255, blue: 0x1c / 255)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.textSecondary.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.runCardBannerHeight)
        }
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

    private var isAbortProtocolWindDown: Bool {
        (run.status == .running || run.status == .paused)
            && (run.sessionPhase == .aborting || run.sessionPhase == .aborted)
    }

    private var progressFillColor: Color {
        if isAbortProtocolWindDown {
            return GuardianSemanticColors.dangerForeground.opacity(0.92)
        }
        switch run.status {
        case .running:
            return GuardianSemanticColors.successForeground.opacity(0.95)
        case .setup:
            return theme.textSecondary.opacity(0.85)
        case .paused:
            return theme.textSecondary.opacity(0.9)
        case .recovery:
            return GuardianSemanticColors.infoForeground.opacity(0.95)
        case .completed:
            return GuardianSemanticColors.infoForeground.opacity(0.95)
        }
    }

    private var timelineSummaryText: String {
        if isAbortProtocolWindDown {
            if let startedAt = run.startedAt {
                return "Abort protocol after run started \(startedAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Abort protocol in progress"
        }
        switch run.status {
        case .setup:
            return "Created \(run.createdAt.formatted(date: .abbreviated, time: .shortened))"
        case .running, .paused:
            if let startedAt = run.startedAt {
                return "Started \(startedAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Created \(run.createdAt.formatted(date: .abbreviated, time: .shortened))"
        case .recovery:
            if let startedAt = run.startedAt {
                return "Recovery after run started \(startedAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Recovery in progress"
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
                .foregroundStyle(theme.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct AddMissionRunSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var missionStore: MissionStore
    let onCreateRun: (Mission) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    /// Archived templates stay in Missions but must not be startable from Mission Control.
    private var missionsSelectableForNewRun: [Mission] {
        missionStore.missions.filter { !$0.isArchived }
    }

    var body: some View {
        Modal(
            title: "Select Mission",
            headerActions: {
                GuardianThemedButton(
                    title: "Close",
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: { dismiss() }
                )
                .keyboardShortcut(.cancelAction)
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: 12) {
                    if missionsSelectableForNewRun.isEmpty {
                        Group {
                            if missionStore.missions.isEmpty {
                                Text("No mission templates available.")
                            } else {
                                Text("All mission templates are archived. Unarchive a mission in Missions to start a run.")
                            }
                        }
                        .foregroundStyle(theme.textSecondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(missionsSelectableForNewRun) { mission in
                                    Button {
                                        onCreateRun(mission)
                                        dismiss()
                                    } label: {
                                        HStack(alignment: .center, spacing: 10) {
                                            MissionCardThumbnailView(mission: mission, fixedLength: 48)
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
