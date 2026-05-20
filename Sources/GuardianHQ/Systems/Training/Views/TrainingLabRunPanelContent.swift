import SwiftUI

/// **Training** rail — transit run status (Phase 4c).
struct TrainingLabRunPanelContent: View {
    @ObservedObject var run: TrainingLabRunOrchestrator
    @AppStorage(TrainingLabRunPreferences.failRunOnFirstSquadFailureKey)
    private var failRunOnFirstSquadFailure = true

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                Text("Transit run")
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(theme.textPrimary)

                phaseRow

                runSettingsSection

                if !run.statusText.isEmpty {
                    Text(run.statusText)
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !run.result.squadOutcomes.isEmpty {
                    Text("Squads")
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(theme.textSecondary)
                    ForEach(run.result.squadOutcomes, id: \.squadID) { outcome in
                        squadOutcomeRow(outcome)
                    }
                }

                if !run.logLines.isEmpty {
                    Text("Run log")
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.top, GuardianSpacing.sm)
                    ForEach(run.logLines) { line in
                        Text(runLogLineText(line))
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textTertiary)
                            .textSelection(.enabled)
                    }
                }

                if run.phase == .idle, run.logLines.isEmpty {
                    Text("Run moves every linked single-vehicle squad from the start zone to the end formation. The learning squad is trained; other squads use known-simple brain transit.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(GuardianSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var runSettingsSection: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            Text("Run policy")
                .font(GuardianTypography.font(.formFieldLabel))
                .foregroundStyle(theme.textSecondary)
            Toggle(isOn: $failRunOnFirstSquadFailure) {
                Text("End run when any squad fails")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textPrimary)
            }
            .toggleStyle(.switch)
            .disabled(run.isSessionActive)
            .help(
                "When on, a drive or end-zone failure for any squad stops the whole run. "
                    + "When off, other squads keep going; the run succeeds if the learning squad reaches the end formation."
            )
        }
    }

    private var phaseRow: some View {
        HStack(spacing: GuardianSpacing.sm) {
            Text("Status")
                .font(GuardianTypography.font(.formFieldLabel))
                .foregroundStyle(theme.textSecondary)
            Text(phaseTitle)
                .font(GuardianTypography.font(.denseCaption12Medium))
                .foregroundStyle(phaseColor)
        }
    }

    private var phaseTitle: String {
        switch run.phase {
        case .idle: return "Idle"
        case .staged: return "Staged"
        case .running: return "Running"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        }
    }

    private var phaseColor: Color {
        switch run.phase {
        case .succeeded:
            return GuardianSemanticColors.successForeground
        case .failed:
            return GuardianSemanticColors.dangerForeground
        case .running, .staged:
            return GuardianSemanticColors.infoForeground
        case .idle:
            return theme.textPrimary
        }
    }

    private func runLogLineText(_ line: TrainingPanelLogLine) -> String {
        let time = line.timestamp.formatted(date: .omitted, time: .standard)
        return "\(time)  \(line.message)"
    }

    private func squadOutcomeRow(_ outcome: TrainingRunSquadOutcome) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            HStack(spacing: GuardianSpacing.xs) {
                Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(
                        outcome.succeeded
                            ? GuardianSemanticColors.successForeground
                            : GuardianSemanticColors.dangerForeground
                    )
                Text(outcome.operatorMessage ?? (outcome.succeeded ? "Reached end zone." : "Did not finish."))
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
            }
            if let code = outcome.failureCode {
                Text(code.operatorTitle)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}
