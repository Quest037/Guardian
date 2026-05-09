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
                Button("Close") {
                    disarmPreflightArmsThenAbandon()
                    dismiss()
                    onAbandonWithoutStart()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                .disabled(probeRunning || allSlotsPassed)
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(rows) { row in
                                preflightRowView(row)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 160, maxHeight: 320)

                    HStack {
                        if probeRunning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking roster…")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textTertiary)
                        } else if allSlotsPassed {
                            Label("All vehicles armed successfully.", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.green.opacity(0.9))
                        } else {
                            Label("One or more slots failed — fix and try again.", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.orange.opacity(0.95))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 12)
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: row.phase))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconTint(for: row.phase))
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 6) {
                Text(row.slotName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(row.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if row.phase == .failed, let advice = row.remediationAdvice {
                    PreflightProbeRemediationBlock(advice: advice)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
        case .pending: return .gray.opacity(0.55)
        case .testing: return .blue.opacity(0.85)
        case .passed: return .green.opacity(0.9)
        case .failed: return .red.opacity(0.9)
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
                category: .paladin,
                onPaladinCommandOutcome: nil
            )
        }
        vehicleIDsArmedDuringProbe = []
    }
}
