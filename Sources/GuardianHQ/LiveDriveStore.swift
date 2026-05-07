import Foundation

struct LiveDriveSession: Equatable {
    let id: UUID
    var controlledVehicleID: String?
    var isConnected: Bool
    var startedAt: Date

    init(
        id: UUID = UUID(),
        controlledVehicleID: String? = nil,
        isConnected: Bool = false,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.controlledVehicleID = controlledVehicleID
        self.isConnected = isConnected
        self.startedAt = startedAt
    }
}

@MainActor
final class LiveDriveStore: ObservableObject {
    /// Vehicle currently inspected in Live Drive (map/log/telemetry/camera).
    @Published var activeVehicleID: String?
    /// Non-nil only while operator has explicitly started direct-control session.
    @Published var session: LiveDriveSession?

    var hasActiveSession: Bool { session != nil }

    func beginSession() {
        session = LiveDriveSession(controlledVehicleID: activeVehicleID)
    }

    func endSession() {
        session = nil
    }

    func selectVehicle(_ vehicleID: String?) {
        activeVehicleID = vehicleID
    }

    func clearActiveVehicleIfIdle() {
        guard session == nil else { return }
        activeVehicleID = nil
    }
}
