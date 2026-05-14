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

/// JSON `altitude_units` — v1 supports meters only.
enum MissionGeofenceAltitudeUnits: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case meters = "m"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .meters: return "Meters (m)"
        }
    }
}

/// JSON `altitude_reference` for the fence altitude band.
enum MissionGeofenceAltitudeReference: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case relativeHome = "relative_home"
    case agl = "AGL"
    case msl = "MSL"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .relativeHome: return "Relative to home"
        case .agl: return "Above ground level (AGL)"
        case .msl: return "Mean sea level (MSL)"
        }
    }
}

/// One geofence region on a mission template — either **mission-wide** (``Mission/missionGeofences``) or scoped to a **task** (``MissionTask/geofences``).
struct MissionGeofence: Identifiable, Equatable, Sendable {
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
    /// JSON `min_altitude` — lower bound of the allowed altitude band (meters).
    var minAltitudeMeters: Double
    /// JSON `max_altitude` — upper bound of the allowed altitude band (meters).
    var maxAltitudeMeters: Double
    var altitudeUnits: MissionGeofenceAltitudeUnits
    var altitudeReference: MissionGeofenceAltitudeReference

    init(
        id: UUID = UUID(),
        name: String,
        boundary: MissionGeofenceBoundaryKind = .inclusion,
        shape: MissionGeofenceShapeKind,
        polygonVertices: [RouteCoordinate] = [],
        circleCenter: RouteCoordinate = RouteCoordinate(),
        circleRadiusMeters: Double = 150,
        minAltitudeMeters: Double = 0,
        maxAltitudeMeters: Double = 120,
        altitudeUnits: MissionGeofenceAltitudeUnits = .meters,
        altitudeReference: MissionGeofenceAltitudeReference = .relativeHome
    ) {
        self.id = id
        self.name = name
        self.boundary = boundary
        self.shape = shape
        self.polygonVertices = polygonVertices
        self.circleCenter = circleCenter
        self.circleRadiusMeters = max(1, circleRadiusMeters)
        self.minAltitudeMeters = minAltitudeMeters
        self.maxAltitudeMeters = maxAltitudeMeters
        self.altitudeUnits = altitudeUnits
        self.altitudeReference = altitudeReference
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
            circleRadiusMeters: circleRadiusMeters,
            minAltitudeMeters: minAltitudeMeters,
            maxAltitudeMeters: maxAltitudeMeters,
            altitudeUnits: altitudeUnits,
            altitudeReference: altitudeReference
        )
    }
}

extension MissionGeofence: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case boundary
        case shape
        case polygonVertices
        case circleCenter
        case circleRadiusMeters
        case minAltitudeMeters = "min_altitude"
        case maxAltitudeMeters = "max_altitude"
        case altitudeUnits = "altitude_units"
        case altitudeReference = "altitude_reference"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        boundary = try c.decode(MissionGeofenceBoundaryKind.self, forKey: .boundary)
        shape = try c.decode(MissionGeofenceShapeKind.self, forKey: .shape)
        polygonVertices = try c.decodeIfPresent([RouteCoordinate].self, forKey: .polygonVertices) ?? []
        circleCenter = try c.decodeIfPresent(RouteCoordinate.self, forKey: .circleCenter) ?? RouteCoordinate()
        circleRadiusMeters = max(1, try c.decodeIfPresent(Double.self, forKey: .circleRadiusMeters) ?? 150)
        minAltitudeMeters = try c.decodeIfPresent(Double.self, forKey: .minAltitudeMeters) ?? 0
        maxAltitudeMeters = try c.decodeIfPresent(Double.self, forKey: .maxAltitudeMeters) ?? 120
        altitudeUnits = try c.decodeIfPresent(MissionGeofenceAltitudeUnits.self, forKey: .altitudeUnits) ?? .meters
        altitudeReference = try c.decodeIfPresent(MissionGeofenceAltitudeReference.self, forKey: .altitudeReference) ?? .relativeHome
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(boundary, forKey: .boundary)
        try c.encode(shape, forKey: .shape)
        try c.encode(polygonVertices, forKey: .polygonVertices)
        try c.encode(circleCenter, forKey: .circleCenter)
        try c.encode(circleRadiusMeters, forKey: .circleRadiusMeters)
        try c.encode(minAltitudeMeters, forKey: .minAltitudeMeters)
        try c.encode(maxAltitudeMeters, forKey: .maxAltitudeMeters)
        try c.encode(altitudeUnits, forKey: .altitudeUnits)
        try c.encode(altitudeReference, forKey: .altitudeReference)
    }
}
