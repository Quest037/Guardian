import SwiftUI

/// Vehicles grid — one-shot arm probe with the same MAVSDK path and remediation as Mission Control preflight.
struct VehicleTestArmSheet: View {
    let vehicleTitle: String
    let vehicleID: String
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let controlStore: MissionControlStore

    @Environment(\.dismiss) private var dismiss

    @State private var probeRunning = true
    @State private var result: SingleVehicleArmProbeResult?

    var body: some View {
        GuardianModalTemplate(
            title: "Test arm",
            subtitle: vehicleTitle,
            headerActions: {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                .disabled(probeRunning)
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: 14) {
                    if probeRunning {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Sending arm command…")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.gray.opacity(0.9))
                        }
                    } else if let result {
                        outcomeBlock(result)

                        if result.passed, result.armedDuringProbe {
                            Text("The vehicle was disarmed automatically after the test.")
                                .font(.system(size: 11))
                                .foregroundStyle(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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
    private func outcomeBlock(_ result: SingleVehicleArmProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(result.passed ? Color.green.opacity(0.9) : Color.red.opacity(0.9))
                    .frame(width: 22, alignment: .center)
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.passed ? "Pass" : "Fail")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(result.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.gray.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    if !result.passed, let advice = result.remediationAdvice {
                        ArmProbeRemediationBlock(advice: advice)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func runProbe() async {
        let r = await controlStore.runSingleVehicleArmProbe(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl
        )
        result = r
        probeRunning = false

        if r.passed && r.armedDuringProbe {
            disarmAfterSuccessfulTestArm()
        }
    }

    private func disarmAfterSuccessfulTestArm() {
        _ = fleetLink.executeVehicleCommand(
            vehicleID: vehicleID,
            command: .disarm,
            source: "vehicles.testArmAutoDisarm",
            category: .paladin,
            onPaladinCommandOutcome: nil
        )
    }
}
