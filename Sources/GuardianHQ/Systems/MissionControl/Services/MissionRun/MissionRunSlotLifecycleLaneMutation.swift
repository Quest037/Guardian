import Foundation

/// Typed mutations for ``MissionRunAssignment/slotLifecycleLanes`` — **single writer** choke point for roster slot policy lanes (``TaskRosterAssignmentStatesToDo.md`` §4).
///
/// Storage remains **on-row** (README **Roster slot state storage** — option **(a)**). Do not assign ``slotLifecycleLanes`` from feature code outside ``MissionRunEnvironment/applySlotLifecycleLaneMutation`` except Codable decode / run reset paths that wholesale replace ``assignments``.
enum MissionRunSlotLifecycleLaneMutation: Equatable {
    /// Set **commanded** and **observed** to the same terminal (§3 push / pull policy terminals).
    case setCommandedAndObservedToSame(assignmentID: UUID, terminal: MissionRunAssignmentSlotState)
    /// §4 dispatch start: set **commanded** only; ``observed`` stays for hub / §3 evidence.
    case advanceCommandedLaneForDispatchStart(assignmentID: UUID, commanded: MissionRunAssignmentSlotState)
    /// §4 dispatch outcome for mission-upload / between-cycles traffic: sync ``observed`` to ``commanded`` on success, or ``policyFailed`` on failure (§3 policy terminals use ``setCommandedAndObservedToSame`` instead).
    case syncObservedAfterNonPolicyFleetOutcome(assignmentID: UUID, success: Bool)
}

extension MissionRunEnvironment {

    /// Applies one slot-lane mutation. **Single writer** for policy lane fields; returns whether ``assignments`` changed.
    @discardableResult
    internal func applySlotLifecycleLaneMutation(_ mutation: MissionRunSlotLifecycleLaneMutation) -> Bool {
        switch mutation {
        case .setCommandedAndObservedToSame(let assignmentID, let terminal):
            return applySetCommandedAndObservedToSameSlotLanes(assignmentID: assignmentID, terminal: terminal)
        case .advanceCommandedLaneForDispatchStart(let assignmentID, let commanded):
            return applyAdvanceCommandedLaneForDispatchStart(assignmentID: assignmentID, commanded: commanded)
        case .syncObservedAfterNonPolicyFleetOutcome(let assignmentID, let success):
            return applySyncObservedAfterNonPolicyFleetOutcome(assignmentID: assignmentID, success: success)
        }
    }

    /// §3 push / pull helper — prefer ``applySlotLifecycleLaneMutation(.setCommandedAndObservedToSame(…))`` in new code; name retained for existing call sites.
    @discardableResult
    internal func setSlotPolicyLanesBoth(assignmentID: UUID, terminal: MissionRunAssignmentSlotState) -> Bool {
        applySlotLifecycleLaneMutation(.setCommandedAndObservedToSame(assignmentID: assignmentID, terminal: terminal))
    }

    private func applySetCommandedAndObservedToSameSlotLanes(
        assignmentID: UUID,
        terminal: MissionRunAssignmentSlotState
    ) -> Bool {
        guard let idx = assignments.firstIndex(where: { $0.id == assignmentID }) else { return false }
        var row = assignments[idx]
        var lanes = row.slotLifecycleLanes ?? MissionRunAssignmentSlotStateLanes()
        if lanes.commanded == terminal, lanes.observed == terminal {
            return false
        }
        lanes.observed = terminal
        lanes.commanded = terminal
        row.slotLifecycleLanes = lanes
        assignments[idx] = row
        return true
    }

    private func applyAdvanceCommandedLaneForDispatchStart(
        assignmentID: UUID,
        commanded next: MissionRunAssignmentSlotState
    ) -> Bool {
        guard let idx = assignments.firstIndex(where: { $0.id == assignmentID }) else { return false }
        var row = assignments[idx]
        var lanes = row.slotLifecycleLanes ?? MissionRunAssignmentSlotStateLanes()
        let from = lanes.commanded
        if from == next { return false }
        guard Self.slotCommandedLaneAllowsDispatchStartTransition(from: from, to: next) else { return false }
        lanes.commanded = next
        row.slotLifecycleLanes = lanes
        assignments[idx] = row
        return true
    }

    /// Prevents §4 dispatch-start from clobbering §3 terminals or fighting in-flight policy lanes.
    private static func slotCommandedLaneAllowsDispatchStartTransition(
        from: MissionRunAssignmentSlotState,
        to: MissionRunAssignmentSlotState
    ) -> Bool {
        switch to {
        case .policyAborting, .policyCompleting:
            switch from {
            case .policySucceeded, .policyFailed, .supersededReassigned, .notApplicableEmptySlot:
                return false
            default:
                return true
            }
        case .executingMission, .staging:
            switch from {
            case .idle, .staging, .betweenCycles, .executingMission:
                return true
            default:
                return false
            }
        case .betweenCycles:
            switch from {
            case .idle, .staging, .betweenCycles, .executingMission:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    private func applySyncObservedAfterNonPolicyFleetOutcome(assignmentID: UUID, success: Bool) -> Bool {
        guard let idx = assignments.firstIndex(where: { $0.id == assignmentID }) else { return false }
        var row = assignments[idx]
        var lanes = row.slotLifecycleLanes ?? MissionRunAssignmentSlotStateLanes()
        let newObserved: MissionRunAssignmentSlotState
        if success {
            if lanes.commanded.isCommandedTerminalOrNonParticipatingMergeLock { return false }
            newObserved = lanes.commanded
        } else {
            switch lanes.commanded {
            case .policySucceeded, .supersededReassigned, .notApplicableEmptySlot:
                return false
            default:
                newObserved = .policyFailed
            }
        }
        if lanes.observed == newObserved { return false }
        lanes.observed = newObserved
        row.slotLifecycleLanes = lanes
        assignments[idx] = row
        return true
    }
}
