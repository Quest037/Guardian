import SwiftUI

/// Fleet simulator row card (Formations sims tab and Training vehicle controls).
struct GuardianSimulatorSlotCardView: View {
    let title: String
    let slot: FormationsPlaygroundSlotState
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    let showRetry: Bool
    let retryButtonTitle: String
    let showReplace: Bool
    let cardActionsLocked: Bool
    let onInspect: (String, FleetVehicleModel?) -> Void
    let onRetry: () -> Void
    let onReplace: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        let lifecycle = lifecycleStatus(for: slot)
        let preflight = preflightStatusPresentation(for: slot)
        let vehicleModel = slot.vehicleID.flatMap { fleetLink.vehicleModel(forVehicleID: $0) }
        let statusColor = lifecycle?.color.uiColor ?? theme.borderSubtle

        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xs) {
                Text(title)
                    .font(GuardianTypography.font(.denseCaption12Medium))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: GuardianSpacing.xsTight)
                if let shortID = vehicleModel?.displayShortID, !shortID.isEmpty {
                    Text(shortID)
                        .font(GuardianTypography.font(.telemetryMono10Semibold))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
                if let lifecycle {
                    Text(lifecycle.compactTwoWordStatus)
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(lifecycle.color.uiColor.opacity(0.95))
                } else {
                    Text("Link connecting")
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(Color.yellow.opacity(0.95))
                }
                Spacer(minLength: 0)
                Text(preflight.twoWordLabel)
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(preflight.color.opacity(0.95))
            }

            if let detail = preflight.detailLine {
                Text(detail)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let lifecycle {
                Text(lifecycle.sentence)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionBar(vehicleModel: vehicleModel, lifecycle: lifecycle)
        }
        .padding(GuardianSpacing.sm)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                .strokeBorder(statusColor.opacity(0.55), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func actionBar(vehicleModel: FleetVehicleModel?, lifecycle: VehicleLifecycleStatus?) -> some View {
        HStack(spacing: GuardianSpacing.xs) {
            if let vehicleID = slot.vehicleID {
                GuardianThemedButton(
                    accent: .neutral,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !cardActionsLocked,
                    contentSizing: .squareToolbarCell,
                    action: { onInspect(vehicleID, vehicleModel) },
                    label: {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                    }
                )
                .help("Open Vehicle Inspector (calibration, preflight, manual control)")
                .guardianPointerOnHover()
            }
            if showRetry {
                GuardianThemedButton(
                    title: retryButtonTitle,
                    accent: .primary,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !cardActionsLocked,
                    action: onRetry
                )
                .help(
                    slot.linkReady
                        ? "Run preflight again on this simulator"
                        : "Reconnect telemetry and run preflight"
                )
                .guardianPointerOnHover()
            }
            if showReplace {
                GuardianThemedButton(
                    title: "Replace",
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    isEnabled: !cardActionsLocked,
                    action: onReplace
                )
                .help(
                    slot.linkReady
                        ? "Stop this simulator and spawn a new one"
                        : "Stop the stuck simulator and spawn a new one"
                )
                .guardianPointerOnHover()
            }
            Spacer(minLength: 0)
        }
    }

    private struct PreflightStatusPresentation {
        let twoWordLabel: String
        let color: Color
        let detailLine: String?
    }

    private func preflightStatusPresentation(for slot: FormationsPlaygroundSlotState) -> PreflightStatusPresentation {
        guard slot.linkReady else {
            return PreflightStatusPresentation(
                twoWordLabel: "Awaiting link",
                color: GuardianSemanticColors.warningStroke,
                detailLine: "Tap Retry link to reconnect telemetry, or Replace to spawn a new simulator."
            )
        }
        if let passed = slot.preflightPassed {
            if passed {
                return PreflightStatusPresentation(
                    twoWordLabel: "Preflight passed",
                    color: GuardianSemanticColors.successStroke,
                    detailLine: slot.preflightDetail
                )
            }
            return PreflightStatusPresentation(
                twoWordLabel: "Preflight failed",
                color: GuardianSemanticColors.dangerStroke,
                detailLine: slot.preflightDetail ?? "Preflight failed"
            )
        }
        return PreflightStatusPresentation(
            twoWordLabel: "Preflight pending",
            color: GuardianSemanticColors.warningStroke,
            detailLine: "Run spawn or Retry preflight"
        )
    }

    private func lifecycleStatus(for slot: FormationsPlaygroundSlotState) -> VehicleLifecycleStatus? {
        guard let inst = sitl.instances.first(where: { $0.id == slot.sitlSessionID }) else { return nil }
        let resolvedVehicleID = fleetLink.vehicleID(forSystemID: inst.mavlinkSystemID)
            ?? slot.vehicleID
            ?? inst.guardianVehicleStreamKey
        let model = fleetLink.vehicleModel(forVehicleID: resolvedVehicleID)
        if let code = inst.lastExitCode, !inst.isAlive {
            return VehicleLifecycleStatus(
                stage: .failed,
                sentenceOverride:
                    "The simulator exited with code \(code), so telemetry is unavailable until this vehicle is restarted."
            )
        }
        if let explicit = model?.collections.lifecycleStatus ?? fleetLink.vehicleStatus(forVehicleID: resolvedVehicleID) {
            return explicit
        }
        if model?.data.telemetry != nil {
            return VehicleLifecycleStatus(stage: .live)
        }
        if inst.isAlive {
            return VehicleLifecycleStatus(stage: .connecting)
        }
        return VehicleLifecycleStatus(stage: .stopped)
    }
}
