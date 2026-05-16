import SwiftUI

/// MC-R assignment triage: Park / Loiter, context-aware **Continue**, and optional Live Drive after park.
@MainActor
struct MCRAssignmentTriageEngageStabilizeActions: View {
    let fleetLink: FleetLinkService
    let vehicleID: String?
    let operatorPhase: FleetMcrOperatorVehiclePhase
    let continueIntent: MissionRunOperatorContinueAfterParkIntent
    /// True while an async **Retry recovery / abort protocol** jolt is in flight for this overlay.
    var isPolicyWindDownRetryBusy: Bool = false
    let offersLoiter: Bool
    let onPark: () -> Void
    let onLoiter: () -> Void
    let onContinue: () -> Void
    let onEngageLiveDrive: () -> Void
    let stabilizeTelemetryNotice: AnyView?

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var showContinue: Bool { continueIntent.isActionable }
    private var showLiveDriveAfterPark: Bool {
        operatorPhase == .operatorParkAwaitingContinue && continueIntent == .resumeMission
    }

    var body: some View {
        Group {
            if showContinue {
                triageActionRowCard(
                    bodyCaption: continueIntent == .resumeMission ? "Resume after park" : "End protocol"
                ) {
                    continuePrimaryButton
                }
            }
            if showLiveDriveAfterPark {
                triageActionRowCard(bodyCaption: "Live Drive") {
                    GuardianPrimaryProminentButton(title: "Engage", action: onEngageLiveDrive)
                        .guardianPointerOnHover()
                        .help("Open Live Drive for this vehicle to take manual control.")
                }
            }
            if operatorPhase != .operatorParkAwaitingContinue || !showContinue {
                triageActionRowCard(bodyCaption: "Stop Vehicle") {
                    HStack(spacing: GuardianSpacing.xs) {
                        GuardianThemedButton(
                            title: "Park",
                            accent: .primary,
                            surface: .solid,
                            size: .small,
                            shape: .cornered,
                            isEnabled: !isPolicyWindDownRetryBusy,
                            action: onPark
                        )
                        .guardianPointerOnHover()
                        .help(
                            "Stop active move+park or mission traffic, then park this vehicle through the mission run log."
                        )
                        if offersLoiter {
                            GuardianThemedButton(
                                title: "Loiter",
                                accent: .primary,
                                surface: .outline,
                                size: .small,
                                shape: .cornered,
                                isEnabled: !isPolicyWindDownRetryBusy,
                                action: onLoiter
                            )
                            .guardianPointerOnHover()
                            .help("Send a loiter / hold catalogue command to this vehicle through the mission run log.")
                        }
                    }
                }
                if let stabilizeTelemetryNotice {
                    stabilizeTelemetryNotice
                }
            }
        }
    }

    @ViewBuilder
    private var continuePrimaryButton: some View {
        let busy = isPolicyWindDownRetryBusy && continueIntent.isPolicyWindDownRetry
        let title = busy ? "Retrying…" : continueIntent.operatorShortLabel
        HStack(spacing: GuardianSpacing.xs) {
            if busy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            GuardianThemedButton(
                title: title,
                accent: .primary,
                surface: .solid,
                size: .small,
                shape: .cornered,
                isEnabled: !busy,
                action: onContinue
            )
            .guardianPointerOnHover()
            .help(continueIntent.operatorHelp)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(busy ? "Retrying end protocol" : continueIntent.operatorShortLabel)
        .accessibilityAddTraits(busy ? [.updatesFrequently] : [])
    }

    @ViewBuilder
    private func triageActionRowCard<Trailing: View>(
        bodyCaption: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianCardLayout.defaultBodyPadding
            ),
            body: {
                HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                    Text(bodyCaption)
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailing()
                }
            }
        )
    }
}
