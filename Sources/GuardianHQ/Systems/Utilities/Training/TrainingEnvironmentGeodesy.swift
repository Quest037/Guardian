import Foundation

/// Maps environment-local ENU anchors into WGS84 training poses.
enum TrainingEnvironmentGeodesy {
  /// WGS84 anchor for this map's training floor: manifest ``defaultSpawn`` ENU relative to operator ``fallback`` (global sim defaults).
  ///
  /// Maps without explicit geodetic metadata still get a stable local origin for PX4 / Nav2; Gazebo proxies use absolute floor ENU.
  static func mapSessionOrigin(
    manifest: TrainingEnvironmentManifest,
    fallback: SimSpawnDefaults
  ) -> SimSpawnDefaults {
    let anchor = taskPose(environmentPose: manifest.defaultSpawn, origin: fallback)
    return SimSpawnDefaults(
      latitudeDeg: anchor.latitudeDeg,
      longitudeDeg: anchor.longitudeDeg,
      altitudeM: anchor.absoluteAltitudeM,
      headingDeg: manifest.defaultSpawn.yawDeg,
      batteryPercent: fallback.batteryPercent,
      batteryVoltageV: fallback.batteryVoltageV,
      batteryCurrentA: fallback.batteryCurrentA
    )
  }

  /// Environment frame: **x** = east (m), **y** = north (m), **z** = up (m); yaw in degrees.
  static func taskPose(
    environmentPose: TrainingEnvironmentPose,
    origin: SimSpawnDefaults
  ) -> TrainingTaskPose {
    let coord = coordinate(
      originLat: origin.latitudeDeg,
      originLon: origin.longitudeDeg,
      eastM: environmentPose.xM,
      northM: environmentPose.yM
    )
    return TrainingTaskPose(
      latitudeDeg: coord.lat,
      longitudeDeg: coord.lon,
      headingDeg: environmentPose.yawDeg,
      absoluteAltitudeM: origin.altitudeM + environmentPose.zM
    )
  }

  static func coordinate(
    originLat: Double,
    originLon: Double,
    eastM: Double,
    northM: Double
  ) -> RouteCoordinate {
    let latRad = originLat * .pi / 180
    let metresPerDegreeLat = 111_320.0
    let metresPerDegreeLon = metresPerDegreeLat * max(0.01, cos(latRad))
    let lat = originLat + northM / metresPerDegreeLat
    let lon = originLon + eastM / metresPerDegreeLon
    return RouteCoordinate(lat: lat, lon: lon)
  }

  /// Inverse of ``taskPose(environmentPose:origin:)`` — ENU metres + yaw for Gazebo proxy placement.
  static func environmentPose(
    taskPose: TrainingTaskPose,
    origin: SimSpawnDefaults
  ) -> TrainingEnvironmentPose {
    let latRad = origin.latitudeDeg * .pi / 180
    let metresPerDegreeLat = 111_320.0
    let metresPerDegreeLon = metresPerDegreeLat * max(0.01, cos(latRad))
    let northM = (taskPose.latitudeDeg - origin.latitudeDeg) * metresPerDegreeLat
    let eastM = (taskPose.longitudeDeg - origin.longitudeDeg) * metresPerDegreeLon
    let zM = taskPose.absoluteAltitudeM - origin.altitudeM
    return TrainingEnvironmentPose(
      xM: eastM,
      yM: northM,
      zM: zM,
      yawDeg: taskPose.headingDeg
    )
  }
}
