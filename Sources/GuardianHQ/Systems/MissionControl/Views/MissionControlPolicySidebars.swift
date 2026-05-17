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

                if taskHasSquadWingmen {
                    Text("Squad formation")
                        .font(GuardianTypography.font(.disclosureRowTitle))
                        .foregroundStyle(theme.textPrimary)
                    Text("Wingman assembly and follow offsets for every primary squad on this task.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer(minLength: 0)
                        Picker("Squad formation", selection: squadFormationBinding) {
                            ForEach(MissionSquadFormationKind.allCases) { kind in
                                Text(kind.displayTitle).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel("Squad formation")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    Text("Shape")
                        .font(GuardianTypography.font(.disclosureRowTitle))
                        .foregroundStyle(theme.textPrimary)
                    Text("How tightly wingmen pack for the chosen formation.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer(minLength: 0)
                        Picker("Shape", selection: squadFormationShapeBinding) {
                            ForEach(MissionSquadFormationShape.allCases) { shape in
                                Text(shape.displayTitle).tag(shape)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel("Formation shape")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

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

    private var taskHasSquadWingmen: Bool {
        guard let mission = missionSnapshot, let task = resolvedTask() else { return false }
        return MissionControlSquadFollowBindingUtilities.taskHasWingmen(mission: mission, task: task)
    }

    private var squadFormationBinding: Binding<MissionSquadFormationKind> {
        Binding(
            get: { resolvedTask()?.squadFormation ?? .convoy },
            set: { newValue in
                _ = run.updateTaskSquadFormation(taskID: taskId, newValue, credential: credential)
                onChange()
            }
        )
    }

    private var squadFormationShapeBinding: Binding<MissionSquadFormationShape> {
        Binding(
            get: { resolvedTask()?.squadFormationShape ?? .normal },
            set: { newValue in
                _ = run.updateTaskSquadFormationShape(taskID: taskId, newValue, credential: credential)
                onChange()
            }
        )
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

                if showsPrimarySquadFormationOverride {
                    Text("Squad formation")
                        .font(GuardianTypography.font(.disclosureRowTitle))
                        .foregroundStyle(theme.textPrimary)
                    Text("Primary slot only. Inherit uses the task formation (\(inheritedSquadFormationLabel)).")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer(minLength: 0)
                        Picker("Squad formation", selection: primarySquadFormationPickerBinding) {
                            Text("Inherit (\(inheritedSquadFormationLabel))").tag(PrimarySquadFormationPickerChoice.inherit)
                            ForEach(MissionSquadFormationKind.allCases) { kind in
                                Text(kind.displayTitle).tag(PrimarySquadFormationPickerChoice.explicit(kind))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel("Squad formation override")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    Text("Shape")
                        .font(GuardianTypography.font(.disclosureRowTitle))
                        .foregroundStyle(theme.textPrimary)
                    Text("Primary slot only. Inherit uses the task shape (\(inheritedSquadFormationShapeLabel)).")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer(minLength: 0)
                        Picker("Shape", selection: primarySquadFormationShapePickerBinding) {
                            Text("Inherit (\(inheritedSquadFormationShapeLabel))").tag(PrimarySquadFormationShapePickerChoice.inherit)
                            ForEach(MissionSquadFormationShape.allCases) { shape in
                                Text(shape.displayTitle).tag(PrimarySquadFormationShapePickerChoice.explicit(shape))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel("Formation shape override")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

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

    private var showsPrimarySquadFormationOverride: Bool {
        guard let mission = missionSnapshot,
              let assignment = run.assignments.first(where: { $0.id == assignmentId }),
              let device = mission.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId }),
              device.slot == .primary,
              let taskID = MissionRunPolicyResolution.resolvedTaskId(for: assignment, mission: mission),
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID })
        else { return false }
        return MissionControlSquadFollowBindingUtilities.taskHasWingmen(mission: mission, task: task)
    }

    private var inheritedSquadFormationLabel: String {
        guard let mission = missionSnapshot,
              let assignment = run.assignments.first(where: { $0.id == assignmentId })
        else { return MissionSquadFormationKind.convoy.displayTitle }
        return MissionRunPolicyResolution.inheritedSquadFormationForPrimarySlot(assignment: assignment, mission: mission)
            .displayTitle
    }

    private enum PrimarySquadFormationPickerChoice: Hashable {
        case inherit
        case explicit(MissionSquadFormationKind)
    }

    private var primarySquadFormationPickerBinding: Binding<PrimarySquadFormationPickerChoice> {
        Binding(
            get: {
                if let override = run.assignments.first(where: { $0.id == assignmentId })?
                    .policies.squadFormationOverride {
                    return .explicit(override)
                }
                return .inherit
            },
            set: { choice in
                let formation: MissionSquadFormationKind? = switch choice {
                case .inherit: nil
                case .explicit(let kind): kind
                }
                _ = run.updateAssignmentSquadFormationOverride(
                    assignmentID: assignmentId,
                    formation,
                    credential: credential
                )
                onChange()
            }
        )
    }

    private var inheritedSquadFormationShapeLabel: String {
        guard let mission = missionSnapshot,
              let assignment = run.assignments.first(where: { $0.id == assignmentId })
        else { return MissionSquadFormationShape.normal.displayTitle }
        return MissionRunPolicyResolution.inheritedSquadFormationShapeForPrimarySlot(assignment: assignment, mission: mission)
            .displayTitle
    }

    private enum PrimarySquadFormationShapePickerChoice: Hashable {
        case inherit
        case explicit(MissionSquadFormationShape)
    }

    private var primarySquadFormationShapePickerBinding: Binding<PrimarySquadFormationShapePickerChoice> {
        Binding(
            get: {
                if let override = run.assignments.first(where: { $0.id == assignmentId })?
                    .policies.squadFormationShapeOverride {
                    return .explicit(override)
                }
                return .inherit
            },
            set: { choice in
                let shape: MissionSquadFormationShape? = switch choice {
                case .inherit: nil
                case .explicit(let value): value
                }
                _ = run.updateAssignmentSquadFormationShapeOverride(
                    assignmentID: assignmentId,
                    shape,
                    credential: credential
                )
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
