import SwiftUI

/// Modal arm preflight before Mission Control enters **running**; on full success runs `onSuccess` and dismisses.
struct MissionRunStartPreflightSheet: View {
    let run: MissionRunEnvironment
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let controlStore: MissionControlStore
    /// Compile Paladin, mark run running, and notify parent (same as legacy Start Run tail).
    let onSuccess: () -> Void
    let onAbandonWithoutStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var rows: [MissionRunPreflightSlotRow] = []
    @State private var probeRunning = true
    @State private var allSlotsPassed = false
    @State private var vehicleIDsArmedDuringProbe: [String] = []

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Modal(
            title: "Paladin preflight",
            subtitle: "Checking all vehicles are ready to be armed.",
            headerActions: {
                GuardianThemedButton(
                    title: "Close",
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !(probeRunning || allSlotsPassed),
                    action: {
                        disarmPreflightArmsThenAbandon()
                        dismiss()
                        onAbandonWithoutStart()
                    }
                )
                .keyboardShortcut(.cancelAction)
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                            ForEach(rows) { row in
                                preflightRowView(row)
                            }
                        }
                        .padding(.vertical, GuardianSpacing.xxs)
                    }
                    .frame(minHeight: 160, maxHeight: 320)

                    HStack {
                        if probeRunning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking roster…")
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(theme.textTertiary)
                        } else if allSlotsPassed {
                            Label("All vehicles armed successfully.", systemImage: "checkmark.circle.fill")
                                .font(GuardianTypography.font(.denseCaption12Medium))
                                .foregroundStyle(GuardianSemanticColors.successStroke)
                        } else {
                            Label("One or more slots failed — fix and try again.", systemImage: "exclamationmark.triangle.fill")
                                .font(GuardianTypography.font(.denseCaption12Medium))
                                .foregroundStyle(GuardianSemanticColors.warningStroke)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, GuardianSpacing.sm)
                }
            }
        )
        .frame(minWidth: 420)
        .task {
            await runProbe()
        }
        .interactiveDismissDisabled(probeRunning)
    }

    @ViewBuilder
    private func preflightRowView(_ row: MissionRunPreflightSlotRow) -> some View {
        HStack(alignment: .top, spacing: GuardianSpacing.denseGutter) {
            Image(systemName: iconName(for: row.phase))
                .font(GuardianTypography.font(.sectionHeadingSemibold))
                .foregroundStyle(iconTint(for: row.phase))
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                Text(row.slotName)
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(theme.textPrimary)
                Text(row.detail)
                    .font(GuardianTypography.font(.telemetryMono11Regular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if row.phase == .failed, let advice = row.remediationAdvice {
                    PreflightProbeRemediationBlock(advice: advice)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, GuardianSpacing.xxs)
    }

    private func iconName(for phase: MissionRunPreflightSlotPhase) -> String {
        switch phase {
        case .pending: return "circle.dashed"
        case .testing: return "ellipsis.circle"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func iconTint(for phase: MissionRunPreflightSlotPhase) -> Color {
        switch phase {
        case .pending: return theme.textTertiary
        case .testing: return GuardianSemanticColors.infoForeground
        case .passed: return GuardianSemanticColors.successStroke
        case .failed: return GuardianSemanticColors.dangerStroke
        }
    }

    private func runProbe() async {
        rows = run.assignments.map {
            MissionRunPreflightSlotRow(
                assignmentID: $0.id,
                slotName: $0.slotName,
                phase: .pending,
                detail: "Waiting…"
            )
        }

        let result = await controlStore.runSingleVehiclePreflightProbeForStartRun(
            run: run,
            fleetLink: fleetLink,
            sitl: sitl,
            rowUpdated: { updated in
                if let idx = rows.firstIndex(where: { $0.assignmentID == updated.assignmentID }) {
                    rows[idx] = updated
                }
            }
        )

        vehicleIDsArmedDuringProbe = result.vehicleIDsArmedDuringProbe
        allSlotsPassed = result.allPassed
        probeRunning = false

        if result.allPassed {
            onSuccess()
            dismiss()
        }
    }

    private func disarmPreflightArmsThenAbandon() {
        for vehicleID in vehicleIDsArmedDuringProbe {
            _ = fleetLink.executeVehicleCommand(
                vehicleID: vehicleID,
                command: .disarm,
                source: "missionControl.preflightAbandon",
                category: .missionControl,
                onCommandOutcome: nil
            )
        }
        vehicleIDsArmedDuringProbe = []
    }
}
