import Foundation

/// Maps ``FleetVehicleType`` to Nav2 vs Aerostack2 (Guardian autonomy product lock).
enum GuardianAutonomyPlannerRouting {
    /// UGV and USV use Nav2-style ground/surface planning; UAV uses Aerostack2; UUV deferred (none until marine stack is defined).
    static func defaultPlannerKind(for vehicleType: FleetVehicleType) -> GuardianAutonomyPlannerKind {
        switch vehicleType.universalClass {
        case .ugv, .usv:
            return .nav2
        case .uav:
            return .aerostack2
        case .uuv, .unknown:
            return .none
        }
    }

    static func plannerKind(
        for vehicleType: FleetVehicleType,
        override: GuardianAutonomyPlannerKind?
    ) -> GuardianAutonomyPlannerKind {
        override ?? defaultPlannerKind(for: vehicleType)
    }
}
