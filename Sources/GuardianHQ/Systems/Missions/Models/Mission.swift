import Foundation

enum MissionType: String, Codable, CaseIterable, Identifiable {
    case mobile
    case staticType = "static"

    var id: String { rawValue }
}

/// Mission behavioral / persona role for MRE and Paladin (e.g. scout); extend over time.
enum RosterRole: String, Codable, CaseIterable, Identifiable {
    case none

    var id: String { rawValue }
}

/// Primary / wingman / reserve for a roster slot (mission template). Hardware binds in Mission Control.
enum MissionRosterSlotRole: String, Codable, CaseIterable, Identifiable {
    case primary
    case wingman
    case reserve

    var id: String { rawValue }
}

/// A placeholder device slot on the mission roster (assign real hardware later).
struct RosterDevice: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// Behavioral / persona role for MRE and Paladin (scout, etc.); ``none`` until expanded.
    var role: RosterRole
    var slot: MissionRosterSlotRole
    var vehicleClass: FleetVehicleType
    /// When ``slot`` is ``wingman`` or ``reserve``, optional primary on this task to follow; if nil, MRE may infer.
    var leaderRosterDeviceId: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        role: RosterRole = .none,
        slot: MissionRosterSlotRole = .primary,
        vehicleClass: FleetVehicleType = .unknown,
        leaderRosterDeviceId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.slot = slot
        self.vehicleClass = vehicleClass
        self.leaderRosterDeviceId = leaderRosterDeviceId
    }

    enum CodingKeys: String, CodingKey {
        case id, name, role, slot, vehicleClass, leaderRosterDeviceId
        case legacyWingmanPrimaryRosterDeviceId = "wingmanPrimaryRosterDeviceId"
        case legacyCharacter = "character"
        case legacySlotRole = "slotRole"
        case positionHint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try c.decodeIfPresent(RosterRole.self, forKey: .role)
            ?? (try c.decodeIfPresent(RosterRole.self, forKey: .legacyCharacter)) ?? .none
        if let sr = try c.decodeIfPresent(MissionRosterSlotRole.self, forKey: .slot) {
            slot = sr
        } else if let sr = try c.decodeIfPresent(MissionRosterSlotRole.self, forKey: .legacySlotRole) {
            slot = sr
        } else {
            slot = .primary
        }
        vehicleClass = try c.decodeIfPresent(FleetVehicleType.self, forKey: .vehicleClass) ?? .unknown
        leaderRosterDeviceId = try c.decodeIfPresent(UUID.self, forKey: .leaderRosterDeviceId)
            ?? (try c.decodeIfPresent(UUID.self, forKey: .legacyWingmanPrimaryRosterDeviceId))
        _ = try? c.decodeIfPresent(String.self, forKey: .positionHint)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(role, forKey: .role)
        try c.encode(slot, forKey: .slot)
        try c.encode(vehicleClass, forKey: .vehicleClass)
        try c.encodeIfPresent(leaderRosterDeviceId, forKey: .leaderRosterDeviceId)
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
    case followCourse
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
            self = .followCourse
        case "followPath", "followCourse":
            self = .followCourse
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
            self = .followCourse
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

// MARK: - Task path segments (flat ``waypoints`` for MRE; metadata for hybrid legs + future reroute)

/// Whether a waypoint is operator-authored or generated along a leg.
enum RouteWaypointPathRole: String, Codable, Equatable {
    case anchor
    case segmentInterior
}

/// Geometry mode for a leg to the **next** anchor (interior points copy this value).
enum RouteSegmentKind: String, Codable, Equatable, Hashable, CaseIterable {
    /// Straight interpolation to the next anchor.
    case direct
    /// Road network routing (dense interior waypoints).
    case followRoads
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

    /// `nil` on anchors; shared by all interior samples on one leg.
    var pathSegmentId: UUID?
    var pathRole: RouteWaypointPathRole
    /// Kind of geometry for this waypoint’s leg bucket (interiors mirror the anchor’s outgoing kind).
    var pathSegmentKind: RouteSegmentKind
    /// When ``pathRole == .anchor``, how we reach the **next** anchor. `nil` on the final anchor.
    var outgoingSegmentKind: RouteSegmentKind?

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
        transition: RouteTransition = RouteTransition(),
        pathSegmentId: UUID? = nil,
        pathRole: RouteWaypointPathRole = .anchor,
        pathSegmentKind: RouteSegmentKind = .direct,
        outgoingSegmentKind: RouteSegmentKind? = nil
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
        self.pathSegmentId = pathSegmentId
        self.pathRole = pathRole
        self.pathSegmentKind = pathSegmentKind
        self.outgoingSegmentKind = outgoingSegmentKind
    }

    enum CodingKeys: String, CodingKey {
        case id, coord, altitude, heading, headingPreset, delaySec, delayUnit, action, camera, transition
        case pathSegmentId, pathRole, pathSegmentKind, outgoingSegmentKind
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
        pathSegmentId = try container.decodeIfPresent(UUID.self, forKey: .pathSegmentId)
        pathRole = try container.decodeIfPresent(RouteWaypointPathRole.self, forKey: .pathRole) ?? .anchor
        pathSegmentKind = try container.decodeIfPresent(RouteSegmentKind.self, forKey: .pathSegmentKind) ?? .direct
        outgoingSegmentKind = try container.decodeIfPresent(RouteSegmentKind.self, forKey: .outgoingSegmentKind)
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
        try container.encodeIfPresent(pathSegmentId, forKey: .pathSegmentId)
        try container.encode(pathRole, forKey: .pathRole)
        try container.encode(pathSegmentKind, forKey: .pathSegmentKind)
        try container.encodeIfPresent(outgoingSegmentKind, forKey: .outgoingSegmentKind)
    }
}

/// How a ``MissionTask`` is executed on the autopilot stack (authoring; runtime may narrow further).
enum MissionTaskExecutionMethod: String, Codable, CaseIterable, Identifiable {
    case group
    case staggered

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .group: return "Group"
        case .staggered: return "Staggered"
        }
    }

    /// Migrates legacy persisted `executionMethod` strings.
    static func migrated(fromRaw raw: String) -> MissionTaskExecutionMethod {
        switch raw.lowercased() {
        case "staggered": return .staggered
        case "group": return .group
        case "mavlink", "manual_guided", "companion_offboard": return .group
        default: return .group
        }
    }
}

/// How often this task is intended to run within a broader mission schedule.
enum MissionTaskRegularity: String, Codable, CaseIterable, Identifiable {
    case onceAtStart
    case continuous
    case continuousWithDelay
    case operatorTriggered

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .onceAtStart: return "Once at start"
        case .continuous: return "Continuous"
        case .continuousWithDelay: return "Continuous with delay"
        case .operatorTriggered: return "Operator triggered"
        }
    }

    /// Migrates legacy persisted `regularity` strings.
    static func migrated(fromRaw raw: String) -> MissionTaskRegularity {
        switch raw.lowercased() {
        case "onceatstart", "once", "once_per_run", "onceperrun": return .onceAtStart
        case "twicestartend", "twice_start_end": return .operatorTriggered
        case "continuous", "each_loop", "eachmissionloop": return .continuous
        case "continuouswithdelay", "continuous_with_delay": return .continuousWithDelay
        case "operatortriggered", "operator", "operator_keyed", "operatorkeyed": return .operatorTriggered
        default: return .onceAtStart
        }
    }
}

/// Autopilot action for a squad between scheduled task cycles (e.g. while waiting for a delayed next run).
enum MissionTaskBetweenCyclesAction: String, Codable, CaseIterable, Identifiable {
    case returnToLaunch
    case holdPosition
    case land
    case none

    var id: String { rawValue }
}

/// High-level formation / route pattern for planner and authoring (distinct from waypoint loop geometry).
enum MissionTaskPattern: String, Codable, CaseIterable, Identifiable {
    case patrol
    case convoy

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .patrol: return "Patrol"
        case .convoy: return "Convoy"
        }
    }
}

/// One executable route + roster slice in a mission (formerly ``RoutePath``). JSON still uses the `paths` array key under ``RouteMacro``.
struct MissionTask: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var enabled: Bool
    var waypoints: [RouteWaypoint]
    var loopMode: String
    /// For ``regularity`` ``continuous`` / ``continuousWithDelay``: exact number of task cycles to run. ``0`` means unlimited. Clamped 0...100.
    var cycles: Int
    /// Gap between continuous-with-delay cycles (same unit model as waypoint dwell; see ``MissionDelayPolicy``).
    var regularityDelayValue: Double
    var regularityDelayUnit: DelayUnit
    /// Autopilot / planner execution strategy for this task.
    var executionMethod: MissionTaskExecutionMethod
    /// Cadence / scheduling intent for this task within the mission.
    var regularity: MissionTaskRegularity
    /// What a squad should do between cycles when this task is not immediately continuous.
    var betweenCycles: MissionTaskBetweenCyclesAction
    /// Formation / pattern intent (e.g. patrol vs convoy column).
    var pattern: MissionTaskPattern
    /// Device slots assigned to this task (IDs into `Mission.rosterDevices`).
    var rosterDeviceIds: [UUID]
    /// Defer this task’s MAVLink mission upload/start after execution begins (``MissionDelayPolicy``); MC Setup can override per run (``TaskStartDelay``).
    var startDelayValue: Double
    var startDelayUnit: DelayUnit
    /// When set, overrides ``RouteRules/missionAbortPolicy`` for this task’s roster slots (unless a slot sets ``MissionRunAssignmentPolicies/abort``).
    var abortPolicyOverride: MissionRunAbortPolicy?
    /// When set, overrides ``RouteRules/missionCompletePolicy`` for this task’s roster slots (unless a slot sets ``MissionRunAssignmentPolicies/complete``).
    var completePolicyOverride: MissionRunCompletePolicy?

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, waypoints, loopMode, cycles
        case legacyRepeatCount = "repeatCount"
        case executionMethod, regularity, betweenCycles, pattern
        case startDelayValue, startDelayUnit, regularityDelayValue, regularityDelayUnit
        case legacyRegularityDelayMinutes = "regularityDelayMinutes"
        case legacyStartDelayInt = "startDelay"
        case rosterDeviceIds = "spaceBindings"
        case legacyScheduleRefs = "scheduleRefs"
        case abortPolicyOverride, completePolicyOverride
    }

    /// Effective start deferral duration for execution (seconds).
    var startDelayTotalSeconds: TimeInterval {
        MissionDelayPolicy.clampTotalSeconds(
            MissionDelayPolicy.totalSeconds(value: startDelayValue, unit: startDelayUnit),
            minimumTotalSeconds: 0
        )
    }

    /// Effective inter-cycle delay for ``continuousWithDelay`` (seconds, minimum 1).
    var regularityDelayTotalSeconds: TimeInterval {
        MissionDelayPolicy.clampTotalSeconds(
            MissionDelayPolicy.totalSeconds(value: regularityDelayValue, unit: regularityDelayUnit),
            minimumTotalSeconds: 1
        )
    }

    init(
        id: UUID = UUID(),
        name: String = "Task 1",
        enabled: Bool = true,
        waypoints: [RouteWaypoint] = [],
        loopMode: String = "none",
        cycles: Int = 1,
        regularityDelayValue: Double = 1,
        regularityDelayUnit: DelayUnit = .mins,
        executionMethod: MissionTaskExecutionMethod = .group,
        regularity: MissionTaskRegularity = .onceAtStart,
        betweenCycles: MissionTaskBetweenCyclesAction = .returnToLaunch,
        pattern: MissionTaskPattern = .patrol,
        rosterDeviceIds: [UUID] = [],
        startDelayValue: Double = 0,
        startDelayUnit: DelayUnit = .secs,
        abortPolicyOverride: MissionRunAbortPolicy? = nil,
        completePolicyOverride: MissionRunCompletePolicy? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.waypoints = waypoints
        self.loopMode = loopMode
        self.cycles = min(100, max(0, cycles))
        self.regularityDelayValue = regularityDelayValue
        self.regularityDelayUnit = regularityDelayUnit
        self.executionMethod = executionMethod
        self.regularity = regularity
        self.betweenCycles = betweenCycles
        self.pattern = pattern
        self.rosterDeviceIds = rosterDeviceIds
        self.startDelayValue = startDelayValue
        self.startDelayUnit = startDelayUnit
        self.abortPolicyOverride = abortPolicyOverride
        self.completePolicyOverride = completePolicyOverride
        normalizeDelayFields()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        waypoints = try c.decodeIfPresent([RouteWaypoint].self, forKey: .waypoints) ?? []
        loopMode = try c.decodeIfPresent(String.self, forKey: .loopMode) ?? "none"
        if let decodedCycles = try c.decodeIfPresent(Int.self, forKey: .cycles) {
            cycles = min(100, max(0, decodedCycles))
        } else if let legacy = try c.decodeIfPresent(Int.self, forKey: .legacyRepeatCount) {
            cycles = min(100, max(0, legacy))
        } else {
            cycles = 1
        }

        if let rv = try c.decodeIfPresent(Double.self, forKey: .regularityDelayValue),
           let ru = try c.decodeIfPresent(DelayUnit.self, forKey: .regularityDelayUnit) {
            regularityDelayValue = rv
            regularityDelayUnit = ru
        } else {
            let legacyMins = try c.decodeIfPresent(Int.self, forKey: .legacyRegularityDelayMinutes) ?? 1
            regularityDelayValue = Double(legacyMins)
            regularityDelayUnit = .mins
        }

        rosterDeviceIds = try c.decodeIfPresent([UUID].self, forKey: .rosterDeviceIds) ?? []
        _ = try? c.decodeIfPresent([String].self, forKey: .legacyScheduleRefs)

        if let raw = try c.decodeIfPresent(String.self, forKey: .executionMethod) {
            executionMethod = MissionTaskExecutionMethod(rawValue: raw)
                ?? MissionTaskExecutionMethod.migrated(fromRaw: raw)
        } else {
            executionMethod = .group
        }

        if let raw = try c.decodeIfPresent(String.self, forKey: .regularity) {
            regularity = MissionTaskRegularity(rawValue: raw)
                ?? MissionTaskRegularity.migrated(fromRaw: raw)
        } else {
            regularity = .onceAtStart
        }
        betweenCycles = try c.decodeIfPresent(MissionTaskBetweenCyclesAction.self, forKey: .betweenCycles) ?? .returnToLaunch

        pattern = try c.decodeIfPresent(MissionTaskPattern.self, forKey: .pattern) ?? .patrol

        if let sv = try c.decodeIfPresent(Double.self, forKey: .startDelayValue),
           let su = try c.decodeIfPresent(DelayUnit.self, forKey: .startDelayUnit) {
            startDelayValue = sv
            startDelayUnit = su
        } else {
            let legacyStart = try c.decodeIfPresent(Int.self, forKey: .legacyStartDelayInt) ?? 0
            startDelayValue = Double(legacyStart)
            startDelayUnit = .mins
        }

        abortPolicyOverride = try c.decodeIfPresent(MissionRunAbortPolicy.self, forKey: .abortPolicyOverride)
        completePolicyOverride = try c.decodeIfPresent(MissionRunCompletePolicy.self, forKey: .completePolicyOverride)

        waypoints = Self.migratePathMetadataIfNeeded(waypoints)
        normalizeDelayFields()
    }

    mutating func normalizeDelayFields() {
        let s = MissionDelayPolicy.normalizedTaskStart(value: startDelayValue, unit: startDelayUnit)
        startDelayValue = s.0
        startDelayUnit = s.1
        let r = MissionDelayPolicy.normalizedRegularityGap(value: regularityDelayValue, unit: regularityDelayUnit)
        regularityDelayValue = r.0
        regularityDelayUnit = r.1
    }

    /// Ensures path segment fields are populated (legacy JSON had no segment keys).
    static func migratePathMetadataIfNeeded(_ waypoints: [RouteWaypoint]) -> [RouteWaypoint] {
        guard !waypoints.isEmpty else { return waypoints }
        let looksLegacy = waypoints.allSatisfy { wp in
            wp.pathSegmentId == nil && wp.pathRole == .anchor && wp.outgoingSegmentKind == nil
        }
        guard looksLegacy else { return waypoints }
        var migrated = waypoints
        let n = migrated.count
        for i in migrated.indices {
            migrated[i].pathSegmentKind = .direct
            migrated[i].pathRole = .anchor
            migrated[i].pathSegmentId = nil
            migrated[i].outgoingSegmentKind = (i < n - 1) ? .direct : nil
        }
        return migrated
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(waypoints, forKey: .waypoints)
        try c.encode(loopMode, forKey: .loopMode)
        try c.encode(cycles, forKey: .cycles)
        try c.encode(regularityDelayValue, forKey: .regularityDelayValue)
        try c.encode(regularityDelayUnit, forKey: .regularityDelayUnit)
        try c.encode(executionMethod, forKey: .executionMethod)
        try c.encode(regularity, forKey: .regularity)
        try c.encode(betweenCycles, forKey: .betweenCycles)
        try c.encode(pattern, forKey: .pattern)
        try c.encode(rosterDeviceIds, forKey: .rosterDeviceIds)
        try c.encode(startDelayValue, forKey: .startDelayValue)
        try c.encode(startDelayUnit, forKey: .startDelayUnit)
        try c.encodeIfPresent(abortPolicyOverride, forKey: .abortPolicyOverride)
        try c.encodeIfPresent(completePolicyOverride, forKey: .completePolicyOverride)
    }
}

/// Legacy name used in Mission Control for a single executable route (``MissionTask``).
typealias RoutePath = MissionTask

struct RouteRules: Codable, Equatable {
    var defaultSpeed: Double
    var defaultHeadingHold: Bool
    /// Default abort policy for all tasks unless overridden per task or per roster assignment.
    var missionAbortPolicy: MissionRunAbortPolicy
    /// Default complete-policy for recovery wind-down unless overridden per task or per roster assignment.
    var missionCompletePolicy: MissionRunCompletePolicy

    init(
        defaultSpeed: Double = 5,
        defaultHeadingHold: Bool = true,
        missionAbortPolicy: MissionRunAbortPolicy = .returnToLaunch,
        missionCompletePolicy: MissionRunCompletePolicy = .returnToLaunch
    ) {
        self.defaultSpeed = defaultSpeed
        self.defaultHeadingHold = defaultHeadingHold
        self.missionAbortPolicy = missionAbortPolicy
        self.missionCompletePolicy = missionCompletePolicy
    }

    enum CodingKeys: String, CodingKey {
        case defaultSpeed, defaultHeadingHold, missionAbortPolicy, missionCompletePolicy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultSpeed = try c.decodeIfPresent(Double.self, forKey: .defaultSpeed) ?? 5
        defaultHeadingHold = try c.decodeIfPresent(Bool.self, forKey: .defaultHeadingHold) ?? true
        missionAbortPolicy = try c.decodeIfPresent(MissionRunAbortPolicy.self, forKey: .missionAbortPolicy) ?? .returnToLaunch
        missionCompletePolicy = try c.decodeIfPresent(MissionRunCompletePolicy.self, forKey: .missionCompletePolicy) ?? .returnToLaunch
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(defaultSpeed, forKey: .defaultSpeed)
        try c.encode(defaultHeadingHold, forKey: .defaultHeadingHold)
        try c.encode(missionAbortPolicy, forKey: .missionAbortPolicy)
        try c.encode(missionCompletePolicy, forKey: .missionCompletePolicy)
    }
}

struct RouteMacro: Codable, Equatable {
    var version: Int
    /// Mission tasks (serialized as `paths` for backward compatibility).
    var tasks: [MissionTask]
    var rules: RouteRules

    enum CodingKeys: String, CodingKey {
        case version, rules
        case tasks = "paths"
    }

    init(
        version: Int = 2,
        tasks: [MissionTask] = [],
        rules: RouteRules = RouteRules()
    ) {
        self.version = version
        self.tasks = tasks
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var decodedVersion = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        let decodedTasks = try c.decodeIfPresent([MissionTask].self, forKey: .tasks) ?? []
        if decodedVersion < 2 {
            decodedVersion = 2
        }
        version = decodedVersion
        tasks = decodedTasks
        rules = try c.decodeIfPresent(RouteRules.self, forKey: .rules) ?? RouteRules()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(rules, forKey: .rules)
    }
}

extension RouteMacro {
    /// Launch / map reference derived from the first waypoint of an enabled task (or any task).
    var home: RouteHome? {
        for task in tasks where task.enabled {
            guard let wp = task.waypoints.first else { continue }
            return RouteHome(
                coord: wp.coord,
                altitude: wp.altitude,
                heading: wp.heading,
                radiusMeters: 3,
                dockAllowed: true,
                fallbackOnly: false
            )
        }
        guard let wp = tasks.flatMap(\.waypoints).first else { return nil }
        return RouteHome(
            coord: wp.coord,
            altitude: wp.altitude,
            heading: wp.heading,
            radiusMeters: 3,
            dockAllowed: true,
            fallbackOnly: false
        )
    }
}

struct Mission: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var type: MissionType
    var isArchived: Bool
    var count: Int
    var duration: Int
    var deviceIDs: [String]
    var rosterDevices: [RosterDevice]
    var routeMacro: RouteMacro
    let createdAt: Date
    /// Bumped when a new list/grid JPEG is written so SwiftUI reloads ``MissionCardThumbnailView``.
    var cardThumbnailVersion: Int

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        type: MissionType,
        isArchived: Bool = false,
        count: Int = 0,
        duration: Int = 0,
        deviceIDs: [String] = [],
        rosterDevices: [RosterDevice] = [],
        routeMacro: RouteMacro = RouteMacro(),
        createdAt: Date = Date(),
        cardThumbnailVersion: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.isArchived = isArchived
        self.count = count
        self.duration = duration
        self.deviceIDs = deviceIDs
        self.rosterDevices = rosterDevices
        self.routeMacro = routeMacro
        self.createdAt = createdAt
        self.cardThumbnailVersion = cardThumbnailVersion
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, type, isArchived, count, duration, schedule, deviceIDs, routeMacro, createdAt
        case cardThumbnailVersion
        case rosterDevices = "spaces"
        case mapRegion, routePlan // legacy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        type = try container.decodeIfPresent(MissionType.self, forKey: .type) ?? .mobile
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
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
                tasks: legacyRoutePlan.isEmpty ? [] : [MissionTask(name: "Imported task")],
                rules: RouteRules()
            )
            if !legacyMapRegion.isEmpty {
                routeMacro.tasks = [MissionTask(name: legacyMapRegion)]
            }
        }
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        cardThumbnailVersion = try container.decodeIfPresent(Int.self, forKey: .cardThumbnailVersion) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(type, forKey: .type)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(count, forKey: .count)
        try container.encode(duration, forKey: .duration)
        try container.encode(deviceIDs, forKey: .deviceIDs)
        try container.encode(rosterDevices, forKey: .rosterDevices)
        try container.encode(routeMacro, forKey: .routeMacro)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(cardThumbnailVersion, forKey: .cardThumbnailVersion)
    }
}
