// MissionControlLiveTaskTriageProjection.swift — MC-R task triage: narrow Equatable snapshot for operator-protocol chrome (Phase 6).
import SwiftUI

/// Value snapshot of ``MissionRunEnvironment`` fields that drive the **static** task triage strip (state chip,
/// attempting line, §3 auto-ack blockers, end-of-protocol acknowledgement). Wind-down and progress hero stay on
/// ``TimelineView`` paths that need wall-clock / hub merges.
@MainActor
struct MissionControlLiveTaskTriageProjection: Equatable {
    let taskID: UUID
    let taskState: MissionTaskState
    let taskAttempting: MissionTaskAttemptState?
    let showAutoAckSlotBlockers: Bool
    let autoAckBlockerRows: [MissionRunAutoMissionEndAckSlotRowSnapshot]
    let showManualTriageHintForAutoAck: Bool
    let endProtocolAckSurface: EndProtocolAckSurface
    /// Run-level brain bindings (task kind + vehicle class) for operator triage context.
    let brainBindingCaptions: [String]

    enum EndProtocolAckSurface: Equatable {
        case none
        case recovery
        case aborting
    }

    static func make(run: MissionRunEnvironment, task: RoutePath) -> MissionControlLiveTaskTriageProjection {
        let tid = task.id
        let state = run.taskStateByTaskID[tid] ?? .ready
        let attempting = run.taskAttemptingByTaskID[tid]

        let showAutoAck = Self.showsAutoAckSlotBlockers(run: run, task: task)
        let bound = run.assignmentsBoundToMissionTask(taskID: tid)
        let abortIssued = run.missionTaskAbortWindDownIssuedTaskIDs.contains(tid)
        let blockers: [MissionRunAutoMissionEndAckSlotRowSnapshot] = {
            guard showAutoAck else { return [] }
            return abortIssued
                ? MissionRunSlotEvidenceAutoMissionEndAckRules.boundRosterRowsBlockingAutoMissionEndAck(bound)
                : MissionRunSlotEvidenceAutoMissionEndAckRules.boundRosterRowsBlockingCompleteMissionEndAutoAck(bound)
        }()

        let manualHint = Self.endProtocolAcknowledgementVisible(run: run, task: task)

        let endSurface: EndProtocolAckSurface = {
            switch state {
            case .recovery: return .recovery
            case .aborting: return .aborting
            default: return .none
            }
        }()

        let brainCaptions = run.brainBindings
            .sorted {
                if $0.vehicleClassRaw != $1.vehicleClassRaw {
                    return $0.vehicleClassRaw < $1.vehicleClassRaw
                }
                return $0.taskKindRaw < $1.taskKindRaw
            }
            .map { GuardianBrainRunUtilities.bindingCaption($0) }

        return MissionControlLiveTaskTriageProjection(
            taskID: tid,
            taskState: state,
            taskAttempting: attempting,
            showAutoAckSlotBlockers: showAutoAck,
            autoAckBlockerRows: blockers,
            showManualTriageHintForAutoAck: manualHint,
            endProtocolAckSurface: endSurface,
            brainBindingCaptions: brainCaptions
        )
    }

    private static func showsAutoAckSlotBlockers(run: MissionRunEnvironment, task: RoutePath) -> Bool {
        guard run.operatorTriageMarkedMissionTaskStateByTaskID[task.id] == nil else { return false }
        let abortIssued = run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id)
        let completeIssued = run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id)
        let perSquadFiniteRace = MissionRunEnvironment.allPrimariesDispatchedPerSquadCompletePolicyWindDown(task: task, run: run)
        guard abortIssued || completeIssued || perSquadFiniteRace else { return false }
        let bound = run.assignmentsBoundToMissionTask(taskID: task.id)
        guard !bound.isEmpty else { return false }
        if abortIssued {
            return !MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded(bound)
        }
        return !MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsSatisfiedForCompleteMissionEndAutoAck(bound)
    }

    private static func endProtocolAcknowledgementVisible(run: MissionRunEnvironment, task: RoutePath) -> Bool {
        switch run.taskStateByTaskID[task.id] ?? .ready {
        case .recovery, .aborting: return true
        default: return false
        }
    }
}

/// Operator-protocol strip for the task triage sheet (no ``@ObservedObject`` on ``MissionRunEnvironment`` here — ``let run`` only).
@MainActor
struct MissionControlLiveTaskTriageOperatorProtocolStrip: View {
    let projection: MissionControlLiveTaskTriageProjection
    let task: RoutePath
    let run: MissionRunEnvironment
    let onUpdate: (MissionRunEnvironment) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            missionLiveTaskStateBanner(projection.taskState)
                .padding(.top, GuardianSpacing.denseGutter)
            if let attempting = projection.taskAttempting {
                missionLiveTaskAttemptIntentLine(attempting)
                    .padding(.horizontal, GuardianSpacing.denseGutter)
            }

            if !projection.brainBindingCaptions.isEmpty {
                missionLiveBrainBindingsLine(projection.brainBindingCaptions)
                    .padding(.horizontal, GuardianSpacing.denseGutter)
            }

            if projection.showAutoAckSlotBlockers, !projection.autoAckBlockerRows.isEmpty {
                autoAckBlockersSection(
                    task: task,
                    blockers: projection.autoAckBlockerRows,
                    showManualTriageHint: projection.showManualTriageHintForAutoAck
                )
            }

            endProtocolAcknowledgementBlock(surface: projection.endProtocolAckSurface, task: task)
        }
    }

    // MARK: - Chrome (mirrors former ``MissionRunDetailView`` helpers; kept local so this file stays self-contained)

    private func missionLiveTaskStateBanner(_ state: MissionTaskState) -> some View {
        HStack(spacing: GuardianSpacing.xs) {
            Circle()
                .fill(missionLiveTaskStateForeground(state))
                .frame(width: 7, height: 7)
            Text(state.displayTitle)
                .font(GuardianTypography.font(.inlineNoticeTitle))
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .padding(.vertical, GuardianSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.backgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(missionLiveTaskStateForeground(state).opacity(0.32), lineWidth: 1)
                )
        )
    }

    private func missionLiveTaskStateForeground(_ state: MissionTaskState) -> Color {
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

    @ViewBuilder
    private func missionLiveBrainBindingsLine(_ captions: [String]) -> some View {
        Text("Brains: \(captions.joined(separator: " · "))")
            .font(GuardianTypography.font(.denseCaption12Regular))
            .foregroundStyle(theme.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Autonomy brains: \(captions.joined(separator: ", "))")
    }

    @ViewBuilder
    private func missionLiveTaskAttemptIntentLine(_ attempt: MissionTaskAttemptState) -> some View {
        Text(attempt.displayTitle)
            .font(GuardianTypography.font(.denseCaption12Regular))
            .foregroundStyle(theme.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Wind-down intent: \(attempt.displayTitle)")
    }

    @ViewBuilder
    private func autoAckBlockersSection(
        task: RoutePath,
        blockers: [MissionRunAutoMissionEndAckSlotRowSnapshot],
        showManualTriageHint: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text("Automatic protocol confirmation waits on every roster slot below to settle (each slot must leave in-progress policy states).")
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(blockers, id: \.assignmentID) { snap in
                HStack(alignment: .center, spacing: GuardianSpacing.xsTight) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            MissionRunSlotAutoAckBlockerTriageChrome.railColor(
                                for: snap.mergedState,
                                neutralRail: theme.borderSubtle
                            )
                        )
                        .frame(width: 4)
                        .accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xsTight) {
                        Text(snap.slotName)
                            .font(GuardianTypography.font(.denseCaption12Medium))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2)
                        Text("—")
                            .font(GuardianTypography.font(.denseCaption10Regular))
                            .foregroundStyle(theme.textTertiary)
                        Text(snap.mergedState.displayTitle)
                            .font(GuardianTypography.font(.denseCaption12Medium))
                            .foregroundStyle(
                                MissionRunSlotAutoAckBlockerTriageChrome.labelForeground(
                                    for: snap.mergedState,
                                    neutralText: theme.textSecondary
                                )
                            )
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, GuardianSpacing.xxs)
                .padding(.horizontal, GuardianSpacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MissionRunSlotAutoAckBlockerTriageChrome.rowHighlightFill(for: snap.mergedState))
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(snap.slotName), merged slot state \(snap.mergedState.displayTitle)")
            }
            if showManualTriageHint {
                Text(
                    "If you must record the outcome before every row reaches policy complete, use the confirmation control below — that records manual triage on this task."
                )
                .font(GuardianTypography.font(.denseCaption10Regular))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .padding(.vertical, GuardianSpacing.xsTight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.backgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Task \(task.name): automatic protocol confirmation waits on \(blockers.count) roster slot\(blockers.count == 1 ? "" : "s") before policy complete on every row."
        )
    }

    @ViewBuilder
    private func endProtocolAcknowledgementBlock(surface: MissionControlLiveTaskTriageProjection.EndProtocolAckSurface, task: RoutePath) -> some View {
        switch surface {
        case .none:
            EmptyView()
        case .recovery:
            VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                Text("When this task’s roster has finished recovery, confirm here.")
                    .font(GuardianTypography.denseAcknowledgementCaption(compact: false))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                GuardianThemedButton(
                    title: "Recovery complete",
                    accent: .primary,
                    surface: .solid,
                    size: .medium,
                    shape: .cornered,
                    action: {
                        run.acknowledgeTaskMissionEndRecovery(taskID: task.id)
                        onUpdate(run)
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 0)
        case .aborting:
            VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                Text("When this task’s roster has finished the abort protocol, confirm here.")
                    .font(GuardianTypography.denseAcknowledgementCaption(compact: false))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                GuardianThemedButton(
                    title: "Abort protocol complete",
                    accent: .primary,
                    surface: .solid,
                    size: .medium,
                    shape: .cornered,
                    action: {
                        run.acknowledgeTaskMissionEndAbort(taskID: task.id)
                        onUpdate(run)
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 0)
        }
    }
}
