import Foundation

extension MissionRunEnvironment {

    /// §3 policy terminals + §4 **dispatch outcome** for tracked non-policy traffic (mission upload / between-cycles).
    ///
    /// **Policy-shaped** ``MissionRunIssuedCommand`` rows still use ``MissionRunPolicySlotPushEvidence`` → both lanes
    /// (same as legacy ``applySlotPolicyPushEvidence``). **Otherwise**, mission-execute upload / between-cycles rows
    /// sync **observed** to match **commanded** on fleet success, or set **observed** to ``policyFailed`` on failure
    /// (catalogue timeouts, ``FleetCommandAsyncOutcome`` failures, and ``FleetRecipeOutcome`` failures all arrive as
    /// ``success == false`` at this boundary; recipe escalation resolves before outcomes reach here).
    func applySlotDispatchOutcomeEvidence(issued: MissionRunIssuedCommand, success: Bool) {
        if let terminal = MissionRunPolicySlotPushEvidence.terminalSlotStateIfAffected(issued: issued, success: success) {
            let changed = setSlotPolicyLanesBoth(assignmentID: issued.assignmentID, terminal: terminal)
            if changed {
                if allowsMissionEndAutoSettlement {
                    applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([issued.assignmentID]))
                } else {
                    refreshDerivedTaskStates()
                }
            }
            return
        }
        guard MissionRunPolicySlotDispatchStart.tracksSlotLanesThroughFleetOutcome(issued: issued) else { return }
        _ = applySlotLifecycleLaneMutation(
            .syncObservedAfterNonPolicyFleetOutcome(assignmentID: issued.assignmentID, success: success)
        )
    }

    /// Legacy §3 name — forwards to ``applySlotDispatchOutcomeEvidence(issued:success:)`` (same catalogue / recipe ack boundary).
    func applySlotPolicyPushEvidence(issued: MissionRunIssuedCommand, success: Bool) {
        applySlotDispatchOutcomeEvidence(issued: issued, success: success)
    }
}
