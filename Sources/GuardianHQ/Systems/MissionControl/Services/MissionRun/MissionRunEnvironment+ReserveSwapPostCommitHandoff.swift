import Foundation
import Mavsdk

extension MissionRunEnvironment {

    /// Canonical **post-commit** entrypoint after ``MissionControlStore/recompileMissionControlPlanAfterFloatingReserveSwap``
    /// (or equivalent plan refresh): resolves **vacancy** vs **displaced** fleet stream rows, emits
    /// ``MissionRunReserveSwapPipelinePhase/postCommitHandoff``, then (when the run is **live executing** with dispatch
    /// context) enqueues **displaced** catalogue mission clear, **vacancy** mission upload+arm+start (standard or
    /// ``FleetMissionRecipeRegistrations/doMissionUploadStartItemRecipeName`` when displaced hub mission progress &gt; 0),
    /// and **displaced** reserve-swap preference wind-down (RTL / map rally+park / loiter / park) in one immediate batch.
    func beginPostCommitReserveSwapHandoffPipeline(
        correlation: MissionRunReserveRecipeRunnerCorrelation,
        triggerSource: String
    ) {
        let floatingPool: MissionRunReservePool?
        let floatingSlotID: UUID?
        if let slotID = correlation.reservePoolSlotID {
            floatingPool = reservePool(forTaskID: correlation.missionTaskID)
            floatingSlotID = slotID
        } else {
            floatingPool = nil
            floatingSlotID = nil
        }
        let outcome = MissionRunReserveSwapPostCommitStreamResolver.resolve(
            assignments: assignments,
            vacancyAssignmentID: correlation.vacancyAssignmentID,
            displacedStreamAssignmentID: correlation.reserveStreamAssignmentID,
            floatingReservePool: floatingPool,
            floatingReservePoolSlotID: floatingSlotID
        )
        switch outcome {
        case .resolved(let snap):
            let detail = "Post-commit handoff (\(triggerSource)); newActiveToken=\(snap.vacancyFleetStorageKey) displacedActiveToken=\(snap.displacedFleetStorageKey)."
            appendReserveSwapPipelinePhaseLog(
                phase: .postCommitHandoff,
                passed: true,
                correlation: correlation,
                detail: detail
            )
            enqueueReserveSwapPostCommitHandoffFleetWork(
                correlation: correlation,
                triggerSource: triggerSource,
                snap: snap
            )
        default:
            let detail = "Post-commit handoff resolution failed (\(triggerSource)): \(outcome.logDetailFragment)."
            appendReserveSwapPipelinePhaseLog(
                phase: .postCommitHandoff,
                passed: false,
                correlation: correlation,
                detail: detail
            )
        }
    }

    private func enqueueReserveSwapPostCommitHandoffFleetWork(
        correlation: MissionRunReserveRecipeRunnerCorrelation,
        triggerSource: String,
        snap: MissionRunReserveSwapPostCommitStreamSnapshot
    ) {
        let live = MissionRunReserveSwapMidCycleExecutionInvariantPolicy.isLiveExecutingSession(
            status: status,
            sessionPhase: sessionPhase
        )
        if !live {
            appendReserveSwapPipelinePhaseLog(
                phase: .displacedMissionClear,
                passed: true,
                correlation: correlation,
                detail: "Skipped catalogue mission clear on displaced stream (run not in live executing session; \(triggerSource))."
            )
            appendReserveSwapPipelinePhaseLog(
                phase: .missionUpload,
                passed: true,
                correlation: correlation,
                detail: "Skipped vacancy mission upload recipe (run not in live executing session; \(triggerSource))."
            )
            appendReserveSwapPipelinePhaseLog(
                phase: .displacedFleetWindDown,
                passed: true,
                correlation: correlation,
                detail: "Skipped displaced reserve-swap wind-down (run not in live executing session; \(triggerSource))."
            )
            return
        }
        guard let ctx = effectiveExecutionContextForDispatch(),
              let mission = ctx.missionProvider() ?? template,
              let fleetLink,
              let sitl
        else {
            appendReserveSwapPipelinePhaseLog(
                phase: .displacedMissionClear,
                passed: false,
                correlation: correlation,
                detail: "No execution context for displaced-stream mission clear (\(triggerSource))."
            )
            appendReserveSwapPipelinePhaseLog(
                phase: .missionUpload,
                passed: false,
                correlation: correlation,
                detail: "No execution context for vacancy mission upload (\(triggerSource))."
            )
            appendReserveSwapPipelinePhaseLog(
                phase: .displacedFleetWindDown,
                passed: false,
                correlation: correlation,
                detail: "No execution context for displaced reserve-swap wind-down (\(triggerSource))."
            )
            return
        }

        let displacedRow: MissionRunAssignment?
        if let slotID = correlation.reservePoolSlotID {
            let pool = reservePool(forTaskID: correlation.missionTaskID)
            if let slot = pool.entries.first(where: { $0.id == slotID }) {
                displacedRow = MissionRunAssignment.syntheticForReservePool(slot: slot)
            } else {
                displacedRow = nil
            }
        } else {
            displacedRow = assignments.first(where: { $0.id == correlation.reserveStreamAssignmentID })
        }
        var commands: [MissionRunIssuedCommand] = []

        if let displacedRow,
           let clear = MissionRunPlannerSubsystem.catalogueMissionClearCommand(
               forAssignment: displacedRow,
               issuerKey: MissionRunCommandIssuerKey.plannerReserveSwapPostCommit
           ) {
            commands.append(clear)
        } else if displacedRow != nil {
            appendReserveSwapPipelinePhaseLog(
                phase: .displacedMissionClear,
                passed: true,
                correlation: correlation,
                detail: "Skipped catalogue mission clear (displaced row has no parsable fleet token; \(triggerSource))."
            )
        } else {
            appendReserveSwapPipelinePhaseLog(
                phase: .displacedMissionClear,
                passed: false,
                correlation: correlation,
                detail: "Displaced stream assignment row missing after resolve (\(triggerSource))."
            )
        }

        guard let vacancyRow = assignments.first(where: { $0.id == correlation.vacancyAssignmentID }),
              let vacToken = vacancyRow.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !vacToken.isEmpty,
              FleetMissionVehicleToken(storageKey: vacToken) != nil
        else {
            appendReserveSwapPipelinePhaseLog(
                phase: .missionUpload,
                passed: false,
                correlation: correlation,
                detail: "Vacancy row missing or has no parsable fleet token after commit (\(triggerSource))."
            )
            appendDisplacedReserveSwapWindDownCommands(
                commands: &commands,
                mission: mission,
                displacedRow: displacedRow,
                correlation: correlation,
                triggerSource: triggerSource
            )
            enqueueReserveSwapPostCommitBatchIfNonEmpty(
                commands: commands,
                context: ctx,
                correlation: correlation,
                triggerSource: triggerSource
            )
            return
        }

        guard let squad = reserveSwapPlannedSquadForVacancy(
            vacancyAssignmentID: correlation.vacancyAssignmentID,
            mission: mission,
            taskID: correlation.missionTaskID
        ) else {
            appendReserveSwapPipelinePhaseLog(
                phase: .missionUpload,
                passed: false,
                correlation: correlation,
                detail: "No compiled task squad mission for vacancy task \(correlation.missionTaskID) (\(triggerSource))."
            )
            appendDisplacedReserveSwapWindDownCommands(
                commands: &commands,
                mission: mission,
                displacedRow: displacedRow,
                correlation: correlation,
                triggerSource: triggerSource
            )
            enqueueReserveSwapPostCommitBatchIfNonEmpty(
                commands: commands,
                context: ctx,
                correlation: correlation,
                triggerSource: triggerSource
            )
            return
        }

        let missionItemsJSON: String
        do {
            let plan = Mavsdk.Mission.MissionPlan(missionItems: squad.missionItems)
            missionItemsJSON = try FleetVehicleCommandMissionItemPayload.encodeMissionPlanToJSON(plan: plan)
        } catch {
            appendReserveSwapPipelinePhaseLog(
                phase: .missionUpload,
                passed: false,
                correlation: correlation,
                detail: "Mission plan encode failed: \(error.localizedDescription) (\(triggerSource))."
            )
            appendDisplacedReserveSwapWindDownCommands(
                commands: &commands,
                mission: mission,
                displacedRow: displacedRow,
                correlation: correlation,
                triggerSource: triggerSource
            )
            enqueueReserveSwapPostCommitBatchIfNonEmpty(
                commands: commands,
                context: ctx,
                correlation: correlation,
                triggerSource: triggerSource
            )
            return
        }

        let hub = reserveSwapHubMissionProgressForDisplacedStorageKey(
            snap.displacedFleetStorageKey,
            fleetLink: fleetLink,
            sitl: sitl
        )
        let resumeIndex = MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection.handoffMissionStartItemIndex(
            hubMissionProgressCurrent: hub.current,
            hubMissionProgressTotal: hub.total
        )

        let recipeName: FleetRecipeName
        let recipeParams: FleetRecipeParameters
        if let idx = resumeIndex {
            recipeName = FleetMissionRecipeRegistrations.doMissionUploadStartItemRecipeName
            recipeParams = FleetRecipeParameters(values: [
                "missionItemsJSON": .string(missionItemsJSON),
                "missionStartItemIndex": .integer(Int64(idx)),
            ])
        } else {
            recipeName = FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName
            recipeParams = FleetRecipeParameters(values: [
                "missionItemsJSON": .string(missionItemsJSON),
            ])
        }

        let uploadIssued = MissionRunIssuedCommand(
            assignmentID: vacancyRow.id,
            slotName: vacancyRow.slotName,
            vehicleTokenKey: vacToken,
            dispatch: .recipe(
                name: recipeName,
                parameters: recipeParams
            ),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerReserveSwapPostCommit,
            category: .missionControl
        )
        commands.append(uploadIssued)

        appendDisplacedReserveSwapWindDownCommands(
            commands: &commands,
            mission: mission,
            displacedRow: displacedRow,
            correlation: correlation,
            triggerSource: triggerSource
        )

        enqueueReserveSwapPostCommitBatchIfNonEmpty(
            commands: commands,
            context: ctx,
            correlation: correlation,
            triggerSource: triggerSource
        )
    }

    /// Appends at most one optimistic wind-down command for the **displaced** stream row (same shapes as
    /// ``MissionRunExecutionSubsystem/buildReserveSwapPolicyWindDownCommands``) and emits ``displacedFleetWindDown`` phase logs.
    private func appendDisplacedReserveSwapWindDownCommands(
        commands: inout [MissionRunIssuedCommand],
        mission: Mission,
        displacedRow: MissionRunAssignment?,
        correlation: MissionRunReserveRecipeRunnerCorrelation,
        triggerSource: String
    ) {
        guard let displacedRow else {
            appendReserveSwapPipelinePhaseLog(
                phase: .displacedFleetWindDown,
                passed: false,
                correlation: correlation,
                detail: "Displaced stream assignment row missing; cannot run reserve-swap wind-down (\(triggerSource))."
            )
            return
        }
        let trimmedToken = displacedRow.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedToken.isEmpty, FleetMissionVehicleToken(storageKey: trimmedToken) != nil else {
            appendReserveSwapPipelinePhaseLog(
                phase: .displacedFleetWindDown,
                passed: true,
                correlation: correlation,
                detail: "Skipped displaced reserve-swap wind-down (displaced row has no parsable fleet token; \(triggerSource))."
            )
            return
        }

        let normalizedChain = MissionRunReserveSwapTactic.normalizedPreferenceChain(
            MissionRunPolicyResolution.resolvedReserveSwapPreferenceChain(assignment: displacedRow, mission: mission)
        )
        let noneOnly = normalizedChain.count == 1 && normalizedChain[0].kind == .none

        let wind: [MissionRunIssuedCommand]
        if assignments.contains(where: { $0.id == displacedRow.id }) {
            wind = systems.executor.buildReserveSwapPolicyWindDownCommands(
                limitedToAssignmentIDs: Set([displacedRow.id])
            )
        } else if let one = systems.executor.buildReserveSwapPolicyWindDownCommand(forExplicitAssignment: displacedRow) {
            wind = [one]
        } else {
            wind = []
        }
        if let cmd = wind.first {
            commands.append(cmd)
            let detail: String
            switch cmd.dispatch {
            case .vehicleCommand(let command):
                detail = "Enqueued displaced reserve-swap wind-down vehicle command (\(command.missionRunDispatchShortLabel)) (\(triggerSource))."
            case .recipe(let name, _):
                detail = "Enqueued displaced reserve-swap wind-down recipe \(name.rawValue) (\(triggerSource))."
            case .catalogue(let name, _):
                detail = "Enqueued displaced reserve-swap wind-down catalogue \(name.rawValue) (\(triggerSource))."
            }
            appendReserveSwapPipelinePhaseLog(
                phase: .displacedFleetWindDown,
                passed: true,
                correlation: correlation,
                detail: detail
            )
        } else if noneOnly {
            appendReserveSwapPipelinePhaseLog(
                phase: .displacedFleetWindDown,
                passed: true,
                correlation: correlation,
                detail: "Skipped displaced reserve-swap wind-down (slot chain is none-only; \(triggerSource))."
            )
        } else {
            appendReserveSwapPipelinePhaseLog(
                phase: .displacedFleetWindDown,
                passed: false,
                correlation: correlation,
                detail: "No dispatchable displaced reserve-swap wind-down for resolved chain (map hub / mission points prerequisites; \(triggerSource))."
            )
        }
    }

    private func enqueueReserveSwapPostCommitBatchIfNonEmpty(
        commands: [MissionRunIssuedCommand],
        context: MissionRunExecutionContext,
        correlation: MissionRunReserveRecipeRunnerCorrelation,
        triggerSource: String
    ) {
        guard !commands.isEmpty else { return }
        let ackContext = MissionRunReserveSwapPostCommitBatchAckContext(
            correlation: correlation,
            triggerSource: triggerSource
        )
        let batch = MissionRunQueuedCommandBatch(
            tag: .reserveSwapPostCommit,
            dispatch: .immediate,
            commands: commands,
            reserveSwapPostCommitAckContext: ackContext
        )
        systems.executor.enqueueCommandBatch(batch, context: context, replacingTags: [])
    }

    private func reserveSwapHubMissionProgressForDisplacedStorageKey(
        _ displacedKey: String,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> (current: Int32?, total: Int32?) {
        let trimmed = displacedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = FleetMissionVehicleToken(storageKey: trimmed),
              let vid = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl),
              let hub = fleetLink.vehicleModel(forVehicleID: vid)?.data.telemetry
        else {
            return (nil, nil)
        }
        return (hub.missionProgressCurrent, hub.missionProgressTotal)
    }

    /// Primary squad matching the vacancy assignment id, or — for a **wingman** vacancy — the leader primary’s squad.
    private func reserveSwapPlannedSquadForVacancy(
        vacancyAssignmentID: UUID,
        mission: Mission,
        taskID: UUID
    ) -> MissionRunPlannerSubsystem.PlannedTaskSquadMission? {
        let squads = systems.planner.buildTaskSquadMissions(mission: mission, taskId: taskID)
        guard !squads.isEmpty else { return nil }
        if let direct = squads.first(where: { $0.squad.primaryAssignment.id == vacancyAssignmentID }) {
            return direct
        }
        let rosterByID = Dictionary(uniqueKeysWithValues: mission.rosterDevices.map { ($0.id, $0) })
        guard let vac = assignments.first(where: { $0.id == vacancyAssignmentID }),
              let vacDev = rosterByID[vac.rosterDeviceId],
              vacDev.slot == .wingman,
              let leaderDeviceId = vacDev.leaderRosterDeviceId,
              let primaryAssignment = assignments.first(where: { $0.rosterDeviceId == leaderDeviceId })
        else {
            return squads.first
        }
        return squads.first(where: { $0.squad.primaryAssignment.id == primaryAssignment.id }) ?? squads.first
    }
}
