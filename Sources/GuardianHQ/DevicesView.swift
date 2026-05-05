import SwiftUI

/// Fleet devices — MAVLink / MAVSDK configuration is under Settings.
struct DevicesView: View {
    @ObservedObject var fleetLink: FleetLinkService

    private let bgMain = Color(red: 0.07, green: 0.07, blue: 0.08)
    private let bgPanel = Color(red: 0.12, green: 0.12, blue: 0.13)

    var body: some View {
        Group {
            if fleetLink.isRunning {
                devicesContent
            } else {
                serverOfflineMessage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgMain)
    }

    private var serverOfflineMessage: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.gray)
            Text("Server isn’t running")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            (
                Text("Turn on ")
                + Text("Server").fontWeight(.semibold)
                + Text(" in the top bar to bring up MAVSDK and listen for vehicles.")
            )
            .font(.system(size: 14))
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)
        }
        .padding(32)
    }

    private var devicesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Devices")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                bridgeStatusRow

                if let t = fleetLink.telemetry, fleetLink.bridgePhase == .live {
                    telemetryCard(t)
                } else if fleetLink.isRunning {
                    Text(bridgeIdleDetailMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bridgeStatusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(bridgeStatusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(bridgeStatusTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(bridgeStatusSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
            Spacer()
        }
        .padding(14)
        .background(bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var bridgeStatusColor: Color {
        switch fleetLink.bridgePhase {
        case .live:
            return .green
        case .awaitingVehicle:
            return .yellow
        case .connecting, .inactive:
            break
        }
        if fleetLink.isRunning { return .orange }
        return .gray
    }

    private var bridgeStatusTitle: String {
        switch fleetLink.bridgePhase {
        case .live:
            return "Live telemetry connected"
        case .awaitingVehicle:
            return "Waiting for aircraft"
        case .connecting:
            return "Connecting live telemetry…"
        case .inactive:
            break
        }
        if fleetLink.isRunning { return "Connecting live telemetry…" }
        return "Offline"
    }

    private var bridgeStatusSubtitle: String {
        switch fleetLink.bridgePhase {
        case .live:
            return "Receiving updates from the first aircraft on this link."
        case .awaitingVehicle:
            return "MAVSDK is listening. Start SITL or point your link at this machine’s MAVLink port (see Settings) until a heartbeat arrives."
        case .connecting:
            return "Hang on—this usually takes a second after the server starts."
        case .inactive:
            break
        }
        if fleetLink.isRunning {
            return "Hang on—this usually takes a second after the server starts."
        }
        return "Turn on Server in the top bar to begin."
    }

    private var bridgeIdleDetailMessage: String {
        switch fleetLink.bridgePhase {
        case .live, .awaitingVehicle:
            return "No vehicle data yet. When a simulated or real aircraft is sending on your link, status and position will show here."
        case .connecting, .inactive:
            return "Connecting live telemetry…"
        }
    }

    private func telemetryCard(_ t: FleetTelemetrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aircraft status")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            HStack {
                statusPill("Armed", value: t.isArmed ? "Yes" : "No", on: t.isArmed)
                statusPill("Mode", value: t.flightMode, on: true)
            }
            if let lat = t.latitudeDeg, let lon = t.longitudeDeg {
                Text(String(format: "Position: %.6f°, %.6f°", lat, lon))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.gray)
                if let alt = t.relativeAltM {
                    Text(String(format: "Relative alt: %.1f m", alt))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.gray)
                }
            }
            Text("Updated \(t.lastUpdate.formatted(date: .omitted, time: .standard))")
                .font(.system(size: 11))
                .foregroundStyle(.gray.opacity(0.9))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusPill(_ title: String, value: String, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? .white : .gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.10, green: 0.10, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Offline") {
    DevicesView(fleetLink: FleetLinkService())
        .frame(width: 720, height: 480)
}
