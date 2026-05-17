import Foundation

/// Horizontal geofence legality for routing and streamed setpoints (v2 § P).
enum MissionGeofenceLegalityUtilities {

    private static let geom = MissionGeofenceGeometryUtilities()

    /// `true` when the horizontal position must not be used (inside an exclusion or outside all inclusions).
    /// When `clearanceM > 0`, exclusion polygons/circles are treated as expanded by that margin (routing skirt).
    static func coordinateViolatesGeofences(
        coordinate: RouteCoordinate,
        geofences: [MissionGeofence],
        clearanceM: Double = 0
    ) -> Bool {
        guard !geofences.isEmpty else { return false }
        var hasInclusion = false
        var insideAnyInclusion = false
        for fence in geofences {
            switch fence.boundary {
            case .exclusion:
                if exclusionViolates(coordinate: coordinate, fence: fence, clearanceM: clearanceM) {
                    return true
                }
            case .inclusion:
                hasInclusion = true
                if pointInsideFence(coordinate: coordinate, fence: fence) {
                    insideAnyInclusion = true
                }
            }
        }
        if hasInclusion, !insideAnyInclusion { return true }
        return false
    }

    /// Visibility-graph / A* edge test: exclusion **interior** and inclusion rules only (no horizontal clearance skirt on segments).
    static func segmentViolatesGeofenceTopology(
        from start: RouteCoordinate,
        to end: RouteCoordinate,
        geofences: [MissionGeofence],
        sampleCount: Int? = nil
    ) -> Bool {
        if segmentViolatesGeofences(
            from: start,
            to: end,
            geofences: geofences,
            clearanceM: 0,
            sampleCount: sampleCount
        ) {
            return true
        }
        for fence in geofences where fence.boundary == .exclusion {
            switch fence.shape {
            case .polygon where fence.polygonVertices.count >= 3:
                if segmentCrossesExclusionPolygonHorizontally(
                    from: start,
                    to: end,
                    vertices: fence.polygonVertices
                ) {
                    return true
                }
            case .circle:
                if segmentCrossesExclusionCircleHorizontally(
                    from: start,
                    to: end,
                    center: fence.circleCenter,
                    radiusM: fence.circleRadiusMeters
                ) {
                    return true
                }
            case .polygon:
                break
            }
        }
        return false
    }

    /// `true` when the chord enters an exclusion polygon (endpoints outside but chord cuts the ring).
    static func segmentCrossesExclusionPolygonHorizontally(
        from start: RouteCoordinate,
        to end: RouteCoordinate,
        vertices: [RouteCoordinate]
    ) -> Bool {
        guard vertices.count >= 3 else { return false }
        if geom.pointInsidePolygonHorizontallyWGS84(point: start, polygonVertices: vertices)
            || geom.pointInsidePolygonHorizontallyWGS84(point: end, polygonVertices: vertices) {
            return true
        }
        let latScale = MissionControlSquadConvoyFormationUtilities.metresPerDegreeLatitude
        let lat0 = vertices.map(\.lat).reduce(0, +) / Double(vertices.count)
        let lon0 = vertices.map(\.lon).reduce(0, +) / Double(vertices.count)
        let lonScale = latScale * cos(lat0 * .pi / 180.0)
        func toXY(_ c: RouteCoordinate) -> (x: Double, y: Double) {
            ((c.lon - lon0) * lonScale, (c.lat - lat0) * latScale)
        }
        let a = toXY(start)
        let b = toXY(end)
        let ring = vertices.map(toXY)
        let count = ring.count
        for i in 0..<count {
            let j = (i + 1) % count
            if segmentsIntersectProperly(a: a, b: b, c: ring[i], d: ring[j]) {
                return true
            }
        }
        return false
    }

    private static func segmentCrossesExclusionCircleHorizontally(
        from start: RouteCoordinate,
        to end: RouteCoordinate,
        center: RouteCoordinate,
        radiusM: Double
    ) -> Bool {
        guard radiusM > 0 else { return false }
        let distStart = MissionTelemetryGeo.horizontalDistanceM(
            lat1: start.lat, lon1: start.lon, lat2: center.lat, lon2: center.lon
        )
        let distEnd = MissionTelemetryGeo.horizontalDistanceM(
            lat1: end.lat, lon1: end.lon, lat2: center.lat, lon2: center.lon
        )
        if distStart <= radiusM || distEnd <= radiusM { return true }
        let latScale = MissionControlSquadConvoyFormationUtilities.metresPerDegreeLatitude
        let lonScale = latScale * cos(start.lat * .pi / 180.0)
        let sx = (start.lon - center.lon) * lonScale
        let sy = (start.lat - center.lat) * latScale
        let ex = (end.lon - center.lon) * lonScale
        let ey = (end.lat - center.lat) * latScale
        let dx = ex - sx
        let dy = ey - sy
        let len2 = dx * dx + dy * dy
        if len2 < 1e-12 { return distStart <= radiusM }
        let t = max(0, min(1, -(sx * dx + sy * dy) / len2))
        let cx = sx + t * dx
        let cy = sy + t * dy
        return hypot(cx, cy) < radiusM
    }

    private static func segmentsIntersectProperly(
        a: (x: Double, y: Double),
        b: (x: Double, y: Double),
        c: (x: Double, y: Double),
        d: (x: Double, y: Double)
    ) -> Bool {
        func orient(_ p: (x: Double, y: Double), _ q: (x: Double, y: Double), _ r: (x: Double, y: Double)) -> Double {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let o1 = orient(a, b, c)
        let o2 = orient(a, b, d)
        let o3 = orient(c, d, a)
        let o4 = orient(c, d, b)
        if o1 == 0, o2 == 0, o3 == 0, o4 == 0 {
            return false
        }
        return (o1 > 0) != (o2 > 0) && (o3 > 0) != (o4 > 0)
    }

    /// `true` when every sampled point along the chord is legal (dense sampling for long chords).
    static func segmentViolatesGeofences(
        from start: RouteCoordinate,
        to end: RouteCoordinate,
        geofences: [MissionGeofence],
        clearanceM: Double = 0,
        sampleCount: Int? = nil
    ) -> Bool {
        guard !geofences.isEmpty else { return false }
        let n = sampleCount ?? defaultSampleCount(from: start, to: end, clearanceM: clearanceM)
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            let lat = start.lat + (end.lat - start.lat) * t
            let lon = start.lon + (end.lon - start.lon) * t
            if coordinateViolatesGeofences(
                coordinate: RouteCoordinate(lat: lat, lon: lon),
                geofences: geofences,
                clearanceM: clearanceM
            ) {
                return true
            }
        }
        return false
    }

    static func pointInsideFence(coordinate: RouteCoordinate, fence: MissionGeofence) -> Bool {
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

    /// Horizontal distance from `coordinate` to the nearest edge of a polygon (metres); `nil` when not a polygon.
    static func horizontalDistanceToPolygonEdgeM(
        coordinate: RouteCoordinate,
        vertices: [RouteCoordinate]
    ) -> Double? {
        guard vertices.count >= 2 else { return nil }
        var best = Double.greatestFiniteMagnitude
        for i in vertices.indices {
            let j = (i + 1) % vertices.count
            let d = horizontalDistanceToSegmentM(
                point: coordinate,
                a: vertices[i],
                b: vertices[j]
            )
            best = min(best, d)
        }
        return best
    }

    private static func exclusionViolates(
        coordinate: RouteCoordinate,
        fence: MissionGeofence,
        clearanceM: Double
    ) -> Bool {
        switch fence.shape {
        case .polygon:
            if pointInsideFence(coordinate: coordinate, fence: fence) { return true }
            guard clearanceM > 0,
                  let edgeM = horizontalDistanceToPolygonEdgeM(
                      coordinate: coordinate,
                      vertices: fence.polygonVertices
                  )
            else { return false }
            return edgeM < clearanceM
        case .circle:
            let d = MissionTelemetryGeo.horizontalDistanceM(
                lat1: coordinate.lat,
                lon1: coordinate.lon,
                lat2: fence.circleCenter.lat,
                lon2: fence.circleCenter.lon
            )
            return d <= fence.circleRadiusMeters + max(0, clearanceM)
        }
    }

    private static func defaultSampleCount(
        from start: RouteCoordinate,
        to end: RouteCoordinate,
        clearanceM: Double
    ) -> Int {
        let spanM = MissionTelemetryGeo.horizontalDistanceM(
            lat1: start.lat,
            lon1: start.lon,
            lat2: end.lat,
            lon2: end.lon
        )
        let perFiveM = Int(ceil(spanM / 5.0))
        let base = clearanceM > 0 ? 24 : 16
        return max(2, min(64, base + perFiveM))
    }

    private static func horizontalDistanceToSegmentM(
        point: RouteCoordinate,
        a: RouteCoordinate,
        b: RouteCoordinate
    ) -> Double {
        let latScale = MissionControlSquadConvoyFormationUtilities.metresPerDegreeLatitude
        let lonScale = latScale * cos(point.lat * .pi / 180.0)
        let px = (point.lon - a.lon) * lonScale
        let py = (point.lat - a.lat) * latScale
        let bx = (b.lon - a.lon) * lonScale
        let by = (b.lat - a.lat) * latScale
        let len2 = bx * bx + by * by
        if len2 < 1e-12 {
            return hypot(px, py)
        }
        let t = max(0, min(1, (px * bx + py * by) / len2))
        let qx = t * bx
        let qy = t * by
        return hypot(px - qx, py - qy)
    }
}
