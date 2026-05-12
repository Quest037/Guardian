import Foundation
import XCTest

@testable import GuardianHQ

@MainActor
final class MissionRunOrderedStartRunPreflightProbeTargetsTests: XCTestCase {

    func test_ordered_targets_roster_then_filled_pool_slots_task_id_sorted() {
        let taskB = MissionTask(name: "Bravo")
        let taskA = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [taskB, taskA])
        )
        let assign = MissionRunAssignment(
            id: UUID(),
            rosterDeviceId: UUID(),
            slotName: "Primary",
            attachedDevice: "",
            attachedFleetVehicleToken: "live"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [assign])

        let slotEmpty = MissionRunReservePoolSlot(label: "Empty", attachedDevice: "  ")
        let sitlB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let slotB1 = MissionRunReservePoolSlot(
            id: sitlB,
            label: "PoolB1",
            attachedFleetVehicleToken: "sitl:\(sitlB.uuidString)",
            attachedDevice: ""
        )
        let slotA1 = MissionRunReservePoolSlot(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            label: "PoolA1",
            attachedDevice: "LEGACY"
        )

        run.setReservePool(MissionRunReservePool(entries: [slotB1, slotEmpty]), forTaskID: taskB.id)
        run.setReservePool(MissionRunReservePool(entries: [slotA1]), forTaskID: taskA.id)

        let targets = run.orderedStartRunPreflightProbeTargets()
        XCTAssertEqual(targets.count, 3)

        XCTAssertEqual(targets[0].identity, .rosterAssignment(assign.id))
        XCTAssertEqual(targets[0].displayTitle, "Primary")
        XCTAssertEqual(targets[0].assignment.id, assign.id)

        let taskOrder = [taskA.id, taskB.id].sorted { $0.uuidString < $1.uuidString }
        XCTAssertEqual(taskOrder[0], taskA.id)

        XCTAssertEqual(targets[1].identity, .floatingReservePool(taskID: taskA.id, slotID: slotA1.id))
        XCTAssertEqual(targets[1].displayTitle, "Alpha reserve · PoolA1")
        XCTAssertEqual(targets[1].assignment.id, slotA1.id)
        XCTAssertEqual(targets[1].assignment.slotName, "PoolA1")

        XCTAssertEqual(targets[2].identity, .floatingReservePool(taskID: taskB.id, slotID: slotB1.id))
        XCTAssertEqual(targets[2].displayTitle, "Bravo reserve · PoolB1")
        XCTAssertEqual(targets[2].assignment.id, slotB1.id)
    }

    func test_synthetic_for_reserve_pool_matches_slot_binding() {
        let sitlID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let slot = MissionRunReservePoolSlot(
            label: "Reserve 1",
            attachedFleetVehicleToken: "sitl:\(sitlID.uuidString)",
            attachedDevice: "call"
        )
        let syn = MissionRunAssignment.syntheticForReservePool(slot: slot)
        XCTAssertEqual(syn.id, slot.id)
        XCTAssertEqual(syn.rosterDeviceId, slot.id)
        XCTAssertEqual(syn.slotName, slot.label)
        XCTAssertEqual(syn.attachedFleetVehicleToken, slot.attachedFleetVehicleToken)
        XCTAssertEqual(syn.attachedDevice, slot.attachedDevice)
    }
}
