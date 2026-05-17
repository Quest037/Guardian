import Foundation

/// Body-frame OFFBOARD / Guided pursuit output from the movement planner.
struct GuardianMovementPursuitPlan: Equatable, Sendable {
    let movementID: GuardianMovementID
    /// Body forward (m/s); negative = astern.
    let bodyForwardMS: Double
    /// Body right (m/s); only non-zero when ``movementID`` is ``GuardianMovementID/strafe`` and supported.
    let bodyRightMS: Double
    let yawspeedDegS: Double
    /// When set, OFFBOARD position / velocity pursues this plotted carrot instead of the convoy leash.
    let pursuitSetpoint: RouteCoordinate?
    /// True when a sequence failed and the vehicle must hold for operator analysis (no compensation).
    let sequenceHalted: Bool
    /// Operator / log strip summary.
    let summary: String

    init(
        movementID: GuardianMovementID,
        bodyForwardMS: Double,
        bodyRightMS: Double,
        yawspeedDegS: Double,
        pursuitSetpoint: RouteCoordinate? = nil,
        sequenceHalted: Bool = false,
        summary: String
    ) {
        self.movementID = movementID
        self.bodyForwardMS = bodyForwardMS
        self.bodyRightMS = bodyRightMS
        self.yawspeedDegS = yawspeedDegS
        self.pursuitSetpoint = pursuitSetpoint
        self.sequenceHalted = sequenceHalted
        self.summary = summary
    }
}
