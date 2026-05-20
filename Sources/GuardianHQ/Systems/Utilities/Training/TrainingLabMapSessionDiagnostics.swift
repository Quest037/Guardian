import Foundation

/// Operator-facing diagnostics for Training lab ``TrainingLabMapSessionLifecycle`` (map build / reset).
enum TrainingLabMapSessionDiagnostics {
    typealias LogHandler = @MainActor (String) -> Void

    @MainActor
    static func log(_ handler: LogHandler?, _ message: String) {
        handler?(message)
    }

    static func formatPose(_ pose: TrainingEnvironmentPose) -> String {
        String(
            format: "ENU x=%.1f y=%.1f z=%.2f yaw=%.0f°",
            pose.xM,
            pose.yM,
            pose.zM,
            pose.yawDeg
        )
    }

    static func formatTaskPose(_ pose: TrainingTaskPose) -> String {
        String(
            format: "WGS84 lat=%.6f lon=%.6f alt=%.1fm hdg=%.0f°",
            pose.latitudeDeg,
            pose.longitudeDeg,
            pose.absoluteAltitudeM,
            pose.headingDeg
        )
    }

    @MainActor
    static func contextSummary(_ context: TrainingLabMapSessionContext) -> String {
        var parts: [String] = []
        if let env = context.environment {
            parts.append("map=\(env.manifest.displayName)")
            parts.append("zones start=\(env.manifest.startZoneConfigured) end=\(env.manifest.endZoneConfigured)")
        } else {
            parts.append("map=nil")
        }
        parts.append("squads=\(context.squads.count)")
        parts.append("gazebo=\(context.gazebo != nil ? "yes" : "no")")
        if let worldID = context.activeGazeboWorldID {
            let alive = context.gazebo?.isWorldAlive(id: worldID) == true
            parts.append("worldID=\(worldID.uuidString.prefix(8))… alive=\(alive)")
        } else {
            parts.append("worldID=nil")
        }
        parts.append(
            String(
                format: "origin lat=%.5f lon=%.5f",
                context.mapGeodeticOrigin.latitudeDeg,
                context.mapGeodeticOrigin.longitudeDeg
            )
        )
        return parts.joined(separator: ", ")
    }
}
