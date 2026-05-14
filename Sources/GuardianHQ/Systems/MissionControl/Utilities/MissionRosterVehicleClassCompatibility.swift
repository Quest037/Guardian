import Foundation

/// MCS / MC-R manual roster binding: when to warn that the picked fleet unit does not match the template slot’s class.
enum MissionRosterVehicleClassCompatibility {
    /// When `true`, the operator should confirm before binding `candidate` to a roster row that expects `expected`
    /// under ``FleetVehicleSubstitutionPolicy/missionRunReserveSwap`` (same tier as floating-reserve class checks).
    static func bindingShowsDifferentClassWarning(expected: FleetVehicleType, candidate: FleetVehicleType) -> Bool {
        if expected == .unknown { return false }
        return !FleetVehicleType.substitutionMatches(required: expected, candidate: candidate, policy: .missionRunReserveSwap)
    }
}
