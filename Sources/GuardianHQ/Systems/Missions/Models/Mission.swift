import Foundation

enum MissionType: String, Codable, CaseIterable, Identifiable {
    case mobile
    case staticType = "static"

    var id: String { rawValue }
}

/// Mission behavioral / persona role for MRE and Paladin.
/// Catalog: ``RosterRoleCatalog``; resolved per run for MC export: ``MissionRunRosterRoleResolver``.
enum RosterRole: String, Codable, CaseIterable, Identifiable {
    case none
    case guardian
    case scout
    case marauder
    case relay
    case shepherd
    case warden
    case breacher
    case medic

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
    /// Stable behavior role slug: ``RosterRole/rawValue`` for built-ins (including `none`), or a plugin-owned id.
    var behaviorRoleID: String
    var slot: MissionRosterSlotRole
    var vehicleClass: FleetVehicleType
    /// Footprint band from `Resources/vehicle_size_matrix.md` (default **medium** when omitted in JSON).
    var vehicleSizeTier: VehicleSizeTier
    /// When ``slot`` is ``wingman`` or ``reserve``, optional primary on this task to follow; if nil, MRE may infer.
    var leaderRosterDeviceId: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        behaviorRoleID: String,
        slot: MissionRosterSlotRole = .primary,
        vehicleClass: FleetVehicleType = .unknown,
        vehicleSizeTier: VehicleSizeTier? = nil,
        leaderRosterDeviceId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.behaviorRoleID = behaviorRoleID.isEmpty ? RosterRole.none.rawValue : behaviorRoleID
        self.slot = slot
        self.vehicleClass = vehicleClass
        self.vehicleSizeTier = vehicleSizeTier ?? VehicleClassSizeCatalogue.defaultTier(for: vehicleClass)
        self.leaderRosterDeviceId = leaderRosterDeviceId
    }

    /// Convenience: built-in enum maps to its ``RosterRole/rawValue``.
    init(
        id: UUID = UUID(),
        name: String,
        role: RosterRole = .none,
        slot: MissionRosterSlotRole = .primary,
        vehicleClass: FleetVehicleType = .unknown,
        vehicleSizeTier: VehicleSizeTier? = nil,
        leaderRosterDeviceId: UUID? = nil
    ) {
        self.init(
            id: id,
            name: name,
            behaviorRoleID: role.rawValue,
            slot: slot,
            vehicleClass: vehicleClass,
            vehicleSizeTier: vehicleSizeTier,
            leaderRosterDeviceId: leaderRosterDeviceId
        )
    }

    var resolvedFootprint: VehicleFootprint {
        VehicleClassSizeCatalogue.footprint(vehicleClass: vehicleClass, tier: vehicleSizeTier)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, role, slot, vehicleClass, vehicleSizeTier, leaderRosterDeviceId
        case legacyWingmanPrimaryRosterDeviceId = "wingmanPrimaryRosterDeviceId"
        case legacyCharacter = "character"
        case legacySlotRole = "slotRole"
        case positionHint
    }

    /// Preserves any non-empty `role` / legacy string so plugin ids round-trip on the template.
    private static func decodeBehaviorRoleID(
        from c: KeyedDecodingContainer<CodingKeys>,
        primaryKey: CodingKeys,
        legacyKey: CodingKeys
    ) -> String {
        if let raw = try? c.decodeIfPresent(String.self, forKey: primaryKey), !raw.isEmpty {
            return raw
        }
        if let raw = try? c.decodeIfPresent(String.self, forKey: legacyKey), !raw.isEmpty {
            return raw
        }
        if let r = try? c.decodeIfPresent(RosterRole.self, forKey: primaryKey) { return r.rawValue }
        if let r = try? c.decodeIfPresent(RosterRole.self, forKey: legacyKey) { return r.rawValue }
        return RosterRole.none.rawValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        behaviorRoleID = Self.decodeBehaviorRoleID(from: c, primaryKey: .role, legacyKey: .legacyCharacter)
        if let sr = try c.decodeIfPresent(MissionRosterSlotRole.self, forKey: .slot) {
            slot = sr
        } else if let sr = try c.decodeIfPresent(MissionRosterSlotRole.self, forKey: .legacySlotRole) {
            slot = sr
        } else {
            slot = .primary
        }
        vehicleClass = try c.decodeIfPresent(FleetVehicleType.self, forKey: .vehicleClass) ?? .unknown
        vehicleSizeTier = try c.decodeIfPresent(VehicleSizeTier.self, forKey: .vehicleSizeTier)
            ?? VehicleClassSizeCatalogue.defaultTier(for: vehicleClass)
        leaderRosterDeviceId = try c.decodeIfPresent(UUID.self, forKey: .leaderRosterDeviceId)
            ?? (try c.decodeIfPresent(UUID.self, forKey: .legacyWingmanPrimaryRosterDeviceId))
        _ = try? c.decodeIfPresent(String.self, forKey: .positionHint)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(behaviorRoleID, forKey: .role)
        try c.encode(slot, forKey: .slot)
        try c.encode(vehicleClass, forKey: .vehicleClass)
        try c.encode(vehicleSizeTier, forKey: .vehicleSizeTier)
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

/// What the squad does in the **gap between task cycles** (repeating / delayed-repeat tasks only).
/// Operator labels: **Return to Launch**, **Loiter**, **Park** — map to fleet dispatch via ``MissionRunFleetDispatch/betweenCyclesTaskDispatch``.
enum MissionTaskBetweenCyclesAction: String, Codable, CaseIterable, Identifiable {
    case returnToLaunch
    case holdPosition
    case park

    var id: String { rawValue }

    /// Short label for mission authoring and Mission Control task settings (no autopilot jargon).
    var displayTitle: String {
        switch self {
        case .returnToLaunch: return "Return to Launch"
        case .holdPosition: return "Loiter"
        case .park: return "Park"
        }
    }

    /// Normalizes persisted strings from older mission JSON into the v1 enum set.
    static func migrated(fromRaw raw: String) -> MissionTaskBetweenCyclesAction {
        switch raw.lowercased() {
        case "returntolaunch", "rtl": return .returnToLaunch
        case "holdposition", "loiter": return .holdPosition
        case "park": return .park
        case "land", "none":
            return .returnToLaunch
        default:
            return MissionTaskBetweenCyclesAction(rawValue: raw) ?? .returnToLaunch
        }
    }
}

/// How the **first wave** of primary squads is spaced when a task starts (one primary per squad).
enum MissionTaskStaggerTrigger: String, Codable, CaseIterable, Identifiable {
    /// Estimate seconds between launches from the first path leg distance and speed.
    case pathEstimate
    /// Fixed interval between each primary's first launch.
    case fixedInterval
    /// Each primary after the first launches when the lead reaches ``MissionTask/staggerWaypointIndex``.
    case waypointReached
    /// Only the first primary launches automatically; operator releases each following primary.
    case operatorFirstWaveGate

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .pathEstimate: return "Automatic spacing"
        case .fixedInterval: return "Fixed interval"
        case .waypointReached: return "Waypoint reached"
        case .operatorFirstWaveGate: return "Operator starts each squad"
        }
    }

    /// Primaries after index 0 are not auto-started in the first launch pass (MRE §4–5 completes release).
    var defersSubsequentPrimariesInFirstWave: Bool {
        switch self {
        case .waypointReached, .operatorFirstWaveGate: return true
        case .pathEstimate, .fixedInterval: return false
        }
    }
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
    /// Cadence / scheduling intent for this task within the mission.
    var regularity: MissionTaskRegularity
    /// What a squad should do between cycles when this task is not immediately continuous.
    var betweenCycles: MissionTaskBetweenCyclesAction
    /// Formation / pattern intent (e.g. patrol vs convoy column).
    var pattern: MissionTaskPattern
    /// Wingman slot geometry when this task has a squad (convoy / chevron / arrowhead).
    var squadFormation: MissionSquadFormationKind
    /// How tightly wingmen pack for the chosen formation (tight / normal / loose).
    var squadFormationSpacing: MissionSquadFormationSpacing
    /// First-wave spacing between primary squads (see ``MissionTaskStaggerTrigger``).
    var staggerTrigger: MissionTaskStaggerTrigger
    /// Fixed interval between primaries when ``staggerTrigger`` is ``fixedInterval``.
    var staggerIntervalValue: Double
    var staggerIntervalUnit: DelayUnit
    /// 0-based task waypoint index when ``staggerTrigger`` is ``waypointReached``.
    var staggerWaypointIndex: Int
    /// Device slots assigned to this task (IDs into `Mission.rosterDevices`).
    var rosterDeviceIds: [UUID]
    /// Defer this task’s MAVLink mission upload/start after execution begins (``MissionDelayPolicy``); MC Setup can override per run (``TaskStartDelay``).
    var startDelayValue: Double
    var startDelayUnit: DelayUnit
    /// When non-empty, overrides ``RouteRules/missionAbortPreferenceChain`` for this task’s roster slots (unless a slot sets its own ``MissionRunAssignmentPolicies/abortPreferenceChain``).
    var abortPreferenceChainOverride: [MissionRunAbortTactic]?
    /// When non-empty, overrides ``RouteRules/missionCompletePreferenceChain`` for this task’s roster slots (unless a slot sets ``MissionRunAssignmentPolicies/completePreferenceChain``).
    var completePreferenceChainOverride: [MissionRunCompleteTactic]?
    /// When non-empty, overrides ``RouteRules/missionReserveSwapPreferenceChain`` for this task’s roster slots (unless a slot sets ``MissionRunAssignmentPolicies/reserveSwapPreferenceChain``).
    var reserveSwapPreferenceChainOverride: [MissionRunReserveSwapTactic]?
    /// Task-scoped geofences (``Mission/missionGeofences`` are mission-wide).
    var geofences: [MissionGeofence]

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, waypoints, loopMode, cycles
        case legacyRepeatCount = "repeatCount"
        case regularity, betweenCycles, pattern
        case staggerTrigger, staggerIntervalValue, staggerIntervalUnit, staggerWaypointIndex
        case startDelayValue, startDelayUnit, regularityDelayValue, regularityDelayUnit
        case legacyRegularityDelayMinutes = "regularityDelayMinutes"
        case legacyStartDelayInt = "startDelay"
        case rosterDeviceIds = "spaceBindings"
        case legacyScheduleRefs = "scheduleRefs"
        case abortPreferenceChainOverride, completePreferenceChainOverride, reserveSwapPreferenceChainOverride
        case geofences
        case squadFormation
        case squadFormationSpacing
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

    /// Effective fixed first-wave stagger interval (seconds, minimum 1).
    var staggerIntervalTotalSeconds: TimeInterval {
        MissionDelayPolicy.clampTotalSeconds(
            MissionDelayPolicy.totalSeconds(value: staggerIntervalValue, unit: staggerIntervalUnit),
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
        regularity: MissionTaskRegularity = .onceAtStart,
        betweenCycles: MissionTaskBetweenCyclesAction = .returnToLaunch,
        pattern: MissionTaskPattern = .patrol,
        squadFormation: MissionSquadFormationKind = .convoy,
        squadFormationSpacing: MissionSquadFormationSpacing = .normal,
        staggerTrigger: MissionTaskStaggerTrigger = .pathEstimate,
        staggerIntervalValue: Double = 20,
        staggerIntervalUnit: DelayUnit = .secs,
        staggerWaypointIndex: Int = 0,
        rosterDeviceIds: [UUID] = [],
        startDelayValue: Double = 0,
        startDelayUnit: DelayUnit = .secs,
        abortPreferenceChainOverride: [MissionRunAbortTactic]? = nil,
        completePreferenceChainOverride: [MissionRunCompleteTactic]? = nil,
        reserveSwapPreferenceChainOverride: [MissionRunReserveSwapTactic]? = nil,
        geofences: [MissionGeofence] = []
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.waypoints = waypoints
        self.loopMode = loopMode
        self.cycles = min(100, max(0, cycles))
        self.regularityDelayValue = regularityDelayValue
        self.regularityDelayUnit = regularityDelayUnit
        self.regularity = regularity
        self.betweenCycles = betweenCycles
        self.pattern = pattern
        self.squadFormation = squadFormation
        self.squadFormationSpacing = squadFormationSpacing
        self.staggerTrigger = staggerTrigger
        self.staggerIntervalValue = staggerIntervalValue
        self.staggerIntervalUnit = staggerIntervalUnit
        self.staggerWaypointIndex = staggerWaypointIndex
        self.rosterDeviceIds = rosterDeviceIds
        self.startDelayValue = startDelayValue
        self.startDelayUnit = startDelayUnit
        self.abortPreferenceChainOverride = abortPreferenceChainOverride
        self.completePreferenceChainOverride = completePreferenceChainOverride
        self.reserveSwapPreferenceChainOverride = reserveSwapPreferenceChainOverride
        self.geofences = geofences
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

        if let raw = try c.decodeIfPresent(String.self, forKey: .regularity) {
            regularity = MissionTaskRegularity(rawValue: raw)
                ?? MissionTaskRegularity.migrated(fromRaw: raw)
        } else {
            regularity = .onceAtStart
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .betweenCycles) {
            betweenCycles = MissionTaskBetweenCyclesAction(rawValue: raw)
                ?? MissionTaskBetweenCyclesAction.migrated(fromRaw: raw)
        } else {
            betweenCycles = .returnToLaunch
        }

        pattern = try c.decodeIfPresent(MissionTaskPattern.self, forKey: .pattern) ?? .patrol
        squadFormation = try c.decodeIfPresent(MissionSquadFormationKind.self, forKey: .squadFormation) ?? .convoy
        squadFormationSpacing = try c.decodeIfPresent(MissionSquadFormationSpacing.self, forKey: .squadFormationSpacing) ?? .normal

        staggerTrigger = try c.decodeIfPresent(MissionTaskStaggerTrigger.self, forKey: .staggerTrigger) ?? .pathEstimate
        if let iv = try c.decodeIfPresent(Double.self, forKey: .staggerIntervalValue),
           let iu = try c.decodeIfPresent(DelayUnit.self, forKey: .staggerIntervalUnit) {
            staggerIntervalValue = iv
            staggerIntervalUnit = iu
        } else {
            staggerIntervalValue = 20
            staggerIntervalUnit = .secs
        }
        staggerWaypointIndex = try c.decodeIfPresent(Int.self, forKey: .staggerWaypointIndex) ?? 0

        if let sv = try c.decodeIfPresent(Double.self, forKey: .startDelayValue),
           let su = try c.decodeIfPresent(DelayUnit.self, forKey: .startDelayUnit) {
            startDelayValue = sv
            startDelayUnit = su
        } else {
            let legacyStart = try c.decodeIfPresent(Int.self, forKey: .legacyStartDelayInt) ?? 0
            startDelayValue = Double(legacyStart)
            startDelayUnit = .mins
        }

        abortPreferenceChainOverride = try c.decodeIfPresent([MissionRunAbortTactic].self, forKey: .abortPreferenceChainOverride)
        completePreferenceChainOverride = try c.decodeIfPresent([MissionRunCompleteTactic].self, forKey: .completePreferenceChainOverride)
        reserveSwapPreferenceChainOverride = try c.decodeIfPresent([MissionRunReserveSwapTactic].self, forKey: .reserveSwapPreferenceChainOverride)
        geofences = try c.decodeIfPresent([MissionGeofence].self, forKey: .geofences) ?? []

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
        let g = MissionDelayPolicy.normalizedRegularityGap(value: staggerIntervalValue, unit: staggerIntervalUnit)
        staggerIntervalValue = g.0
        staggerIntervalUnit = g.1
        if waypoints.isEmpty {
            staggerWaypointIndex = 0
        } else {
            staggerWaypointIndex = min(max(0, staggerWaypointIndex), waypoints.count - 1)
        }
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
        try c.encode(regularity, forKey: .regularity)
        try c.encode(betweenCycles, forKey: .betweenCycles)
        try c.encode(pattern, forKey: .pattern)
        if squadFormation != .convoy {
            try c.encode(squadFormation, forKey: .squadFormation)
        }
        if squadFormationSpacing != .normal {
            try c.encode(squadFormationSpacing, forKey: .squadFormationSpacing)
        }
        try c.encode(staggerTrigger, forKey: .staggerTrigger)
        try c.encode(staggerIntervalValue, forKey: .staggerIntervalValue)
        try c.encode(staggerIntervalUnit, forKey: .staggerIntervalUnit)
        try c.encode(staggerWaypointIndex, forKey: .staggerWaypointIndex)
        try c.encode(rosterDeviceIds, forKey: .rosterDeviceIds)
        try c.encode(startDelayValue, forKey: .startDelayValue)
        try c.encode(startDelayUnit, forKey: .startDelayUnit)
        try c.encodeIfPresent(abortPreferenceChainOverride, forKey: .abortPreferenceChainOverride)
        try c.encodeIfPresent(completePreferenceChainOverride, forKey: .completePreferenceChainOverride)
        try c.encodeIfPresent(reserveSwapPreferenceChainOverride, forKey: .reserveSwapPreferenceChainOverride)
        try c.encode(geofences, forKey: .geofences)
    }
}

/// Legacy name used in Mission Control for a single executable route (``MissionTask``).
typealias RoutePath = MissionTask

struct RouteRules: Codable, Equatable {
    var defaultSpeed: Double
    var defaultHeadingHold: Bool
    /// Default **ordered** abort tactics for all tasks unless overridden per task or per roster assignment.
    var missionAbortPreferenceChain: [MissionRunAbortTactic]
    /// Default **ordered** complete (recovery) tactics unless overridden per task or per roster assignment.
    var missionCompletePreferenceChain: [MissionRunCompleteTactic]
    /// Default **ordered** reserve-swap (displaced active wind-down) tactics unless overridden per task or per roster assignment.
    var missionReserveSwapPreferenceChain: [MissionRunReserveSwapTactic]

    init(
        defaultSpeed: Double = 5,
        defaultHeadingHold: Bool = true,
        missionAbortPreferenceChain: [MissionRunAbortTactic] = MissionRunAbortTactic.defaultMissionAbortPreferenceChain,
        missionCompletePreferenceChain: [MissionRunCompleteTactic] = MissionRunCompleteTactic.defaultMissionCompletePreferenceChain,
        missionReserveSwapPreferenceChain: [MissionRunReserveSwapTactic] = MissionRunReserveSwapTactic.defaultMissionReserveSwapPreferenceChain
    ) {
        self.defaultSpeed = defaultSpeed
        self.defaultHeadingHold = defaultHeadingHold
        self.missionAbortPreferenceChain = MissionRunAbortTactic.normalizedPreferenceChain(missionAbortPreferenceChain)
        self.missionCompletePreferenceChain = MissionRunCompleteTactic.upgradingStoredMissionWideChain(
            missionCompletePreferenceChain
        )
        self.missionReserveSwapPreferenceChain = MissionRunReserveSwapTactic.normalizedPreferenceChain(missionReserveSwapPreferenceChain)
    }

    enum CodingKeys: String, CodingKey {
        case defaultSpeed, defaultHeadingHold, missionAbortPreferenceChain, missionCompletePreferenceChain, missionReserveSwapPreferenceChain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultSpeed = try c.decodeIfPresent(Double.self, forKey: .defaultSpeed) ?? 5
        defaultHeadingHold = try c.decodeIfPresent(Bool.self, forKey: .defaultHeadingHold) ?? true
        if let decoded = try c.decodeIfPresent([MissionRunAbortTactic].self, forKey: .missionAbortPreferenceChain),
           !decoded.isEmpty {
            missionAbortPreferenceChain = MissionRunAbortTactic.normalizedPreferenceChain(decoded)
        } else {
            missionAbortPreferenceChain = MissionRunAbortTactic.defaultMissionAbortPreferenceChain
        }
        if let decoded = try c.decodeIfPresent([MissionRunCompleteTactic].self, forKey: .missionCompletePreferenceChain),
           !decoded.isEmpty {
            missionCompletePreferenceChain = MissionRunCompleteTactic.upgradingStoredMissionWideChain(decoded)
        } else {
            missionCompletePreferenceChain = MissionRunCompleteTactic.defaultMissionCompletePreferenceChain
        }
        if let decoded = try c.decodeIfPresent([MissionRunReserveSwapTactic].self, forKey: .missionReserveSwapPreferenceChain),
           !decoded.isEmpty {
            missionReserveSwapPreferenceChain = MissionRunReserveSwapTactic.normalizedPreferenceChain(decoded)
        } else {
            missionReserveSwapPreferenceChain = MissionRunReserveSwapTactic.defaultMissionReserveSwapPreferenceChain
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(defaultSpeed, forKey: .defaultSpeed)
        try c.encode(defaultHeadingHold, forKey: .defaultHeadingHold)
        try c.encode(missionAbortPreferenceChain, forKey: .missionAbortPreferenceChain)
        try c.encode(missionCompletePreferenceChain, forKey: .missionCompletePreferenceChain)
        try c.encode(missionReserveSwapPreferenceChain, forKey: .missionReserveSwapPreferenceChain)
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
    /// Map / geofence authoring reference from the first waypoint of an enabled task (or any task).
    ///
    /// **Not** the per-vehicle operator launch used for Return to Launch — that is
    /// ``MissionRunEnvironment/operatorLaunchPoseByAssignmentID`` (captured in MCS at **Start Run**).
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

// MARK: - Mission points (typed map pins; not path waypoints)

/// Kind of ``MissionPoint`` (rally, extraction, …). Extensible for future metadata families.
enum MissionPointKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case rally
    case extraction

    var id: String { rawValue }

    /// Compact map prefix (e.g. RP, EP) paired with a short suffix in UI.
    var mapChipPrefix: String {
        switch self {
        case .rally: "RP"
        case .extraction: "EP"
        }
    }
}

/// A mission-scoped map point (rally / extraction / …), orthogonal to task route waypoints.
/// See ``Mission/missionPoints`` and README **Mission template points**.
struct MissionPoint: Identifiable, Codable, Equatable, Sendable {
    /// Row identity in the mission document (distinct from ``pointId`` slug for MRE).
    let id: UUID
    /// Stable slug for MRE, recipes, and logs (unique within the parent ``Mission``).
    var pointId: String
    var label: String
    var kind: MissionPointKind
    var coordinate: RouteCoordinate
    /// `nil` = mission-wide; otherwise scoped to that ``MissionTask``.
    var taskID: UUID?
    /// Catchment radius in metres; allowed **1…1000**, default **10**.
    var catchmentRadiusM: Double
    /// When `true`, planners / MRE should ignore this point until reopened.
    var isClosed: Bool

    /// Default catchment when creating or decoding a partial payload.
    static let defaultCatchmentRadiusM: Double = 10

    static func clampedCatchmentRadiusM(_ value: Double) -> Double {
        min(1000, max(1, value))
    }

    init(
        id: UUID = UUID(),
        pointId: String,
        label: String,
        kind: MissionPointKind,
        coordinate: RouteCoordinate,
        taskID: UUID? = nil,
        catchmentRadiusM: Double = MissionPoint.defaultCatchmentRadiusM,
        isClosed: Bool = false
    ) {
        self.id = id
        self.pointId = pointId
        self.label = label
        self.kind = kind
        self.coordinate = coordinate
        self.taskID = taskID
        self.catchmentRadiusM = Self.clampedCatchmentRadiusM(catchmentRadiusM)
        self.isClosed = isClosed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let decodedPointId = try c.decodeIfPresent(String.self, forKey: .pointId) ?? ""
        pointId = decodedPointId.isEmpty ? "point.\(id.uuidString.lowercased())" : decodedPointId
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        kind = try c.decodeIfPresent(MissionPointKind.self, forKey: .kind) ?? .rally
        coordinate = try c.decodeIfPresent(RouteCoordinate.self, forKey: .coordinate) ?? RouteCoordinate()
        taskID = try c.decodeIfPresent(UUID.self, forKey: .taskID)
        let rawCatchment = try c.decodeIfPresent(Double.self, forKey: .catchmentRadiusM)
            ?? MissionPoint.defaultCatchmentRadiusM
        catchmentRadiusM = Self.clampedCatchmentRadiusM(rawCatchment)
        isClosed = try c.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(pointId, forKey: .pointId)
        try c.encode(label, forKey: .label)
        try c.encode(kind, forKey: .kind)
        try c.encode(coordinate, forKey: .coordinate)
        try c.encodeIfPresent(taskID, forKey: .taskID)
        try c.encode(catchmentRadiusM, forKey: .catchmentRadiusM)
        try c.encode(isClosed, forKey: .isClosed)
    }

    enum CodingKeys: String, CodingKey {
        case id, pointId, label, kind, coordinate, taskID, catchmentRadiusM, isClosed
    }

    /// Numeric suffix from slug `rally.3` / `extraction.2` (for display after ``Mission/renumberMissionPointSlugsByListOrder()``).
    var slugOrdinalSuffix: Int? {
        let parts = pointId.split(separator: ".")
        guard let last = parts.last else { return nil }
        return Int(String(last))
    }

    /// List / selected-map chip, e.g. `RP:1`, `EP:2`.
    var mapChipLabel: String {
        let n = slugOrdinalSuffix.map(String.init) ?? "?"
        return "\(kind.mapChipPrefix):\(n)"
    }

    /// Single digit (or number) on map when unselected — colour encodes kind.
    var mapGlyphDigit: String {
        slugOrdinalSuffix.map(String.init) ?? "?"
    }

    /// Copy for a cloned mission: new row ``id``; keeps ``pointId`` (namespaced by owning mission id on disk).
    func duplicatedForClonedMission() -> MissionPoint {
        MissionPoint(
            id: UUID(),
            pointId: pointId,
            label: label,
            kind: kind,
            coordinate: coordinate,
            taskID: taskID,
            catchmentRadiusM: catchmentRadiusM,
            isClosed: isClosed
        )
    }
}

extension MissionPoint {
    /// Next `rally.n` / `extraction.n` with integer **n** strictly greater than any existing same-kind slug in `existing`
    /// whose tail is all digits (template / editor rows). Non-numeric tails (e.g. `rally.alpha`) are ignored for the max
    /// so they do not consume ordinals — matches ``MissionRunEnvironment`` runtime slug rules.
    static func makeUniquePointId(kind: MissionPointKind, existing: Set<String>) -> String {
        let prefix = kind == .rally ? "rally." : "extraction."
        var maxN = 0
        for raw in existing where raw.hasPrefix(prefix) {
            let tail = String(raw.dropFirst(prefix.count))
            guard let n = Int(tail) else { continue }
            maxN = max(maxN, n)
        }
        return "\(prefix)\(maxN + 1)"
    }

    /// Mission Control run **live overview** map — see README **Mission template points** and `MissionPoint.filteredForMissionControlLiveMap`.
    /// When `focusedTaskID` is `nil`, returns all points. Otherwise returns mission-wide (`taskID == nil`) plus rows scoped to that task.
    static func filteredForMissionControlLiveMap(_ points: [MissionPoint], focusedTaskID: UUID?) -> [MissionPoint] {
        guard let tid = focusedTaskID else { return points }
        return points.filter { $0.taskID == nil || $0.taskID == tid }
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
    /// Typed map pins (rally, extraction, …) — orthogonal to task path waypoints; see ``MissionPoint``.
    var missionPoints: [MissionPoint]
    /// Mission-wide geofences (all tasks); see ``MissionTask/geofences`` for per-task regions.
    var missionGeofences: [MissionGeofence]
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
        missionPoints: [MissionPoint] = [],
        missionGeofences: [MissionGeofence] = [],
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
        self.missionPoints = missionPoints
        self.missionGeofences = missionGeofences
        self.createdAt = createdAt
        self.cardThumbnailVersion = cardThumbnailVersion
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, type, isArchived, count, duration, schedule, deviceIDs, routeMacro, createdAt
        case cardThumbnailVersion, missionPoints, missionGeofences
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
        missionPoints = try container.decodeIfPresent([MissionPoint].self, forKey: .missionPoints) ?? []
        missionGeofences = try container.decodeIfPresent([MissionGeofence].self, forKey: .missionGeofences) ?? []
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
        try container.encode(missionPoints, forKey: .missionPoints)
        try container.encode(missionGeofences, forKey: .missionGeofences)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(cardThumbnailVersion, forKey: .cardThumbnailVersion)
    }
}

extension Mission {
    /// Removes points scoped to a task that is being deleted (`taskID` match). Mission-wide rows (`taskID == nil`) are kept.
    mutating func removeMissionPoints(forRemovedTaskID taskID: UUID) {
        missionPoints.removeAll { $0.taskID == taskID }
    }

    /// Rewrites ``MissionPoint/pointId`` as `rally.1`, `rally.2`, … and `extraction.1`, … in **current array order**; clears labels (display is chip-only).
    mutating func renumberMissionPointSlugsByListOrder() {
        var rallyN = 0
        var extractionN = 0
        for i in missionPoints.indices {
            switch missionPoints[i].kind {
            case .rally:
                rallyN += 1
                missionPoints[i].pointId = "rally.\(rallyN)"
            case .extraction:
                extractionN += 1
                missionPoints[i].pointId = "extraction.\(extractionN)"
            }
            missionPoints[i].label = ""
        }
    }
}
