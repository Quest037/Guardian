import Foundation

/// Discrete controls the training lab may forbid per vehicle class (not one axis for both directions).
enum TrainingControlAxis: String, Codable, CaseIterable, Sendable, Hashable {
    case driveForward
    case driveReverse
    case turnClockwise
    case turnCounterClockwise
    case strafeRight
    case climb

    var displayTitle: String {
        switch self {
        case .driveForward: return "Forward"
        case .driveReverse: return "Reverse"
        case .turnClockwise: return "Turn clockwise"
        case .turnCounterClockwise: return "Turn counter-clockwise"
        case .strafeRight: return "Strafe right"
        case .climb: return "Climb / descent"
        }
    }

    /// Controls this vehicle class can use in the training lab.
    static func supported(for vehicleType: FleetVehicleType) -> [TrainingControlAxis] {
        switch vehicleType.universalClass {
        case .uav:
            return [.driveForward, .driveReverse, .turnClockwise, .turnCounterClockwise, .strafeRight, .climb]
        case .ugv, .usv:
            return [.driveForward, .driveReverse, .turnClockwise, .turnCounterClockwise]
        case .uuv:
            return [.driveForward, .driveReverse, .turnClockwise, .turnCounterClockwise, .strafeRight, .climb]
        case .unknown:
            return [.driveForward, .driveReverse, .turnClockwise, .turnCounterClockwise]
        }
    }
}
