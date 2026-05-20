import Foundation

/// Nav2 / geodesic transit polylines for the embedded Gazebo viewport (ENU metres on the training floor).
struct TrainingLabTransitRouteOverlayPath: Equatable, Sendable, Identifiable {
    var id: String
    var squadLabel: String
    var pathSource: TrainingNav2PlanPathResponse.Source
    var points: [TrainingEnvironmentPose]

    var pointCount: Int { points.count }
}

enum TrainingLabTransitRouteOverlay {
    /// Above zone/formation overlays in gzweb (see ``slotPlaneZ`` / ``MAP_SURFACE_LIFT_M`` in ``guardian_viewer.html``).
    private static let routeLiftZM = WorldBuilderZoneBoundsCheck.mapBaseTopZM + 0.14

    /// Converts resolved run paths to map-frame ENU for ``GazeboWebViewportTransitRoutesBridge``.
    static func makePaths(
        plans: [TrainingLabRunVehiclePlan],
        resolvedByVehicleID: [String: TrainingLabTransitMotion.PathResolution],
        mapGeodeticOrigin: SimSpawnDefaults
    ) -> [TrainingLabTransitRouteOverlayPath] {
        plans.compactMap { plan in
            guard let resolution = resolvedByVehicleID[plan.vehicleID],
                  resolution.points.count >= 2
            else { return nil }
            let enu = resolution.points.map { coord in
                var pose = TrainingEnvironmentGeodesy.environmentPose(
                    taskPose: TrainingTaskPose(
                        latitudeDeg: coord.lat,
                        longitudeDeg: coord.lon,
                        headingDeg: 0,
                        absoluteAltitudeM: mapGeodeticOrigin.altitudeM
                    ),
                    origin: mapGeodeticOrigin
                )
                pose.zM = routeLiftZM
                return pose
            }
            return TrainingLabTransitRouteOverlayPath(
                id: plan.vehicleID,
                squadLabel: plan.squadLabel,
                pathSource: resolution.source,
                points: enu
            )
        }
    }
}
