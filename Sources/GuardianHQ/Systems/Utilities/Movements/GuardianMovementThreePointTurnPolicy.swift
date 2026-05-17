import Foundation

/// Tuning for wheeled / tracked UGV in-slot heading alignment via one slow 3-point attempt.
enum GuardianMovementThreePointTurnPolicy {
    /// Position must be at least this good before any heading movement runs (m).
    static let formationPositionLockedMaxDistM: Double = MissionSquadConvoyFollowControlPolicy.pursuitSnapArrivalM
    static let formationPositionLockedMaxAlongM: Double = 0.4
    static let formationPositionLockedMaxLateralM: Double = 0.4
    /// Start heading maneuver when |error| exceeds assembly tolerance (deg).
    static let headingManeuverStartErrorDeg: Double = MissionSquadConvoyFollowControlPolicy.convoyAssemblyHeadingToleranceDeg
    /// If the vehicle drifts farther than this from slot during the maneuver, fail (m).
    static let abortIfDistFromSlotExceedsM: Double = 0.85
    /// Whole maneuver timeout — then fail (s).
    static let wholeManeuverTimeoutS: TimeInterval = 45
    /// Reverse leg body speed (m/s, magnitude) — slow.
    static let reverseLegForwardMS: Double = 0.18
    /// Forward leg body speed (m/s) — slow.
    static let forwardLegForwardMS: Double = 0.22
    static let minReverseArcLengthM: Double = 1.0
    static let reverseArcLengthM: Double = 2.0
    static let maxMidLegHeadingOffsetDeg: Double = 42
    static let routeWaypointCountPerLeg: Int = 4
    static let waypointArrivalM: Double = 0.32
    /// Yaw rate scale during 3-point legs (fraction of pursuit max).
    static let legYawRateScale: Double = 0.35
    static let maxLegYawRateDegS: Double = 12
}
