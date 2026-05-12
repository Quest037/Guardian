import XCTest
@testable import GuardianHQ

@MainActor
final class MissionControlStoreCreateRunTests: XCTestCase {

    func test_createRun_seedsEnvironmentTemplateWithSourceMissionTasks() {
        let controlStore = MissionControlStore()
        let taskID = UUID()
        let task = MissionTask(id: taskID, name: "Surface")
        let mission = Mission(
            name: "Op",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task], rules: RouteRules())
        )
        let run = controlStore.createRun(from: mission)
        XCTAssertEqual(run.template?.id, mission.id)
        XCTAssertEqual(run.template?.routeMacro.tasks.count, 1)
        XCTAssertEqual(run.template?.routeMacro.tasks.first?.id, taskID)

        let decision = run.updateTaskAbortPreferenceChainOverride(
            taskID: taskID,
            [MissionRunAbortTactic(kind: .loiter)],
            credential: .localOperator(callsign: "T")
        )
        XCTAssertEqual(decision, .allowed)
        XCTAssertEqual(run.template?.routeMacro.tasks.first?.abortPreferenceChainOverride?.first?.kind, .loiter)
    }
}
