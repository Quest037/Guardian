import SwiftUI

/// Autopilot / GCS stack shown on fleet cards. Extend with new cases when additional SITL stacks or MAVLink sources are wired.
enum FleetAutopilotStack: String, Codable, Equatable, Sendable, CaseIterable {
    case ardupilot
    case px4
    /// MAVLink connected but stack not identified (or non-ArduPilot/non-PX4 firmware).
    case unknown

    init(simulationPlatform: SimulationPlatform) {
        switch simulationPlatform {
        case .ardupilot: self = .ardupilot
        case .px4: self = .px4
        }
    }

    var displayName: String {
        switch self {
        case .ardupilot: return "ArduPilot"
        case .px4: return "PX4"
        case .unknown: return "MAVLink"
        }
    }

    var badgeBackground: Color {
        switch self {
        case .ardupilot:
            return Color(red: 0.16, green: 0.38, blue: 0.62)
        case .px4:
            return Color(red: 0.12, green: 0.50, blue: 0.48)
        case .unknown:
            return Color(red: 0.22, green: 0.22, blue: 0.24)
        }
    }
}
