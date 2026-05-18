import Foundation

/// Per-vehicle ROS 2 bridge row (mirrors Python `VehicleConnectionConfig`).
struct Ros2VehicleBridgeEntry: Codable, Equatable, Sendable {
    var vehicleID: String
    var stack: String
    var vehicleClass: String
    var rosNamespace: String
    /// `nav2`, `aerostack2`, or `none` — see ``GuardianAutonomyPlannerKind``.
    var autonomyPlanner: String
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case vehicleID = "vehicle_id"
        case stack
        case vehicleClass = "vehicle_class"
        case rosNamespace = "ros_namespace"
        case autonomyPlanner = "autonomy_planner"
        case enabled
    }
}

/// Fleet-wide ROS 2 bridge process phase (distinct from per-vehicle ``Ros2VehicleConnectionState``).
enum Ros2BridgeProcessPhase: String, Equatable, Sendable {
    case inactive
    case starting
    case running
    case unavailable
    case failed
}

/// Per-vehicle PX4 ROS 2 / uXRCE connection health from the Python sidecar.
enum Ros2VehicleConnectionState: String, Equatable, Sendable, Codable {
    case disconnected = "DISCONNECTED"
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
    case degraded = "DEGRADED"
    case error = "ERROR"
}
