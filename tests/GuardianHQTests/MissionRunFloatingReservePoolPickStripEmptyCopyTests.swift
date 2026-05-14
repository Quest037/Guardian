import Foundation
import XCTest

@testable import GuardianHQ

@MainActor
final class MissionRunFloatingReservePoolPickStripEmptyCopyTests: XCTestCase {

    func test_returns_nil_when_pool_swap_candidate_exists() {
        let primaryID = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [primaryID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .unknown)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "Primary",
            attachedDevice: "x",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "P1", attachedDevice: "pool"),
            ]),
            forTaskID: task.id
        )
        XCTAssertNil(run.floatingReservePoolPickStripEmptyOperatorCopy(vacancyAssignmentID: vacancy.id, taskID: task.id))
    }

    func test_empty_no_reserve_berths_on_task() {
        let primaryID = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [primaryID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .unknown)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "Primary",
            attachedDevice: "x",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        let copy = run.floatingReservePoolPickStripEmptyOperatorCopy(vacancyAssignmentID: vacancy.id, taskID: task.id)
        XCTAssertEqual(copy?.title, "No reserve berths")
        XCTAssertTrue(copy?.subtitle.contains("Add floating reserve slots") ?? false)
    }

    func test_empty_no_bindings_in_pool_berths() {
        let primaryID = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [primaryID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .unknown)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "Primary",
            attachedDevice: "x",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "Empty", attachedFleetVehicleToken: nil, attachedDevice: ""),
            ]),
            forTaskID: task.id
        )
        let copy = run.floatingReservePoolPickStripEmptyOperatorCopy(vacancyAssignmentID: vacancy.id, taskID: task.id)
        XCTAssertEqual(copy?.title, "No bound reserves")
        XCTAssertTrue(copy?.subtitle.contains("Bind vehicles") ?? false)
    }

    func test_empty_class_mismatch_shows_template_class() {
        let primaryID = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [primaryID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "Primary",
            attachedDevice: "x",
            attachedFleetVehicleToken: nil
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavFixedWing)
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "Wing", attachedFleetVehicleToken: "live", attachedDevice: "sim"),
            ]),
            forTaskID: task.id
        )
        let copy = run.floatingReservePoolPickStripEmptyOperatorCopy(vacancyAssignmentID: vacancy.id, taskID: task.id)
        XCTAssertEqual(copy?.title, "No matching reserves")
        XCTAssertTrue(copy?.subtitle.contains("No floating reserve matches") ?? false)
    }

    func test_empty_duplicate_fleet_token_across_pool_and_vacancy() {
        let primaryID = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [primaryID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .unknown)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let sharedTok = "live"
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "Primary",
            attachedDevice: "on",
            attachedFleetVehicleToken: sharedTok
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "Pool", attachedFleetVehicleToken: sharedTok, attachedDevice: "p"),
            ]),
            forTaskID: task.id
        )
        let copy = run.floatingReservePoolPickStripEmptyOperatorCopy(vacancyAssignmentID: vacancy.id, taskID: task.id)
        XCTAssertEqual(copy?.title, "No other reserves")
        XCTAssertTrue(copy?.subtitle.contains("fleet binding") ?? false)
    }

    func test_bench_reserve_hint_when_no_pool_but_template_reserve_row_exists() {
        let primaryID = UUID()
        let reserveID = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [primaryID, reserveID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .unknown),
                RosterDevice(id: reserveID, name: "Bench", slot: .reserve, vehicleClass: .unknown),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "Primary",
            attachedDevice: "x",
            attachedFleetVehicleToken: nil
        )
        let reserveAssignment = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: reserveID,
            slotName: "R",
            attachedDevice: "bench text",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy, reserveAssignment])
        let copy = run.floatingReservePoolPickStripEmptyOperatorCopy(vacancyAssignmentID: vacancy.id, taskID: task.id)
        XCTAssertEqual(copy?.title, "No reserve berths")
        XCTAssertTrue(copy?.subtitle.contains("template reserve row") ?? false)
    }

    func test_empty_all_pool_vehicles_written_off_for_reserve_draws() {
        let primaryID = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [primaryID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .unknown)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "Primary",
            attachedDevice: "x",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "A", attachedFleetVehicleToken: "tokA", attachedDevice: "a"),
                MissionRunReservePoolSlot(label: "B", attachedFleetVehicleToken: "tokB", attachedDevice: "b"),
            ]),
            forTaskID: task.id
        )
        run.markFleetVehicleWrittenOffForReservePool(storageKey: "tokA")
        run.markFleetVehicleWrittenOffForReservePool(storageKey: "tokB")
        let copy = run.floatingReservePoolPickStripEmptyOperatorCopy(vacancyAssignmentID: vacancy.id, taskID: task.id)
        XCTAssertEqual(copy?.title, "No eligible reserves")
        XCTAssertTrue(copy?.subtitle.contains("floating reserve vehicles") ?? false)
        XCTAssertTrue(copy?.subtitle.contains("written off") ?? false)
    }
}
