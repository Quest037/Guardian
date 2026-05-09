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
    let onInfo: (() -> Void)?
    let onTestArm: (() -> Void)?
    /// When non-`nil`, the Test button is disabled and this string is used for `.help`.
    let testArmDisabledReason: String?
    let onStopSim: (() -> Void)?
    /// When non-`nil`, the Stop button is disabled and this string is used for `.help` (e.g. live Mission Control run).
    let stopSimDisabledReason: String?
    let onDismissSim: (() -> Void)?
    /// Spawn another SIM with the same preset/platform (SIM rows only).
    let onCloneSim: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 6) {
                if isSimulation {
                    simStatusRow
                } else {
                    liveStatusRow
                }
            }
            .padding(12)
        }
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(statusColor.opacity(0.08))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(statusColor.opacity(0.55), lineWidth: 1)
                .allowsHitTesting(false)
        )
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
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private var liveStatusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusBadge
            if let lifecycleStatus {
                Text(lifecycleStatus.sentence)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if onInfo != nil || onTestArm != nil {
                HStack(spacing: 8) {
                    if let onTestArm {
                        Button(action: onTestArm) {
                            Image(systemName: "checkmark.circle")
                                .appIconGlyph()
                        }
                        .buttonStyle(.bordered)
                        .uniformIconButton(width: 30, height: 26)
                        .disabled(testArmDisabledReason != nil)
                        .help(testArmDisabledReason ?? "Run a one-shot arm check (same as Mission Control preflight).")
                    }
                    if let onInfo {
                        Button(action: onInfo) {
                            Image(systemName: "info.circle")
                                .appIconGlyph()
                        }
                        .buttonStyle(.bordered)
                        .uniformIconButton(width: 30, height: 26)
                        .help("Vehicle telemetry details")
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var simStatusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusBadge
            if let lifecycleStatus {
                Text(lifecycleStatus.sentence)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if let onTestArm {
                    Button(action: onTestArm) {
                        Image(systemName: "checkmark.circle")
                            .appIconGlyph()
                    }
                    .buttonStyle(.bordered)
                    .uniformIconButton(width: 30, height: 26)
                    .disabled(testArmDisabledReason != nil)
                    .help(testArmDisabledReason ?? "Run a one-shot arm check (same as Mission Control preflight).")
                }
                if let onInfo {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .appIconGlyph()
                    }
                    .buttonStyle(.bordered)
                    .uniformIconButton(width: 30, height: 26)
                    .help("Vehicle telemetry details")
                }
                if let clone = onCloneSim {
                    Button(action: clone) {
                        Image(systemName: "doc.on.doc")
                            .appIconGlyph()
                    }
                    .buttonStyle(.bordered)
                    .uniformIconButton(width: 30, height: 26)
                    .help("Spawn another simulator with this vehicle preset")
                }
                if sitlAlive == true, let stop = onStopSim {
                    Button(action: stop) {
                        Image(systemName: "stop.circle")
                            .appIconGlyph()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .uniformIconButton(width: 30, height: 26)
                    .disabled(stopSimDisabledReason != nil)
                    .help(stopSimDisabledReason ?? "Stop the simulator process.")
                } else if sitlAlive == false, let dismiss = onDismissSim {
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle")
                            .appIconGlyph()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .uniformIconButton(width: 30, height: 26)
                    .disabled(stopSimDisabledReason != nil)
                    .help(stopSimDisabledReason ?? "Remove this sim row from the grid.")
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let lifecycleStatus {
                Text(lifecycleStatus.compactTwoWordStatus)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(lifecycleStatus.color.uiColor.opacity(0.95))
            } else if simTelemetryIsLive {
                Text("Telemetry live")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.95))
            } else {
                Text("Link connecting")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.yellow.opacity(0.95))
            }

            Spacer(minLength: 6)

            if let displayShortID = vehicleModel?.displayShortID, !displayShortID.isEmpty {
                Text(displayShortID)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
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
