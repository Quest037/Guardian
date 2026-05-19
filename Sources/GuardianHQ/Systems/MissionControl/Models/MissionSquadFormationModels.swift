import Foundation

/// v1 formation shape for squad wingmen (see `SquadFollow&Formation.md`). Geometry: ``MissionSquadFormationGeometry``.
enum MissionSquadFormationKind: String, Codable, CaseIterable, Sendable, Equatable, Identifiable {
    /// Single-file astern line (no alternating lateral lanes).
    case convoy
    /// Alternating left/right lanes astern of the primary (zig-zag).
    case staggeredConvoy
    case chevron
    case arrowhead

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .convoy: return "Convoy"
        case .staggeredConvoy: return "Staggered convoy"
        case .chevron: return "Chevron"
        case .arrowhead: return "Arrowhead"
        }
    }
}

/// How tightly wingmen pack for any formation kind (convoy / chevron / arrowhead).
enum MissionSquadFormationSpacing: String, Codable, CaseIterable, Sendable, Equatable, Identifiable {
    case tight
    case normal
    case loose

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .tight: return "Tight"
        case .normal: return "Normal"
        case .loose: return "Loose"
        }
    }

    /// Scales along-track row / ordinal spacing.
    var alongTrackScale: Double {
        switch self {
        case .tight: return 0.72
        case .normal: return 1.0
        case .loose: return 1.38
        }
    }

    /// Scales lateral lane / row width.
    var lateralScale: Double {
        switch self {
        case .tight: return 0.68
        case .normal: return 1.0
        case .loose: return 1.42
        }
    }
}

/// Locked convoy spacing defaults until mission authoring exposes per-task fields.
struct MissionSquadConvoySpacing: Equatable, Sendable {
    /// Metres **behind** the primary per wingman ordinal (1st wingman = 1×, 2nd = 2×, …).
    var alongTrackMetersPerOrdinal: Double
    /// Optional lateral lane offset (metres to the right of the primary heading); `0` = straight line astern.
    var lateralLaneMeters: Double

    static let uavDefault = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 25, lateralLaneMeters: 0)
    /// Tight astern spacing for UGV convoy SIM / field testing until per-task authoring ships.
    static let ugvConvoyTest = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 3, lateralLaneMeters: 0)
    static let surfaceDefault = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 15, lateralLaneMeters: 0)
    static let genericDefault = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 20, lateralLaneMeters: 0)
}

enum MissionSquadConvoySpacingPolicy {
    /// Vehicle-class baseline spacing before formation shape and kind adjustments.
    static func lockedSpacing(
        taskPattern: MissionTaskPattern,
        primaryGranularClass: FleetVehicleType?
    ) -> MissionSquadConvoySpacing {
        if let cls = primaryGranularClass {
            switch cls.universalClass {
            case .uav: return .uavDefault
            case .ugv: return .ugvConvoyTest
            case .usv, .uuv, .unknown: return .surfaceDefault
            }
        }
        if taskPattern == .convoy { return .genericDefault }
        return .genericDefault
    }

    /// Effective spacing for wingman slots (class baseline × operator pack spacing × formation kind).
    static func resolvedSpacing(
        taskPattern: MissionTaskPattern,
        primaryGranularClass: FleetVehicleType?,
        spacing: MissionSquadFormationSpacing,
        formation: MissionSquadFormationKind
    ) -> MissionSquadConvoySpacing {
        let base = lockedSpacing(taskPattern: taskPattern, primaryGranularClass: primaryGranularClass)
        let alongKindScale: Double = switch formation {
        case .convoy, .staggeredConvoy: 1.0
        case .chevron: 0.92
        case .arrowhead: 0.78
        }
        let lateralKindScale: Double = switch formation {
        case .convoy, .staggeredConvoy: 1.0
        case .chevron: 0.92
        case .arrowhead: 0.62
        }
        return MissionSquadConvoySpacing(
            alongTrackMetersPerOrdinal: base.alongTrackMetersPerOrdinal * spacing.alongTrackScale * alongKindScale,
            lateralLaneMeters: base.lateralLaneMeters * spacing.lateralScale * lateralKindScale
        )
    }

}

/// Locked v1 wingman OFFBOARD pursuit / convoy assembly (see `SquadFollow&Formation.md` §C).
enum MissionSquadConvoyFollowControlPolicy {
    /// Wingman within this distance of its heading-based slot counts as in formation (m).
    static let convoyAssemblyArrivalM: Double = 1.5
    /// Wingman |yaw − target| must be within this to count as heading-aligned (degrees).
    static let convoyAssemblyHeadingToleranceDeg: Double = 5.0
    /// Primary ground speed at or below this counts as stationary for wingman in-slot hold (m/s).
    static let primaryConvoyStationaryMaxGroundSpeedMS: Double = 0.2
    /// Abort assembly wait and release the primary anyway (s).
    static let convoyAssemblyTimeoutS: Double = 120
    /// Matches ``MissionRunSquadFollowSubsystem`` tick interval (~10 Hz).
    static let tickIntervalS: Double = 0.1
    /// Per-wingman OFFBOARD stream start attempts before escalating to operator (primary mission pause).
    static let streamReconnectMaxAttempts: Int = 5
    /// Cooldown between wingman stream reconnect tries (s).
    static let streamReconnectCooldownS: TimeInterval = 1.0
    /// Wingmen snap to the task polyline only when the primary is within this lateral distance (metres).
    static let pathAnchorMaxLateralM: Double = 12
    /// Along-path tolerance when comparing primary progress to the first route leg (metres).
    static let pathAnchorFirstWaypointAlongToleranceM: Double = 2.0
    /// Within this horizontal distance of the convoy slot, stream the slot directly (metres).
    static let pursuitSnapArrivalM: Double = 1.25
    /// Beyond this distance, stream the slot directly (full catch-up — same as pre-pursuit v1).
    static let directSlotBeyondM: Double = 3.0
    /// Tighter direct snap when polyline-anchored so wingmen stay on the red path line.
    static let pathAnchoredDirectSlotBeyondM: Double = 1.5
    /// Mid-range OFFBOARD carrot length toward the slot (PX4 UGV ignores sub-metre position hops).
    static let pursuitLeashMinM: Double = 2.5
    static let pursuitLeashMaxM: Double = 6.0
    /// Dynamic leash upper bound when wingman is far behind the convoy slot (PX4 position pursuit).
    static let pursuitLeashCatchUpMaxM: Double = 18.0
    /// Primary speed unknown — assume this cruise (m/s) for gap closure.
    static let pursuitDefaultCruiseMS: Double = 1.0
    static let pursuitMinForwardMS: Double = 0.12
    /// Max forward speed above primary cruise when closing a gap (m/s).
    static let pursuitMaxBoostAbovePrimaryMS: Double = 2.5
    /// Max reduction below primary cruise when ahead of slot (m/s).
    static let pursuitMaxSlowBelowPrimaryMS: Double = 1.8
    /// Along-convoy gap gain (m/s per metre of along-track slot error).
    static let pursuitAlongGain: Double = 0.55
    /// When horizontal distance to slot exceeds this, enforce catch-up floor speed (m).
    static let pursuitCatchUpDistanceM: Double = 4.0
    /// Yaw rate toward convoy heading when |lateral error| exceeds this (deg/s per m, capped).
    static let pursuitYawRateGainDegSPerM: Double = 12.0
    static let pursuitYawRateMaxDegS: Double = 35.0
    /// Start applying yaw rate when |heading error| exceeds this (degrees).
    static let pursuitHeadingAlignStartDeg: Double = 4.0
    /// Yaw rate gain from heading error alone (deg/s per degree of error).
    static let pursuitHeadingAlignGainDegSPerDeg: Double = 0.55
    /// Ahead of slot by more than this (m) — command reverse body speed (ArduPilot / PX4 copter).
    static let pursuitReverseAheadThresholdM: Double = 2.5
    static let pursuitMaxReverseMS: Double = 0.9
    /// Remaining distance along the GR polyline at or below this ends launch approach and starts AUTO (m).
    /// Crow-flies distance to WP1 is **not** used — a path can pass near WP1 while still having long distance left.
    static let guardianRouterFirstWaypointArrivalM: Double = 6.0

    /// True when the primary has reached the end of the routed launch leg (path distance only).
    static func guardianRouterLaunchApproachArrived(remainingAlongRouteM: Double) -> Bool {
        remainingAlongRouteM <= guardianRouterFirstWaypointArrivalM
    }
    /// Wingman slot on GR launch polyline: max lateral error from routed spine (m).
    static let launchApproachPathAnchorMaxLateralM: Double = 30
    /// Launch→WP1: wingman farther than this from its convoy slot counts as lagging (m).
    static let launchLegWingmanLagBehindSlotM: Double = 5.0
    /// Launch→WP1: primary pursuit speed while waiting for lagging wingmen (m/s).
    static let launchLegPrimaryWaitSpeedMS: Double = 0.25

    /// Hold primary in place on the launch leg when wingmen lag or when within this band of WP1 (m).
    static var launchLegPrimaryHoldBandM: Double { guardianRouterFirstWaypointArrivalM * 2 }

    /// Primary OFFBOARD hold during launch→WP1 (wingman catch-up or pre-WP1 deceleration).
    static func launchLegShouldHoldPrimaryInPlace(
        distToFirstWaypointM: Double,
        remainingAlongRouteM: Double,
        wingmenLagging: Bool
    ) -> Bool {
        if wingmenLagging { return true }
        let band = launchLegPrimaryHoldBandM
        return distToFirstWaypointM <= band || remainingAlongRouteM <= band
    }

}

/// Runtime follow state for one wingman assignment.
enum MissionRunSquadWingmanFollowPhase: String, Equatable, Sendable {
    case idle
    case targetsComputed
    case assemblingConvoy
    /// GR launch→first-WP approach leg (OFFBOARD/GUIDED) before primary AUTO mission.
    case approachingRoute
    case following
    /// Between-cycle hold: stream last pose without chasing a moving primary.
    case holdingBetweenCycles
    case streamFailed

    /// Operator-facing roster/triage label; `nil` when no extra chrome is needed.
    var operatorStatusLabel: String? {
        switch self {
        case .idle, .targetsComputed:
            return nil
        case .assemblingConvoy:
            return "Forming convoy"
        case .approachingRoute:
            return "Approaching route"
        case .following:
            return "Following convoy"
        case .holdingBetweenCycles:
            return "Holding position"
        case .streamFailed:
            return "Formation follow unavailable"
        }
    }
}

/// One bound wingman row in a primary squad (planner / follow subsystem).
struct MissionRunSquadWingmanBinding: Equatable, Sendable {
    let assignment: MissionRunAssignment
    let rosterDevice: RosterDevice
}
