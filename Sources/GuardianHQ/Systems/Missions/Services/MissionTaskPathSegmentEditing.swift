import Foundation

/// Authoring helpers for hybrid **segment** paths while MRE still consumes a flat ``[RouteWaypoint]``.
enum MissionTaskPathSegmentEditing {
    // MARK: - Follow-road geometry (smooth road hugging, not user-editable anchors)

    /// Flat indices of ``RouteWaypointPathRole/anchor`` rows (mission editor shows these; interiors are automatic).
    static func anchorFlatIndices(in waypoints: [RouteWaypoint]) -> [Int] {
        waypoints.enumerated().compactMap { $0.element.pathRole == .anchor ? $0.offset : nil }
    }

    private static func metersPerLonDegrees(atLatitudeDegrees lat: Double) -> Double {
        cos(lat * .pi / 180) * 111_320
    }

    /// Perpendicular distance from `point` to segment `a`–`b` (planar equirectangular metres, origin at `a`).
    private static func perpendicularDistanceMeters(
        point: RouteCoordinate,
        lineStart a: RouteCoordinate,
        lineEnd b: RouteCoordinate
    ) -> Double {
        let vx = metersPerLonDegrees(atLatitudeDegrees: a.lat) * (b.lon - a.lon)
        let vy = 111_000 * (b.lat - a.lat)
        let px = metersPerLonDegrees(atLatitudeDegrees: a.lat) * (point.lon - a.lon)
        let py = 111_000 * (point.lat - a.lat)
        let len2 = vx * vx + vy * vy
        if len2 < 1e-4 { return hypot(px, py) }
        let t = max(0, min(1, (px * vx + py * vy) / len2))
        let qx = t * vx
        let qy = t * vy
        return hypot(px - qx, py - qy)
    }

    private static func polylineLengthMeters(_ coords: [RouteCoordinate]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var sum = 0.0
        for i in 1 ..< coords.count {
            sum += meters(from: coords[i - 1], to: coords[i])
        }
        return sum
    }

    /// Ramer–Douglas–Peucker in local metres — follows road curvature without keeping every OSRM vertex.
    private static func rdpSimplify(_ coords: [RouteCoordinate], epsilonMeters: Double) -> [RouteCoordinate] {
        guard coords.count >= 3 else { return coords }
        var dmax = 0.0
        var index = 0
        let first = coords[0]
        let last = coords[coords.count - 1]
        for i in 1 ..< (coords.count - 1) {
            let d = perpendicularDistanceMeters(point: coords[i], lineStart: first, lineEnd: last)
            if d > dmax {
                dmax = d
                index = i
            }
        }
        if dmax > epsilonMeters {
            let left = rdpSimplify(Array(coords[0 ... index]), epsilonMeters: epsilonMeters)
            let right = rdpSimplify(Array(coords[index ..< coords.count]), epsilonMeters: epsilonMeters)
            return left + right.dropFirst()
        }
        return [first, last]
    }

    private static func dedupeConsecutive(_ coords: [RouteCoordinate], minSeparationMeters: Double) -> [RouteCoordinate] {
        var out: [RouteCoordinate] = []
        for c in coords {
            if let last = out.last, meters(from: last, to: c) < minSeparationMeters { continue }
            out.append(c)
        }
        return out
    }

    /// Downsample a long interior run (index-based — good enough for display polylines).
    private static func capInteriorCoordinateCount(_ interior: [RouteCoordinate], maxCount: Int) -> [RouteCoordinate] {
        guard interior.count > maxCount, maxCount >= 2 else { return interior }
        let step = Double(interior.count - 1) / Double(maxCount - 1)
        var out: [RouteCoordinate] = []
        for i in 0 ..< maxCount {
            let idx = min(interior.count - 1, Int((Double(i) * step).rounded(.down)))
            out.append(interior[idx])
        }
        return dedupeConsecutive(out, minSeparationMeters: 5)
    }

    /// Interior coordinates between OSRM endpoints: **curve-following** polyline for map + runtime, while pilots
    /// only edit anchors. These become ``RouteWaypointPathRole/segmentInterior`` (hidden in the mission sidebar).
    private static func followRoadInteriorCoordinates(
        trimmedPolyline: [RouteCoordinate],
        rdpEpsilonMeters: Double = 11,
        maxInteriorPoints: Int = 96,
        minPathMetersForCap: Double = 140
    ) -> [RouteCoordinate] {
        let pts = trimmedPolyline
        guard pts.count >= 3 else { return [] }

        let simplified = rdpSimplify(pts, epsilonMeters: rdpEpsilonMeters)
        if simplified.count <= 2 {
            if polylineLengthMeters(pts) >= 40 {
                return dedupeConsecutive([pts[pts.count / 2]], minSeparationMeters: 1)
            }
            return []
        }

        var interior = Array(simplified.dropFirst().dropLast())
        if interior.isEmpty, polylineLengthMeters(pts) >= 35 {
            interior = [pts[pts.count / 2]]
        }
        if polylineLengthMeters(pts) >= minPathMetersForCap, interior.count > maxInteriorPoints {
            interior = capInteriorCoordinateCount(interior, maxCount: maxInteriorPoints)
        }
        return dedupeConsecutive(interior, minSeparationMeters: 6)
    }

    /// Index of the next anchor strictly after `index`, if any.
    static func indexOfNextAnchor(in waypoints: [RouteWaypoint], after index: Int) -> Int? {
        var j = index + 1
        while j < waypoints.count {
            if waypoints[j].pathRole == .anchor { return j }
            j += 1
        }
        return nil
    }

    /// Previous anchor index strictly before `index`, if any.
    static func indexOfPreviousAnchor(in waypoints: [RouteWaypoint], before index: Int) -> Int? {
        var j = index - 1
        while j >= 0 {
            if waypoints[j].pathRole == .anchor { return j }
            j -= 1
        }
        return nil
    }

    /// Drop OSRM endpoints that duplicate anchors (within a few metres).
    static func trimDenseCoordinates(
        _ coords: [RouteCoordinate],
        start: RouteCoordinate,
        end: RouteCoordinate
    ) -> [RouteCoordinate] {
        guard !coords.isEmpty else { return [start, end] }
        var c = coords
        while let f = c.first, meters(from: f, to: start) < 12 { c.removeFirst() }
        while let l = c.last, meters(from: l, to: end) < 12 { c.removeLast() }
        return [start] + c + [end]
    }

    static func meters(from: RouteCoordinate, to: RouteCoordinate) -> Double {
        let la = from.lat * .pi / 180
        let lb = to.lat * .pi / 180
        let dLat = (to.lat - from.lat) * .pi / 180
        let dLon = (to.lon - from.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la) * cos(lb) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(h), sqrt(1 - h))
        return 6_371_000 * c
    }

    /// Append a **direct** leg to `coordinate` from the current last anchor.
    static func appendDirectLeg(
        waypoints: inout [RouteWaypoint],
        coordinate: RouteCoordinate,
        outgoingKind: RouteSegmentKind
    ) {
        let template = waypoints.last
        let la = waypoints.count - 1
        if waypoints.indices.contains(la) {
            waypoints[la].outgoingSegmentKind = outgoingKind
        }
        waypoints.append(
            RouteWaypoint(
                coord: coordinate,
                altitude: template?.altitude ?? RouteAltitude(),
                heading: template?.heading ?? 0,
                headingPreset: .followCourse,
                pathSegmentId: nil,
                pathRole: .anchor,
                pathSegmentKind: .direct,
                outgoingSegmentKind: nil
            )
        )
    }

    /// Inserts smoothed OSRM polyline samples (``segmentInterior``) then a new anchor at `coordinate`.
    /// Updates outgoing kind on the anchor at `templateIndex`.
    static func appendFollowRoadLeg(
        waypoints: inout [RouteWaypoint],
        templateIndex: Int,
        coordinate: RouteCoordinate,
        denseCoords: [RouteCoordinate]
    ) {
        guard waypoints.indices.contains(templateIndex) else { return }
        let template = waypoints[templateIndex]
        waypoints[templateIndex].outgoingSegmentKind = .followRoads
        let legId = UUID()
        let trimmed = trimDenseCoordinates(denseCoords, start: template.coord, end: coordinate)
        let interiorCoords = followRoadInteriorCoordinates(trimmedPolyline: trimmed)
        var insertAt = templateIndex + 1
        for c in interiorCoords {
            waypoints.insert(
                RouteWaypoint(
                    coord: c,
                    altitude: template.altitude,
                    heading: template.heading,
                    headingPreset: .followCourse,
                    pathSegmentId: legId,
                    pathRole: .segmentInterior,
                    pathSegmentKind: .followRoads,
                    outgoingSegmentKind: nil
                ),
                at: insertAt
            )
            insertAt += 1
        }
        waypoints.append(
            RouteWaypoint(
                coord: coordinate,
                altitude: template.altitude,
                heading: template.heading,
                headingPreset: .followCourse,
                pathSegmentId: nil,
                pathRole: .anchor,
                pathSegmentKind: .direct,
                outgoingSegmentKind: nil
            )
        )
    }

    /// Rebuild interior road geometry for a follow-road leg starting at anchor `anchorFromIndex`.
    static func rebuildFollowRoadInterior(
        waypoints: inout [RouteWaypoint],
        anchorFromIndex: Int,
        denseCoords: [RouteCoordinate]
    ) {
        guard waypoints.indices.contains(anchorFromIndex) else { return }
        guard waypoints[anchorFromIndex].outgoingSegmentKind == .followRoads else { return }
        guard let toIdx = indexOfNextAnchor(in: waypoints, after: anchorFromIndex) else { return }
        let fromCoord = waypoints[anchorFromIndex].coord
        let toCoord = waypoints[toIdx].coord
        let template = waypoints[anchorFromIndex]
        guard toIdx > anchorFromIndex + 1,
              let legId = waypoints[anchorFromIndex + 1].pathSegmentId
        else { return }

        waypoints.removeSubrange((anchorFromIndex + 1) ..< toIdx)
        let trimmed = trimDenseCoordinates(denseCoords, start: fromCoord, end: toCoord)
        let interiorCoords = followRoadInteriorCoordinates(trimmedPolyline: trimmed)
        var insertAt = anchorFromIndex + 1
        for c in interiorCoords {
            waypoints.insert(
                RouteWaypoint(
                    coord: c,
                    altitude: template.altitude,
                    heading: template.heading,
                    headingPreset: .followCourse,
                    pathSegmentId: legId,
                    pathRole: .segmentInterior,
                    pathSegmentKind: .followRoads,
                    outgoingSegmentKind: nil
                ),
                at: insertAt
            )
            insertAt += 1
        }
    }
}
