import Foundation

// MARK: - Kind & orientation

enum TrainingEnvironmentObstacleKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cube
    case cuboid
    case cylinder
    case cone
    case pyramid
    case toblerone

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cube: return "Cube"
        case .cuboid: return "Cuboid"
        case .cylinder: return "Cylinder"
        case .cone: return "Cone"
        case .pyramid: return "Pyramid"
        case .toblerone: return "Toblerone"
        }
    }
}

enum TrainingObstacleAxisOrientation: String, Codable, CaseIterable, Identifiable, Sendable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        }
    }

    static func resolved(from raw: String?) -> TrainingObstacleAxisOrientation {
        guard let raw, let value = TrainingObstacleAxisOrientation(rawValue: raw) else { return .vertical }
        return value
    }
}

// MARK: - Protocol & concrete parameters

protocol TrainingEnvironmentObstacle: Sendable {
    static var kind: TrainingEnvironmentObstacleKind { get }
    /// Axis-aligned extents (m) for vertical pose, yaw 0°, before world rotation.
    func verticalExtentsM() -> (dx: Double, dy: Double, dz: Double)
}

struct TrainingObstacleCube: TrainingEnvironmentObstacle, Codable, Equatable {
    static let kind: TrainingEnvironmentObstacleKind = .cube
    var edgeM: Double

    func verticalExtentsM() -> (dx: Double, dy: Double, dz: Double) {
        let e = max(edgeM, 0.01)
        return (e, e, e)
    }
}

struct TrainingObstacleCuboid: TrainingEnvironmentObstacle, Codable, Equatable {
    static let kind: TrainingEnvironmentObstacleKind = .cuboid
    var lengthM: Double
    var widthM: Double
    var heightM: Double

    func verticalExtentsM() -> (dx: Double, dy: Double, dz: Double) {
        (
            max(lengthM, 0.01),
            max(widthM, 0.01),
            max(heightM, 0.01)
        )
    }
}

struct TrainingObstacleCylinder: TrainingEnvironmentObstacle, Codable, Equatable {
    static let kind: TrainingEnvironmentObstacleKind = .cylinder
    var radiusM: Double
    var heightM: Double

    func verticalExtentsM() -> (dx: Double, dy: Double, dz: Double) {
        let r = max(radiusM, 0.01)
        let h = max(heightM, 0.01)
        return (r * 2, r * 2, h)
    }
}

struct TrainingObstacleCone: TrainingEnvironmentObstacle, Codable, Equatable {
    static let kind: TrainingEnvironmentObstacleKind = .cone
    var radiusM: Double
    var heightM: Double

    func verticalExtentsM() -> (dx: Double, dy: Double, dz: Double) {
        let r = max(radiusM, 0.01)
        let h = max(heightM, 0.01)
        return (r * 2, r * 2, h)
    }
}

struct TrainingObstaclePyramid: TrainingEnvironmentObstacle, Codable, Equatable {
    static let kind: TrainingEnvironmentObstacleKind = .pyramid
    var baseWidthM: Double
    var baseDepthM: Double
    var heightM: Double

    func verticalExtentsM() -> (dx: Double, dy: Double, dz: Double) {
        (
            max(baseWidthM, 0.01),
            max(baseDepthM, 0.01),
            max(heightM, 0.01)
        )
    }
}

struct TrainingObstacleToblerone: TrainingEnvironmentObstacle, Codable, Equatable {
    static let kind: TrainingEnvironmentObstacleKind = .toblerone
    /// Equilateral-triangle cross-section width (m).
    var widthM: Double
    /// Prism length along the triangle edge direction when vertical (m).
    var lengthM: Double

    func verticalExtentsM() -> (dx: Double, dy: Double, dz: Double) {
        let w = max(widthM, 0.01)
        let l = max(lengthM, 0.01)
        let triHeight = w * sqrt(3) / 2
        return (w, triHeight, l)
    }
}

// MARK: - Instance record

struct TrainingEnvironmentObstacleRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: TrainingEnvironmentObstacleKind
    var centerXM: Double
    var centerYM: Double
    var centerZM: Double
    var yawDeg: Double
    var usesAutoZ: Bool
    var axisOrientation: TrainingObstacleAxisOrientation
    var cube: TrainingObstacleCube?
    var cuboid: TrainingObstacleCuboid?
    var cylinder: TrainingObstacleCylinder?
    var cone: TrainingObstacleCone?
    var pyramid: TrainingObstaclePyramid?
    var toblerone: TrainingObstacleToblerone?

    static let maxCount = 100

    static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    static func defaults(for kind: TrainingEnvironmentObstacleKind) -> TrainingEnvironmentObstacleRecord {
        var record = TrainingEnvironmentObstacleRecord(
            id: newID(),
            kind: kind,
            centerXM: 0,
            centerYM: 0,
            centerZM: 0,
            yawDeg: 0,
            usesAutoZ: true,
            axisOrientation: .vertical
        )
        record.applyDefaultParameters()
        return record
    }

    mutating func applyDefaultParameters() {
        cube = nil
        cuboid = nil
        cylinder = nil
        cone = nil
        pyramid = nil
        toblerone = nil
        switch kind {
        case .cube:
            cube = TrainingObstacleCube(edgeM: 2)
        case .cuboid:
            cuboid = TrainingObstacleCuboid(lengthM: 3, widthM: 2, heightM: 1.5)
        case .cylinder:
            cylinder = TrainingObstacleCylinder(radiusM: 1, heightM: 3)
        case .cone:
            cone = TrainingObstacleCone(radiusM: 1.5, heightM: 3)
        case .pyramid:
            pyramid = TrainingObstaclePyramid(baseWidthM: 3, baseDepthM: 3, heightM: 2.5)
        case .toblerone:
            toblerone = TrainingObstacleToblerone(widthM: 3, lengthM: 4)
        }
    }

    /// Ensures kind-specific parameter storage exists (for form edits).
    mutating func ensureParametersForKind() {
        if cube != nil || cuboid != nil || cylinder != nil || cone != nil || pyramid != nil || toblerone != nil {
            return
        }
        applyDefaultParameters()
    }

    mutating func setEdgeM(_ value: Double) {
        ensureParametersForKind()
        var params = cube ?? TrainingObstacleCube(edgeM: 2)
        params.edgeM = value
        cube = params
    }

    mutating func setCuboidDimensions(lengthM: Double? = nil, widthM: Double? = nil, heightM: Double? = nil) {
        ensureParametersForKind()
        var params = cuboid ?? TrainingObstacleCuboid(lengthM: 3, widthM: 2, heightM: 1.5)
        if let lengthM { params.lengthM = lengthM }
        if let widthM { params.widthM = widthM }
        if let heightM { params.heightM = heightM }
        cuboid = params
    }

    mutating func setCylinderDimensions(radiusM: Double? = nil, heightM: Double? = nil) {
        ensureParametersForKind()
        var params = cylinder ?? TrainingObstacleCylinder(radiusM: 1, heightM: 3)
        if let radiusM { params.radiusM = radiusM }
        if let heightM { params.heightM = heightM }
        cylinder = params
    }

    mutating func setConeDimensions(radiusM: Double? = nil, heightM: Double? = nil) {
        ensureParametersForKind()
        var params = cone ?? TrainingObstacleCone(radiusM: 1.5, heightM: 3)
        if let radiusM { params.radiusM = radiusM }
        if let heightM { params.heightM = heightM }
        cone = params
    }

    mutating func setPyramidDimensions(baseWidthM: Double? = nil, baseDepthM: Double? = nil, heightM: Double? = nil) {
        ensureParametersForKind()
        var params = pyramid ?? TrainingObstaclePyramid(baseWidthM: 3, baseDepthM: 3, heightM: 2.5)
        if let baseWidthM { params.baseWidthM = baseWidthM }
        if let baseDepthM { params.baseDepthM = baseDepthM }
        if let heightM { params.heightM = heightM }
        pyramid = params
    }

    mutating func setTobleroneDimensions(widthM: Double? = nil, lengthM: Double? = nil) {
        ensureParametersForKind()
        var params = toblerone ?? TrainingObstacleToblerone(widthM: 3, lengthM: 4)
        if let widthM { params.widthM = widthM }
        if let lengthM { params.lengthM = lengthM }
        toblerone = params
    }

    func verticalExtentsM() -> (dx: Double, dy: Double, dz: Double) {
        switch kind {
        case .cube:
            return (cube ?? TrainingObstacleCube(edgeM: 2)).verticalExtentsM()
        case .cuboid:
            return (cuboid ?? TrainingObstacleCuboid(lengthM: 2, widthM: 2, heightM: 2)).verticalExtentsM()
        case .cylinder:
            return (cylinder ?? TrainingObstacleCylinder(radiusM: 1, heightM: 2)).verticalExtentsM()
        case .cone:
            return (cone ?? TrainingObstacleCone(radiusM: 1, heightM: 2)).verticalExtentsM()
        case .pyramid:
            return (pyramid ?? TrainingObstaclePyramid(baseWidthM: 2, baseDepthM: 2, heightM: 2)).verticalExtentsM()
        case .toblerone:
            return (toblerone ?? TrainingObstacleToblerone(widthM: 2, lengthM: 2)).verticalExtentsM()
        }
    }

    /// Gazebo model name for this instance.
    var gazeboModelName: String {
        TrainingEnvironmentObstacleNaming.modelName(obstacleID: id)
    }
}

enum TrainingEnvironmentObstacleNaming {
    static let modelPrefix = "guardian_obstacle_"

    static func modelName(obstacleID: String) -> String {
        "\(modelPrefix)\(sanitizedIDSuffix(obstacleID))"
    }

    static func sanitizedIDSuffix(_ obstacleID: String) -> String {
        obstacleID
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: #"[^a-z0-9_]"#, with: "", options: .regularExpression)
    }

    /// True when a live Gazebo model name refers to this obstacle id.
    static func matchesModelName(_ gazeboModelName: String, obstacleID: String) -> Bool {
        let expected = Self.modelName(obstacleID: obstacleID)
        if gazeboModelName == expected { return true }
        guard gazeboModelName.hasPrefix(modelPrefix) else { return false }
        let suffix = String(gazeboModelName.dropFirst(modelPrefix.count))
        return suffix == sanitizedIDSuffix(obstacleID)
    }
}

// MARK: - Manifest bridge

enum WorldBuilderObstacleManifestSupport {
    static let dimensionMinM = 0.25
    static let dimensionMaxM = 80.0
    /// Obstacle foot (lowest point) height (m) relative to map-base top (z = 0).
    static let footZMinM = -500.0
    static let footZMaxM = 2000.0

    static func obstacles(from manifest: TrainingEnvironmentManifest) -> [TrainingEnvironmentObstacleRecord] {
        manifest.obstacles
    }

    /// Clamps dimensions, terrain Z, and floor position for one record (toolbar / placement buffer).
    static func normalizeRecord(
        _ record: inout TrainingEnvironmentObstacleRecord,
        floorHalfM: Double,
        sceneType: TrainingEnvironmentSceneType
    ) {
        normalizeDimensions(&record)
        if record.usesAutoZ {
            reclampAutoZ(&record, floorHalfM: floorHalfM, sceneType: sceneType)
        } else {
            clampFootZM(&record)
        }
        clampToFloor(&record, floorHalfM: floorHalfM)
    }

    static func footZM(for record: TrainingEnvironmentObstacleRecord) -> Double {
        record.centerZM + lowestPointOffsetZM(record: record)
    }

    static func setFootZM(_ footZM: Double, record: inout TrainingEnvironmentObstacleRecord) {
        let ext = orientedExtents(record: record)
        record.centerZM = footZM + ext.dz / 2
    }

    static func clampFootZM(_ record: inout TrainingEnvironmentObstacleRecord) {
        let clamped = min(footZMaxM, max(footZMinM, footZM(for: record)))
        setFootZM(clamped, record: &record)
    }

    static func apply(_ obstacles: [TrainingEnvironmentObstacleRecord], to manifest: inout TrainingEnvironmentManifest) {
        var clamped = Array(obstacles.prefix(TrainingEnvironmentObstacleRecord.maxCount))
        let floorHalfM = TrainingEnvironmentFloorSize.resolved(from: manifest.floorSize).floorSideM / 2
        let scene = TrainingEnvironmentSceneType.resolved(from: manifest.sceneType)
        for index in clamped.indices {
            normalizeDimensions(&clamped[index])
            if clamped[index].usesAutoZ {
                reclampAutoZ(&clamped[index], floorHalfM: floorHalfM, sceneType: scene)
            } else {
                clampFootZM(&clamped[index])
            }
            clampToFloor(&clamped[index], floorHalfM: floorHalfM)
        }
        manifest.obstacles = clamped
    }

    static func clampToFloor(_ record: inout TrainingEnvironmentObstacleRecord, floorHalfM: Double) {
        let yawRad = record.yawDeg * .pi / 180
        let (hx, hy) = footprintHalfExtents(record: record, yawRad: yawRad)
        let maxX = max(0, floorHalfM - hx)
        let maxY = max(0, floorHalfM - hy)
        record.centerXM = min(maxX, max(-maxX, record.centerXM))
        record.centerYM = min(maxY, max(-maxY, record.centerYM))
    }

    static func footprintHalfExtents(
        record: TrainingEnvironmentObstacleRecord,
        yawRad: Double
    ) -> (hx: Double, hy: Double) {
        let ext = orientedExtents(record: record)
        let c = abs(cos(yawRad))
        let s = abs(sin(yawRad))
        let hx = (ext.dx / 2) * c + (ext.dy / 2) * s
        let hy = (ext.dx / 2) * s + (ext.dy / 2) * c
        return (hx, hy)
    }

    /// Bottom-center pose for Harmonic entity factory (`zM` = lowest point).
    static func entityFactoryPose(for record: TrainingEnvironmentObstacleRecord) -> TrainingEnvironmentPose {
        let ext = orientedExtents(record: record)
        return TrainingEnvironmentPose(
            xM: record.centerXM,
            yM: record.centerYM,
            zM: record.centerZM - ext.dz / 2,
            yawDeg: record.yawDeg
        )
    }

    static func orientedExtents(record: TrainingEnvironmentObstacleRecord) -> (dx: Double, dy: Double, dz: Double) {
        var ext = record.verticalExtentsM()
        if record.axisOrientation == .horizontal {
            switch record.kind {
            case .cylinder, .toblerone:
                ext = (ext.dz, ext.dy, ext.dx)
            default:
                break
            }
        }
        return ext
    }

    static func lowestPointOffsetZM(record: TrainingEnvironmentObstacleRecord) -> Double {
        -orientedExtents(record: record).dz / 2
    }

    static func supportSurfaceZM(
        centerXM: Double,
        centerYM: Double,
        record: TrainingEnvironmentObstacleRecord,
        sceneType: TrainingEnvironmentSceneType
    ) -> Double {
        let yawRad = record.yawDeg * .pi / 180
        let (hx, hy) = footprintHalfExtents(record: record, yawRad: yawRad)
        let samples: [(Double, Double)] = [
            (centerXM, centerYM),
            (centerXM + hx, centerYM + hy),
            (centerXM + hx, centerYM - hy),
            (centerXM - hx, centerYM + hy),
            (centerXM - hx, centerYM - hy),
        ]
        return samples.map { TrainingEnvironmentTerrainHeightQuery.heightM(xM: $0.0, yM: $0.1, sceneType: sceneType) }
            .min() ?? 0
    }

    static func centerZMForAutoFlush(
        record: TrainingEnvironmentObstacleRecord,
        sceneType: TrainingEnvironmentSceneType
    ) -> Double {
        let support = supportSurfaceZM(
            centerXM: record.centerXM,
            centerYM: record.centerYM,
            record: record,
            sceneType: sceneType
        )
        return support - lowestPointOffsetZM(record: record)
    }

    static func reclampAutoZ(
        _ record: inout TrainingEnvironmentObstacleRecord,
        floorHalfM: Double,
        sceneType: TrainingEnvironmentSceneType
    ) {
        if record.usesAutoZ {
            record.centerZM = centerZMForAutoFlush(record: record, sceneType: sceneType)
        }
        clampToFloor(&record, floorHalfM: floorHalfM)
    }

    static func normalizeDimensions(_ record: inout TrainingEnvironmentObstacleRecord) {
        func clamp(_ value: Double) -> Double {
            min(dimensionMaxM, max(dimensionMinM, value))
        }
        switch record.kind {
        case .cube:
            if var cube = record.cube {
                cube.edgeM = clamp(cube.edgeM)
                record.cube = cube
            }
        case .cuboid:
            if var cuboid = record.cuboid {
                cuboid.lengthM = clamp(cuboid.lengthM)
                cuboid.widthM = clamp(cuboid.widthM)
                cuboid.heightM = clamp(cuboid.heightM)
                record.cuboid = cuboid
            }
        case .cylinder:
            if var cylinder = record.cylinder {
                cylinder.radiusM = clamp(cylinder.radiusM)
                cylinder.heightM = clamp(cylinder.heightM)
                record.cylinder = cylinder
            }
        case .cone:
            if var cone = record.cone {
                cone.radiusM = clamp(cone.radiusM)
                cone.heightM = clamp(cone.heightM)
                record.cone = cone
            }
        case .pyramid:
            if var pyramid = record.pyramid {
                pyramid.baseWidthM = clamp(pyramid.baseWidthM)
                pyramid.baseDepthM = clamp(pyramid.baseDepthM)
                pyramid.heightM = clamp(pyramid.heightM)
                record.pyramid = pyramid
            }
        case .toblerone:
            if var toblerone = record.toblerone {
                toblerone.widthM = clamp(toblerone.widthM)
                toblerone.lengthM = clamp(toblerone.lengthM)
                record.toblerone = toblerone
            }
        }
    }
}

// MARK: - Map-base bounds (mirrors zone editor snap / failed semantics)

enum WorldBuilderObstacleBoundsCheck {
    /// Footprint corners in ENU (metres) for bounds checks.
    static func edgePoints(for record: TrainingEnvironmentObstacleRecord) -> [(x: Double, y: Double)] {
        let yawRad = record.yawDeg * .pi / 180
        let (hx, hy) = WorldBuilderObstacleManifestSupport.footprintHalfExtents(
            record: record,
            yawRad: yawRad
        )
        let cx = record.centerXM
        let cy = record.centerYM
        let cos = cos(yawRad)
        let sin = sin(yawRad)
        let corners = [(hx, hy), (hx, -hy), (-hx, -hy), (-hx, hy)]
        return corners.map { corner in
            (
                cx + corner.0 * cos - corner.1 * sin,
                cy + corner.0 * sin + corner.1 * cos
            )
        }
    }

    static func fitsOnFloor(_ record: TrainingEnvironmentObstacleRecord, floor: WorldBuilderZoneFloorRect) -> Bool {
        if !floor.contains(x: record.centerXM, y: record.centerYM) {
            return false
        }
        for point in edgePoints(for: record) {
            if !floor.contains(x: point.x, y: point.y) {
                return false
            }
        }
        return true
    }

    /// Translates the obstacle so its footprint fits inside the map-base square (zone-style snap).
    /// - Returns: `false` when the footprint cannot fit on the floor at all.
    @discardableResult
    static func snapObstacleToFloor(
        _ record: inout TrainingEnvironmentObstacleRecord,
        floor: WorldBuilderZoneFloorRect
    ) -> Bool {
        if fitsOnFloor(record, floor: floor) {
            return true
        }

        var points = [(x: record.centerXM, y: record.centerYM)]
        points.append(contentsOf: edgePoints(for: record).map { (x: $0.x, y: $0.y) })

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
            record.centerXM += min(max(0, dxMin), dxMax)
        }
        if dyMin <= dyMax {
            record.centerYM += min(max(0, dyMin), dyMax)
        }

        return fitsOnFloor(record, floor: floor)
    }

    @discardableResult
    static func snapObstaclesToFloor(
        _ obstacles: inout [TrainingEnvironmentObstacleRecord],
        floor: WorldBuilderZoneFloorRect
    ) -> Bool {
        obstacles.indices.allSatisfy { index in
            snapObstacleToFloor(&obstacles[index], floor: floor)
        }
    }
}
