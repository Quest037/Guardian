// MCRLiveTaskListRowChrome.swift — MC-R Tasks list row chrome driven by ``MCRLiveTaskListRowSnapshot`` (card body + live deferral/squad timers).
import SwiftUI

/// Filled capsule progress bar (matches ``MissionRunDetailView/missionLiveAnimatedProgressBar`` chrome).
struct MCRLiveCapsuleProgressBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 7
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        GeometryReader { geo in
            let w = max(0, min(1, fraction)) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.11))
                Capsule()
                    .fill(tint)
                    .frame(width: w)
                    .animation(.easeInOut(duration: 0.35), value: fraction)
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
            )
        }
        .frame(height: height)
    }
}

private func mcrLiveTaskStateForeground(_ state: MissionTaskState, theme: GuardianThemePalette) -> Color {
    switch state {
    case .compiling, .ready:
        return theme.textSecondary
    case .staging:
        return GuardianSemanticColors.infoForeground
    case .executing:
        return GuardianSemanticColors.successForeground
    case .between:
        return GuardianSemanticColors.warningForeground
    case .recovery:
        return GuardianSemanticColors.infoForeground
    case .aborting, .aborted:
        return GuardianSemanticColors.dangerForeground
    case .completed:
        return GuardianSemanticColors.successForeground
    }
}

private func mcrLiveSquadStateBadge(
    _ squad: MCRLiveTaskListSquadRowSnapshot,
    theme: GuardianThemePalette
) -> some View {
    let title = squad.rawSquadState.displayTitle
    let fg: Color = {
        if squad.rawSquadState == .paused {
            return GuardianSemanticColors.warningForeground
        }
        return mcrLiveTaskStateForeground(squad.displayState, theme: theme)
    }()
    return Text(title.uppercased())
        .font(GuardianTypography.font(.mapWaypointMicroHeavy))
        .tracking(0.4)
        .padding(.horizontal, GuardianSpacing.xsTight)
        .padding(.vertical, GuardianSpacing.titleStackTight)
        .foregroundStyle(fg)
        .background(
            Capsule()
                .fill(theme.backgroundElevated)
                .overlay(
                    Capsule()
                        .strokeBorder(fg.opacity(0.4), lineWidth: 1)
                )
        )
}

private func mcrLiveTaskStateBadge(_ state: MissionTaskState, theme: GuardianThemePalette) -> some View {
    let fg = mcrLiveTaskStateForeground(state, theme: theme)
    return Text(state.displayTitle.uppercased())
        .font(GuardianTypography.font(.mapWaypointMicroHeavy))
        .tracking(0.4)
        .padding(.horizontal, GuardianSpacing.xsTight)
        .padding(.vertical, GuardianSpacing.titleStackTight)
        .foregroundStyle(fg)
        .background(
            Capsule()
                .fill(theme.backgroundElevated)
                .overlay(
                    Capsule()
                        .strokeBorder(fg.opacity(0.4), lineWidth: 1)
                )
        )
}

/// Tappable summary + progress bars for one MC-R task row (footer actions stay in ``MissionRunDetailView``).
struct MCRLiveTaskListRowChrome: View {
    let presentation: MCRLiveTaskListRowPresentation
    let task: RoutePath
    let onTap: () -> Void
    /// When set, per-squad MAVLink start deferral rows render **Sooner / Later / Start** under the countdown bar.
    var squadDeferralAlterRow: ((MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var s: MCRLiveTaskListRowSnapshot { presentation.snapshot }

    private var missionBarTint: Color {
        let mapTint = MissionTaskMapColor.swiftUIColor(forTaskIndex: s.taskIndex)
        return s.taskEnabled ? mapTint : Color.gray.opacity(0.35)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    HStack(alignment: .center, spacing: GuardianSpacing.xsTight) {
                        Text(s.taskName)
                            .font(GuardianTypography.font(.formFieldLabel))
                            .foregroundStyle(s.taskEnabled ? theme.textPrimary : theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: GuardianSpacing.xsTight) {
                            mcrLiveTaskStateBadge(s.taskState, theme: theme)
                            if let slotAttention = s.slotAttention {
                                MissionControlRosterSlotAttentionCapsule(
                                    severity: slotAttention.severity,
                                    title: slotAttention.title,
                                    help: slotAttention.help,
                                    compactMetrics: true
                                )
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    if let attempting = s.attemptingState {
                        Text(attempting.displayTitle)
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Wind-down intent: \(attempting.displayTitle)")
                    }

                    cycleWaypointRow

                    if s.showMissionProgressBar {
                        MCRLiveCapsuleProgressBar(
                            fraction: s.missionProgressFraction,
                            tint: missionBarTint,
                            height: 7
                        )
                    }

                    if s.showPerSquadBars {
                        MCRLiveSquadRowsFromSnapshot(
                            snapshot: s,
                            compactMetrics: true,
                            deferralAlterRow: squadDeferralAlterRow
                        )
                            .padding(.top, GuardianSpacing.micro)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(GuardianPointerPlainButtonStyle())
            .help("Open task triage")

            if s.showStandaloneDeferralBlock, let def = s.taskStartDeferralForStandaloneBlock {
                standaloneDeferralBlock(def: def)
            }
        }
    }

    private var cycleWaypointRow: some View {
        let font = GuardianTypography.font(.inlineNoticeDetail)
        return HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
            if let cycle = s.cyclesLineText {
                Text(cycle)
                    .font(font)
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: GuardianSpacing.xs)
            Text(s.waypointsLineText)
                .font(font)
                .foregroundStyle(theme.textSecondary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func standaloneDeferralBlock(def: MissionTaskStartDeferral) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            Divider()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    Text(
                        MCRLiveTaskListProgressFormatting.formattedTaskStartDeferralStatus(
                            remaining: max(0, def.startAt.timeIntervalSince(now)),
                            totalDelay: def.totalDelay
                        )
                    )
                    .font(GuardianTypography.font(.telemetryMono10Regular))
                    .foregroundStyle(Color.cyan.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    MCRLiveCapsuleProgressBar(
                        fraction: MCRLiveTaskListProgressFormatting.missionTaskStartDeferralBarFraction(
                            taskStartDef: def,
                            now: now
                        ),
                        tint: Color.cyan.opacity(0.78),
                        height: 7
                    )
                }
            }
        }
    }

}

/// Per-primary squad stack from ``MCRLiveTaskListRowSnapshot`` (task list compact layout vs triage hero metrics).
struct MCRLiveSquadRowsFromSnapshot: View {
    let snapshot: MCRLiveTaskListRowSnapshot
    var compactMetrics: Bool
    var deferralAlterRow: ((MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var mapTint: Color { MissionTaskMapColor.swiftUIColor(forTaskIndex: snapshot.taskIndex) }

    private var missionBarTint: Color {
        snapshot.taskEnabled ? mapTint : Color.gray.opacity(0.35)
    }

    private func resolvedPerSquadBarTint() -> Color {
        compactMetrics ? missionBarTint.opacity(0.88) : mapTint.opacity(0.82)
    }

    var body: some View {
        let squadBarTint = resolvedPerSquadBarTint()
        let nameFont = compactMetrics
            ? GuardianTypography.font(.telemetryMono10Regular)
            : GuardianTypography.font(.denseCaption10Regular)
        let labelTint = compactMetrics ? theme.textTertiary : theme.textSecondary
        let deferralCaptionFont = compactMetrics
            ? GuardianTypography.font(.telemetryMono10Regular)
            : GuardianTypography.font(.inlineNoticeDetail)
        let squadBlockSpacing: CGFloat = compactMetrics ? GuardianSpacing.sm : GuardianSpacing.xs

        VStack(alignment: .leading, spacing: squadBlockSpacing) {
            ForEach(snapshot.squadRows) { squad in
                VStack(alignment: .leading, spacing: compactMetrics ? GuardianSpacing.xs : GuardianSpacing.xsTight) {
                    HStack(alignment: .center, spacing: compactMetrics ? GuardianSpacing.xsTight : GuardianSpacing.xs) {
                        Text(squad.squadLabel)
                            .font(nameFont)
                            .foregroundStyle(labelTint)
                        Spacer(minLength: 0)
                        mcrLiveSquadStateBadge(squad, theme: theme)
                    }
                    MCRLiveCapsuleProgressBar(
                        fraction: squad.progressFraction,
                        tint: squadBarTint,
                        height: 7
                    )
                    if let def = squad.activeStartDeferral {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let now = context.date
                            VStack(alignment: .leading, spacing: compactMetrics ? GuardianSpacing.xsTight : GuardianSpacing.xs) {
                                Text(
                                    MCRLiveTaskListProgressFormatting.formattedTaskStartDeferralStatus(
                                        remaining: max(0, def.startAt.timeIntervalSince(now)),
                                        totalDelay: def.totalDelay
                                    )
                                )
                                .font(deferralCaptionFont)
                                .foregroundStyle(Color.cyan.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                MCRLiveCapsuleProgressBar(
                                    fraction: MCRLiveTaskListProgressFormatting.missionTaskStartDeferralBarFraction(
                                        taskStartDef: def,
                                        now: now
                                    ),
                                    tint: Color.cyan.opacity(0.78),
                                    height: 7
                                )
                                if let deferralAlterRow {
                                    deferralAlterRow(squad, def, now)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
