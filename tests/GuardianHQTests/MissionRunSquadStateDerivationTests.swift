import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunSquadStateDerivationTests: XCTestCase {

    private func twoSquadMission() -> (Mission, MissionRunEnvironment, UUID, UUID) {
        let rd1 = UUID()
        let rd2 = UUID()
        let task = MissionTask(
            name: "Dagger",
            enabled: true,
            cycles: 0,
            regularity: .continuous,
            rosterDeviceIds: [rd1, rd2]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: rd1, name: "P1", vehicleClass: .uavCopter),
                RosterDevice(id: rd2, name: "P2", vehicleClass: .uavCopter),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: rd1,
            slotName: "Dagger:1",
            attachedFleetVehicleToken: "legacy:1"
        )
        let a2 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: rd2,
            slotName: "Dagger:2",
            attachedFleetVehicleToken: "legacy:2"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        return (mission, run, a1.id, a2.id)
    }

    func test_multi_squad_task_rollup_executing_when_one_squad_in_cycle() {
        let (_, run, a1, _) = twoSquadMission()
        let taskID = run.template!.routeMacro.tasks[0].id
        run.status = .running
        run.setSessionPhase(.executing)
        run.markSquadActiveInCurrentCycle(a1)
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.squadStateByAssignmentID[a1], .executing)
        XCTAssertEqual(run.taskStateByTaskID[taskID], .executing)
    }

    func test_multi_squad_one_finished_cycle_other_active_task_stays_executing() {
        let (mission, run, a1, a2) = twoSquadMission()
        let taskID = mission.routeMacro.tasks[0].id
        run.status = .running
        run.setSessionPhase(.executing)
        _ = run.recordSquadCycleCompletions(assignmentIDs: [a1], mission: mission)
        run.markSquadActiveInCurrentCycle(a2)
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.squadStateByAssignmentID[a1], .executing)
        XCTAssertEqual(run.squadStateByAssignmentID[a2], .executing)
        XCTAssertEqual(run.taskStateByTaskID[taskID], .executing)
    }

    func test_task_cycle_boundary_closes_only_when_all_squads_match() {
        let (mission, run, a1, a2) = twoSquadMission()
        let taskID = mission.routeMacro.tasks[0].id
        _ = run.recordSquadCycleCompletions(assignmentIDs: [a1], mission: mission)
        XCTAssertEqual(run.squadCyclesCompletedByAssignmentID[a1], 1)
        XCTAssertEqual(run.squadCyclesCompletedByAssignmentID[a2], nil)
        XCTAssertEqual(run.taskCyclesCompletedByTaskID[taskID], 0)

        let closed = run.recordSquadCycleCompletions(assignmentIDs: [a2], mission: mission)
        XCTAssertEqual(closed, [taskID])
        XCTAssertEqual(run.taskCyclesCompletedByTaskID[taskID], 1)
    }

    func test_three_primary_squads_task_cycle_increments_only_after_third_closes() {
        let rd1 = UUID()
        let rd2 = UUID()
        let rd3 = UUID()
        let task = MissionTask(
            name: "Triple",
            enabled: true,
            cycles: 0,
            regularity: .continuous,
            rosterDeviceIds: [rd1, rd2, rd3]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: rd1, name: "P1", vehicleClass: .uavCopter),
                RosterDevice(id: rd2, name: "P2", vehicleClass: .uavCopter),
                RosterDevice(id: rd3, name: "P3", vehicleClass: .uavCopter),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd1,
            slotName: "T1",
            attachedFleetVehicleToken: "legacy:1"
        )
        let a2 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd2,
            slotName: "T2",
            attachedFleetVehicleToken: "legacy:2"
        )
        let a3 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd3,
            slotName: "T3",
            attachedFleetVehicleToken: "legacy:3"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2, a3])
        let taskID = task.id
        XCTAssertTrue(run.recordSquadCycleCompletions(assignmentIDs: [a1.id], mission: mission).isEmpty)
        XCTAssertTrue(run.recordSquadCycleCompletions(assignmentIDs: [a2.id], mission: mission).isEmpty)
        let closed = run.recordSquadCycleCompletions(assignmentIDs: [a3.id], mission: mission)
        XCTAssertEqual(closed, [taskID])
        XCTAssertEqual(run.taskCyclesCompletedByTaskID[taskID], 1)
    }

    func test_continuous_with_delay_squad_between_task_rollup_executing() {
        let rd1 = UUID()
        let rd2 = UUID()
        let task = MissionTask(
            name: "Delay",
            enabled: true,
            cycles: 0,
            regularityDelayValue: 10,
            regularityDelayUnit: .secs,
            regularity: .continuousWithDelay,
            rosterDeviceIds: [rd1, rd2]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: rd1, name: "P1", vehicleClass: .uavCopter),
                RosterDevice(id: rd2, name: "P2", vehicleClass: .uavCopter),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd1,
            slotName: "Delay:1",
            attachedFleetVehicleToken: "legacy:1"
        )
        let a2 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd2,
            slotName: "Delay:2",
            attachedFleetVehicleToken: "legacy:2"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        run.status = .running
        run.setSessionPhase(.executing)
        _ = run.recordSquadCycleCompletions(assignmentIDs: [a1.id], mission: mission)
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.squadStateByAssignmentID[a1.id], MissionSquadState.between)
        XCTAssertEqual(run.taskStateByTaskID[task.id], MissionTaskState.executing)
    }

    func test_recovery_session_squad_completed_when_complete_wind_down_slots_satisfied() {
        let rd = UUID()
        let task = MissionTask(
            name: "Lance",
            enabled: true,
            cycles: 1,
            regularity: .continuous,
            rosterDeviceIds: [rd]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", slot: .primary, vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "P1",
            attachedFleetVehicleToken: "legacy:1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a])
        run.status = .recovery
        run.setSessionPhase(.recovery)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: task.id)

        let squad = MissionRunEnvironment.deriveMissionSquadState(
            task: task,
            assignment: a,
            squadIndex: 0,
            run: run,
            now: Date()
        )
        XCTAssertEqual(squad, .completed)
    }
}
