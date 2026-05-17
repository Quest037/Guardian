import Foundation

/// Which movements a vehicle type may execute (planner must not select unsupported ids).
enum GuardianMovementCapabilities {
    static func supports(_ movement: GuardianMovementID, vehicleType: FleetVehicleType) -> Bool {
        supports(movement, universalClass: vehicleType.universalClass, granularType: vehicleType)
    }

    static func supports(
        _ movement: GuardianMovementID,
        universalClass: UniversalVehicleClass,
        granularType: FleetVehicleType = .unknown
    ) -> Bool {
        switch movement {
        case .forwardPursuit:
            return universalClass != .unknown
        case .reverse:
            switch universalClass {
            case .uav, .ugv, .usv:
                return true
            case .uuv, .unknown:
                return false
            }
        case .threePointReverse, .threePointForward:
            switch granularType {
            case .ugvWheeled, .ugvTracked:
                return true
            case .uavCopter, .uavVTOL, .uavFixedWing, .ugvLegged, .usv, .uuv, .unknown:
                return false
            }
        case .strafe:
            switch granularType {
            case .uavCopter, .uavVTOL:
                return true
            case .uavFixedWing, .ugvWheeled, .ugvTracked, .ugvLegged, .usv, .uuv, .unknown:
                return false
            }
        }
    }

    /// Movements this vehicle can ever use (catalogue filter).
    static func supportedMovements(
        vehicleType: FleetVehicleType
    ) -> [GuardianMovementID] {
        GuardianMovementID.allCases.filter { supports($0, vehicleType: vehicleType) }
    }
}
