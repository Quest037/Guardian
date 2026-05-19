import SwiftUI

/// One cell in the fleet grid (live MAVLink vehicle or local SITL row).
struct FleetVehicleGridCard: View {
    let autopilotStack: FleetAutopilotStack
    /// Bundled `SimulationDevices` PNG basenames to try (without `.png`), or `nil` for the generic live placeholder.
    let simulationImageBasenames: [String]?
    let isSimulation: Bool
    let vehicleModel: FleetVehicleModel?
    let sitlAlive: Bool?
    let sitlExitCode: Int32?
    let onCalibration: (() -> Void)?
    /// Garage configure drawer (size tier and related vehicle settings).
    let onConfigure: (() -> Void)?
    let onStopSim: (() -> Void)?
    /// When non-`nil`, the Stop button is disabled and this string is used for `.help` (e.g. live Mission Control run).
    let stopSimDisabledReason: String?
    let onDismissSim: (() -> Void)?
    /// Spawn another SIM with the same preset/platform (SIM rows only).
    let onCloneSim: (() -> Void)?
    /// Restart Guardian's MAVSDK session while the sim process keeps running (SIM rows only).
    let onReconnectLink: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var cardConfiguration: GuardianCardConfiguration {
        GuardianCardConfiguration(
            border: .none,
            cornerRadius: GuardianCardLayout.cornerRadius,
            bodyPadding: GuardianSpacing.sm
        )
    }

    var body: some View {
        GuardianCard(
            configuration: cardConfiguration,
            media: {
                ZStack(alignment: .topLeading) {
                    imageBlock
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    HStack(alignment: .top, spacing: 0) {
                        FleetAutopilotStackBadge(stack: autopilotStack)

                        Spacer(minLength: 0)

                        if isSimulation {
                            FleetLiveSimBadge(isSimulation: true)
                        }
                    }
                    .padding(GuardianSpacing.xs)
                }
            },
            body: {
                Group {
                    if isSimulation {
                        simStatusRow
                    } else {
                        liveStatusRow
                    }
                }
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: cardConfiguration.cornerRadius, style: .continuous)
                .fill(statusColor.opacity(0.08))
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cardConfiguration.cornerRadius, style: .continuous)
                .strokeBorder(statusColor.opacity(0.55), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var imageBlock: some View {
        if let names = simulationImageBasenames, !names.isEmpty {
            SimulationDeviceThumbnail(imageBasenames: names)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.14, green: 0.18, blue: 0.22), Color(red: 0.08, green: 0.10, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(GuardianTypography.relativeFixed(size: 36, weight: .medium, relativeTo: .title2))
                    .foregroundStyle(theme.textPrimary.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private var liveStatusRow: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            statusBadge
            if let lifecycleStatus {
                Text(lifecycleStatus.sentence)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if onConfigure != nil || onCalibration != nil {
                HStack(spacing: GuardianSpacing.xs) {
                    if let configure = onConfigure {
                        GuardianThemedButton(
                            accent: .neutral,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            contentSizing: .squareToolbarCell,
                            action: configure,
                            label: {
                                Image(systemName: "gearshape")
                                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                            }
                        )
                        .help("Vehicle settings (size tier, class defaults)")
                    }
                    if let onCalibration {
                        GuardianThemedButton(
                            accent: .neutral,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            contentSizing: .squareToolbarCell,
                            action: onCalibration,
                            label: {
                                Image(systemName: "waveform.path.ecg.rectangle")
                                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                            }
                        )
                        .help("Open Vehicle Inspector (calibration, preflight, telemetry)")
                    }
                }
            }
        }
        .padding(.top, GuardianSpacing.micro)
    }

    @ViewBuilder
    private var simStatusRow: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            statusBadge
            if let lifecycleStatus {
                Text(lifecycleStatus.sentence)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: GuardianSpacing.xs) {
                if let configure = onConfigure {
                    GuardianThemedButton(
                        accent: .neutral,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: configure,
                        label: {
                            Image(systemName: "gearshape")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Vehicle settings (size tier, class defaults)")
                }
                if let onCalibration {
                    GuardianThemedButton(
                        accent: .neutral,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: onCalibration,
                        label: {
                            Image(systemName: "waveform.path.ecg.rectangle")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Open Vehicle Inspector (calibration, preflight, telemetry)")
                }
                if let clone = onCloneSim {
                    GuardianThemedButton(
                        accent: .neutral,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: clone,
                        label: {
                            Image(systemName: "doc.on.doc")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Spawn another simulator with this vehicle preset")
                }
                if let reconnect = onReconnectLink {
                    GuardianThemedButton(
                        accent: .primary,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: reconnect,
                        label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Restart Guardian's telemetry link to this simulator without stopping the sim process.")
                }
                if sitlAlive == true, let stop = onStopSim {
                    GuardianThemedButton(
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        isEnabled: stopSimDisabledReason == nil,
                        contentSizing: .squareToolbarCell,
                        action: stop,
                        label: {
                            Image(systemName: "trash")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help(stopSimDisabledReason ?? "Stop the simulator process.")
                } else if sitlAlive == false, let dismiss = onDismissSim {
                    GuardianThemedButton(
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        isEnabled: stopSimDisabledReason == nil,
                        contentSizing: .squareToolbarCell,
                        action: dismiss,
                        label: {
                            Image(systemName: "trash")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help(stopSimDisabledReason ?? "Remove this sim row from the grid.")
                }
            }
        }
        .padding(.top, GuardianSpacing.micro)
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xs) {
            if let lifecycleStatus {
                Text(lifecycleStatus.compactTwoWordStatus)
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(lifecycleStatus.color.uiColor.opacity(0.95))
            } else if simTelemetryIsLive {
                Text("Telemetry live")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(Color.green.opacity(0.95))
            } else {
                Text("Link connecting")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(Color.yellow.opacity(0.95))
            }

            Spacer(minLength: GuardianSpacing.xsTight)

            if let displayShortID = vehicleModel?.displayShortID, !displayShortID.isEmpty {
                Text(displayShortID)
                    .font(GuardianTypography.font(.telemetryMono10Semibold))
                    .foregroundStyle(theme.textSecondary.opacity(0.95))
                    .lineLimit(1)
            }
        }
    }

    private var simTelemetryIsLive: Bool {
        guard let t = simTelemetry else { return false }
        return t.latitudeDeg != nil
            || t.longitudeDeg != nil
            || t.batteryRemainingPercent != nil
            || !t.flightMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || t.healthArmable != nil
            || t.gpsNumSatellites != nil
    }

    private var statusColor: Color {
        lifecycleStatus?.color.uiColor ?? Color.white.opacity(0.12)
    }

    private var liveTelemetry: FleetTelemetrySnapshot? {
        vehicleModel?.collections.telemetrySnapshot
    }

    private var simTelemetry: FleetHubVehicleTelemetry? {
        vehicleModel?.data.telemetry
    }

    private var lifecycleStatus: VehicleLifecycleStatus? {
        vehicleModel?.collections.lifecycleStatus
    }
}
