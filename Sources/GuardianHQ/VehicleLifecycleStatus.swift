import SwiftUI

enum VehicleStatusColor: String, Codable, Sendable {
    case green
    case yellow
    case red

    var uiColor: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }
}

enum VehicleLifecycleStage: String, Codable, Sendable {
    case starting
    case compiling
    case connecting
    case reconnecting
    case awaitingTelemetry
    case live
    case stopped
    case failed
}

struct VehicleLifecycleStatus: Equatable, Sendable {
    let stage: VehicleLifecycleStage
    let sentenceOverride: String?

    init(stage: VehicleLifecycleStage, sentenceOverride: String? = nil) {
        self.stage = stage
        self.sentenceOverride = sentenceOverride
    }

    var color: VehicleStatusColor {
        switch stage {
        case .live:
            return .green
        case .failed:
            return .red
        case .starting, .compiling, .connecting, .reconnecting, .awaitingTelemetry, .stopped:
            return .yellow
        }
    }

    var shortLabel: String {
        switch stage {
        case .starting: return "Starting"
        case .compiling: return "Compiling"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .awaitingTelemetry: return "Awaiting"
        case .live: return "Live"
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        }
    }

    /// Compact badge-friendly phrase (max two words).
    var mediumLabel: String {
        switch stage {
        case .starting: return "SITL booting"
        case .compiling: return "SITL compiling"
        case .connecting: return "Link connecting"
        case .reconnecting: return "Link reconnecting"
        case .awaitingTelemetry: return "Awaiting telemetry"
        case .live: return "Telemetry live"
        case .stopped: return "Session stopped"
        case .failed: return "Session failed"
        }
    }

    var sentence: String {
        if let sentenceOverride, !sentenceOverride.isEmpty {
            return sentenceOverride
        }
        switch stage {
        case .starting:
            return "The vehicle process is starting and preparing runtime dependencies."
        case .compiling:
            return "The simulator is building required binaries before flight telemetry can stream."
        case .connecting:
            return "The telemetry link is being established between the vehicle and MAVSDK."
        case .reconnecting:
            return "The telemetry link dropped and Guardian is waiting for the vehicle to reconnect."
        case .awaitingTelemetry:
            return "The link is up, but Guardian is still waiting for the first telemetry fields."
        case .live:
            return "Live telemetry is flowing for this vehicle."
        case .stopped:
            return "This vehicle session has stopped and is no longer streaming telemetry."
        case .failed:
            return "The vehicle session failed and requires attention before retrying."
        }
    }
}
