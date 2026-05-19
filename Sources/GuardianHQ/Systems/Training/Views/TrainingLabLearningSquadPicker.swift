import SwiftUI

/// Sub-bar control: which squad is designated for skill teaching / promotion (hidden when only one squad).
struct TrainingLabLearningSquadPicker: View {
    @ObservedObject var roster: TrainingLabRosterController
    let controlsLocked: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var selection: Binding<UUID> {
        Binding(
            get: {
                roster.learningSquadID ?? roster.squads.first?.id ?? UUID()
            },
            set: { roster.setLearningSquad(id: $0) }
        )
    }

    var body: some View {
        HStack(spacing: GuardianSpacing.xs) {
            Text("Learning")
                .font(GuardianTypography.font(.formFieldLabel))
                .foregroundStyle(theme.textSecondary)

            Picker("Learning squad", selection: selection) {
                ForEach(Array(roster.squads.enumerated()), id: \.element.id) { squadIndex, squad in
                    Text(TrainingLabSquadCallsign.primaryLabel(squadIndex: squadIndex))
                        .tag(squad.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .disabled(controlsLocked)
        .help("Squad whose skill task is in focus for teach and promote. Other squads keep their own tasks.")
    }
}
