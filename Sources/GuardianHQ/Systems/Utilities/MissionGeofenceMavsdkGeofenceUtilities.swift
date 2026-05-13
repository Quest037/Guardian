import Foundation
import Mavsdk

/// Converts ``MissionGeofence`` regions into MAVSDK ``Geofence`` polygons for fleet upload.
///
/// **Circles** are approximated as regular horizontal polygons (24 edges) using the same
/// spherical offset model as ``FleetCommandStackConverterShared`` move helpers — adequate
/// for tactical fence radii. **Polygons** reuse template vertices; rings are closed when the
/// first and last vertex differ.
enum MissionGeofenceMavsdkGeofenceUtilities: Sendable {

    private static let earthRadiusM = 6_371_000.0
    private static let circleSegments = 24

    /// Builds MAVSDK polygons, **skipping** shapes that cannot be represented (too few vertices,
    /// degenerate circle radius).
    static func mavsdkPolygons(forGeofences fences: [MissionGeofence]) -> [Mavsdk.Geofence.Polygon] {
        let geom = MissionGeofenceGeometryUtilities()
        var out: [Mavsdk.Geofence.Polygon] = []
        out.reserveCapacity(fences.count)
        for fence in fences {
            switch fence.shape {
            case .polygon:
                if geom.polygonHasInsufficientVertices(fence.polygonVertices) { continue }
                var pts = fence.polygonVertices.map {
                    Mavsdk.Geofence.Point(latitudeDeg: $0.lat, longitudeDeg: $0.lon)
                }
                if let first = pts.first, let last = pts.last,
                   (abs(first.latitudeDeg - last.latitudeDeg) > 1e-9 || abs(first.longitudeDeg - last.longitudeDeg) > 1e-9) {
                    pts.append(first)
                }
                out.append(Mavsdk.Geofence.Polygon(points: pts, fenceType: fence.mavsdkFenceType))
            case .circle:
                let r = fence.circleRadiusMeters
                guard r >= 1 else { continue }
                let center = fence.circleCenter
                let points = circleApproximationPoints(center: center, radiusM: r, segments: circleSegments)
                guard points.count >= 3 else { continue }
                out.append(Mavsdk.Geofence.Polygon(points: points, fenceType: fence.mavsdkFenceType))
            }
        }
        return out
    }

    /// JSON array string accepted by ``FleetVehicleCommandGeofencePolygonPayload/decodePolygons(fromJSON:)``.
    static func encodeGeofencePolygonsJSON(forGeofences fences: [MissionGeofence]) throws -> String {
        let polys = mavsdkPolygons(forGeofences: fences)
        return try FleetVehicleCommandGeofencePolygonPayload.encodePolygonsToJSON(polygons: polys)
    }

    private static func circleApproximationPoints(
        center: RouteCoordinate,
        radiusM: Double,
        segments: Int
    ) -> [Mavsdk.Geofence.Point] {
        guard segments >= 3 else { return [] }
        var pts: [Mavsdk.Geofence.Point] = []
        pts.reserveCapacity(segments)
        for k in 0..<segments {
            let bearingDeg = Double(k) * 360.0 / Double(segments)
            let (lat, lon) = offsetLatLon(
                latitudeDeg: center.lat,
                longitudeDeg: center.lon,
                distanceM: radiusM,
                bearingDeg: bearingDeg
            )
            pts.append(Mavsdk.Geofence.Point(latitudeDeg: lat, longitudeDeg: lon))
        }
        return pts
    }

    /// Spherical great-circle offset (same construction as ``FleetCommandStackConverterShared``).
    private static func offsetLatLon(
        latitudeDeg: Double,
        longitudeDeg: Double,
        distanceM: Double,
        bearingDeg: Double
    ) -> (lat: Double, lon: Double) {
        let bearingRad = bearingDeg * .pi / 180
        let lat1 = latitudeDeg * .pi / 180
        let lon1 = longitudeDeg * .pi / 180
        let angularDistance = distanceM / earthRadiusM
        let lat2 = asin(
            sin(lat1) * cos(angularDistance)
                + cos(lat1) * sin(angularDistance) * cos(bearingRad)
        )
        let lon2 = lon1 + atan2(
            sin(bearingRad) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )
        return (lat: lat2 * 180 / .pi, lon: lon2 * 180 / .pi)
    }
}

private extension MissionGeofence {
    var mavsdkFenceType: Mavsdk.Geofence.Polygon.FenceType {
        switch boundary {
        case .inclusion: return .inclusion
        case .exclusion: return .exclusion
        }
    }
}
