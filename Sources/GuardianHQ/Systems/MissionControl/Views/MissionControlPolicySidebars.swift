import SwiftUI

// MARK: - Task settings sidebar (MC-S task card cog + MC-R triage cog)

/// Per-task **Abort** / **Complete** policy overrides. All edits route through
/// ``MissionRunEnvironment`` policy APIs as the local operator so log lines render
/// `[Operator][<callsign>]` and persist via ``MissionRunEnvironment/missionTemplatePersister``.
///
/// Lives in its own `View` struct (rather than a `@ViewBuilder` method on the parent) so
/// `@ObservedObject` on `run`, `missionStore`, and `generalSettings` is tracked inside the
/// `SidebarOverlay` host's view tree — without it, the parent's `MissionStore` republishes
/// would not re-render the picker selection until the sidebar was reopened.
struct MissionRunTaskPolicyOverridesSidebarView: View {
    @ObservedObject var run: MissionRunEnvironment
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    let taskId: UUID
    let taskName: String
    let onChange: () -> Void

    private var credential: MissionRunPolicyEditCredential {
        .localOperator(callsign: generalSettings.callsign)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(taskName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                Text("Policy overrides apply to this task’s roster slots unless a slot sets its own.")
                    .font(.system(size: 11))
                    .foregroundStyle(GuardianDynamicColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                MissionRunPolicySidebarRows.optionalAbortRow(
                    label: "Abort policy",
                    selection: abortBinding
                )
                MissionRunPolicySidebarRows.optionalCompleteRow(
                    label: "Complete policy",
                    selection: completeBinding
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var abortBinding: Binding<MissionRunAbortPolicy?> {
        Binding(
            get: {
                resolvedTask()?.abortPolicyOverride
            },
            set: { newValue in
                _ = run.updateTaskAbortPolicyOverride(taskID: taskId, newValue, credential: credential)
                onChange()
            }
        )
    }

    private var completeBinding: Binding<MissionRunCompletePolicy?> {
        Binding(
            get: {
                resolvedTask()?.completePolicyOverride
            },
            set: { newValue in
                _ = run.updateTaskCompletePolicyOverride(taskID: taskId, newValue, credential: credential)
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
    @ObservedObject var generalSettings: GeneralSettingsStore
    let assignmentId: UUID
    let slotTitle: String
    let onChange: () -> Void

    private var credential: MissionRunPolicyEditCredential {
        .localOperator(callsign: generalSettings.callsign)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(slotTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                Text("Slot policies override the task (and mission defaults).")
                    .font(.system(size: 11))
                    .foregroundStyle(GuardianDynamicColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                MissionRunPolicySidebarRows.optionalAbortRow(
                    label: "Abort policy",
                    selection: abortBinding
                )
                MissionRunPolicySidebarRows.optionalCompleteRow(
                    label: "Complete policy",
                    selection: completeBinding
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var abortBinding: Binding<MissionRunAbortPolicy?> {
        Binding(
            get: {
                run.assignments.first(where: { $0.id == assignmentId })?.policies.abort
            },
            set: { newValue in
                _ = run.updateAssignmentAbortPolicy(assignmentID: assignmentId, newValue, credential: credential)
                onChange()
            }
        )
    }

    private var completeBinding: Binding<MissionRunCompletePolicy?> {
        Binding(
            get: {
                run.assignments.first(where: { $0.id == assignmentId })?.policies.complete
            },
            set: { newValue in
                _ = run.updateAssignmentCompletePolicy(assignmentID: assignmentId, newValue, credential: credential)
                onChange()
            }
        )
    }
}

// MARK: - Shared row helpers

enum MissionRunPolicySidebarRows {
    @ViewBuilder
    static func optionalAbortRow(
        label: String,
        selection: Binding<MissionRunAbortPolicy?>
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: selection) {
                Text("Inherited").tag(nil as MissionRunAbortPolicy?)
                ForEach(MissionRunAbortPolicy.setupPickerCases, id: \.self) { policy in
                    Text(policy.setupMenuLabel).tag(Optional(policy))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 200, alignment: .trailing)
        }
    }

    @ViewBuilder
    static func optionalCompleteRow(
        label: String,
        selection: Binding<MissionRunCompletePolicy?>
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: selection) {
                Text("Inherited").tag(nil as MissionRunCompletePolicy?)
                ForEach(MissionRunCompletePolicy.setupPickerCases, id: \.self) { policy in
                    Text(policy.setupMenuLabel).tag(Optional(policy))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 200, alignment: .trailing)
        }
    }
}
