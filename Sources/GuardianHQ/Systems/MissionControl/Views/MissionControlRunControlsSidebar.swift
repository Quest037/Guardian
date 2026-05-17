import SwiftUI

/// MC-R **Run Rules** drawer: mission-level policy chains, mission-wide run geofence augmentation summary, and rules-of-engagement editor.
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
    /// Rebuilds the compiled Mission Control plan after mission-wide run geofence augmentation changes.
    let onRecompilePlanForGeofenceAugmentationPolicy: () -> Void

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
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                Text("Abort preference chain")
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary)
                MissionRunPreferentialAbortPolicyEditor(
                    chain: missionAbortPreferenceChainBinding,
                    showFootnote: false,
                    compactVerticalRhythm: true
                )
            }
            .padding(.vertical, GuardianSpacing.xs)

            Divider().overlay(theme.borderSubtle)

            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                Text("Complete preference chain")
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary)
                MissionRunPreferentialCompletePolicyEditor(
                    chain: missionCompletePreferenceChainBinding,
                    showFootnote: false,
                    compactVerticalRhythm: true
                )
            }
            .padding(.vertical, GuardianSpacing.xs)

            Divider().overlay(theme.borderSubtle)

            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                Text("Reserve swap preference chain")
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary)
                MissionRunPreferentialReserveSwapPolicyEditor(
                    chain: missionReserveSwapPreferenceChainBinding,
                    showFootnote: false,
                    compactVerticalRhythm: true
                )
            }
            .padding(.vertical, GuardianSpacing.xs)

            Divider().overlay(theme.borderSubtle)

            MissionRunGeofenceAugmentationRunPolicySidebarSection(
                run: run,
                scope: .missionWide,
                title: "Mission run geofence augmentation",
                caption: "Additional fences merge after every task’s template fences for this run. Clear removes mission-wide run-only extras. Edit fence shapes on the mission Geofences tab; edit altitude envelopes below.",
                credential: credential,
                onRecompilePlanForGeofenceAugmentationPolicy: onRecompilePlanForGeofenceAugmentationPolicy,
                onClear: {
                    _ = run.updateMissionGeofenceAugmentation([], credential: credential)
                    onRecompilePlanForGeofenceAugmentationPolicy()
                }
            )
            .padding(.vertical, GuardianSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var missionAbortPreferenceChainBinding: Binding<[MissionRunAbortTactic]> {
        Binding(
            get: {
                let mission = run.template ?? missionStore.missions.first(where: { $0.id == run.missionId })
                let chain = mission?.routeMacro.rules.missionAbortPreferenceChain ?? []
                return MissionRunAbortTactic.normalizedPreferenceChain(chain)
            },
            set: { newValue in
                _ = run.updateMissionAbortPreferenceChain(newValue, credential: credential)
                onChange()
            }
        )
    }

    private var missionCompletePreferenceChainBinding: Binding<[MissionRunCompleteTactic]> {
        Binding(
            get: {
                let mission = run.template ?? missionStore.missions.first(where: { $0.id == run.missionId })
                let chain = mission?.routeMacro.rules.missionCompletePreferenceChain ?? []
                return MissionRunCompleteTactic.upgradingStoredMissionWideChain(chain)
            },
            set: { newValue in
                _ = run.updateMissionCompletePreferenceChain(newValue, credential: credential)
                onChange()
            }
        )
    }

    private var missionReserveSwapPreferenceChainBinding: Binding<[MissionRunReserveSwapTactic]> {
        Binding(
            get: {
                let mission = run.template ?? missionStore.missions.first(where: { $0.id == run.missionId })
                let chain = mission?.routeMacro.rules.missionReserveSwapPreferenceChain ?? []
                return MissionRunReserveSwapTactic.normalizedPreferenceChain(chain)
            },
            set: { newValue in
                _ = run.updateMissionReserveSwapPreferenceChain(newValue, credential: credential)
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
