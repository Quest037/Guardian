import Foundation
import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunOrderedStartRunPreflightProbeTargetsTests: XCTestCase {

    func test_ordered_targets_default_is_roster_only_skips_filled_pool_slots() {
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
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].identity, .rosterAssignment(assign.id))
        XCTAssertEqual(targets[0].displayTitle, "Primary")
        XCTAssertEqual(targets[0].assignment.id, assign.id)
    }

    func test_ordered_targets_include_pool_slots_when_flag_true() {
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

        let targets = run.orderedStartRunPreflightProbeTargets(includeFloatingReservePoolSlots: true)
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

    func test_preflight_probe_sections_group_roster_slots_by_mission_task_order() {
        let rd1 = RosterDevice(id: UUID(), name: "Alpha-1", role: .none, slot: .primary, vehicleClass: .uavCopter)
        let rd2 = RosterDevice(id: UUID(), name: "Bravo-1", role: .none, slot: .primary, vehicleClass: .uavCopter)
        var taskFirst = MissionTask(name: "First task")
        taskFirst.rosterDeviceIds = [rd1.id]
        var taskSecond = MissionTask(name: "Second task")
        taskSecond.rosterDeviceIds = [rd2.id]
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd1, rd2],
            routeMacro: RouteMacro(tasks: [taskFirst, taskSecond])
        )
        let a1 = MissionRunAssignment(
            id: UUID(),
            taskId: taskFirst.id,
            rosterDeviceId: rd1.id,
            slotName: "Slot A",
            attachedDevice: "",
            attachedFleetVehicleToken: "live"
        )
        let a2 = MissionRunAssignment(
            id: UUID(),
            taskId: taskSecond.id,
            rosterDeviceId: rd2.id,
            slotName: "Slot B",
            attachedDevice: "",
            attachedFleetVehicleToken: "live"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])

        let sections = run.orderedStartRunPreflightProbeSections(mission: mission)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "First task")
        XCTAssertEqual(sections[0].targets.map(\.assignment.id), [a1.id])
        XCTAssertEqual(sections[1].title, "Second task")
        XCTAssertEqual(sections[1].targets.map(\.assignment.id), [a2.id])

        let flat = run.orderedStartRunPreflightProbeSequence(mission: mission)
        XCTAssertEqual(flat.map(\.assignment.id), [a1.id, a2.id])
    }
}
