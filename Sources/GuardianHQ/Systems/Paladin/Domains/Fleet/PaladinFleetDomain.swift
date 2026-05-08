import Foundation

@MainActor
final class PaladinFleetDomain: ObservableObject {
    @Published private(set) var readinessByVehicleID: [String: PaladinFleetVehicleReadiness] = [:]

    /// Upsert normalized readiness used by Paladin Mission Control domain decisions.
    func upsertVehicleReadiness(_ readiness: PaladinFleetVehicleReadiness) {
        readinessByVehicleID[readiness.id] = readiness
    }

    /// Fetch latest readiness for one vehicle.
    func readiness(for vehicleID: String) -> PaladinFleetVehicleReadiness? {
        readinessByVehicleID[vehicleID]
    }

    /// Quick aggregate for UI / orchestration status chips.
    func readinessSummary() -> (eligible: Int, eligibleWithRisk: Int, ineligible: Int) {
        var eligible = 0
        var risk = 0
        var ineligible = 0
        for item in readinessByVehicleID.values {
            switch item.autonomyEligibility {
            case .eligible:
                eligible += 1
            case .eligibleWithRisk:
                risk += 1
            case .ineligible:
                ineligible += 1
            }
        }
        return (eligible, risk, ineligible)
    }
}
