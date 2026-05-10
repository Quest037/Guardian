import SwiftUI

/// MC-R cog → mission-level policies + Rules-of-Engagement editor.
///
/// All edits route through ``MissionRunEnvironment``'s policy APIs as the local operator
/// (``MissionRunPolicyEditCredential/localOperator``). The host wraps this view in
/// ``SidebarOverlay`` with a non-`nil` title so chrome is provided by the host shell.
struct MissionRunControlsSidebarView: View {
    @ObservedObject var run: MissionRunEnvironment
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    /// Reflected view-side change so the parent can persist anything that doesn't already round-trip via `missionTemplatePersister`.
    let onChange: () -> Void

    private var credential: MissionRunPolicyEditCredential {
        .localOperator(callsign: generalSettings.callsign)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Mission policies")
            policySection
                .padding(.bottom, 16)

            sectionTitle("Rules of engagement")
            engagementSection
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Sections

    private var policySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            policyRow(
                title: "Abort Policy",
                binding: missionAbortPolicyBinding,
                cases: MissionRunAbortPolicy.setupPickerCases
            ) { $0.setupMenuLabel }

            Divider().overlay(GuardianDynamicColors.borderSubtle)

            policyRow(
                title: "Complete Policy",
                binding: missionCompletePolicyBinding,
                cases: MissionRunCompletePolicy.setupPickerCases
            ) { $0.setupMenuLabel }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var engagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MissionRunEngagementAction.allCases.indices, id: \.self) { idx in
                let action = MissionRunEngagementAction.allCases[idx]
                if idx > 0 {
                    Divider().overlay(GuardianDynamicColors.borderSubtle)
                }
                HStack(alignment: .center, spacing: 12) {
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
                    .frame(minWidth: 180, alignment: .trailing)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianDynamicColors.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(GuardianDynamicColors.textSecondary)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func policyRow<Value: Hashable>(
        title: String,
        binding: Binding<Value>,
        cases: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GuardianDynamicColors.textPrimary)
            Spacer(minLength: 12)
            Picker("", selection: binding) {
                ForEach(cases, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 180, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Bindings (route every set through MRE policy APIs as the local operator)

    private var missionAbortPolicyBinding: Binding<MissionRunAbortPolicy> {
        Binding(
            get: {
                run.template?.routeMacro.rules.missionAbortPolicy
                    ?? missionStore.missions.first(where: { $0.id == run.missionId })?.routeMacro.rules.missionAbortPolicy
                    ?? .returnToLaunch
            },
            set: { newValue in
                _ = run.updateMissionAbortPolicy(newValue, credential: credential)
                onChange()
            }
        )
    }

    private var missionCompletePolicyBinding: Binding<MissionRunCompletePolicy> {
        Binding(
            get: {
                run.template?.routeMacro.rules.missionCompletePolicy
                    ?? missionStore.missions.first(where: { $0.id == run.missionId })?.routeMacro.rules.missionCompletePolicy
                    ?? .returnToLaunch
            },
            set: { newValue in
                _ = run.updateMissionCompletePolicy(newValue, credential: credential)
                onChange()
            }
        )
    }

    private func engagementDispositionBinding(for action: MissionRunEngagementAction) -> Binding<MissionRunEngagementDisposition> {
        Binding(
            get: {
                run.resolvedEngagementDisposition(for: action)
            },
            set: { newDisposition in
                _ = run.updateMissionEngagementDisposition(
                    action: action,
                    disposition: newDisposition,
                    credential: credential
                )
                onChange()
            }
        )
    }
}
