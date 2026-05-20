import Foundation

/// Pushes fleet hub position/heading into Gazebo vehicle proxies during an active Training transit run.
enum TrainingLabGazeboProxyTelemetrySync {
    /// ~5 Hz — enough for operator viewport without hammering `gz service set_pose`.
    static let tickIntervalNs: UInt64 = 200_000_000

    static func mavlinkSystemID(from vehicleID: String) -> Int? {
        guard vehicleID.hasPrefix("sysid:") else { return nil }
        return Int(vehicleID.dropFirst("sysid:".count))
    }

    /// Hub WGS84 → map ENU proxy pose (floor **z** pinned to map base top like spawn).
    static func environmentPose(
        hub: FleetHubVehicleTelemetry,
        mapGeodeticOrigin: SimSpawnDefaults
    ) -> TrainingEnvironmentPose? {
        guard let lat = hub.latitudeDeg, let lon = hub.longitudeDeg else { return nil }
        let heading = hub.headingDeg ?? hub.yawDeg ?? 0
        let task = TrainingTaskPose(
            latitudeDeg: lat,
            longitudeDeg: lon,
            headingDeg: heading,
            absoluteAltitudeM: hub.absoluteAltM ?? mapGeodeticOrigin.altitudeM
        )
        var env = TrainingEnvironmentGeodesy.environmentPose(
            taskPose: task,
            origin: mapGeodeticOrigin
        )
        env.zM = WorldBuilderZoneBoundsCheck.mapBaseTopZM
        return env
    }

    /// Runs on the main actor until cancelled or ``shouldContinue`` returns false.
    @MainActor
    static func runWhileActive(
        gazebo: GazeboService,
        fleetLink: FleetLinkService,
        vehicleIDs: [String],
        mapGeodeticOrigin: SimSpawnDefaults,
        shouldContinue: @escaping @MainActor () -> Bool
    ) async {
        while !Task.isCancelled, shouldContinue() {
            for vehicleID in vehicleIDs {
                guard let sysid = mavlinkSystemID(from: vehicleID),
                      let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                      let pose = environmentPose(hub: hub, mapGeodeticOrigin: mapGeodeticOrigin)
                else { continue }
                _ = await gazebo.updateVehicleProxyPose(
                    mavlinkSystemID: sysid,
                    pose: pose
                )
            }
            try? await Task.sleep(nanoseconds: tickIntervalNs)
        }
    }
}
