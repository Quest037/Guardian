import SwiftUI

/// Drawer: per-squad formation policy (owned by squad id — survives primary vehicle changes).
struct TrainingLabSquadSettingsDrawerContent: View {
    @ObservedObject var roster: TrainingLabRosterController
    let squadID: UUID
    let squadIndex: Int
    let controlsLocked: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var startFormation: MissionSquadFormationKind = .arrowhead
    @State private var startSpacing: MissionSquadFormationSpacing = .tight
    @State private var endFormationChoice: TrainingLabEndFormationChoice = .auto
    @State private var endSpacingChoice: TrainingLabEndSpacingChoice = .auto
    @State private var taskKind: TrainingTaskKind = .reverseIntoSlot

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var squadCallsign: String {
        TrainingLabSquadCallsign.primaryLabel(squadIndex: squadIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(squadCallsign) squad settings")
                .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(GuardianSpacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                    policyRow(
                        title: "Skill task",
                        help: "Task this squad trains toward. The designated learning squad drives teach and promote."
                    ) {
                        Picker("Skill task", selection: $taskKind) {
                            ForEach(TrainingTaskKind.allCases) { kind in
                                Text(kind.displayTitle).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    policyRow(title: "Start formation", help: "Formation when the squad begins.") {
                        Picker("Start formation", selection: $startFormation) {
                            ForEach(MissionSquadFormationKind.allCases) { kind in
                                Text(kind.displayTitle).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    policyRow(title: "Start spacing", help: "Spacing when the squad begins.") {
                        Picker("Start spacing", selection: $startSpacing) {
                            ForEach(MissionSquadFormationSpacing.allCases) { shape in
                                Text(shape.displayTitle).tag(shape)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    policyRow(title: "End formation", help: "Formation required when the squad ends. Auto allows any.") {
                        Picker("End formation", selection: $endFormationChoice) {
                            ForEach(TrainingLabEndFormationChoice.allCases) { choice in
                                Text(choice.displayTitle).tag(choice)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    policyRow(title: "End spacing", help: "Spacing required when the squad ends. Auto allows any.") {
                        Picker("End spacing", selection: $endSpacingChoice) {
                            ForEach(TrainingLabEndSpacingChoice.allCases) { choice in
                                Text(choice.displayTitle).tag(choice)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                .padding(GuardianSpacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: loadFromRoster)
        .onChange(of: startFormation) { _ in persist() }
        .onChange(of: startSpacing) { _ in persist() }
        .onChange(of: endFormationChoice) { _ in persist() }
        .onChange(of: endSpacingChoice) { _ in persist() }
        .onChange(of: taskKind) { _ in persistTaskKind() }
        .disabled(controlsLocked)
    }

    private func policyRow<Content: View>(
        title: String,
        help: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            Text(title)
                .font(GuardianTypography.font(.formFieldLabel))
                .foregroundStyle(theme.textSecondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(help)
    }

    private func loadFromRoster() {
        guard let squad = roster.squad(id: squadID) else { return }
        let policy = squad.formationPolicy
        startFormation = policy.startFormation
        startSpacing = policy.startSpacing
        endFormationChoice = TrainingLabEndFormationChoice(resolved: policy.endFormation)
        endSpacingChoice = TrainingLabEndSpacingChoice(resolved: policy.endSpacing)
        taskKind = squad.taskKind
    }

    private func persistTaskKind() {
        roster.updateTaskKind(squadID: squadID, taskKind: taskKind)
    }

    private func persist() {
        roster.updateFormationPolicy(
            squadID: squadID,
            policy: TrainingLabSquadFormationPolicy(
                startFormation: startFormation,
                startSpacing: startSpacing,
                endFormation: endFormationChoice.resolved,
                endSpacing: endSpacingChoice.resolved
            )
        )
    }
}
