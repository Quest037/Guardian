import Foundation

/// Maps environment-local ENU anchors into WGS84 training poses (spawn defaults = world origin).
enum TrainingEnvironmentGeodesy {
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
}
