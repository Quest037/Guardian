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

    func test_graceful_abort_pending_does_not_publish_mission_end_attempt() {
        let (run, taskID) = runWithBoundAssignment()
        run.systems.scheduling.abortMissionTaskAfterCycle(target: .task(taskID))
        XCTAssertNil(run.taskAttemptingByTaskID[taskID])
        XCTAssertNil(run.taskMissionEndAttemptByTaskID[taskID])
    }

    func test_graceful_complete_pending_does_not_publish_mission_end_attempt() {
        let (run, taskID) = runWithBoundAssignment()
        run.systems.scheduling.completeMissionTaskAfterCycle(target: .task(taskID))
        XCTAssertNil(run.taskAttemptingByTaskID[taskID])
        XCTAssertNil(run.taskMissionEndAttemptByTaskID[taskID])
    }

    func test_mark_issued_alone_does_not_create_attempting_line() {
        let (run, taskID) = runWithBoundAssignment()
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        XCTAssertNil(run.taskAttemptingByTaskID[taskID])
    }

    func test_note_abort_attempt_published() {
        let (run, taskID) = runWithBoundAssignment()
        run.noteMissionTaskEndAttempt(.abortMissionEnd, forTaskID: taskID)
        XCTAssertEqual(run.taskMissionEndAttemptByTaskID[taskID], .abortMissionEnd)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .abortMissionEnd)
    }

    func test_note_recovery_attempt_published() {
        let (run, taskID) = runWithBoundAssignment()
        run.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: taskID)
        XCTAssertEqual(run.taskMissionEndAttemptByTaskID[taskID], .recoveryMissionEnd)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .recoveryMissionEnd)
    }

    func test_abort_note_wins_over_recovery_note() {
        let (run, taskID) = runWithBoundAssignment()
        run.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: taskID)
        run.noteMissionTaskEndAttempt(.abortMissionEnd, forTaskID: taskID)
        XCTAssertEqual(run.taskMissionEndAttemptByTaskID[taskID], .abortMissionEnd)
    }

    func test_recovery_note_does_not_replace_abort_note() {
        let (run, taskID) = runWithBoundAssignment()
        run.noteMissionTaskEndAttempt(.abortMissionEnd, forTaskID: taskID)
        run.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: taskID)
        XCTAssertEqual(run.taskMissionEndAttemptByTaskID[taskID], .abortMissionEnd)
    }

    func test_operator_triage_aborted_clears_mission_end_attempt() {
        let (run, taskID) = runWithBoundAssignment()
        run.noteMissionTaskEndAttempt(.abortMissionEnd, forTaskID: taskID)
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .abortMissionEnd)
        run.operatorMarkMissionTaskTriageState(taskID: taskID, state: .aborted)
        XCTAssertNil(run.taskAttemptingByTaskID[taskID])
        XCTAssertNil(run.taskMissionEndAttemptByTaskID[taskID])
    }

    func test_abort_attempt_survives_all_slots_policy_succeeded_until_auto_ack() {
        let (run, taskID) = runWithBoundAssignment()
        var rows = run.assignments
        rows[0].slotLifecycleLanes = MissionRunAssignmentSlotStateLanes(
            commanded: .policySucceeded,
            observed: .policySucceeded
        )
        run.assignments = rows
        run.status = .running
        run.setSessionPhase(.executing)
        run.noteMissionTaskEndAttempt(.abortMissionEnd, forTaskID: taskID)
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .abortMissionEnd)
        XCTAssertEqual(run.taskStateByTaskID[taskID], .aborting)

        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([rows[0].id]))
        XCTAssertNil(run.taskAttemptingByTaskID[taskID])
        XCTAssertNil(run.taskMissionEndAttemptByTaskID[taskID])
        XCTAssertEqual(run.taskStateByTaskID[taskID], .aborted)
    }

    func test_recovery_attempt_survives_all_slots_policy_succeeded_until_auto_ack() {
        let (run, taskID) = runWithBoundAssignment()
        var rows = run.assignments
        rows[0].slotLifecycleLanes = MissionRunAssignmentSlotStateLanes(
            commanded: .policySucceeded,
            observed: .policySucceeded
        )
        run.assignments = rows
        run.status = .running
        run.setSessionPhase(.executing)
        run.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: taskID)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .recoveryMissionEnd)

        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([rows[0].id]))
        XCTAssertNil(run.taskAttemptingByTaskID[taskID])
        XCTAssertEqual(run.taskStateByTaskID[taskID], .completed)
    }

    func test_operator_triage_completed_clears_mission_end_attempt() {
        let (run, taskID) = runWithBoundAssignment()
        run.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: taskID)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
        XCTAssertEqual(run.taskAttemptingByTaskID[taskID], .recoveryMissionEnd)
        run.operatorMarkMissionTaskTriageState(taskID: taskID, state: .completed)
        XCTAssertNil(run.taskAttemptingByTaskID[taskID])
    }

    func test_disabled_task_hides_attempt_even_if_storage_set() {
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
        run.noteMissionTaskEndAttempt(.abortMissionEnd, forTaskID: task.id)
        XCTAssertNil(run.taskAttemptingByTaskID[task.id])
    }
}
