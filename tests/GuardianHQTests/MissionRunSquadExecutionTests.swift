import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunSquadExecutionTests: XCTestCase {

    func test_deferred_first_wave_queue_registers_non_automatic_squads() {
        let rd1 = UUID()
        let rd2 = UUID()
        let task = MissionTask(
            name: "Gate",
            enabled: true,
            staggerTrigger: .operatorFirstWaveGate,
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
            slotName: "Gate:1",
            attachedFleetVehicleToken: "legacy:1"
        )
        let a2 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd2,
            slotName: "Gate:2",
            attachedFleetVehicleToken: "legacy:2"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        run.registerDeferredFirstWaveSquads(taskID: task.id, assignmentIDs: [a2.id])
        XCTAssertEqual(run.deferredFirstWaveSquadAssignmentIDsByTaskID[task.id], [a2.id])
        XCTAssertEqual(run.consumeNextDeferredFirstWaveSquadAssignmentID(forTaskID: task.id), a2.id)
        XCTAssertNil(run.deferredFirstWaveSquadAssignmentIDsByTaskID[task.id])
    }

    func test_squad_autostart_suppress_does_not_block_sibling_task_suppress_check() {
        let rd1 = UUID()
        let rd2 = UUID()
        let taskA = MissionTask(name: "A", enabled: true, cycles: 0, regularity: .continuous, rosterDeviceIds: [rd1])
        let taskB = MissionTask(name: "B", enabled: true, cycles: 0, regularity: .continuous, rosterDeviceIds: [rd2])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: rd1, name: "P1", vehicleClass: .uavCopter),
                RosterDevice(id: rd2, name: "P2", vehicleClass: .uavCopter),
            ],
            routeMacro: RouteMacro(tasks: [taskA, taskB])
        )
        let a1 = MissionRunAssignment(
            taskId: taskA.id,
            rosterDeviceId: rd1,
            slotName: "A:1",
            attachedFleetVehicleToken: "legacy:1"
        )
        let b1 = MissionRunAssignment(
            taskId: taskB.id,
            rosterDeviceId: rd2,
            slotName: "B:1",
            attachedFleetVehicleToken: "legacy:2"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, b1])
        run.markMissionSquadAutostartSuppressed(forAssignmentID: a1.id)
        XCTAssertTrue(run.shouldSuppressAutopilotAutostart(forSquadAssignmentID: a1.id, taskID: taskA.id, mission: mission))
        XCTAssertFalse(run.shouldSuppressAutopilotAutostart(forSquadAssignmentID: b1.id, taskID: taskB.id, mission: mission))
    }
}
