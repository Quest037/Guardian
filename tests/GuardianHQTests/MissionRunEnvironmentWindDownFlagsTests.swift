import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunEnvironmentWindDownFlagsTests: XCTestCase {

    /// One enabled task with a roster row bound to that task id (``assignmentsBoundToMissionTask`` non-empty).
    private func runWithBoundAssignment() -> (MissionRunEnvironment, UUID) {
        let deviceId = UUID()
        let task = MissionTask(name: "Alpha", rosterDeviceIds: [deviceId])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: deviceId, name: "Slot A")],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(taskId: task.id, rosterDeviceId: deviceId, slotName: "Slot A")
        let run = MissionRunEnvironment(mission: mission, assignments: [assignment])
        return (run, task.id)
    }

    /// Two primary roster rows on one operator-triggered task.
    private func runWithTwoPrimaryOperatorTriggeredSquads() -> (
        MissionRunEnvironment,
        MissionTask,
        MissionRunAssignment,
        MissionRunAssignment
    ) {
        let d1 = UUID()
        let d2 = UUID()
        let task = MissionTask(name: "Layer", regularity: .operatorTriggered, rosterDeviceIds: [d1, d2])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: d1, name: "P1", slot: .primary),
                RosterDevice(id: d2, name: "P2", slot: .primary)
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: d1,
            slotName: "P1",
            attachedFleetVehicleToken: "v1"
        )
        let a2 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: d2,
            slotName: "P2",
            attachedFleetVehicleToken: "v2"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        return (run, task, a1, a2)
    }

    /// Two primary roster rows on one task (fleet tokens present so they count as primaries for squad policy).
    private func runWithTwoPrimarySquads() -> (
        MissionRunEnvironment,
        MissionTask,
        MissionRunAssignment,
        MissionRunAssignment
    ) {
        let d1 = UUID()
        let d2 = UUID()
        let task = MissionTask(name: "Layer", regularity: .continuous, rosterDeviceIds: [d1, d2])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: d1, name: "P1", slot: .primary),
                RosterDevice(id: d2, name: "P2", slot: .primary)
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: d1,
            slotName: "P1",
            attachedFleetVehicleToken: "v1"
        )
        let a2 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: d2,
            slotName: "P2",
            attachedFleetVehicleToken: "v2"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        return (run, task, a1, a2)
    }

    func test_abort_after_cycle_sets_pending_when_whole_run_graceful_none() {
        let (run, taskID) = runWithBoundAssignment()
        XCTAssertEqual(run.gracefulStopKind, .none)
        run.systems.scheduling.abortMissionTaskAfterCycle(target: .task(taskID))
        XCTAssertEqual(run.pendingMissionTaskGracefulWindDownKindByTaskID[taskID], .abortAfterCycle)
    }

    func test_operatorTriggered_multi_primary_complete_after_cycle_fans_out_to_squads() {
        let (run, task, a1, a2) = runWithTwoPrimaryOperatorTriggeredSquads()
        run.systems.scheduling.completeMissionTaskAfterCycle(target: .task(task.id))
        XCTAssertNil(run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id])
        XCTAssertEqual(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[a1.id], .completeAfterCycle)
        XCTAssertEqual(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[a2.id], .completeAfterCycle)
    }

    func test_completeMissionTaskGraceful_operatorTriggered_multi_primary_returns_true() {
        let (run, task, _, _) = runWithTwoPrimaryOperatorTriggeredSquads()
        run.status = .running
        run.setSessionPhase(.executing)
        XCTAssertTrue(run.completeMissionTaskGraceful(.task(task.id)))
        XCTAssertNil(run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id])
    }

    func test_abortMissionTaskGraceful_operatorTriggered_multi_primary_returns_true() {
        let (run, task, _, _) = runWithTwoPrimaryOperatorTriggeredSquads()
        run.status = .running
        run.setSessionPhase(.executing)
        XCTAssertTrue(run.abortMissionTaskGraceful(.task(task.id)))
        XCTAssertNil(run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id])
    }

    func test_operatorTriggered_multi_primary_abort_after_cycle_fans_out_to_squads() {
        let (run, task, a1, a2) = runWithTwoPrimaryOperatorTriggeredSquads()
        run.systems.scheduling.abortMissionTaskAfterCycle(target: .task(task.id))
        XCTAssertNil(run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id])
        XCTAssertEqual(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[a1.id], .abortAfterCycle)
        XCTAssertEqual(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[a2.id], .abortAfterCycle)
    }

    func test_continuous_multi_primary_task_wide_still_uses_task_pending() {
        let (run, task, a1, a2) = runWithTwoPrimarySquads()
        run.systems.scheduling.completeMissionTaskAfterCycle(target: .task(task.id))
        XCTAssertEqual(run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id], .completeAfterCycle)
        XCTAssertNil(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[a1.id])
        XCTAssertNil(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[a2.id])
    }

    func test_operatorTriggered_squad_pending_delivers_recovery_for_one_squad_only() {
        let d1 = UUID()
        let d2 = UUID()
        var rules = RouteRules()
        rules.missionCompletePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        let task = MissionTask(name: "Layer", regularity: .operatorTriggered, rosterDeviceIds: [d1, d2])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: d1, name: "P1", slot: .primary),
                RosterDevice(id: d2, name: "P2", slot: .primary)
            ],
            routeMacro: RouteMacro(tasks: [task], rules: rules)
        )
        var pol = MissionRunAssignmentPolicies()
        pol.completePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        let sitlA = UUID()
        let sitlB = UUID()
        let a1 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: d1,
            slotName: "P1",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlA).storageKey,
            policies: pol
        )
        let a2 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: d2,
            slotName: "P2",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlB).storageKey,
            policies: pol
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlA, stackInstanceIndex: 0)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlB, stackInstanceIndex: 1)
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markSquadActiveInCurrentCycle(a1.id)
        run.markSquadActiveInCurrentCycle(a2.id)
        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            missionProvider: { mission }
        )
        run.captureExecutionContext(ctx)
        run.systems.scheduling.completeMissionTaskAfterCycle(target: .task(task.id))
        run.removeSquadFromActiveCycle(a1.id)
        run.systems.executor.deliverPendingSquadGracefulWindDownsIfNeeded(
            completedSquadAssignmentIDs: [a1.id],
            context: ctx
        )
        XCTAssertTrue(run.squadCompletePolicyWindDownIssuedAssignmentIDs.contains(a1.id))
        XCTAssertFalse(run.squadCompletePolicyWindDownIssuedAssignmentIDs.contains(a2.id))
        XCTAssertFalse(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id))
        XCTAssertNil(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[a1.id])
        XCTAssertEqual(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[a2.id], .completeAfterCycle)
        XCTAssertEqual(run.squadStateByAssignmentID[a1.id], .recovery)
        XCTAssertNotEqual(run.squadStateByAssignmentID[a2.id], .recovery)
    }

    func test_task_wide_graceful_pending_clears_squad_pending() {
        let (run, task, a1, a2) = runWithTwoPrimarySquads()
        run.setPendingMissionSquadGracefulWindDown(kind: .completeAfterCycle, forAssignmentID: a1.id)
        run.setPendingMissionTaskGracefulWindDown(kind: .abortAfterCycle, forTaskID: task.id)
        XCTAssertNil(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[a1.id])
        XCTAssertNil(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[a2.id])
        XCTAssertEqual(run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id], .abortAfterCycle)
    }

    func test_squad_graceful_pending_clears_task_wide_pending() {
        let (run, task, a1, _) = runWithTwoPrimarySquads()
        run.setPendingMissionTaskGracefulWindDown(kind: .completeAfterCycle, forTaskID: task.id)
        run.setPendingMissionSquadGracefulWindDown(kind: .abortAfterCycle, forAssignmentID: a1.id)
        XCTAssertNil(run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id])
        XCTAssertEqual(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[a1.id], .abortAfterCycle)
    }

    func test_shouldSuppressAutopilotAutostart_per_squad_pending_only() {
        let (run, task, a1, a2) = runWithTwoPrimarySquads()
        guard let mission = run.template else {
            XCTFail("expected template")
            return
        }
        run.setPendingMissionSquadGracefulWindDown(kind: .completeAfterCycle, forAssignmentID: a1.id)
        XCTAssertTrue(run.shouldSuppressAutopilotAutostart(forSquadAssignmentID: a1.id, taskID: task.id, mission: mission))
        XCTAssertFalse(run.shouldSuppressAutopilotAutostart(forSquadAssignmentID: a2.id, taskID: task.id, mission: mission))
    }

    func test_abort_after_cycle_skipped_when_whole_run_graceful_active() {
        let (run, taskID) = runWithBoundAssignment()
        run.gracefulStopKind = .abortAfterCycle
        run.systems.scheduling.abortMissionTaskAfterCycle(target: .task(taskID))
        XCTAssertNil(run.pendingMissionTaskGracefulWindDownKindByTaskID[taskID])
    }

    func test_complete_after_cycle_sets_pending() {
        let (run, taskID) = runWithBoundAssignment()
        run.systems.scheduling.completeMissionTaskAfterCycle(target: .task(taskID))
        XCTAssertEqual(run.pendingMissionTaskGracefulWindDownKindByTaskID[taskID], .completeAfterCycle)
    }

    func test_revokeMissionTaskGracefulWindDown_clears_pending_only() {
        let (run, taskID) = runWithBoundAssignment()
        run.systems.scheduling.completeMissionTaskAfterCycle(target: .task(taskID))
        XCTAssertEqual(run.pendingMissionTaskGracefulWindDownKindByTaskID[taskID], .completeAfterCycle)
        run.revokeMissionTaskGracefulWindDown(forTaskID: taskID)
        XCTAssertNil(run.pendingMissionTaskGracefulWindDownKindByTaskID[taskID])
    }

    func test_mark_abort_issued_pairs_autostart_suppression() {
        let (run, taskID) = runWithBoundAssignment()
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        XCTAssertTrue(run.missionTaskAbortWindDownIssuedTaskIDs.contains(taskID))
        XCTAssertTrue(run.missionTaskAutopilotAutostartSuppressedTaskIDs.contains(taskID))
    }

    func test_clearMissionTaskScopedOrchestrationState_clears_pending_and_issued() {
        let (run, taskID) = runWithBoundAssignment()
        run.systems.scheduling.abortMissionTaskAfterCycle(target: .task(taskID))
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        run.clearMissionTaskScopedOrchestrationState()
        XCTAssertNil(run.pendingMissionTaskGracefulWindDownKindByTaskID[taskID])
        XCTAssertFalse(run.missionTaskAbortWindDownIssuedTaskIDs.contains(taskID))
    }

    func test_clearMissionTaskScopedOrchestrationState_preserving_keeps_wind_down_issued() {
        let (run, taskID) = runWithBoundAssignment()
        run.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        run.clearMissionTaskScopedOrchestrationState(preserveEndModeSettlement: true)
        XCTAssertTrue(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskID))
        XCTAssertTrue(run.missionTaskAbortWindDownIssuedTaskIDs.contains(taskID))
    }

    func test_clearMissionTaskScopedOrchestrationState_preserving_keeps_squad_wind_down_issued() {
        let (run, _) = runWithBoundAssignment()
        let aid = run.assignments[0].id
        run.markSquadCompletePolicyWindDownDispatchIssued(forAssignmentID: aid)
        run.markSquadMissionEndRecoveryCompleted(forAssignmentID: aid)
        run.clearMissionTaskScopedOrchestrationState(preserveEndModeSettlement: true)
        XCTAssertTrue(run.squadCompletePolicyWindDownIssuedAssignmentIDs.contains(aid))
        XCTAssertTrue(run.squadMissionEndRecoveryCompletedByAssignmentIDs.contains(aid))
    }

    func test_clearMissionTaskScopedOrchestrationState_clears_squad_pending_graceful() {
        let (run, _) = runWithBoundAssignment()
        let aid = run.assignments[0].id
        run.setPendingMissionSquadGracefulWindDown(kind: .completeAfterCycle, forAssignmentID: aid)
        run.clearMissionTaskScopedOrchestrationState()
        XCTAssertNil(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[aid])
    }

    func test_operator_triage_completed_clears_complete_issued() {
        let (run, taskID) = runWithBoundAssignment()
        run.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
        XCTAssertTrue(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskID))
        run.operatorMarkMissionTaskTriageState(taskID: taskID, state: .completed)
        XCTAssertFalse(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskID))
    }

    func test_operator_triage_aborted_clears_abort_issued() {
        let (run, taskID) = runWithBoundAssignment()
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        XCTAssertTrue(run.missionTaskAbortWindDownIssuedTaskIDs.contains(taskID))
        run.operatorMarkMissionTaskTriageState(taskID: taskID, state: .aborted)
        XCTAssertFalse(run.missionTaskAbortWindDownIssuedTaskIDs.contains(taskID))
    }
}
