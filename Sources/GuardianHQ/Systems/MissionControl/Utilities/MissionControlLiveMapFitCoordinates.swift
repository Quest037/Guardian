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

    /// MC-R live overview **fit-to-content** inputs: home, drawn path vertices, filtered runtime map points, and live vehicle marker positions (same scope as the map payload).
    static func liveOverviewMissionContentPoints(
        homeCoordinate: RouteCoordinate?,
        taskPathCoordinates: [[RouteCoordinate]],
        runtimeMissionPoints: [MissionPoint],
        focusedTaskID: UUID?,
        vehicleMarkerLatLon: [(Double, Double)]
    ) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        if let h = homeCoordinate, isUsableWgs84ForMapFit(lat: h.lat, lon: h.lon) {
            out.append((h.lat, h.lon))
        }
        for path in taskPathCoordinates {
            for c in path {
                guard isUsableWgs84ForMapFit(lat: c.lat, lon: c.lon) else { continue }
                out.append((c.lat, c.lon))
            }
        }
        for mp in MissionPoint.filteredForMissionControlLiveMap(runtimeMissionPoints, focusedTaskID: focusedTaskID) {
            let lat = mp.coordinate.lat
            let lon = mp.coordinate.lon
            guard isUsableWgs84ForMapFit(lat: lat, lon: lon) else { continue }
            out.append((lat, lon))
        }
        for (lat, lon) in vehicleMarkerLatLon {
            guard isUsableWgs84ForMapFit(lat: lat, lon: lon) else { continue }
            out.append((lat, lon))
        }
        return out
    }

    /// WGS84 points used to fit the live map viewport to one template geofence (polygon vertices or a circle bounding box).
    static func geofenceFitCoordinates(_ fence: MissionGeofence) -> [(Double, Double)] {
        switch fence.shape {
        case .polygon:
            return fence.polygonVertices.compactMap { c in
                guard isUsableWgs84ForMapFit(lat: c.lat, lon: c.lon) else { return nil }
                return (c.lat, c.lon)
            }
        case .circle:
            let c = fence.circleCenter
            guard isUsableWgs84ForMapFit(lat: c.lat, lon: c.lon) else { return [] }
            let r = max(1.0, fence.circleRadiusMeters)
            let latRad = c.lat * .pi / 180.0
            let cosLat = max(0.01, cos(latRad))
            let dLat = r / 111_320.0
            let dLon = r / (111_320.0 * cosLat)
            let corners: [(Double, Double)] = [
                (c.lat + dLat, c.lon - dLon),
                (c.lat + dLat, c.lon + dLon),
                (c.lat - dLat, c.lon - dLon),
                (c.lat - dLat, c.lon + dLon),
            ]
            return corners.filter { isUsableWgs84ForMapFit(lat: $0.0, lon: $0.1) }
        }
    }
}
