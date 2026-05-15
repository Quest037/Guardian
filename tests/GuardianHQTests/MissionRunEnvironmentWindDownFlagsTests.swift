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
        run.clearMissionTaskScopedOrchestrationState(preserveMissionEndWindDownIssued: true)
        XCTAssertTrue(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskID))
        XCTAssertTrue(run.missionTaskAbortWindDownIssuedTaskIDs.contains(taskID))
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
