import XCTest
@testable import GuardianHQ

@MainActor
final class MissionControlStoreResetRunToSetupTests: XCTestCase {

    func test_resetRunToSetup_clears_mission_end_triage_and_session_for_fresh_derivation() {
        let store = MissionControlStore()
        let device = RosterDevice(name: "SlotA")
        let taskID = UUID()
        let task = MissionTask(id: taskID, name: "Alpha", rosterDeviceIds: [device.id])
        let mission = Mission(
            name: "Op",
            description: "",
            type: .mobile,
            rosterDevices: [device],
            routeMacro: RouteMacro(tasks: [task], rules: RouteRules())
        )
        let run = store.createRun(from: mission, cloningMissionRunDefaultsFrom: GeneralSettingsStore())
        run.operatorMarkMissionTaskTriageState(taskID: taskID, state: .completed)
        XCTAssertEqual(run.taskStateByTaskID[taskID], .completed)
        XCTAssertTrue(run.taskMissionEndRecoveryCompletedByTaskID.contains(taskID))

        store.resetRunToSetup(
            id: run.id,
            fleetLink: FleetLinkService(),
            sitl: SitlService(),
            generalSettings: GeneralSettingsStore()
        )
        guard let resetRun = store.runs.first(where: { $0.id == run.id }) else {
            XCTFail("expected run in store")
            return
        }
        XCTAssertEqual(resetRun.status, .setup)
        XCTAssertEqual(resetRun.sessionPhase, .draft)
        XCTAssertFalse(resetRun.taskMissionEndRecoveryCompletedByTaskID.contains(taskID))
        XCTAssertEqual(resetRun.taskStateByTaskID[taskID], .ready)
        XCTAssertNil(resetRun.compiledPlan)
    }

    func test_resetRunToSetup_clears_assignment_slot_lifecycle_lanes() {
        let store = MissionControlStore()
        let device = RosterDevice(name: "SlotB")
        let taskID = UUID()
        let task = MissionTask(id: taskID, name: "Bravo", rosterDeviceIds: [device.id])
        let mission = Mission(
            name: "Op",
            description: "",
            type: .mobile,
            rosterDevices: [device],
            routeMacro: RouteMacro(tasks: [task], rules: RouteRules())
        )
        let run = store.createRun(from: mission, cloningMissionRunDefaultsFrom: GeneralSettingsStore())
        XCTAssertEqual(run.assignments.count, 1)
        var rows = run.assignments
        rows[0].slotLifecycleLanes = MissionRunAssignmentSlotStateLanes(
            commanded: .policyCompleting,
            observed: .policyCompleting
        )
        run.assignments = rows
        XCTAssertNotNil(run.assignments[0].slotLifecycleLanes)

        store.resetRunToSetup(
            id: run.id,
            fleetLink: FleetLinkService(),
            sitl: SitlService(),
            generalSettings: GeneralSettingsStore()
        )
        guard let resetRun = store.runs.first(where: { $0.id == run.id }) else {
            XCTFail("expected run in store")
            return
        }
        XCTAssertNil(resetRun.assignments[0].slotLifecycleLanes)
    }

    func test_resetRunToSetup_clears_squad_runtime_orchestration_maps() {
        let store = MissionControlStore()
        let p1 = RosterDevice(name: "P1", slot: .primary)
        let p2 = RosterDevice(name: "P2", slot: .primary)
        let task = MissionTask(name: "Dagger", rosterDeviceIds: [p1.id, p2.id])
        let mission = Mission(
            name: "Op",
            description: "",
            type: .mobile,
            rosterDevices: [p1, p2],
            routeMacro: RouteMacro(tasks: [task], rules: RouteRules())
        )
        let run = store.createRun(from: mission, cloningMissionRunDefaultsFrom: GeneralSettingsStore())
        XCTAssertEqual(run.assignments.count, 2)
        let squadA = run.assignments[0].id
        run.setPendingMissionSquadGracefulWindDown(kind: .abortAfterCycle, forAssignmentID: squadA)
        run.markSquadActiveInCurrentCycle(squadA)
        run.registerDeferredFirstWaveSquads(taskID: task.id, assignmentIDs: [squadA, run.assignments[1].id])
        XCTAssertEqual(run.pendingMissionSquadGracefulWindDownKindByAssignmentID[squadA], .abortAfterCycle)
        XCTAssertTrue(run.activeCycleSquadAssignmentIDs.contains(squadA))
        XCTAssertEqual(run.deferredFirstWaveSquadAssignmentIDsByTaskID[task.id]?.count, 2)

        store.resetRunToSetup(
            id: run.id,
            fleetLink: FleetLinkService(),
            sitl: SitlService(),
            generalSettings: GeneralSettingsStore()
        )
        guard let resetRun = store.runs.first(where: { $0.id == run.id }) else {
            XCTFail("expected run in store")
            return
        }
        XCTAssertTrue(resetRun.pendingMissionSquadGracefulWindDownKindByAssignmentID.isEmpty)
        XCTAssertTrue(resetRun.activeCycleSquadAssignmentIDs.isEmpty)
        XCTAssertTrue(resetRun.deferredFirstWaveSquadAssignmentIDsByTaskID.isEmpty)
    }
}
