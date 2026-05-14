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
        appDefaults.missionControlShowMissionGeofencesOnMap = false
        let run = controlStore.createRun(from: mission, cloningMissionRunDefaultsFrom: appDefaults)
        XCTAssertFalse(run.operatorDisplaySettings.isolateLiveMapToSelectedTask)
        XCTAssertFalse(run.operatorDisplaySettings.showMissionGeofencesOnMap)
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

    func test_updateTaskBetweenCyclesAction_persistsOnRunTemplate() {
        let controlStore = MissionControlStore()
        let taskID = UUID()
        var task = MissionTask(id: taskID, name: "Loop", regularity: .continuous)
        task.betweenCycles = .returnToLaunch
        let mission = Mission(
            name: "Op",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task], rules: RouteRules())
        )
        let run = controlStore.createRun(from: mission, cloningMissionRunDefaultsFrom: GeneralSettingsStore())
        let decision = run.updateTaskBetweenCyclesAction(
            taskID: taskID,
            .park,
            credential: .localOperator(callsign: "T")
        )
        XCTAssertEqual(decision, .allowed)
        XCTAssertEqual(run.template?.routeMacro.tasks.first?.betweenCycles, .park)
    }

    /// MCS / MC‑R work on a **forked** ``MissionRunEnvironment/template`` (value copy at create time); mutating the
    /// run template must not change an unrelated ``Mission`` value the caller still holds.
    func test_createRun_template_fork_is_independent_of_caller_seed_mission() {
        let controlStore = MissionControlStore()
        let seed = Mission(
            name: "Op",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [], rules: RouteRules())
        )
        XCTAssertTrue(seed.missionGeofences.isEmpty)
        let run = controlStore.createRun(from: seed, cloningMissionRunDefaultsFrom: GeneralSettingsStore())
        guard var forked = run.template else {
            XCTFail("expected run template")
            return
        }
        var fence = MissionGeofence.newPolygon(name: "Run fence", around: RouteCoordinate(lat: 0, lon: 0))
        fence.id = UUID()
        forked.missionGeofences.append(fence)
        run.updateTemplate(forked)
        XCTAssertTrue(seed.missionGeofences.isEmpty)
        XCTAssertEqual(run.template?.missionGeofences.count, 1)
    }
}
