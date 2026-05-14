import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunEnvironmentBetweenCycleAutostartSuppressionTests: XCTestCase {

    private func run(task: MissionTask) -> MissionRunEnvironment {
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        return MissionRunEnvironment(mission: mission)
    }

    func test_suppress_false_when_no_wind_down_markers() {
        let task = MissionTask(name: "A", enabled: true)
        let env = run(task: task)
        XCTAssertFalse(env.shouldSuppressBetweenCycleAutostartForMissionEndWindDown())
    }

    func test_suppress_true_when_graceful_stop_kind_set() {
        let task = MissionTask(name: "A", enabled: true)
        let env = run(task: task)
        env.gracefulStopKind = .completeAfterCycle
        XCTAssertTrue(env.shouldSuppressBetweenCycleAutostartForMissionEndWindDown())
    }

    func test_suppress_true_when_pending_per_task_graceful_complete() {
        let task = MissionTask(name: "A", enabled: true)
        let env = run(task: task)
        env.setPendingMissionTaskGracefulWindDown(kind: .completeAfterCycle, forTaskID: task.id)
        XCTAssertTrue(env.shouldSuppressBetweenCycleAutostartForMissionEndWindDown())
    }

    func test_suppress_true_when_complete_wind_down_issued_without_graceful_stop_kind() {
        let task = MissionTask(name: "A", enabled: true)
        let env = run(task: task)
        env.markMissionTaskCompleteWindDownIssued(forTaskID: task.id)
        XCTAssertEqual(env.gracefulStopKind, .none)
        XCTAssertTrue(env.shouldSuppressBetweenCycleAutostartForMissionEndWindDown())
    }

    func test_suppress_true_when_abort_wind_down_issued_without_graceful_stop_kind() {
        let task = MissionTask(name: "A", enabled: true)
        let env = run(task: task)
        env.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        XCTAssertEqual(env.gracefulStopKind, .none)
        XCTAssertTrue(env.shouldSuppressBetweenCycleAutostartForMissionEndWindDown())
    }
}
