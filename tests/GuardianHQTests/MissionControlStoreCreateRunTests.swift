import XCTest
@testable import GuardianHQ

@MainActor
final class MissionControlStoreCreateRunTests: XCTestCase {

    func test_createRun_copiesAppMissionRunDefaultsIntoOperatorDisplaySettings() {
        let controlStore = MissionControlStore()
        let mission = Mission(
            name: "Op",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [], rules: RouteRules())
        )
        let appDefaults = GeneralSettingsStore()
        appDefaults.missionControlLiveMapHideOtherTasksOnTaskSelect = false
        appDefaults.missionRunResetSitlToStartPoseOnSuccessfulComplete = true
        appDefaults.missionRunSimBatteryDrainRate = .none
        let run = controlStore.createRun(from: mission, cloningMissionRunDefaultsFrom: appDefaults)
        XCTAssertFalse(run.operatorDisplaySettings.isolateLiveMapToSelectedTask)
        XCTAssertTrue(run.operatorDisplaySettings.resetSimToStartPoseOnSuccessfulComplete)
        XCTAssertEqual(run.operatorDisplaySettings.simBatteryDrainRateDuringRun, .none)

        appDefaults.missionControlLiveMapHideOtherTasksOnTaskSelect = true
        appDefaults.missionRunSimBatteryDrainRate = .fast
        XCTAssertFalse(run.operatorDisplaySettings.isolateLiveMapToSelectedTask, "Existing run must not follow app default changes")
        XCTAssertEqual(run.operatorDisplaySettings.simBatteryDrainRateDuringRun, .none)
    }

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
        let run = controlStore.createRun(from: mission, cloningMissionRunDefaultsFrom: GeneralSettingsStore())
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
