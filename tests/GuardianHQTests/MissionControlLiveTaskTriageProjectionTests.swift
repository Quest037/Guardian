import XCTest

@testable import GuardianCore

@MainActor
final class MissionControlLiveTaskTriageProjectionTests: XCTestCase {
    func test_make_emptyRun_readyState() {
        let mission = Mission(name: "M", description: "", type: .mobile)
        let task = MissionTask(name: "T1", enabled: true)
        var missionFull = mission
        missionFull.routeMacro.tasks = [task]
        let run = MissionRunEnvironment(mission: missionFull)
        let p = MissionControlLiveTaskTriageProjection.make(run: run, task: task)
        XCTAssertEqual(p.taskID, task.id)
        XCTAssertEqual(p.taskState, .ready)
        XCTAssertNil(p.taskAttempting)
        XCTAssertFalse(p.showAutoAckSlotBlockers)
        XCTAssertTrue(p.autoAckBlockerRows.isEmpty)
        XCTAssertEqual(p.endProtocolAckSurface, .none)
    }

    func test_make_abortIssued_withBlockingSlot_emitsBlockers() {
        let rd = RosterDevice(name: "P1", slot: .primary, vehicleClass: .uavCopter)
        var task = MissionTask(name: "T1", enabled: true, rosterDeviceIds: [rd.id])
        var mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [task])
        )
        task = mission.routeMacro.tasks[0]
        let row = MissionRunAssignment(taskId: task.id, rosterDeviceId: rd.id, slotName: "P1")
        var run = MissionRunEnvironment(mission: mission, assignments: [row])
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        let lanes = MissionRunAssignmentSlotStateLanes(
            commanded: .executingMission,
            observed: .executingMission
        )
        run.assignments[0].slotLifecycleLanes = lanes

        let p = MissionControlLiveTaskTriageProjection.make(run: run, task: task)
        XCTAssertTrue(p.showAutoAckSlotBlockers)
        XCTAssertFalse(p.autoAckBlockerRows.isEmpty)
    }
}
