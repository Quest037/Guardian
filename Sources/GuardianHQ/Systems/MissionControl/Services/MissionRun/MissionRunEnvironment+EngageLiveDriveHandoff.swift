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

    /// Operator **Return to Launch** for one roster row (preferential abort RTL recipe).
    @discardableResult
    func issueOperatorSquadReturnToLaunchDispatch(
        assignment: MissionRunAssignment,
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
        let planningHub: FleetHubVehicleTelemetry? = {
            guard let token = FleetMissionVehicleToken(storageKey: tokenKey),
                  let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
            else { return nil }
            return fleetLink.hubTelemetry(forVehicleID: vehicleID)
        }()
        let dispatch = returnToLaunchFleetDispatch(
            assignment: assignment,
            mission: template,
            planningHub: planningHub
        )
        let issued = MissionRunIssuedCommand(
            assignmentID: assignment.id,
            slotName: assignment.slotName,
            vehicleTokenKey: tokenKey,
            dispatch: dispatch,
            issuer: .operator,
            issuerKey: "operator.squadTriage.returnToLaunch",
            category: .missionControl
        )
        let event = systems.commands.dispatchCommand(issued, fleetLink: fleetLink, sitl: sitl)
        appendEvent(event)
        return event
    }

    func resolveOperatorContinueAfterParkIntent(
        assignment: MissionRunAssignment,
        rosterDevice: RosterDevice?,
        mission: Mission,
        fleetLink: FleetLinkService,
        vehicleID: String?
    ) -> MissionRunOperatorContinueAfterParkIntent {
        MissionControlOperatorContinueAfterParkPolicy.resolve(
            assignment: assignment,
            rosterDevice: rosterDevice,
            mission: mission,
            run: self,
            fleetLink: fleetLink,
            vehicleID: vehicleID
        )
    }

    /// Dispatches **Continue** per ``resolveOperatorContinueAfterParkIntent`` (resume mission vs retry end protocol).
    ///
    /// For policy retry intents, `onPolicyWindDownJoltFinished` runs on the main actor after the async fleet jolt completes.
    @discardableResult
    func issueOperatorContinueAfterPark(
        assignment: MissionRunAssignment,
        rosterDevice: RosterDevice?,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        generalSettings: GeneralSettingsStore?,
        onPolicyWindDownJoltFinished: (@MainActor (MissionRunOperatorPolicyWindDownJoltOutcome) -> Void)? = nil
    ) -> MissionRunEvent {
        let intent = resolveOperatorContinueAfterParkIntent(
            assignment: assignment,
            rosterDevice: rosterDevice,
            mission: mission,
            fleetLink: fleetLink,
            vehicleID: resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl)
        )
        switch intent {
        case .unavailable(let reason):
            let fields = systems.logging.effectiveTaskFields(forAssignmentID: assignment.id)
            let event = MissionRunEvent(
                level: .warning,
                taskID: fields.0,
                taskLabel: fields.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.operatorContinueAfterParkUnavailable,
                templateParams: [
                    "slot": assignment.slotName,
                    "slotID": assignment.id.uuidString,
                    "reason": reason,
                ]
            )
            appendEvent(event)
            return event
        case .resumeMission:
            return issueOperatorContinueMissionAfterParkDispatch(
                assignment: assignment,
                kind: .armModeMissionStart,
                fleetLink: fleetLink,
                sitl: sitl
            )
        case .retryCompleteWindDown, .retryAbortWindDown:
            return issueOperatorRetryPolicyWindDownAfterPark(
                assignment: assignment,
                intent: intent,
                fleetLink: fleetLink,
                sitl: sitl,
                generalSettings: generalSettings,
                onFinished: onPolicyWindDownJoltFinished
            )
        }
    }

    private func issueOperatorRetryPolicyWindDownAfterPark(
        assignment: MissionRunAssignment,
        intent: MissionRunOperatorContinueAfterParkIntent,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        generalSettings: GeneralSettingsStore?,
        onFinished: (@MainActor (MissionRunOperatorPolicyWindDownJoltOutcome) -> Void)? = nil
    ) -> MissionRunEvent {
        let fields = systems.logging.effectiveTaskFields(forAssignmentID: assignment.id)
        guard let ctx = effectiveExecutionContextForDispatch() else {
            let event = MissionRunEvent(
                level: .warning,
                taskID: fields.0,
                taskLabel: fields.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.operatorContinueAfterParkUnavailable,
                templateParams: [
                    "slot": assignment.slotName,
                    "slotID": assignment.id.uuidString,
                    "reason": "Mission run is not in a state that can dispatch fleet commands.",
                ]
            )
            appendEvent(event)
            return event
        }
        attachServices(fleetLink: fleetLink, sitl: sitl, generalSettings: generalSettings)
        let label = intent.operatorShortLabel
        let joltMode: MissionRunOperatorPolicyWindDownJoltMode
        switch intent {
        case .retryCompleteWindDown: joltMode = .complete
        case .retryAbortWindDown: joltMode = .abort
        default:
            let event = MissionRunEvent(
                level: .warning,
                taskID: fields.0,
                taskLabel: fields.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.operatorContinueAfterParkUnavailable,
                templateParams: [
                    "slot": assignment.slotName,
                    "slotID": assignment.id.uuidString,
                    "reason": "Unsupported retry intent.",
                ]
            )
            appendEvent(event)
            return event
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.systems.executor.performOperatorJoltPolicyWindDown(
                target: .squad(primaryAssignmentID: assignment.id),
                mode: joltMode,
                context: ctx
            )
            switch outcome {
            case .redispatched:
                self.systems.logging.appendLogEvent(
                    level: .info,
                    taskID: fields.0,
                    taskLabel: fields.1,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.operatorPolicyWindDownJoltRedispatched,
                    templateParams: [
                        "slot": assignment.slotName,
                        "slotID": assignment.id.uuidString,
                        "intent": label,
                    ]
                )
            case .failedNoCommands:
                self.systems.logging.appendLogEvent(
                    level: .warning,
                    taskID: fields.0,
                    taskLabel: fields.1,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.operatorContinueAfterParkUnavailable,
                    templateParams: [
                        "slot": assignment.slotName,
                        "slotID": assignment.id.uuidString,
                        "reason": "No fleet commands were built for \(label).",
                    ]
                )
            case .failedNoVehicle:
                self.systems.logging.appendLogEvent(
                    level: .warning,
                    taskID: fields.0,
                    taskLabel: fields.1,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.operatorContinueAfterParkUnavailable,
                    templateParams: [
                        "slot": assignment.slotName,
                        "slotID": assignment.id.uuidString,
                        "reason": "No linked vehicle stream for \(label).",
                    ]
                )
            }
            onFinished?(outcome)
        }
        let event = MissionRunEvent(
            level: .info,
            taskID: fields.0,
            taskLabel: fields.1,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.operatorContinueAfterParkQueued,
            templateParams: [
                "slot": assignment.slotName,
                "slotID": assignment.id.uuidString,
                "intent": label,
            ]
        )
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
    /// ``templateParams``: `slot`, `slotID`, `intent`.
    static let operatorContinueAfterParkQueued = "missioncontrol.mre.operator.continue_after_park_queued"
    /// ``templateParams``: `slot`, `slotID`, `reason`.
    static let operatorContinueAfterParkUnavailable = "missioncontrol.mre.operator.continue_after_park_unavailable"
    /// ``templateParams``: `slot`, `slotID`, `intent`.
    static let operatorPolicyWindDownJoltEscalation =
        "missioncontrol.mre.operator.policy_wind_down_jolt_escalation"
    /// ``templateParams``: `slot`, `slotID`, `intent`.
    static let operatorPolicyWindDownJoltRedispatched =
        "missioncontrol.mre.operator.policy_wind_down_jolt_redispatched"
    /// ``templateParams``: `task`, `vehicleID`.
    static let operatorPolicyWindDownJoltParkStabilizationFailed =
        "missioncontrol.mre.operator.policy_wind_down_jolt_park_stabilization_failed"
}
