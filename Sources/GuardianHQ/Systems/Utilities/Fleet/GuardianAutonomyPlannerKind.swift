import Foundation

/// ROS 2 autonomy stack Guardian routes per vehicle class (Nav2 for ground, Aerostack2 for aerial).
enum GuardianAutonomyPlannerKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// No ROS 2 planner sidecar for this vehicle (connection-only or unsupported class).
    case none
    /// [Nav2](https://github.com/ros-navigation/navigation2) — default for UGV / surface planners.
    case nav2
    /// [Aerostack2](https://github.com/aerostack2/aerostack2) — default for UAV planners.
    case aerostack2

    var displayName: String {
        switch self {
        case .none: return "None"
        case .nav2: return "Nav2"
        case .aerostack2: return "Aerostack2"
        }
    }

    /// Config / JSON value for the Python sidecar.
    var configToken: String { rawValue }
}
