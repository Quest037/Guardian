import Foundation

/// Per-vehicle state for one plotted ``GuardianMovementID/threePointReverse`` attempt (UGV).
struct GuardianMovementSlotSequenceState: Equatable, Sendable {
    let movementID: GuardianMovementID
    var status: GuardianMovementThreePointSequenceStatus
    var phase: GuardianMovementThreePointPhase
    var targetHeadingDeg: Double
    var sequenceStartedAt: Date
    var phaseStartedAt: Date
    var route: GuardianMovementThreePointRoute
    var legWaypointIndex: Int
    var failureReason: String?
}
