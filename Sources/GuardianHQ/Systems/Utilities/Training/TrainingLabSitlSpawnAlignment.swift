import Foundation

/// Aligns PX4 / ArduPilot SITL home and optional Gazebo proxy pose with Training map ENU slots (not operator-global defaults alone).
enum TrainingLabSitlSpawnAlignment {
    /// WGS84 + battery seed for ``SitlService/spawn`` (`PX4_HOME_*`, ArduPilot `-l`, fleet pending sim state).
    static func sitlSpawnDefaults(
        environmentPose: TrainingEnvironmentPose,
        mapGeodeticOrigin: SimSpawnDefaults,
        batterySeed: SimSpawnDefaults
    ) -> SimSpawnDefaults {
        let task = TrainingEnvironmentGeodesy.taskPose(
            environmentPose: environmentPose,
            origin: mapGeodeticOrigin
        )
        return SimSpawnDefaults(
            latitudeDeg: task.latitudeDeg,
            longitudeDeg: task.longitudeDeg,
            altitudeM: task.absoluteAltitudeM,
            headingDeg: environmentPose.yawDeg,
            batteryPercent: batterySeed.batteryPercent,
            batteryVoltageV: batterySeed.batteryVoltageV,
            batteryCurrentA: batterySeed.batteryCurrentA
        )
    }

    static func gazeboPlacement(
        worldID: UUID,
        environmentPose: TrainingEnvironmentPose
    ) -> GazeboVehiclePlacement {
        GazeboVehiclePlacement(worldID: worldID, pose: environmentPose)
    }
}
