import SwiftUI

/// Vehicles grid — one-shot preflight probe with the same MAVSDK path and remediation as Mission Control preflight.
struct VehiclePreflightSheet: View {
    let vehicleTitle: String
    let vehicleID: String
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let controlStore: MissionControlStore
    let leaveArmed: Bool
    let autoCloseOnPass: Bool
    let onPassed: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var probeRunning = true
    @State private var result: SingleVehiclePreflightProbeResult?

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    init(
        vehicleTitle: String,
        vehicleID: String,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        controlStore: MissionControlStore,
        leaveArmed: Bool = false,
        autoCloseOnPass: Bool = false,
        onPassed: (() -> Void)? = nil
    ) {
        self.vehicleTitle = vehicleTitle
        self.vehicleID = vehicleID
        self.fleetLink = fleetLink
        self.sitl = sitl
        self.controlStore = controlStore
        self.leaveArmed = leaveArmed
        self.autoCloseOnPass = autoCloseOnPass
        self.onPassed = onPassed
    }

    var body: some View {
        GuardianModalTemplate(
            title: "Preflight check",
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
                            Text("Running preflight arm probe…")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textTertiary)
                        }
                    } else if let result {
                        outcomeBlock(result)

                        if result.passed, result.armedDuringProbe {
                            Text("The vehicle was disarmed automatically after the test.")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textSecondary)
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
    private func outcomeBlock(_ result: SingleVehiclePreflightProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(result.passed ? Color.green.opacity(0.9) : Color.red.opacity(0.9))
                    .frame(width: 22, alignment: .center)
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.passed ? "Pass" : "Fail")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(result.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !result.passed, let advice = result.remediationAdvice {
                        PreflightProbeRemediationBlock(advice: advice)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func runProbe() async {
        let r = await controlStore.runSingleVehiclePreflightProbe(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl,
            leaveArmed: leaveArmed
        )
        result = r
        probeRunning = false
        if r.passed {
            onPassed?()
            if autoCloseOnPass {
                dismiss()
            }
        }
    }
}
