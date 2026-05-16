import Foundation

/// Geofence checks for wingman OFFBOARD/GUIDED setpoints (task + mission fences on the squad).
enum MissionControlSquadConvoySetpointGeofenceUtilities {

    private static let geom = MissionGeofenceGeometryUtilities()

    /// `true` when the horizontal position must not be streamed (inside an exclusion or outside all inclusions).
    static func setpointViolatesGeofences(
        coordinate: RouteCoordinate,
        geofences: [MissionGeofence]
    ) -> Bool {
        guard !geofences.isEmpty else { return false }
        var hasInclusion = false
        var insideAnyInclusion = false
        for fence in geofences {
            let inside = pointInsideFence(coordinate: coordinate, fence: fence)
            switch fence.boundary {
            case .exclusion:
                if inside { return true }
            case .inclusion:
                hasInclusion = true
                if inside { insideAnyInclusion = true }
            }
        }
        if hasInclusion, !insideAnyInclusion { return true }
        return false
    }

    /// Returns `proposed` when allowed; otherwise holds `lastValid` (or `proposed` when no prior valid target).
    static func filteredFormationTarget(
        proposed: FormationFollowStream.Target,
        lastValid: FormationFollowStream.Target?,
        geofences: [MissionGeofence]
    ) -> FormationFollowStream.Target {
        guard setpointViolatesGeofences(coordinate: proposed.coord, geofences: geofences) else {
            return proposed
        }
        return lastValid ?? proposed
    }

    private static func pointInsideFence(coordinate: RouteCoordinate, fence: MissionGeofence) -> Bool {
        switch fence.shape {
        case .polygon:
            return geom.pointInsidePolygonHorizontallyWGS84(
                point: coordinate,
                polygonVertices: fence.polygonVertices
            )
        case .circle:
            let d = MissionTelemetryGeo.horizontalDistanceM(
                lat1: coordinate.lat,
                lon1: coordinate.lon,
                lat2: fence.circleCenter.lat,
                lon2: fence.circleCenter.lon
            )
            return d <= fence.circleRadiusMeters
        }
    }
}
