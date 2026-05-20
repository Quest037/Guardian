import Foundation

/// Resolves start→end paths for all vehicles on a Training **Run** (Nav2 when stack + sidecar are up; geodesic fallback).
enum TrainingLabRunPathPlanning {
    struct RunPaths: Equatable, Sendable {
        var byVehicleID: [String: TrainingLabTransitMotion.PathResolution]
    }

    /// One ``plan_path`` (or geodesic fallback) per driving vehicle — enrolls PX4 ROS sidecar before each request.
    @MainActor
    static func resolveAllForRun(
        fleetLink: FleetLinkService,
        plans: [TrainingLabRunVehiclePlan]
    ) async -> RunPaths {
        var byVehicleID: [String: TrainingLabTransitMotion.PathResolution] = [:]
        for plan in plans {
            let path = await TrainingLabTransitMotion.resolvePath(fleetLink: fleetLink, plan: plan)
            byVehicleID[plan.vehicleID] = path
        }
        return RunPaths(byVehicleID: byVehicleID)
    }

    static func routeLogLine(
        plan: TrainingLabRunVehiclePlan,
        path: TrainingLabTransitMotion.PathResolution
    ) -> String {
        "\(plan.squadLabel): route \(path.source.rawValue), \(path.points.count) pt — drive + stuck monitor use this polyline."
    }

    @MainActor
    static func nav2StackLogLine(fleetLink: FleetLinkService) -> String {
        let ready = fleetLink.nav2TrainingStackReady
        let status = fleetLink.nav2TrainingStackStatus
        let bridge = fleetLink.ros2BridgeProcessPhase == .running ? "ROS bridge running" : "ROS bridge not running"
        return "Nav2 fleet stack: \(status) (ready: \(ready ? "yes" : "no"); \(bridge))."
    }
}
