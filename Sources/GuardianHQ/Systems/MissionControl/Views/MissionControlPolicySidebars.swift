import SwiftUI

// MARK: - Task settings sidebar (MC-S task card cog + MC-R triage cog)

/// Per-task **Abort** / **Complete** / **Reserve swap** policy overrides, and **between-cycles** (Return to Launch / Loiter / Park)
/// for repeating tasks. All edits route through ``MissionRunEnvironment`` policy APIs as the local operator so log lines render
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

                if showsBetweenCyclesControl {
                    Text("Between cycles")
                        .font(GuardianTypography.font(.disclosureRowTitle))
                        .foregroundStyle(theme.textPrimary)
                    Text("When this task repeats, what the squad does in the gap before the next cycle starts.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer(minLength: 0)
                        Picker("Between cycles", selection: betweenCyclesBinding) {
                            ForEach(MissionTaskBetweenCyclesAction.allCases) { action in
                                Text(action.displayTitle).tag(action)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel("Between cycles")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

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
                Text("Reserve swap preference chain")
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary)
                MissionRunOptionalPreferentialReserveSwapPolicyEditor(
                    overrideChain: reserveSwapBinding,
                    inheritedChain: inheritedTaskReserveSwapChain
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

    private var inheritedTaskReserveSwapChain: [MissionRunReserveSwapTactic] {
        MissionRunPolicyResolution.missionTemplateReserveSwapPreferenceChain(mission: missionSnapshot)
    }

    private var showsBetweenCyclesControl: Bool {
        guard let t = resolvedTask() else { return false }
        return t.regularity == .continuous || t.regularity == .continuousWithDelay
    }

    private var betweenCyclesBinding: Binding<MissionTaskBetweenCyclesAction> {
        Binding(
            get: { resolvedTask()?.betweenCycles ?? .returnToLaunch },
            set: { newValue in
                _ = run.updateTaskBetweenCyclesAction(taskID: taskId, newValue, credential: credential)
                onChange()
            }
        )
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

    private var reserveSwapBinding: Binding<[MissionRunReserveSwapTactic]?> {
        Binding(
            get: {
                resolvedTask()?.reserveSwapPreferenceChainOverride
            },
            set: { newValue in
                _ = run.updateTaskReserveSwapPreferenceChainOverride(taskID: taskId, newValue, credential: credential)
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

/// Per-assignment **Abort** / **Complete** / **Reserve swap** policy overrides. Same operator-credentialed routing as
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
                Text("Reserve swap preference chain")
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary)
                MissionRunOptionalPreferentialReserveSwapPolicyEditor(
                    overrideChain: reserveSwapBinding,
                    inheritedChain: inheritedSlotReserveSwapChain
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

    private var inheritedSlotReserveSwapChain: [MissionRunReserveSwapTactic] {
        guard let mission = missionSnapshot,
              let assignment = run.assignments.first(where: { $0.id == assignmentId })
        else {
            return MissionRunReserveSwapTactic.defaultMissionReserveSwapPreferenceChain
        }
        return MissionRunPolicyResolution.inheritedReserveSwapPreferenceChainForSlot(assignment: assignment, mission: mission)
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

    private var reserveSwapBinding: Binding<[MissionRunReserveSwapTactic]?> {
        Binding(
            get: {
                run.assignments.first(where: { $0.id == assignmentId })?.policies.reserveSwapPreferenceChain
            },
            set: { newValue in
                _ = run.updateAssignmentReserveSwapPreferenceChain(assignmentID: assignmentId, newValue, credential: credential)
                onChange()
            }
        )
    }
}

// MARK: - Run geofence augmentation (MCS / MC-R policy chrome)

/// Summary, per-fence **altitude envelope** edits, and **Clear** for one scope of **run-only** extra geofences (additive merge after template fences).
struct MissionRunGeofenceAugmentationRunPolicySidebarSection: View {
    @ObservedObject var run: MissionRunEnvironment
    let scope: MissionRunGeofenceAugmentationPolicyScope
    let title: String
    let caption: String
    let credential: MissionRunPolicyEditCredential
    let onRecompilePlanForGeofenceAugmentationPolicy: () -> Void
    let onClear: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var fences: [MissionGeofence] {
        switch scope {
        case .missionWide:
            run.policies.missionGeofenceAugmentation
        case .task(let taskID):
            run.taskGeofenceAugmentationsByTaskID[taskID] ?? []
        case .assignment(let assignmentID):
            run.assignments.first(where: { $0.id == assignmentID })?.policies.geofenceAugmentation ?? []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            Text(title)
                .font(GuardianTypography.font(.disclosureRowTitle))
                .foregroundStyle(theme.textPrimary)
            Text(caption)
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if !fences.isEmpty {
                Text("Run augmentation fences")
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.top, GuardianSpacing.xs)
                ForEach(Array(fences.enumerated()), id: \.element.id) { idx, fence in
                    VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                        Text(fenceDisplayTitle(fence))
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(theme.textPrimary)
                        MissionGeofenceAltitudeEnvelopeSection(fence: fenceBinding(fenceID: fence.id))
                    }
                    .padding(.vertical, GuardianSpacing.xs)
                    if idx < fences.count - 1 {
                        Divider().overlay(theme.borderSubtle)
                    }
                }
            }
            HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                Text(countLabel)
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
                GuardianThemedButton(
                    title: "Clear",
                    accent: .danger,
                    surface: .outline,
                    isEnabled: !fences.isEmpty,
                    action: onClear
                )
            }
        }
    }

    private func fenceDisplayTitle(_ fence: MissionGeofence) -> String {
        let trimmed = fence.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled fence" : trimmed
    }

    private func fenceBinding(fenceID: UUID) -> Binding<MissionGeofence> {
        Binding(
            get: {
                fences.first(where: { $0.id == fenceID }) ?? MissionGeofence(name: "", shape: .circle)
            },
            set: { newValue in
                var arr = fences
                guard let i = arr.firstIndex(where: { $0.id == fenceID }) else { return }
                arr[i] = newValue
                switch scope {
                case .missionWide:
                    _ = run.updateMissionGeofenceAugmentation(arr, credential: credential)
                case .task(let taskID):
                    _ = run.updateTaskGeofenceAugmentation(taskID: taskID, arr, credential: credential)
                case .assignment(let assignmentID):
                    _ = run.updateAssignmentGeofenceAugmentation(assignmentID: assignmentID, arr, credential: credential)
                }
                onRecompilePlanForGeofenceAugmentationPolicy()
            }
        )
    }

    private var countLabel: String {
        let fenceCount = fences.count
        if fenceCount == 0 { return "No additional fences" }
        if fenceCount == 1 { return "1 additional fence" }
        return "\(fenceCount) additional fences"
    }
}
