import Foundation

/// Along-route progress for Training transit safety (project hub position onto the drive polyline).
enum TrainingLabTransitPathProgress {
    /// Metres from path start to the closest point on the route polyline (not straight-line to goal).
    static func alongTrackProgressM(
        latitudeDeg: Double,
        longitudeDeg: Double,
        path: [RouteCoordinate]
    ) -> Double? {
        let polyline = MissionControlSquadConvoyFormationUtilities.pathPolyline(route: path)
        guard polyline.count >= 2 else { return nil }
        return MissionControlSquadConvoyFormationUtilities.projectOntoPolyline(
            latitudeDeg: latitudeDeg,
            longitudeDeg: longitudeDeg,
            polyline: polyline
        )?.alongTrackM
    }

    /// Route used for stuck checks when Nav2/geodesic resolution is not yet available.
    static func fallbackPath(for plan: TrainingLabRunVehiclePlan) -> [RouteCoordinate] {
        TrainingGeodesicPathPlanner.plan(
            start: plan.layout.start,
            goal: plan.layout.goal,
            stepM: 5
        )
    }
}
