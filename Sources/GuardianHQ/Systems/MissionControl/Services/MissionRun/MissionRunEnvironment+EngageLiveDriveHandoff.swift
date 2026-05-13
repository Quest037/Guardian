import Foundation

extension MissionRunEnvironment {

    /// Queues operator **park** or **loiter** stabilisation through the same ``MissionRunCommandSubsystem``
    /// catalogue path as other MRE fleet dispatches (run log + async fleet ack). Requires a non-empty
    /// ``MissionRunAssignment/attachedFleetVehicleToken`` storage key.
    ///
    /// Engage flow (``README.md`` Live Drive): stabilize (elsewhere), pending batch cancel here, ``noteOperatorLiveDriveHandoffActive`` from MC‑R Engage; handoff clears when Live Drive control session ends for that vehicle.
    @discardableResult
    func issueOperatorEngageStabilizeDispatch(
        assignment: MissionRunAssignment,
        kind: MissionRunEngageStabilizeDispatchKind,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> MissionRunEvent {
        let tokenKey = (assignment.attachedFleetVehicleToken ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = systems.logging.effectiveTaskFields(forAssignmentID: assignment.id)
        guard !tokenKey.isEmpty else {
            let event = MissionRunEvent(
                level: .warning,
                taskID: fields.0,
                taskLabel: fields.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.commandInvalidToken,
                templateParams: [
                    "slot": assignment.slotName,
                    "slotID": assignment.id.uuidString,
                ]
            )
            appendEvent(event)
            return event
        }

        let issued = MissionRunIssuedCommand(
            assignmentID: assignment.id,
            slotName: assignment.slotName,
            vehicleTokenKey: tokenKey,
            dispatch: kind.missionRunFleetDispatch,
            issuer: .operator,
            issuerKey: "operator.engageLiveDrive.stabilize.\(kind.rawValue)",
            category: .missionControl
        )
        let event = systems.commands.dispatchCommand(issued, fleetLink: fleetLink, sitl: sitl)
        appendEvent(event)
        return event
    }

    /// Queues the **continue mission** recipe after PX4 UGV operator park (same command subsystem path as stabilize).
    @discardableResult
    func issueOperatorContinueMissionAfterParkDispatch(
        assignment: MissionRunAssignment,
        kind: MissionRunOperatorContinueMissionAfterParkDispatchKind,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> MissionRunEvent {
        let tokenKey = (assignment.attachedFleetVehicleToken ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = systems.logging.effectiveTaskFields(forAssignmentID: assignment.id)
        guard !tokenKey.isEmpty else {
            let event = MissionRunEvent(
                level: .warning,
                taskID: fields.0,
                taskLabel: fields.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.commandInvalidToken,
                templateParams: [
                    "slot": assignment.slotName,
                    "slotID": assignment.id.uuidString,
                ]
            )
            appendEvent(event)
            return event
        }

        let issued = MissionRunIssuedCommand(
            assignmentID: assignment.id,
            slotName: assignment.slotName,
            vehicleTokenKey: tokenKey,
            dispatch: kind.missionRunFleetDispatch,
            issuer: .operator,
            issuerKey: "operator.engageLiveDrive.continueMissionAfterPark.\(kind.rawValue)",
            category: .missionControl
        )
        let event = systems.commands.dispatchCommand(issued, fleetLink: fleetLink, sitl: sitl)
        appendEvent(event)
        return event
    }

    /// Cancels every pending tagged executor batch before navigating to Live Drive so queued mission work
    /// does not race manual control (Engage handoff; see ``README.md`` Live Drive control session).
    ///
    /// Cancels **all** ``MissionRunCommandQueueTag`` buckets (`abort`, `complete`, `missionStart`,
    /// `reserveSwapPostCommit`). Call only when the operator path has already satisfied stabilize (§1); if a
    /// reserve-swap post-commit pipeline is mid-flight, cancelling `reserveSwapPostCommit` can strand handoff —
    /// product should not offer **Engage** in that window until swap work completes or is aborted separately.
    @discardableResult
    func cancelPendingExecutorBatchesForOperatorLiveDriveEngage(assignment: MissionRunAssignment) -> Int {
        let fields = systems.logging.effectiveTaskFields(forAssignmentID: assignment.id)
        let removed = systems.executor.cancelPendingCommandBatches(tags: Set(MissionRunCommandQueueTag.allCases))
        if removed > 0 {
            systems.logging.appendLogEvent(
                level: .info,
                taskID: fields.0,
                taskLabel: fields.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.executorPendingBatchesCancelledForLiveDriveEngage,
                templateParams: [
                    "slot": assignment.slotName,
                    "slotID": assignment.id.uuidString,
                    "removedCount": String(removed),
                ]
            )
        }
        return removed
    }
}

extension MissionRunLogTemplateKey {
    /// ``templateParams``: `slot`, `slotID`, `removedCount`.
    static let executorPendingBatchesCancelledForLiveDriveEngage =
        "missioncontrol.mre.executor.pending_batches_cancelled_live_drive"
}
