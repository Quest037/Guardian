import XCTest
@testable import GuardianCore

@MainActor
final class MissionRunEnvironmentBetweenCycleAutostartSuppressionTests: XCTestCase {

    private func run(tasks: [MissionTask]) -> MissionRunEnvironment {
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: tasks)
        )
        return MissionRunEnvironment(mission: mission)
    }

    func test_mission_wide_suppress_false_when_no_graceful_stop_kind() {
        let task = MissionTask(name: "A", enabled: true)
        let env = run(tasks: [task])
        XCTAssertFalse(env.shouldSuppressMissionWideBetweenCycleAutostart())
    }

    func test_mission_wide_suppress_true_only_for_graceful_stop_kind() {
        let task = MissionTask(name: "A", enabled: true)
        let env = run(tasks: [task])
        env.gracefulStopKind = .completeAfterCycle
        XCTAssertTrue(env.shouldSuppressMissionWideBetweenCycleAutostart())
    }

    func test_per_task_wind_down_does_not_set_mission_wide_suppress() {
        let task = MissionTask(name: "A", enabled: true)
        let env = run(tasks: [task])
        env.setPendingMissionTaskGracefulWindDown(kind: .completeAfterCycle, forTaskID: task.id)
        env.markMissionTaskCompleteWindDownIssued(forTaskID: task.id)
        env.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        XCTAssertEqual(env.gracefulStopKind, .none)
        XCTAssertFalse(env.shouldSuppressMissionWideBetweenCycleAutostart())
    }

    func test_unioned_suppress_includes_ending_task_not_sibling_continuous() {
        let taskA = MissionTask(name: "A", enabled: true, regularity: .continuousWithDelay)
        let taskB = MissionTask(name: "B", enabled: true, regularity: .continuous)
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [taskA, taskB])
        )
        let env = MissionRunEnvironment(mission: mission)
        env.markMissionTaskCompleteWindDownIssued(forTaskID: taskA.id)

        let union = env.unionedMissionTaskIDsSuppressingAutopilotAutostart(forMission: mission)
        XCTAssertTrue(union.contains(taskA.id))
        XCTAssertFalse(union.contains(taskB.id))
        XCTAssertFalse(env.shouldSuppressMissionWideBetweenCycleAutostart())
    }

    func test_pending_per_task_graceful_in_union_without_mission_wide_freeze() {
        let taskA = MissionTask(name: "A", enabled: true)
        let taskB = MissionTask(name: "B", enabled: true)
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [taskA, taskB])
        )
        let env = MissionRunEnvironment(mission: mission)
        env.setPendingMissionTaskGracefulWindDown(kind: .completeAfterCycle, forTaskID: taskA.id)

        let union = env.unionedMissionTaskIDsSuppressingAutopilotAutostart(forMission: mission)
        XCTAssertTrue(union.contains(taskA.id))
        XCTAssertFalse(union.contains(taskB.id))
        XCTAssertFalse(env.shouldSuppressMissionWideBetweenCycleAutostart())
    }
}
