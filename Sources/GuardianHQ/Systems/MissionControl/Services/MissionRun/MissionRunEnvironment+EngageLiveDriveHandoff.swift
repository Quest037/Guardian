import Foundation

extension MissionRunEnvironment {

    /// Queues operator **park** or **loiter** stabilisation through the same ``MissionRunCommandSubsystem``
    /// catalogue path as other MRE fleet dispatches (run log + async fleet ack). Requires a non-empty
    /// ``MissionRunAssignment/attachedFleetVehicleToken`` storage key.
    ///
    /// See ``HandOffToDoList.md`` (Engage flow) — later steps add tab switch, queue cancel, and ``InLiveDrive`` gating.
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
}
