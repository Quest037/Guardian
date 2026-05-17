import Foundation

/// Formation playground vehicle picker (maps to ``SimulationVehiclePreset`` + ``FleetVehicleType``).
enum FormationsPlaygroundVehicleClass: String, CaseIterable, Identifiable, Sendable {
    case uavCopter
    case ugvWheeled
    case ugvTracked

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .uavCopter: return "UAV-C"
        case .ugvWheeled: return "UGV-W"
        case .ugvTracked: return "UGV-T"
        }
    }

    var simulationPreset: SimulationVehiclePreset {
        switch self {
        case .uavCopter: return .uavMultirotor
        case .ugvWheeled: return .ugvWheeled
        case .ugvTracked: return .ugvTracked
        }
    }

    var fleetVehicleType: FleetVehicleType {
        switch self {
        case .uavCopter: return .uavCopter
        case .ugvWheeled: return .ugvWheeled
        case .ugvTracked: return .ugvTracked
        }
    }
}

enum FormationsPlaygroundPhase: Equatable, Sendable {
    case idle
    case spawning
    case connecting
    case locking
    case preflight
    case assembling
    case following
}

struct FormationsPlaygroundSlotState: Identifiable, Equatable {
    let sitlSessionID: UUID
    var vehicleID: String?
    var linkReady: Bool
    var preflightPassed: Bool?
    var preflightDetail: String?

    var id: UUID { sitlSessionID }
}

enum FormationsPlaygroundFollowState: String, Sendable, Equatable {
    case idle
    case movingToPosition
    case inPosition
    case stuck
    case noTelemetry
}

/// Plain-text export for operator paste (e.g. support chat); oldest line first.
enum FormationsPlaygroundLogExport {
    static func plainText(from lines: [FormationsPlaygroundLogLine]) -> String {
        guard !lines.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return lines.reversed().map { line in
            let ts = formatter.string(from: line.timestamp)
            return "[\(ts)] \(line.vehicleLabel) · \(line.state.rawValue): \(line.message)"
        }
        .joined(separator: "\n")
    }
}

struct FormationsPlaygroundLogLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let vehicleLabel: String
    let state: FormationsPlaygroundFollowState
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        vehicleLabel: String,
        state: FormationsPlaygroundFollowState,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.vehicleLabel = vehicleLabel
        self.state = state
        self.message = message
    }
}
