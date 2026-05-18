import Foundation

/// Local geodesic A→B sampling when the ROS 2 bridge is unavailable (matches Python fallback).
enum TrainingGeodesicPathPlanner {
    static func plan(
        start: TrainingTaskPose,
        goal: TrainingTaskPose,
        stepM: Double = 2.0
    ) -> [RouteCoordinate] {
        let step = max(0.5, stepM)
        let r = 6_378_137.0
        let dLat = (goal.latitudeDeg - start.latitudeDeg) * .pi / 180
        let dLon = (goal.longitudeDeg - start.longitudeDeg) * .pi / 180
        let midLat = (start.latitudeDeg + goal.latitudeDeg) * 0.5
        let northM = dLat * r
        let eastM = dLon * r * cos(midLat * .pi / 180)
        let distM = hypot(northM, eastM)
        let steps = max(1, Int(ceil(distM / step)))
        var points: [RouteCoordinate] = []
        points.reserveCapacity(steps + 1)
        for i in 0...steps {
            let frac = Double(i) / Double(steps)
            points.append(
                RouteCoordinate(
                    lat: start.latitudeDeg + (goal.latitudeDeg - start.latitudeDeg) * frac,
                    lon: start.longitudeDeg + (goal.longitudeDeg - start.longitudeDeg) * frac
                )
            )
        }
        return points
    }
}
