import XCTest
@testable import GuardianHQ

@MainActor
final class MissionControlStoreFloatingReserveSwapRecompileTests: XCTestCase {

    func test_recompileAfterFloatingReserveSwap_setup_delegatesToFullCompile() {
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
        XCTAssertEqual(run.status, .setup)
        XCTAssertEqual(run.sessionPhase, .draft)

        controlStore.recompileMissionControlPlanAfterFloatingReserveSwap(
            run: run,
            mission: mission,
            fleetVehicles: []
        )

        XCTAssertEqual(run.sessionPhase, .compiled)
        XCTAssertNotNil(run.compiledPlan)
    }

    func test_recompileAfterFloatingReserveSwap_nonSetup_preservesSessionPhase() {
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
        controlStore.compileMissionControlPlan(run: run, mission: mission, fleetVehicles: [])
        XCTAssertEqual(run.sessionPhase, .compiled)

        run.status = .running
        run.setSessionPhase(.executing)

        controlStore.recompileMissionControlPlanAfterFloatingReserveSwap(
            run: run,
            mission: mission,
            fleetVehicles: []
        )

        XCTAssertEqual(run.sessionPhase, .executing)
        XCTAssertEqual(run.status, .running)
        XCTAssertNotNil(run.compiledPlan)
    }
}
