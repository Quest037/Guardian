import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunEnvironmentTaskDerivationTests: XCTestCase {

    private func environment(task: MissionTask) -> MissionRunEnvironment {
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        return MissionRunEnvironment(mission: mission)
    }

    func test_disabled_task_derives_ready() {
        let task = MissionTask(name: "Off", enabled: false)
        let run = environment(task: task)
        run.status = .running
        run.setSessionPhase(.executing)
        run.markTaskActiveInCurrentCycle(task.id)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .ready)
    }

    func test_operator_triage_pin_aborted_overrides_executing() {
        let task = MissionTask(name: "Alpha", enabled: true)
        let run = environment(task: task)
        run.status = .running
        run.setSessionPhase(.executing)
        run.markTaskActiveInCurrentCycle(task.id)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .executing)

        run.operatorMarkMissionTaskTriageState(taskID: task.id, state: .aborted)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborted)
    }

    func test_abort_wind_down_issued_then_acknowledge_moves_triage_sets() {
        let task = MissionTask(name: "Bravo", enabled: true)
        let run = environment(task: task)
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborting)
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))

        run.acknowledgeTaskMissionEndAbort(taskID: task.id)
        XCTAssertTrue(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborted)
    }

    func test_prepareMissionTaskForOperatorRestart_clears_ack_sets_and_triage() {
        let task = MissionTask(name: "Charlie", enabled: true)
        let run = environment(task: task)
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        run.acknowledgeTaskMissionEndAbort(taskID: task.id)
        XCTAssertTrue(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))

        run.prepareMissionTaskForOperatorRestart(taskID: task.id)
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))
        XCTAssertFalse(run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id))
        XCTAssertNil(run.operatorTriageMarkedMissionTaskStateByTaskID[task.id])
    }
}
