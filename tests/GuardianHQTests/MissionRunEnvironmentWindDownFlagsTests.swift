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

    func test_abort_after_cycle_sets_pending_when_whole_run_graceful_none() {
        let (run, taskID) = runWithBoundAssignment()
        XCTAssertEqual(run.gracefulStopKind, .none)
        run.systems.scheduling.abortMissionTaskAfterCycle(target: .task(taskID))
        XCTAssertEqual(run.pendingMissionTaskGracefulWindDownKindByTaskID[taskID], .abortAfterCycle)
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
