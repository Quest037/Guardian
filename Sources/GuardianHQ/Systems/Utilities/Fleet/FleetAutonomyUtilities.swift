import Foundation

@MainActor
struct FleetAutonomyUtilities {
    func defaultPlannerKind(for vehicleType: FleetVehicleType) -> GuardianAutonomyPlannerKind {
        GuardianAutonomyPlannerRouting.defaultPlannerKind(for: vehicleType)
    }
}
