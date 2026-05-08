import Foundation

/// How a Live Drive stint was started (mission handoff is a placeholder for future wiring).
enum LiveDriveSessionKind: String, Codable, Equatable {
    case freestyle
    case mission
}

/// Discrete event inside a session (exportable context).
struct LiveDriveSessionEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    /// Short label, e.g. "Session start", "Battery drain", "Keyboard"
    let title: String
    /// Optional detail line
    let detail: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        title: String,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
    }
}

/// Full exportable record for one Live Drive session.
struct LiveDriveSessionRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let vehicleID: String
    let kind: LiveDriveSessionKind
    let isSimulationVehicle: Bool
    let startedAt: Date
    /// Non-nil after the session ends.
    var endedAt: Date?
    var events: [LiveDriveSessionEvent]
    /// Fleet log lines attributed to this vehicle accumulated during the session window.
    var sessionLogLines: [String]
    /// Internal: index into `FleetLinkService` per-vehicle buffer at session start (filled on finalize).
    var logBufferStartIndex: Int

    var isActive: Bool { endedAt == nil }

    init(
        id: UUID = UUID(),
        vehicleID: String,
        kind: LiveDriveSessionKind,
        isSimulationVehicle: Bool,
        startedAt: Date,
        endedAt: Date? = nil,
        events: [LiveDriveSessionEvent],
        sessionLogLines: [String],
        logBufferStartIndex: Int
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.kind = kind
        self.isSimulationVehicle = isSimulationVehicle
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.events = events
        self.sessionLogLines = sessionLogLines
        self.logBufferStartIndex = logBufferStartIndex
    }
}

/// Wrapper for writing JSON to disk / sharing.
struct LiveDriveSessionExportEnvelope: Codable, Equatable {
    var exportSchemaVersion: Int
    var exportedAt: Date
    var activeVehicleID: String?
    var completedSessions: [LiveDriveSessionRecord]

    static let currentSchemaVersion = 2
}
