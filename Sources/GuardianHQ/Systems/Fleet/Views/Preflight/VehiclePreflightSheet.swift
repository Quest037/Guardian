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
        Modal(
            title: "Preflight check",
            subtitle: vehicleTitle,
            headerActions: {
                GuardianThemedButton(
                    title: "Close",
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !probeRunning,
                    action: { dismiss() }
                )
                .keyboardShortcut(.cancelAction)
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                    if probeRunning {
                        HStack(spacing: GuardianSpacing.denseGutter) {
                            ProgressView().controlSize(.small)
                            Text("Running preflight arm probe…")
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(theme.textTertiary)
                        }
                    } else if let result {
                        outcomeBlock(result)

                        if result.passed, result.armedDuringProbe {
                            Text("The vehicle was disarmed automatically after the test.")
                                .font(GuardianTypography.font(.denseFootnoteRegular))
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
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            HStack(alignment: .top, spacing: GuardianSpacing.denseGutter) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(GuardianTypography.font(.missionProminentGlyph18Semibold))
                    .foregroundStyle(result.passed ? GuardianSemanticColors.successStroke : GuardianSemanticColors.dangerStroke)
                    .frame(width: 22, alignment: .center)
                VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                    GuardianBadge(
                        text: result.passed ? "Pass" : "Fail",
                        accent: result.passed ? .success : .danger,
                        paint: .solid,
                        size: .medium,
                        shape: .cornered
                    )
                    Text(result.detail)
                        .font(GuardianTypography.font(.telemetryMono11Regular))
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
