import Foundation

/// Optional panel docked over the viewport (opened from the build rail).
enum WorldBuilderSceneToolPanel: String, Equatable, Sendable {
    case zoneEditor
    case obstacleEditor
}

/// Start / end training zone edited in World Builder (maps to manifest spawn / goal).
enum WorldBuilderZoneKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case start
    case end

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .start: return "Start"
        case .end: return "End"
        }
    }
}

enum TrainingEnvironmentZoneShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case circle
    case square

    var id: String { rawValue }

    static func resolved(from raw: String?) -> TrainingEnvironmentZoneShape {
        guard let raw, let shape = TrainingEnvironmentZoneShape(rawValue: raw) else { return .circle }
        return shape
    }
}

/// One start or end zone on the training floor (ENU metres).
struct WorldBuilderZoneState: Codable, Equatable, Sendable {
    var placed: Bool
    var centerXM: Double
    var centerYM: Double
    var centerZM: Double
    var radiusM: Double
    var shape: TrainingEnvironmentZoneShape

    static let defaultRadiusM = 30.0
    static let minRadiusM = 20.0
    static let maxRadiusM = 80.0

    static func unplaced(shape: TrainingEnvironmentZoneShape = .circle) -> WorldBuilderZoneState {
        WorldBuilderZoneState(
            placed: false,
            centerXM: 0,
            centerYM: 0,
            centerZM: 0,
            radiusM: defaultRadiusM,
            shape: shape
        )
    }
}

struct WorldBuilderZonesSnapshot: Codable, Equatable, Sendable {
    var start: WorldBuilderZoneState
    var end: WorldBuilderZoneState

    static let empty = WorldBuilderZonesSnapshot(
        start: .unplaced(),
        end: .unplaced()
    )
}

/// Axis-aligned map-base square in environment ENU (metres).
struct WorldBuilderZoneFloorRect: Equatable, Sendable {
    var minXM: Double
    var maxXM: Double
    var minYM: Double
    var maxYM: Double

    static func centeredSquare(halfExtentM: Double) -> WorldBuilderZoneFloorRect {
        let half = max(halfExtentM, 0)
        return WorldBuilderZoneFloorRect(
            minXM: -half,
            maxXM: half,
            minYM: -half,
            maxYM: half
        )
    }

    func contains(x: Double, y: Double, epsilon: Double = 1e-6) -> Bool {
        x >= minXM - epsilon
            && x <= maxXM + epsilon
            && y >= minYM - epsilon
            && y <= maxYM + epsilon
    }
}

enum WorldBuilderZoneBoundsCheck {
    static let circleEdgeSampleCount = 16

    /// Open-field map-base top face (``TrainingEnvironmentWorldSDF`` floor collision top at z = 0).
    static let mapBaseTopZM: Double = 0

    /// Pins zone centre Z to the map-base top (open-field overlays are planar at z = 0).
    static func clampCenterZMToMapBase(_ zone: inout WorldBuilderZoneState) {
        guard zone.placed else { return }
        zone.centerZM = mapBaseTopZM
    }

    /// Boundary sample points: square corners or circle circumference (evenly spaced).
    static func edgePoints(for zone: WorldBuilderZoneState) -> [(x: Double, y: Double)] {
        guard zone.placed else { return [] }
        let cx = zone.centerXM
        let cy = zone.centerYM
        let r = zone.radiusM
        switch zone.shape {
        case .square:
            return [
                (cx - r, cy - r),
                (cx + r, cy - r),
                (cx + r, cy + r),
                (cx - r, cy + r),
            ]
        case .circle:
            var points: [(x: Double, y: Double)] = []
            points.reserveCapacity(circleEdgeSampleCount)
            for i in 0..<circleEdgeSampleCount {
                let t = (Double(i) / Double(circleEdgeSampleCount)) * 2 * Double.pi
                points.append((cx + cos(t) * r, cy + sin(t) * r))
            }
            return points
        }
    }

    /// True when the zone center and every edge sample lie inside the map-base square.
    static func fitsOnFloor(_ zone: WorldBuilderZoneState, floor: WorldBuilderZoneFloorRect) -> Bool {
        guard zone.placed else { return true }
        if !floor.contains(x: zone.centerXM, y: zone.centerYM) {
            return false
        }
        for point in edgePoints(for: zone) {
            if !floor.contains(x: point.x, y: point.y) {
                return false
            }
        }
        return true
    }

    static func zonesFitOnFloor(_ zones: WorldBuilderZonesSnapshot, floor: WorldBuilderZoneFloorRect) -> Bool {
        fitsOnFloor(zones.start, floor: floor) && fitsOnFloor(zones.end, floor: floor)
    }

    /// `true` when both zones are placed and their footprints share any area (touching counts as overlap).
    static func zonesOverlap(_ zones: WorldBuilderZonesSnapshot) -> Bool {
        guard zones.start.placed, zones.end.placed else { return false }
        return zonesOverlap(zones.start, zones.end)
    }

    /// `true` when a placed zone footprint shares area with an obstacle (same rule as obstacle vs zone).
    static func overlapsObstacle(
        _ zone: WorldBuilderZoneState,
        _ obstacle: TrainingEnvironmentObstacleRecord
    ) -> Bool {
        guard zone.placed else { return false }
        let zonePoly = edgePoints(for: zone).map { (x: $0.x, y: $0.y) }
        let obstaclePoly = WorldBuilderObstacleBoundsCheck.edgePoints(for: obstacle)
        return WorldBuilderObstacleBoundsCheck.convexPolygonsOverlap(zonePoly, obstaclePoly)
    }

    static func zonesOverlapAnyObstacle(
        _ zones: WorldBuilderZonesSnapshot,
        obstacles: [TrainingEnvironmentObstacleRecord]
    ) -> Bool {
        guard !obstacles.isEmpty else { return false }
        for zone in [zones.start, zones.end] where zone.placed {
            for obstacle in obstacles {
                if overlapsObstacle(zone, obstacle) {
                    return true
                }
            }
        }
        return false
    }

    static func zonesOverlap(_ a: WorldBuilderZoneState, _ b: WorldBuilderZoneState) -> Bool {
        guard a.placed, b.placed else { return false }
        switch (a.shape, b.shape) {
        case (.circle, .circle):
            let dx = a.centerXM - b.centerXM
            let dy = a.centerYM - b.centerYM
            let dist = (dx * dx + dy * dy).squareRoot()
            return dist < a.radiusM + b.radiusM - separationEpsilonM
        case (.square, .square):
            return axisAlignedSquaresOverlap(a, b)
        case (.circle, .square):
            return circleOverlapsSquare(circle: a, square: b)
        case (.square, .circle):
            return circleOverlapsSquare(circle: b, square: a)
        }
    }

    private static let separationEpsilonM = 1e-6

    private static func axisAlignedSquaresOverlap(
        _ a: WorldBuilderZoneState,
        _ b: WorldBuilderZoneState
    ) -> Bool {
        let aMinX = a.centerXM - a.radiusM
        let aMaxX = a.centerXM + a.radiusM
        let aMinY = a.centerYM - a.radiusM
        let aMaxY = a.centerYM + a.radiusM
        let bMinX = b.centerXM - b.radiusM
        let bMaxX = b.centerXM + b.radiusM
        let bMinY = b.centerYM - b.radiusM
        let bMaxY = b.centerYM + b.radiusM
        if aMaxX <= bMinX + separationEpsilonM { return false }
        if bMaxX <= aMinX + separationEpsilonM { return false }
        if aMaxY <= bMinY + separationEpsilonM { return false }
        if bMaxY <= aMinY + separationEpsilonM { return false }
        return true
    }

    private static func circleOverlapsSquare(
        circle: WorldBuilderZoneState,
        square: WorldBuilderZoneState
    ) -> Bool {
        let half = square.radiusM
        let closestX = min(max(circle.centerXM, square.centerXM - half), square.centerXM + half)
        let closestY = min(max(circle.centerYM, square.centerYM - half), square.centerYM + half)
        let dx = circle.centerXM - closestX
        let dy = circle.centerYM - closestY
        let distSq = dx * dx + dy * dy
        let r = circle.radiusM
        return distSq < r * r - separationEpsilonM
    }

    /// Moves or shrinks the zone so center and edge samples fit inside the map-base square.
    /// - Returns: `false` when the zone cannot fit even at minimum radius.
    @discardableResult
    static func snapZoneToFloor(
        _ zone: inout WorldBuilderZoneState,
        floor: WorldBuilderZoneFloorRect,
        maxZoneRadiusM: Double = WorldBuilderZoneState.maxRadiusM
    ) -> Bool {
        guard zone.placed else { return true }
        clampCenterZMToMapBase(&zone)
        WorldBuilderZoneManifestSupport.clampZoneRadiusToAllowedRange(&zone, maxRadiusM: maxZoneRadiusM)
        if fitsOnFloor(zone, floor: floor) {
            return true
        }

        var points = [(x: zone.centerXM, y: zone.centerYM)]
        points.append(contentsOf: edgePoints(for: zone).map { (x: $0.x, y: $0.y) })

        var dxMin = -Double.infinity
        var dxMax = Double.infinity
        var dyMin = -Double.infinity
        var dyMax = Double.infinity
        for point in points {
            dxMin = max(dxMin, floor.minXM - point.x)
            dxMax = min(dxMax, floor.maxXM - point.x)
            dyMin = max(dyMin, floor.minYM - point.y)
            dyMax = min(dyMax, floor.maxYM - point.y)
        }

        if dxMin <= dxMax {
            zone.centerXM += min(max(0, dxMin), dxMax)
        }
        if dyMin <= dyMax {
            zone.centerYM += min(max(0, dyMin), dyMax)
        }

        if fitsOnFloor(zone, floor: floor) {
            clampCenterZMToMapBase(&zone)
            return true
        }

        let maxRadiusM = min(
            zone.centerXM - floor.minXM,
            floor.maxXM - zone.centerXM,
            zone.centerYM - floor.minYM,
            floor.maxYM - zone.centerYM,
            maxZoneRadiusM
        )
        if maxRadiusM < WorldBuilderZoneState.minRadiusM {
            return false
        }
        if zone.radiusM > maxRadiusM {
            zone.radiusM = max(WorldBuilderZoneState.minRadiusM, maxRadiusM)
        }
        clampCenterZMToMapBase(&zone)
        return fitsOnFloor(zone, floor: floor)
    }

    @discardableResult
    static func snapZonesToFloor(
        _ zones: inout WorldBuilderZonesSnapshot,
        floor: WorldBuilderZoneFloorRect,
        maxZoneRadiusM: Double = WorldBuilderZoneState.maxRadiusM,
        obstacles: [TrainingEnvironmentObstacleRecord] = []
    ) -> Bool {
        let snapped = snapZoneToFloor(&zones.start, floor: floor, maxZoneRadiusM: maxZoneRadiusM)
            && snapZoneToFloor(&zones.end, floor: floor, maxZoneRadiusM: maxZoneRadiusM)
        return snapped && !zonesOverlap(zones) && !zonesOverlapAnyObstacle(zones, obstacles: obstacles)
    }
}

enum WorldBuilderZoneManifestSupport {
    static let defaultRadiusM = WorldBuilderZoneState.defaultRadiusM

    static func zones(from manifest: TrainingEnvironmentManifest) -> WorldBuilderZonesSnapshot {
        WorldBuilderZonesSnapshot(
            start: zone(
                pose: manifest.defaultSpawn,
                radiusM: manifest.startZoneRadiusM,
                shape: manifest.startZoneShape,
                configured: manifest.startZoneConfigured
            ),
            end: zone(
                pose: manifest.defaultGoal,
                radiusM: manifest.endZoneRadiusM,
                shape: manifest.endZoneShape,
                configured: manifest.endZoneConfigured
            )
        )
    }

    static func apply(_ zones: WorldBuilderZonesSnapshot, to manifest: inout TrainingEnvironmentManifest) {
        var copy = zones
        let floorSize = TrainingEnvironmentFloorSize.resolved(from: manifest.floorSize)
        clampZoneRadiiToAllowedRange(&copy, floorSize: floorSize)
        if copy.start.placed {
            WorldBuilderZoneBoundsCheck.clampCenterZMToMapBase(&copy.start)
        }
        if copy.end.placed {
            WorldBuilderZoneBoundsCheck.clampCenterZMToMapBase(&copy.end)
        }
        manifest.startZoneRadiusM = copy.start.radiusM
        manifest.startZoneShape = copy.start.shape.rawValue
        manifest.endZoneRadiusM = copy.end.radiusM
        manifest.endZoneShape = copy.end.shape.rawValue
        if copy.start.placed {
            manifest.defaultSpawn = pose(from: copy.start)
        }
        manifest.startZoneConfigured = copy.start.placed
        if copy.end.placed {
            manifest.defaultGoal = pose(from: copy.end)
        }
        manifest.endZoneConfigured = copy.end.placed
    }

    /// Clamps radius to the editor min/max only (floor fit is validated separately).
    static func clampZoneRadiiToAllowedRange(
        _ zones: inout WorldBuilderZonesSnapshot,
        floorSize: TrainingEnvironmentFloorSize
    ) {
        let maxR = floorSize.maxZoneRadiusM
        clampZoneRadiusToAllowedRange(&zones.start, maxRadiusM: maxR)
        clampZoneRadiusToAllowedRange(&zones.end, maxRadiusM: maxR)
    }

    static func clampZoneRadiusToAllowedRange(
        _ zone: inout WorldBuilderZoneState,
        maxRadiusM: Double = WorldBuilderZoneState.maxRadiusM
    ) {
        zone.radiusM = min(
            maxRadiusM,
            max(WorldBuilderZoneState.minRadiusM, zone.radiusM)
        )
    }

    private static func zone(
        pose: TrainingEnvironmentPose,
        radiusM: Double,
        shape: String,
        configured: Bool
    ) -> WorldBuilderZoneState {
        WorldBuilderZoneState(
            placed: configured,
            centerXM: pose.xM,
            centerYM: pose.yM,
            centerZM: pose.zM,
            radiusM: radiusM > 0 ? radiusM : defaultRadiusM,
            shape: TrainingEnvironmentZoneShape.resolved(from: shape)
        )
    }

    private static func pose(from zone: WorldBuilderZoneState) -> TrainingEnvironmentPose {
        TrainingEnvironmentPose(xM: zone.centerXM, yM: zone.centerYM, zM: zone.centerZM, yawDeg: 0)
    }
}
