import Foundation

enum MissionType: String, Codable, CaseIterable, Identifiable {
    case mobile
    case staticType = "static"

    var id: String { rawValue }
}

struct MissionSpace: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var roleType: String
    var positionHint: String

    init(id: UUID = UUID(), name: String, roleType: String, positionHint: String) {
        self.id = id
        self.name = name
        self.roleType = roleType
        self.positionHint = positionHint
    }
}

struct RouteCoordinate: Codable, Equatable {
    var lat: Double
    var lon: Double

    init(lat: Double = 0, lon: Double = 0) {
        self.lat = lat
        self.lon = lon
    }
}

struct RouteAltitude: Codable, Equatable {
    var value: Double
    var unit: String
    var reference: String

    init(value: Double = 0, unit: String = "m", reference: String = "AGL") {
        self.value = value
        self.unit = unit
        self.reference = reference
    }
}

struct RouteHome: Codable, Equatable {
    var coord: RouteCoordinate
    var altitude: RouteAltitude
    var heading: Double
    var radiusMeters: Double
    var dockAllowed: Bool
    var fallbackOnly: Bool

    init(
        coord: RouteCoordinate = RouteCoordinate(),
        altitude: RouteAltitude = RouteAltitude(),
        heading: Double = 0,
        radiusMeters: Double = 3,
        dockAllowed: Bool = true,
        fallbackOnly: Bool = false
    ) {
        self.coord = coord
        self.altitude = altitude
        self.heading = heading
        self.radiusMeters = radiusMeters
        self.dockAllowed = dockAllowed
        self.fallbackOnly = fallbackOnly
    }
}

struct RouteTransition: Codable, Equatable {
    var mode: String
    var targetSpeed: Double

    init(mode: String = "straight", targetSpeed: Double = 5) {
        self.mode = mode
        self.targetSpeed = targetSpeed
    }
}

struct RouteWaypoint: Identifiable, Codable, Equatable {
    let id: UUID
    var coord: RouteCoordinate
    var altitude: RouteAltitude
    var heading: Double
    var delaySec: Double
    var action: String
    var transition: RouteTransition

    init(
        id: UUID = UUID(),
        coord: RouteCoordinate = RouteCoordinate(),
        altitude: RouteAltitude = RouteAltitude(),
        heading: Double = 0,
        delaySec: Double = 0,
        action: String = "",
        transition: RouteTransition = RouteTransition()
    ) {
        self.id = id
        self.coord = coord
        self.altitude = altitude
        self.heading = heading
        self.delaySec = delaySec
        self.action = action
        self.transition = transition
    }
}

struct RoutePath: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var enabled: Bool
    var waypoints: [RouteWaypoint]
    var loopMode: String
    var repeatCount: Int
    var scheduleRefs: [String]
    var spaceBindings: [UUID]

    init(
        id: UUID = UUID(),
        name: String = "Path 1",
        enabled: Bool = true,
        waypoints: [RouteWaypoint] = [],
        loopMode: String = "none",
        repeatCount: Int = 1,
        scheduleRefs: [String] = [],
        spaceBindings: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.waypoints = waypoints
        self.loopMode = loopMode
        self.repeatCount = repeatCount
        self.scheduleRefs = scheduleRefs
        self.spaceBindings = spaceBindings
    }
}

struct RouteRules: Codable, Equatable {
    var defaultSpeed: Double
    var defaultHeadingHold: Bool

    init(defaultSpeed: Double = 5, defaultHeadingHold: Bool = true) {
        self.defaultSpeed = defaultSpeed
        self.defaultHeadingHold = defaultHeadingHold
    }
}

struct RouteMacro: Codable, Equatable {
    var version: Int
    var home: RouteHome?
    var paths: [RoutePath]
    var rules: RouteRules

    init(
        version: Int = 1,
        home: RouteHome? = nil,
        paths: [RoutePath] = [],
        rules: RouteRules = RouteRules()
    ) {
        self.version = version
        self.home = home
        self.paths = paths
        self.rules = rules
    }
}

struct Mission: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var type: MissionType
    var count: Int
    var duration: Int
    var schedule: [String]
    var deviceIDs: [String]
    var spaces: [MissionSpace]
    var routeMacro: RouteMacro
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        type: MissionType,
        count: Int = 0,
        duration: Int = 0,
        schedule: [String] = [],
        deviceIDs: [String] = [],
        spaces: [MissionSpace] = [],
        routeMacro: RouteMacro = RouteMacro(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.count = count
        self.duration = duration
        self.schedule = schedule
        self.deviceIDs = deviceIDs
        self.spaces = spaces
        self.routeMacro = routeMacro
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, type, count, duration, schedule, deviceIDs, spaces, routeMacro, createdAt
        case mapRegion, routePlan // legacy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        type = try container.decodeIfPresent(MissionType.self, forKey: .type) ?? .mobile
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        schedule = try container.decodeIfPresent([String].self, forKey: .schedule) ?? []
        deviceIDs = try container.decodeIfPresent([String].self, forKey: .deviceIDs) ?? []
        spaces = try container.decodeIfPresent([MissionSpace].self, forKey: .spaces) ?? []
        if let decodedRouteMacro = try container.decodeIfPresent(RouteMacro.self, forKey: .routeMacro) {
            routeMacro = decodedRouteMacro
        } else {
            let legacyMapRegion = try container.decodeIfPresent(String.self, forKey: .mapRegion) ?? ""
            let legacyRoutePlan = try container.decodeIfPresent(String.self, forKey: .routePlan) ?? ""
            routeMacro = RouteMacro(
                home: RouteHome(),
                paths: legacyRoutePlan.isEmpty ? [] : [RoutePath(name: "Imported Path")],
                rules: RouteRules()
            )
            if !legacyMapRegion.isEmpty {
                routeMacro.paths = [RoutePath(name: legacyMapRegion)]
            }
        }
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(type, forKey: .type)
        try container.encode(count, forKey: .count)
        try container.encode(duration, forKey: .duration)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(deviceIDs, forKey: .deviceIDs)
        try container.encode(spaces, forKey: .spaces)
        try container.encode(routeMacro, forKey: .routeMacro)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
