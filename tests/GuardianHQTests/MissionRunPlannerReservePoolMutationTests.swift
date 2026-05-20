import Foundation
import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunPlannerReservePoolMutationTests: XCTestCase {

    func test_reservePoolContainsFleetVehicleStorageKey_trims_and_matches() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "p", attachedFleetVehicleToken: "  fleet:A  ", attachedDevice: ""),
            ]),
            forTaskID: task.id
        )
        XCTAssertTrue(run.reservePoolContainsFleetVehicleStorageKey("fleet:A"))
        XCTAssertFalse(run.reservePoolContainsFleetVehicleStorageKey("fleet:B"))
        XCTAssertFalse(run.reservePoolContainsFleetVehicleStorageKey("   "))
    }

    func test_applyMutation_replaceAssignmentVehicleToken_rejected_when_token_held_in_pool() {
        let primary = RosterDevice(name: "Primary", slot: .primary)
        let task = MissionTask(name: "T", rosterDeviceIds: [primary.id])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [primary],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assign = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: primary.id,
            slotName: primary.name,
            attachedDevice: "",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "berth", attachedFleetVehicleToken: "held-in-pool", attachedDevice: ""),
            ]),
            forTaskID: task.id
        )
        let fleet: [MissionPickableFleetVehicle] = []
        let rejected = run.systems.planner.applyMutation(
            .replaceAssignmentVehicleToken(assignmentID: assign.id, vehicleTokenKey: "held-in-pool"),
            mission: mission,
            fleetVehicles: fleet
        )
        XCTAssertNil(rejected)
        XCTAssertNil(run.assignments[0].attachedFleetVehicleToken)

        let accepted = run.systems.planner.applyMutation(
            .replaceAssignmentVehicleToken(assignmentID: assign.id, vehicleTokenKey: "free-key"),
            mission: mission,
            fleetVehicles: fleet
        )
        XCTAssertNotNil(accepted)
        XCTAssertEqual(run.assignments[0].attachedFleetVehicleToken, "free-key")
    }

    func test_applyMutation_updateAssignmentTask_rejected_when_destination_task_pool_holds_same_token() {
        let pA = RosterDevice(name: "PA", slot: .primary)
        let pB = RosterDevice(name: "PB", slot: .primary)
        let tA = MissionTask(name: "A", rosterDeviceIds: [pA.id])
        let tB = MissionTask(name: "B", rosterDeviceIds: [pB.id])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [pA, pB],
            routeMacro: RouteMacro(tasks: [tA, tB])
        )
        let assignA = MissionRunAssignment(
            id: UUID(),
            taskId: tA.id,
            rosterDeviceId: pA.id,
            slotName: pA.name,
            attachedDevice: "",
            attachedFleetVehicleToken: "shared-tok"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [assignA])
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "r", attachedFleetVehicleToken: "shared-tok", attachedDevice: ""),
            ]),
            forTaskID: tB.id
        )
        let fleet: [MissionPickableFleetVehicle] = []
        let rejected = run.systems.planner.applyMutation(
            .updateAssignmentTask(assignmentID: assignA.id, taskID: tB.id),
            mission: mission,
            fleetVehicles: fleet
        )
        XCTAssertNil(rejected)
        XCTAssertEqual(run.assignments[0].taskId, tA.id)

        run.clearReservePool(forTaskID: tB.id)
        let accepted = run.systems.planner.applyMutation(
            .updateAssignmentTask(assignmentID: assignA.id, taskID: tB.id),
            mission: mission,
            fleetVehicles: fleet
        )
        XCTAssertNotNil(accepted)
        XCTAssertEqual(run.assignments[0].taskId, tB.id)
    }
}
