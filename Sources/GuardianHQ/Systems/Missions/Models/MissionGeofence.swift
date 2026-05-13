import Foundation

/// Stay-in vs no-go semantics aligned with MAVSDK / MAVLink fence items.
enum MissionGeofenceBoundaryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case inclusion
    case exclusion

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .inclusion: return "Inclusion"
        case .exclusion: return "Exclusion"
        }
    }
}

enum MissionGeofenceShapeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case polygon
    case circle

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .polygon: return "Polygon"
        case .circle: return "Circle"
        }
    }
}

/// One geofence region on a mission template — either **mission-wide** (``Mission/missionGeofences``) or scoped to a **task** (``MissionTask/geofences``).
struct MissionGeofence: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var boundary: MissionGeofenceBoundaryKind
    var shape: MissionGeofenceShapeKind
    /// WGS84 vertices for ``shape`` ``polygon`` (minimum **3** non-collinear points for a visible map ring).
    var polygonVertices: [RouteCoordinate]
    /// Center for ``shape`` ``circle``.
    var circleCenter: RouteCoordinate
    /// Radius in **meters** for ``shape`` ``circle`` (minimum **1**).
    var circleRadiusMeters: Double

    init(
        id: UUID = UUID(),
        name: String,
        boundary: MissionGeofenceBoundaryKind = .inclusion,
        shape: MissionGeofenceShapeKind,
        polygonVertices: [RouteCoordinate] = [],
        circleCenter: RouteCoordinate = RouteCoordinate(),
        circleRadiusMeters: Double = 150
    ) {
        self.id = id
        self.name = name
        self.boundary = boundary
        self.shape = shape
        self.polygonVertices = polygonVertices
        self.circleCenter = circleCenter
        self.circleRadiusMeters = max(1, circleRadiusMeters)
    }

    /// Template row for a new **polygon** near ``center`` (~220 m triangle).
    static func newPolygon(name: String, around center: RouteCoordinate) -> MissionGeofence {
        let d = 0.002
        let verts: [RouteCoordinate] = [
            RouteCoordinate(lat: center.lat + d, lon: center.lon - d),
            RouteCoordinate(lat: center.lat - d, lon: center.lon - d),
            RouteCoordinate(lat: center.lat, lon: center.lon + d),
        ]
        return MissionGeofence(
            name: name,
            boundary: .inclusion,
            shape: .polygon,
            polygonVertices: verts,
            circleCenter: center,
            circleRadiusMeters: 150
        )
    }

    static func newCircle(name: String, center: RouteCoordinate) -> MissionGeofence {
        MissionGeofence(
            name: name,
            boundary: .inclusion,
            shape: .circle,
            polygonVertices: [],
            circleCenter: center,
            circleRadiusMeters: 150
        )
    }

    func duplicatedForClonedMission() -> MissionGeofence {
        MissionGeofence(
            id: UUID(),
            name: name,
            boundary: boundary,
            shape: shape,
            polygonVertices: polygonVertices,
            circleCenter: circleCenter,
            circleRadiusMeters: circleRadiusMeters
        )
    }
}
