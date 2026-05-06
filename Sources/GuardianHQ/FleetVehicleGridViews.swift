import SwiftUI

private let cardBg = Color(red: 0.12, green: 0.12, blue: 0.13)
private let cardInner = Color(red: 0.10, green: 0.10, blue: 0.11)

/// One cell in the fleet grid (live MAVLink vehicle or local SITL row).
struct FleetVehicleGridCard: View {
    let title: String
    let domain: VehicleDomain
    let autopilotStack: FleetAutopilotStack
    let vehicleId: String?
    let systemId: Int?
    let sessionUUID: String?
    /// Bundled `SimulationDevices` PNG basenames to try (without `.png`), or `nil` for the generic live placeholder.
    let simulationImageBasenames: [String]?
    let isSimulation: Bool
    let liveTelemetry: FleetTelemetrySnapshot?
    let sitlAlive: Bool?
    let sitlExitCode: Int32?
    let onInfo: (() -> Void)?
    let onStopSim: (() -> Void)?
    let onDismissSim: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                imageBlock
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()

                HStack(alignment: .top, spacing: 0) {
                    Text(autopilotStack.displayName)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(autopilotStack.badgeBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    Spacer(minLength: 0)

                    if isSimulation {
                        Text("Sim")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(domain.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray)

                if let t = liveTelemetry {
                    liveTelemetryBlock(t)
                }

                if isSimulation {
                    simStatusRow
                } else {
                    liveStatusRow
                }
            }
            .padding(12)
        }
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
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
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private func liveTelemetryBlock(_ t: FleetTelemetrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                pill("Armed", t.isArmed ? "Yes" : "No", emphasis: t.isArmed)
                pill("Mode", t.flightMode, emphasis: true)
            }
            if let lat = t.latitudeDeg, let lon = t.longitudeDeg {
                Text(String(format: "%.5f°, %.5f°", lat, lon))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.gray)
            }
            if let alt = t.relativeAltM {
                Text(String(format: "Rel. alt %.1f m", alt))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.gray)
            }
            Text("Updated \(t.lastUpdate.formatted(date: .omitted, time: .standard))")
                .font(.system(size: 10))
                .foregroundStyle(.gray.opacity(0.85))
        }
        .padding(.top, 2)
    }

    private func pill(_ k: String, _ v: String, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.gray)
            Text(v)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(emphasis ? .white : .gray)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(cardInner)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var liveStatusRow: some View {
        if let onInfo {
            HStack(spacing: 8) {
                Button("Info", action: onInfo)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var simStatusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let alive = sitlAlive {
                if alive {
                    Text("Running")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green.opacity(0.95))
                    if let vehicleId, !vehicleId.isEmpty {
                        Text("Vehicle ID: \(vehicleId)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.gray)
                    }
                    if let systemId {
                        Text("System ID: \(systemId)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.gray)
                    }
                    if let sessionUUID, !sessionUUID.isEmpty {
                        Text("Session UUID: \(sessionUUID)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.gray.opacity(0.75))
                    }
                } else if let code = sitlExitCode {
                    Text("Exited (code \(code))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 8) {
                if let onInfo {
                    Button("Info", action: onInfo)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if sitlAlive == true, let stop = onStopSim {
                    Button("Stop", action: stop)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if sitlAlive == false, let dismiss = onDismissSim {
                    Button("Dismiss", action: dismiss)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.top, 2)
    }
}
