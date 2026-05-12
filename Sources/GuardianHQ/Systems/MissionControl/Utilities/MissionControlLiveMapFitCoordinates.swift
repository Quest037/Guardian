// MissionControlLiveMapFitCoordinates.swift — MC-R “show on map” bbox inputs (pure geometry lists).

import Foundation

/// Builds WGS84 coordinate lists for Mission Control **running** map fit operations (no hub I/O).
enum MissionControlLiveMapFitCoordinates {
    /// Drops unset `(0,0)` defaults, non-finite values, and coordinates outside WGS84 so ``fitBounds`` is not
    /// stretched across the globe (which forces a very wide zoom).
    static func isUsableWgs84ForMapFit(lat: Double, lon: Double) -> Bool {
        guard lat.isFinite, lon.isFinite else { return false }
        if lat == 0, lon == 0 { return false }
        return (-85 ... 85).contains(lat) && (-180 ... 180).contains(lon)
    }

    /// Task triage “show on map”: task route waypoints, **task-owned** runtime map points (`taskID == taskID`),
    /// and pre-resolved roster vehicle hub positions for assignments bound to that task.
    static func taskTriageFitCoordinates(
        taskWaypoints: [RouteWaypoint],
        taskID: UUID,
        runtimeMissionPoints: [MissionPoint],
        rosterVehicleHubCoordinates: [(Double, Double)]
    ) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        for wp in taskWaypoints {
            let lat = wp.coord.lat
            let lon = wp.coord.lon
            guard isUsableWgs84ForMapFit(lat: lat, lon: lon) else { continue }
            out.append((lat, lon))
        }
        for mp in runtimeMissionPoints where mp.taskID == taskID {
            let lat = mp.coordinate.lat
            let lon = mp.coordinate.lon
            guard isUsableWgs84ForMapFit(lat: lat, lon: lon) else { continue }
            out.append((lat, lon))
        }
        for pair in rosterVehicleHubCoordinates {
            guard isUsableWgs84ForMapFit(lat: pair.0, lon: pair.1) else { continue }
            out.append(pair)
        }
        return out
    }
}
