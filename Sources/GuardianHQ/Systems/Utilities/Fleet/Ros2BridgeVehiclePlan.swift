import Foundation

/// Builds the PX4 ROS 2 vehicle list for the Python sidecar from active fleet sessions.
enum Ros2BridgeVehiclePlan {
    struct SessionContext: Equatable, Sendable {
        var vehicleID: String
        var autopilotStack: FleetAutopilotStack
        var vehicleType: FleetVehicleType
        /// PX4 SITL `-i` index when known (`nil` for live hardware).
        var px4SitlInstance: Int?
        /// When false, the ROS 2 / Micro XRCE sidecar is not started (Vehicles / Formation MAVLink-only spawns).
        var ros2SidecarDesired: Bool = false
        /// Mission brain pack planner overlay (MCR runs with bindings).
        var brainPlannerOverlay: Ros2BrainPlannerSidecarOverlay?
    }

    /// ROS namespace prefix before `fmu/out/...` (empty → `/fmu/out/vehicle_status`).
    static func rosNamespace(px4SitlInstance: Int?) -> String {
        guard let instance = px4SitlInstance else { return "" }
        if instance <= 0 { return "" }
        return "px4_\(instance)"
    }

    static func entry(for context: SessionContext) -> Ros2VehicleBridgeEntry? {
        guard context.ros2SidecarDesired, context.autopilotStack == .px4 else { return nil }
        let planner = GuardianAutonomyPlannerRouting.defaultPlannerKind(for: context.vehicleType).configToken
        var entry = Ros2VehicleBridgeEntry(
            vehicleID: context.vehicleID,
            stack: "px4",
            vehicleClass: context.vehicleType.ros2ConfigClassValue,
            rosNamespace: rosNamespace(px4SitlInstance: context.px4SitlInstance),
            autonomyPlanner: planner,
            enabled: true
        )
        if let overlay = context.brainPlannerOverlay {
            entry.brainId = overlay.brainId.uuidString
            entry.brainVersion = overlay.brainVersion.semverString
            entry.nav2ParamOverlayJSON = overlay.nav2ParamOverlayJSON
            entry.aerostack2ParamOverlayJSON = overlay.aerostack2ParamOverlayJSON
        }
        return entry
    }

    static func entries(from contexts: [SessionContext]) -> [Ros2VehicleBridgeEntry] {
        contexts.compactMap { entry(for: $0) }
    }
}

extension FleetVehicleType {
    /// Snake-case class string for `guardian_ros2_vehicle_bridge` YAML / stdin.
    var ros2ConfigClassValue: String {
        switch self {
        case .uavCopter: return "uav_copter"
        case .uavFixedWing: return "uav_fixed_wing"
        case .uavVTOL: return "uav_vtol"
        case .ugvWheeled: return "ugv_wheeled"
        case .ugvTracked: return "ugv_tracked"
        case .ugvLegged: return "ugv_legged"
        case .usv: return "usv"
        case .uuv: return "uuv"
        case .unknown: return "unknown"
        }
    }
}
