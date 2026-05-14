import Foundation

/// §3 **failure classes** for roster slot terminals: disposition when task-level auto-triage (``TaskRosterAssignmentStatesToDo.md`` §3) is implemented.
///
/// v1 **push** maps every wind-down catalogue/recipe failure on policy-shaped traffic to ``MissionRunAssignmentSlotState/policyFailed`` without a persisted sub-reason on the row. **Pull** v1 only promotes ``policySucceeded`` — it does not author a distinct failure terminal.
enum MissionRunSlotPolicyFailureClass: String, Equatable, CaseIterable {
    /// Catalogue or wrapped recipe reported failure on a policy-filtered wind-down dispatch (mission clear, loiter, park, RTL, move+park, vehicle park).
    case fleetWindDownStepRejected
    /// Roster row has no usable fleet binding for that policy leg — operational block, not a fleet “ack false” on a dispatched command.
    case noVehicleBoundForSlotRow
}

enum MissionRunSlotPolicyFailureRollup {
    /// v1 product lock: **no** failure class may satisfy “task policy resolved” gates or insert into mission-end ack sets without operator action.
    static func allowsTaskLevelAutoTriageRollup(_ failureClass: MissionRunSlotPolicyFailureClass) -> Bool {
        switch failureClass {
        case .fleetWindDownStepRejected, .noVehicleBoundForSlotRow:
            false
        }
    }

    /// Classifies terminal slot states that should **block** task rollup until the operator or a future retry path clears them.
    static func failureClass(forSlotTerminal state: MissionRunAssignmentSlotState) -> MissionRunSlotPolicyFailureClass? {
        switch state {
        case .policyFailed:
            return .fleetWindDownStepRejected
        case .blockedNoVehicle:
            return .noVehicleBoundForSlotRow
        default:
            return nil
        }
    }

    /// When push evidence would set ``policyFailed`` for this issued row, the rollup class is always ``fleetWindDownStepRejected`` until per-row failure reasons exist.
    static func failureClassIfPolicyFailedIssued(_ issued: MissionRunIssuedCommand) -> MissionRunSlotPolicyFailureClass? {
        guard MissionRunPolicySlotPushEvidence.terminalSlotStateIfAffected(issued: issued, success: false) == .policyFailed else {
            return nil
        }
        return .fleetWindDownStepRejected
    }
}
