import XCTest
@testable import GuardianHQ

@MainActor
final class MissionTaskAttemptStateDerivationTests: XCTestCase {

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

    func test_graceful_abort_pending_maps_to_scheduled_attempting() {
        let (run, taskID) = runWithBoundAssignment()
        run.systems.scheduling.abortMissionTaskAfterCycle(target: .task(taskID))
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .abortWindDownScheduledAfterCycle)
    }

    func test_graceful_complete_pending_maps_to_scheduled_attempting() {
        let (run, taskID) = runWithBoundAssignment()
        run.systems.scheduling.completeMissionTaskAfterCycle(target: .task(taskID))
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .recoveryWindDownScheduledAfterCycle)
    }

    func test_abort_issued_maps_to_abort_wind_down_attempting() {
        let (run, taskID) = runWithBoundAssignment()
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .abortWindDownIssued)
    }

    func test_complete_issued_maps_to_recovery_wind_down_attempting() {
        let (run, taskID) = runWithBoundAssignment()
        run.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .recoveryWindDownIssued)
    }

    func test_abort_issued_takes_precedence_over_complete_issued() {
        let (run, taskID) = runWithBoundAssignment()
        run.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .abortWindDownIssued)
    }

    func test_abort_issued_takes_precedence_over_graceful_pending() {
        let (run, taskID) = runWithBoundAssignment()
        run.systems.scheduling.completeMissionTaskAfterCycle(target: .task(taskID))
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .recoveryWindDownScheduledAfterCycle)
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .abortWindDownIssued)
    }

    func test_operator_triage_aborted_clears_task_attempting() {
        let (run, taskID) = runWithBoundAssignment()
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .abortWindDownIssued)
        run.operatorMarkMissionTaskTriageState(taskID: taskID, state: .aborted)
        XCTAssertNil(run.taskAttemptingByTaskID[taskID])
    }

    func test_operator_triage_completed_clears_task_attempting() {
        let (run, taskID) = runWithBoundAssignment()
        run.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .recoveryWindDownIssued)
        run.operatorMarkMissionTaskTriageState(taskID: taskID, state: .completed)
        XCTAssertNil(run.taskAttemptingByTaskID[taskID])
    }

    func test_disabled_task_has_no_attempting_even_if_pending_internally_set() {
        let deviceId = UUID()
        let task = MissionTask(name: "Off", enabled: false, rosterDeviceIds: [deviceId])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: deviceId, name: "Slot A")],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(taskId: task.id, rosterDeviceId: deviceId, slotName: "Slot A")
        let run = MissionRunEnvironment(mission: mission, assignments: [assignment])
        run.setPendingMissionTaskGracefulWindDown(kind: .abortAfterCycle, forTaskID: task.id)
        XCTAssertNil(run.taskAttemptingByTaskID[task.id])
    }
}
