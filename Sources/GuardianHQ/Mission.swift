import Foundation

enum MissionType: String, Codable, CaseIterable, Identifiable {
    case mobile
    case staticType = "static"

    var id: String { rawValue }
}

/// A placeholder device slot on the mission roster (assign real hardware later).
struct RosterDevice: Identifiable, Codable, Equatable {
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

enum AltitudeUnit: String, Codable, CaseIterable, Identifiable {
    case m
    case km

    var id: String { rawValue }
}

enum AltitudeReference: String, Codable, CaseIterable, Identifiable {
    case agl = "AGL"
    case msl = "MSL"
    case asl = "ASL"

    var id: String { rawValue }
}

struct RouteAltitude: Codable, Equatable {
    var value: Double
    var unit: AltitudeUnit
    var reference: AltitudeReference

    init(value: Double = 0, unit: AltitudeUnit = .m, reference: AltitudeReference = .agl) {
        self.value = value
        self.unit = unit
        self.reference = reference
    }

    enum CodingKeys: String, CodingKey {
        case value, unit, reference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeIfPresent(Double.self, forKey: .value) ?? 0

        if let decodedUnit = try? container.decode(AltitudeUnit.self, forKey: .unit) {
            unit = decodedUnit
        } else {
            let rawUnit = (try? container.decode(String.self, forKey: .unit))?.lowercased()
            unit = AltitudeUnit(rawValue: rawUnit ?? "") ?? .m
        }

        if let decodedReference = try? container.decode(AltitudeReference.self, forKey: .reference) {
            reference = decodedReference
        } else {
            let rawReference = (try? container.decode(String.self, forKey: .reference))?.uppercased()
            reference = AltitudeReference(rawValue: rawReference ?? "") ?? .agl
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(unit, forKey: .unit)
        try container.encode(reference, forKey: .reference)
    }
}

enum TransitionMode: String, Codable, CaseIterable, Identifiable {
    case straight
    case zigZag = "zig-zag"

    var id: String { rawValue }
}

enum SpeedUnit: String, Codable, CaseIterable, Identifiable {
    case metersPerSecond = "m/s"
    case kilometersPerHour = "km/h"

    var id: String { rawValue }
}

enum DelayUnit: String, Codable, CaseIterable, Identifiable {
    case secs
    case mins
    case hrs

    var id: String { rawValue }
}

enum HeadingPreset: String, Codable, CaseIterable, Identifiable {
    case followPath
    case perimeterOutward
    case perimeterInward
    case north
    case east
    case south
    case west

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        switch raw {
        case "auto":
            self = .followPath
        case "followPath":
            self = .followPath
        case "perimeterOutward":
            self = .perimeterOutward
        case "perimeterInward":
            self = .perimeterInward
        case "north":
            self = .north
        case "east":
            self = .east
        case "south":
            self = .south
        case "west":
            self = .west
        default:
            self = .followPath
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum CameraMode: String, Codable, CaseIterable, Identifiable {
    case followHeading
    case perimeterOutward
    case perimeterInward
    case manualBearing

    var id: String { rawValue }
}

enum TransitionCameraMode: String, Codable, CaseIterable, Identifiable {
    case holdCurrent
    case faceNextWaypoint
    case perimeterOutward
    case perimeterInward
    case manualBearing

    var id: String { rawValue }
}

struct RouteCamera: Codable, Equatable {
    var mode: CameraMode
    var bearing: Double
    var fovDeg: Double

    init(mode: CameraMode = .followHeading, bearing: Double = 0, fovDeg: Double = 60) {
        self.mode = mode
        self.bearing = bearing
        self.fovDeg = fovDeg
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
    var mode: TransitionMode
    var targetSpeed: Double
    var speedUnit: SpeedUnit
    var cameraMode: TransitionCameraMode
    var cameraBearing: Double

    init(
        mode: TransitionMode = .straight,
        targetSpeed: Double = 5,
        speedUnit: SpeedUnit = .metersPerSecond,
        cameraMode: TransitionCameraMode = .holdCurrent,
        cameraBearing: Double = 0
    ) {
        self.mode = mode
        self.targetSpeed = targetSpeed
        self.speedUnit = speedUnit
        self.cameraMode = cameraMode
        self.cameraBearing = cameraBearing
    }

    enum CodingKeys: String, CodingKey {
        case mode, targetSpeed, speedUnit, cameraMode, cameraBearing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let decodedMode = try? container.decode(TransitionMode.self, forKey: .mode) {
            mode = decodedMode
        } else {
            let rawMode = (try? container.decode(String.self, forKey: .mode))?.lowercased()
            mode = TransitionMode(rawValue: rawMode ?? "") ?? .straight
        }

        targetSpeed = try container.decodeIfPresent(Double.self, forKey: .targetSpeed) ?? 5
        speedUnit = (try? container.decode(SpeedUnit.self, forKey: .speedUnit)) ?? .metersPerSecond
        if let decodedCameraMode = try? container.decode(TransitionCameraMode.self, forKey: .cameraMode) {
            cameraMode = decodedCameraMode
        } else {
            let rawCameraMode = (try? container.decode(String.self, forKey: .cameraMode)) ?? ""
            cameraMode = TransitionCameraMode(rawValue: rawCameraMode) ?? .holdCurrent
        }
        cameraBearing = try container.decodeIfPresent(Double.self, forKey: .cameraBearing) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(targetSpeed, forKey: .targetSpeed)
        try container.encode(speedUnit, forKey: .speedUnit)
        try container.encode(cameraMode, forKey: .cameraMode)
        try container.encode(cameraBearing, forKey: .cameraBearing)
    }
}

struct RouteWaypoint: Identifiable, Codable, Equatable {
    let id: UUID
    var coord: RouteCoordinate
    var altitude: RouteAltitude
    var heading: Double
    var headingPreset: HeadingPreset?
    var delaySec: Double
    var delayUnit: DelayUnit
    var action: String
    var camera: RouteCamera
    var transition: RouteTransition

    init(
        id: UUID = UUID(),
        coord: RouteCoordinate = RouteCoordinate(),
        altitude: RouteAltitude = RouteAltitude(),
        heading: Double = 0,
        headingPreset: HeadingPreset? = nil,
        delaySec: Double = 0,
        delayUnit: DelayUnit = .secs,
        action: String = "none",
        camera: RouteCamera = RouteCamera(),
        transition: RouteTransition = RouteTransition()
    ) {
        self.id = id
        self.coord = coord
        self.altitude = altitude
        self.heading = heading
        self.headingPreset = headingPreset
        self.delaySec = delaySec
        self.delayUnit = delayUnit
        self.action = action
        self.camera = camera
        self.transition = transition
    }

    enum CodingKeys: String, CodingKey {
        case id, coord, altitude, heading, headingPreset, delaySec, delayUnit, action, camera, transition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        coord = try container.decodeIfPresent(RouteCoordinate.self, forKey: .coord) ?? RouteCoordinate()
        altitude = try container.decodeIfPresent(RouteAltitude.self, forKey: .altitude) ?? RouteAltitude()
        heading = try container.decodeIfPresent(Double.self, forKey: .heading) ?? 0
        headingPreset = try container.decodeIfPresent(HeadingPreset.self, forKey: .headingPreset)
        delaySec = try container.decodeIfPresent(Double.self, forKey: .delaySec) ?? 0
        if let decodedDelay = try? container.decode(DelayUnit.self, forKey: .delayUnit) {
            delayUnit = decodedDelay
        } else {
            let rawDelay = (try? container.decode(String.self, forKey: .delayUnit))?.lowercased()
            switch rawDelay {
            case "s", "sec", "secs", "second", "seconds":
                delayUnit = .secs
            case "m", "min", "mins", "minute", "minutes":
                delayUnit = .mins
            case "h", "hr", "hrs", "hour", "hours":
                delayUnit = .hrs
            default:
                delayUnit = .secs
            }
        }
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? "none"
        camera = try container.decodeIfPresent(RouteCamera.self, forKey: .camera) ?? RouteCamera()
        transition = try container.decodeIfPresent(RouteTransition.self, forKey: .transition) ?? RouteTransition()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(coord, forKey: .coord)
        try container.encode(altitude, forKey: .altitude)
        try container.encode(heading, forKey: .heading)
        try container.encodeIfPresent(headingPreset, forKey: .headingPreset)
        try container.encode(delaySec, forKey: .delaySec)
        try container.encode(delayUnit, forKey: .delayUnit)
        try container.encode(action, forKey: .action)
        try container.encode(camera, forKey: .camera)
        try container.encode(transition, forKey: .transition)
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
    /// Device slots assigned to this path (IDs into `Mission.rosterDevices`).
    var rosterDeviceIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, waypoints, loopMode, repeatCount, scheduleRefs
        case rosterDeviceIds = "spaceBindings"
    }

    init(
        id: UUID = UUID(),
        name: String = "Path 1",
        enabled: Bool = true,
        waypoints: [RouteWaypoint] = [],
        loopMode: String = "none",
        repeatCount: Int = 1,
        scheduleRefs: [String] = [],
        rosterDeviceIds: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.waypoints = waypoints
        self.loopMode = loopMode
        self.repeatCount = repeatCount
        self.scheduleRefs = scheduleRefs
        self.rosterDeviceIds = rosterDeviceIds
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
    var deviceIDs: [String]
    var rosterDevices: [RosterDevice]
    var routeMacro: RouteMacro
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        type: MissionType,
        count: Int = 0,
        duration: Int = 0,
        deviceIDs: [String] = [],
        rosterDevices: [RosterDevice] = [],
        routeMacro: RouteMacro = RouteMacro(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.count = count
        self.duration = duration
        self.deviceIDs = deviceIDs
        self.rosterDevices = rosterDevices
        self.routeMacro = routeMacro
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, type, count, duration, schedule, deviceIDs, routeMacro, createdAt
        case rosterDevices = "spaces"
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
        _ = try? container.decodeIfPresent([String].self, forKey: .schedule)
        deviceIDs = try container.decodeIfPresent([String].self, forKey: .deviceIDs) ?? []
        rosterDevices = try container.decodeIfPresent([RosterDevice].self, forKey: .rosterDevices) ?? []
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
        try container.encode(deviceIDs, forKey: .deviceIDs)
        try container.encode(rosterDevices, forKey: .rosterDevices)
        try container.encode(routeMacro, forKey: .routeMacro)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
