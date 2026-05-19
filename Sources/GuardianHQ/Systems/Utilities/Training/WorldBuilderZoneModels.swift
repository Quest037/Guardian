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

    /// Moves or shrinks the zone so center and edge samples fit inside the map-base square.
    /// - Returns: `false` when the zone cannot fit even at minimum radius.
    @discardableResult
    static func snapZoneToFloor(_ zone: inout WorldBuilderZoneState, floor: WorldBuilderZoneFloorRect) -> Bool {
        guard zone.placed else { return true }
        WorldBuilderZoneManifestSupport.clampZoneRadiusToAllowedRange(&zone)
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
            return true
        }

        let maxRadiusM = min(
            zone.centerXM - floor.minXM,
            floor.maxXM - zone.centerXM,
            zone.centerYM - floor.minYM,
            floor.maxYM - zone.centerYM,
            WorldBuilderZoneState.maxRadiusM
        )
        if maxRadiusM < WorldBuilderZoneState.minRadiusM {
            return false
        }
        if zone.radiusM > maxRadiusM {
            zone.radiusM = max(WorldBuilderZoneState.minRadiusM, maxRadiusM)
        }
        return fitsOnFloor(zone, floor: floor)
    }

    @discardableResult
    static func snapZonesToFloor(_ zones: inout WorldBuilderZonesSnapshot, floor: WorldBuilderZoneFloorRect) -> Bool {
        snapZoneToFloor(&zones.start, floor: floor) && snapZoneToFloor(&zones.end, floor: floor)
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
        clampZoneRadiiToAllowedRange(&copy)
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
    static func clampZoneRadiiToAllowedRange(_ zones: inout WorldBuilderZonesSnapshot) {
        clampZoneRadiusToAllowedRange(&zones.start)
        clampZoneRadiusToAllowedRange(&zones.end)
    }

    static func clampZoneRadiusToAllowedRange(_ zone: inout WorldBuilderZoneState) {
        zone.radiusM = min(
            WorldBuilderZoneState.maxRadiusM,
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
