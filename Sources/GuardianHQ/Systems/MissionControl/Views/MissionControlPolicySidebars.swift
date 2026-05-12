import SwiftUI

// MARK: - Task settings sidebar (MC-S task card cog + MC-R triage cog)

/// Per-task **Abort** / **Complete** policy overrides. All edits route through
/// ``MissionRunEnvironment`` policy APIs as the local operator so log lines render
/// `[Operator][<callsign>]` and persist via ``MissionRunEnvironment/missionTemplatePersister``.
///
/// Lives in its own `View` struct (rather than a `@ViewBuilder` method on the parent) so
/// `@ObservedObject` on `run`, `missionStore`, and `generalSettings` is tracked inside the
/// ``AppDrawer`` host's view tree — without it, the parent's `MissionStore` republishes
/// would not re-render the picker selection until the sidebar was reopened.
struct MissionRunTaskPolicyOverridesSidebarView: View {
    @ObservedObject var run: MissionRunEnvironment
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    let taskId: UUID
    let taskName: String
    let onChange: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var credential: MissionRunPolicyEditCredential {
        .localOperator(callsign: generalSettings.callsign)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                Text(taskName)
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(theme.textSecondary)
                Text("Policy overrides apply to this task’s roster slots unless a slot sets its own.")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Abort preference chain")
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary)
                MissionRunOptionalPreferentialAbortPolicyEditor(
                    overrideChain: abortBinding,
                    inheritedChain: inheritedTaskAbortChain
                )
                Text("Complete preference chain")
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary)
                MissionRunOptionalPreferentialCompletePolicyEditor(
                    overrideChain: completeBinding,
                    inheritedChain: inheritedTaskCompleteChain
                )
            }
            .padding(.horizontal, GuardianSpacing.md)
            .padding(.vertical, GuardianSpacing.cardBodyInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var missionSnapshot: Mission? {
        run.template ?? missionStore.missions.first(where: { $0.id == run.missionId })
    }

    private var inheritedTaskAbortChain: [MissionRunAbortTactic] {
        MissionRunPolicyResolution.missionTemplateAbortPreferenceChain(mission: missionSnapshot)
    }

    private var inheritedTaskCompleteChain: [MissionRunCompleteTactic] {
        MissionRunPolicyResolution.missionTemplateCompletePreferenceChain(mission: missionSnapshot)
    }

    private var abortBinding: Binding<[MissionRunAbortTactic]?> {
        Binding(
            get: {
                resolvedTask()?.abortPreferenceChainOverride
            },
            set: { newValue in
                _ = run.updateTaskAbortPreferenceChainOverride(taskID: taskId, newValue, credential: credential)
                onChange()
            }
        )
    }

    private var completeBinding: Binding<[MissionRunCompleteTactic]?> {
        Binding(
            get: {
                resolvedTask()?.completePreferenceChainOverride
            },
            set: { newValue in
                _ = run.updateTaskCompletePreferenceChainOverride(taskID: taskId, newValue, credential: credential)
                onChange()
            }
        )
    }

    /// Prefer the live MRE template (kept in sync via ``MissionRunEnvironment/missionTemplatePersister``);
    /// fall back to the store snapshot when the run hasn't loaded its template yet.
    private func resolvedTask() -> MissionTask? {
        if let templateTask = run.template?.routeMacro.tasks.first(where: { $0.id == taskId }) {
            return templateTask
        }
        return missionStore.missions
            .first(where: { $0.id == run.missionId })?
            .routeMacro.tasks.first(where: { $0.id == taskId })
    }
}

// MARK: - Slot settings sidebar (MC-S roster card cog)

/// Per-assignment **Abort** / **Complete** policy overrides. Same operator-credentialed routing as
/// ``MissionRunTaskPolicyOverridesSidebarView`` so MC-S slot edits log + permission-check identically.
struct MissionRunAssignmentPolicyOverridesSidebarView: View {
    @ObservedObject var run: MissionRunEnvironment
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    let assignmentId: UUID
    let slotTitle: String
    let onChange: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var credential: MissionRunPolicyEditCredential {
        .localOperator(callsign: generalSettings.callsign)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                Text(slotTitle)
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(theme.textSecondary)
                Text("Slot policies override the task (and mission defaults).")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Abort preference chain")
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary)
                MissionRunOptionalPreferentialAbortPolicyEditor(
                    overrideChain: abortBinding,
                    inheritedChain: inheritedSlotAbortChain
                )
                Text("Complete preference chain")
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary)
                MissionRunOptionalPreferentialCompletePolicyEditor(
                    overrideChain: completeBinding,
                    inheritedChain: inheritedSlotCompleteChain
                )
            }
            .padding(.horizontal, GuardianSpacing.md)
            .padding(.vertical, GuardianSpacing.cardBodyInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var missionSnapshot: Mission? {
        run.template ?? missionStore.missions.first(where: { $0.id == run.missionId })
    }

    private var inheritedSlotAbortChain: [MissionRunAbortTactic] {
        guard let mission = missionSnapshot,
              let assignment = run.assignments.first(where: { $0.id == assignmentId })
        else {
            return MissionRunAbortTactic.defaultMissionAbortPreferenceChain
        }
        return MissionRunPolicyResolution.inheritedAbortPreferenceChainForSlot(assignment: assignment, mission: mission)
    }

    private var inheritedSlotCompleteChain: [MissionRunCompleteTactic] {
        guard let mission = missionSnapshot,
              let assignment = run.assignments.first(where: { $0.id == assignmentId })
        else {
            return MissionRunCompleteTactic.defaultMissionCompletePreferenceChain
        }
        return MissionRunPolicyResolution.inheritedCompletePreferenceChainForSlot(assignment: assignment, mission: mission)
    }

    private var abortBinding: Binding<[MissionRunAbortTactic]?> {
        Binding(
            get: {
                run.assignments.first(where: { $0.id == assignmentId })?.policies.abortPreferenceChain
            },
            set: { newValue in
                _ = run.updateAssignmentAbortPreferenceChain(assignmentID: assignmentId, newValue, credential: credential)
                onChange()
            }
        )
    }

    private var completeBinding: Binding<[MissionRunCompleteTactic]?> {
        Binding(
            get: {
                run.assignments.first(where: { $0.id == assignmentId })?.policies.completePreferenceChain
            },
            set: { newValue in
                _ = run.updateAssignmentCompletePreferenceChain(assignmentID: assignmentId, newValue, credential: credential)
                onChange()
            }
        )
    }
}
