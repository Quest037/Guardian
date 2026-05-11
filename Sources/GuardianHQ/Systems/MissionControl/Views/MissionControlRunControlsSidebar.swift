import SwiftUI

/// MC-R cog → mission-level policies + Rules-of-Engagement editor.
///
/// All edits route through ``MissionRunEnvironment``'s policy APIs as the local operator
/// (``MissionRunPolicyEditCredential/localOperator``). The host wraps this view in
/// ``AppDrawer`` with a non-`nil` title so chrome is provided by the host shell.
struct MissionRunControlsSidebarView: View {
    @ObservedObject var run: MissionRunEnvironment
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    /// Reflected view-side change so the parent can persist anything that doesn't already round-trip via `missionTemplatePersister`.
    let onChange: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var credential: MissionRunPolicyEditCredential {
        .localOperator(callsign: generalSettings.callsign)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Mission policies")
            policySection
                .padding(.bottom, GuardianSpacing.md)

            sectionTitle("Rules of engagement")
            engagementSection
        }
        .padding(.horizontal, GuardianSpacing.md)
        .padding(.top, GuardianSpacing.md)
        .padding(.bottom, GuardianSpacing.xl)
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

            Divider().overlay(theme.borderSubtle)

            policyRow(
                title: "Complete Policy",
                binding: missionCompletePolicyBinding,
                cases: MissionRunCompletePolicy.setupPickerCases
            ) { $0.setupMenuLabel }
        }
        .padding(GuardianSpacing.cardBodyInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var engagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MissionRunEngagementAction.allCases.indices, id: \.self) { idx in
                let action = MissionRunEngagementAction.allCases[idx]
                if idx > 0 {
                    Divider().overlay(theme.borderSubtle)
                }
                HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                    Text(action.setupLabel)
                        .font(GuardianTypography.font(.disclosureRowTitle))
                        .foregroundStyle(theme.textPrimary)
                    Spacer(minLength: GuardianSpacing.sm)
                    Picker("", selection: engagementDispositionBinding(for: action)) {
                        ForEach(MissionRunEngagementDisposition.allCases, id: \.self) { disposition in
                            Text(disposition.setupMenuLabel).tag(disposition)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 180, alignment: .trailing)
                }
                .padding(.vertical, GuardianSpacing.xs)
            }
        }
        .padding(GuardianSpacing.cardBodyInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(GuardianTypography.font(.subsectionTitleSemibold))
            .foregroundStyle(theme.textSecondary)
            .padding(.bottom, GuardianSpacing.xs)
    }

    @ViewBuilder
    private func policyRow<Value: Hashable>(
        title: String,
        binding: Binding<Value>,
        cases: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            Text(title)
                .font(GuardianTypography.font(.disclosureRowTitle))
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: GuardianSpacing.sm)
            Picker("", selection: binding) {
                ForEach(cases, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 180, alignment: .trailing)
        }
        .padding(.vertical, GuardianSpacing.xs)
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
