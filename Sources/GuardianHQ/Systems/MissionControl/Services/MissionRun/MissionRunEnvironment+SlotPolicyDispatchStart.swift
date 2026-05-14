import Foundation

extension MissionRunEnvironment {

    /// §4: when a rostered dispatch **leaves** MRE toward fleet, advance the slot **commanded** lane (observed unchanged).
    internal func applySlotPolicyDispatchStartIfNeeded(issued: MissionRunIssuedCommand) {
        let taskID = systems.logging.effectiveTaskFields(forAssignmentID: issued.assignmentID).0
        guard let next = MissionRunPolicySlotDispatchStart.commandedSlotStateIfDispatchLeavesMRE(
            issued: issued,
            effectiveTaskID: taskID,
            abortWindDownIssuedTaskIDs: missionTaskAbortWindDownIssuedTaskIDs,
            completeWindDownIssuedTaskIDs: missionTaskCompleteWindDownIssuedTaskIDs,
            sessionPhase: sessionPhase
        ) else { return }
        _ = applySlotLifecycleLaneMutation(
            .advanceCommandedLaneForDispatchStart(assignmentID: issued.assignmentID, commanded: next)
        )
    }
}
