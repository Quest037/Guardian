import Foundation

/// Retains in-slot movement sequences between formation pursuit ticks (~10 Hz).
@MainActor
final class GuardianMovementSequenceStore {
    private var byVehicleID: [String: GuardianMovementSlotSequenceState] = [:]

    func state(for vehicleID: String) -> GuardianMovementSlotSequenceState? {
        byVehicleID[vehicleID]
    }

    func setState(_ state: GuardianMovementSlotSequenceState?, for vehicleID: String) {
        if let state {
            byVehicleID[vehicleID] = state
        } else {
            byVehicleID.removeValue(forKey: vehicleID)
        }
    }

    func clear(for vehicleID: String) {
        byVehicleID.removeValue(forKey: vehicleID)
    }

    func clearAll() {
        byVehicleID.removeAll()
    }
}
