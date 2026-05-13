import Foundation

/// Planar geometry checks for **mission template** geofence authoring (polygons on small AOIs).
///
/// Self-intersection uses a **local tangent plane** in meters (centroid as origin). Adequate for tactical fence sizes; not a geodesic survey.
struct MissionGeofenceGeometryUtilities: Sendable {
    private static let earthMetersPerDegreeLat = 111_320.0

    /// `true` when the closed ring has **fewer than three** distinct corners (map overlay is suppressed until fixed).
    func polygonHasInsufficientVertices(_ vertices: [RouteCoordinate]) -> Bool {
        vertices.count < 3
    }

    /// `true` when **non-adjacent** edges intersect in the local meter plane (bow-tie / hourglass rings).
    ///
    /// - Returns `false` when there are fewer than three vertices.
    func polygonSelfIntersectsWGS84(vertices: [RouteCoordinate]) -> Bool {
        guard vertices.count >= 3 else { return false }
        let planar = Self.planarMetersFromWGS84(vertices: vertices)
        return Self.planarPolygonEdgesSelfIntersect(planar: planar)
    }

    private static func planarMetersFromWGS84(vertices: [RouteCoordinate]) -> [(x: Double, y: Double)] {
        let n = vertices.count
        guard n > 0 else { return [] }
        var sumLat = 0.0
        var sumLon = 0.0
        for v in vertices {
            sumLat += v.lat
            sumLon += v.lon
        }
        let lat0 = sumLat / Double(n)
        let lon0 = sumLon / Double(n)
        let mPerLon = earthMetersPerDegreeLat * cos(lat0 * .pi / 180.0)
        return vertices.map { v in
            let x = (v.lon - lon0) * mPerLon
            let y = (v.lat - lat0) * earthMetersPerDegreeLat
            return (x, y)
        }
    }

    private static func planarPolygonEdgesSelfIntersect(planar: [(x: Double, y: Double)]) -> Bool {
        let n = planar.count
        guard n >= 3 else { return false }
        for i in 0..<n {
            let a1 = planar[i]
            let a2 = planar[(i + 1) % n]
            for j in (i + 1)..<n {
                let b1 = planar[j]
                let b2 = planar[(j + 1) % n]
                let vertsI: Set<Int> = [i, (i + 1) % n]
                let vertsJ: Set<Int> = [j, (j + 1) % n]
                if !vertsI.isDisjoint(with: vertsJ) { continue }
                if segmentsIntersectProper(a1, a2, b1, b2) { return true }
            }
        }
        return false
    }

    /// Segment intersection excluding collinear overlap (rare for operator-drawn fences); catches bow-ties.
    private static func segmentsIntersectProper(
        _ p1: (x: Double, y: Double),
        _ p2: (x: Double, y: Double),
        _ p3: (x: Double, y: Double),
        _ p4: (x: Double, y: Double)
    ) -> Bool {
        let o1 = orientation(p1, p2, p3)
        let o2 = orientation(p1, p2, p4)
        let o3 = orientation(p3, p4, p1)
        let o4 = orientation(p3, p4, p2)
        if o1 != o2 && o3 != o4 { return true }
        return false
    }

    /// 0 = collinear, 1 = clockwise, 2 = counter-clockwise
    private static func orientation(
        _ a: (x: Double, y: Double),
        _ b: (x: Double, y: Double),
        _ c: (x: Double, y: Double)
    ) -> Int {
        let v = (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y)
        if abs(v) < 1e-12 { return 0 }
        return v > 0 ? 1 : 2
    }
}
