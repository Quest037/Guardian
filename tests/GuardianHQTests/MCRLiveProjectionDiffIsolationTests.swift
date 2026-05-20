import XCTest
@testable import GuardianCore

/// Phase 10 / MC-R row contracts: equatable projections should **not** churn when unrelated MRE rows / tasks change (see ``README_FULL.md`` → **MC-R live UI row contracts**).
@MainActor
final class MCRLiveProjectionDiffIsolationTests: XCTestCase {

    private func twoTaskMission() -> (Mission, MissionRunEnvironment, RoutePath, RoutePath) {
        let rd1 = UUID()
        let rd2 = UUID()
        let taskA = MissionTask(
            name: "Alpha",
            enabled: true,
            rosterDeviceIds: [rd1]
        )
        let taskB = MissionTask(
            name: "Bravo",
            enabled: true,
            rosterDeviceIds: [rd2]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: rd1, name: "A1", vehicleClass: .uavCopter),
                RosterDevice(id: rd2, name: "B1", vehicleClass: .uavCopter),
            ],
            routeMacro: RouteMacro(tasks: [taskA, taskB])
        )
        let aRow = MissionRunAssignment(
            taskId: taskA.id,
            rosterDeviceId: rd1,
            slotName: "Alpha:1",
            attachedFleetVehicleToken: "legacy:a"
        )
        let bRow = MissionRunAssignment(
            taskId: taskB.id,
            rosterDeviceId: rd2,
            slotName: "Bravo:1",
            attachedFleetVehicleToken: "legacy:b"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [aRow, bRow])
        return (mission, run, taskA, taskB)
    }

    func test_task_live_projection_stable_when_only_other_task_squad_enters_cycle() {
        let (mission, run, taskA, taskB) = twoTaskMission()
        run.status = .running
        run.setSessionPhase(.executing)
        let now = Date()
        let before = MCRLiveTaskListProgressFormatting.makeTaskLiveProjection(
            run: run,
            mission: mission,
            task: taskA,
            now: now
        )
        let bAssignmentID = run.assignments.first(where: { $0.taskId == taskB.id })!.id
        run.markSquadActiveInCurrentCycle(bAssignmentID)
        run.refreshDerivedTaskStates()
        let after = MCRLiveTaskListProgressFormatting.makeTaskLiveProjection(
            run: run,
            mission: mission,
            task: taskA,
            now: now
        )
        XCTAssertEqual(before, after)
    }

    func test_assignment_live_projection_changes_when_own_slot_lanes_change() {
        let rd = UUID()
        let task = MissionTask(name: "Solo", enabled: true, rosterDeviceIds: [rd])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        var row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Solo:1",
            attachedFleetVehicleToken: "legacy:1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes()
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        let idleProj = MissionRunAssignmentLiveProjection.make(
            assignment: row,
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            liveReserveSwapPick: nil,
            focusedLiveTaskID: nil
        )
        row.slotLifecycleLanes = MissionRunAssignmentSlotStateLanes(
            commanded: .executingMission,
            observed: .idle
        )
        let execProj = MissionRunAssignmentLiveProjection.make(
            assignment: row,
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            liveReserveSwapPick: nil,
            focusedLiveTaskID: nil
        )
        XCTAssertNotEqual(idleProj, execProj)
        XCTAssertEqual(idleProj.mergedSlotState, .idle)
        XCTAssertEqual(execProj.mergedSlotState, .executingMission)
    }
}
