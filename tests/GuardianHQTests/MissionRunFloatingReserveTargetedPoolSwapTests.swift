import Foundation
import XCTest

@testable import GuardianHQ

@MainActor
final class MissionRunFloatingReserveTargetedPoolSwapTests: XCTestCase {

    func test_targeted_pool_swap_succeeds_when_slot_is_enumerated() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "LEGACY",
            attachedFleetVehicleToken: nil
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let tid = task.id
        let poolSlotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(
                    id: poolSlotID,
                    label: "P1",
                    attachedFleetVehicleToken: "live",
                    attachedDevice: ""
                ),
            ]),
            forTaskID: tid
        )
        let out = run.swapRosterAssignmentWithFloatingReservePoolSlot(
            assignmentID: assignID,
            taskID: tid,
            poolSlotID: poolSlotID,
            triggerSource: "test"
        )
        guard case .success(let used, _) = out else {
            XCTFail("expected success, got \(out)")
            return
        }
        XCTAssertEqual(used, poolSlotID)
        XCTAssertEqual(run.assignments[0].attachedFleetVehicleToken, "live")
        let pool = run.reservePool(forTaskID: tid)
        XCTAssertEqual(pool.entries.count, 1)
        XCTAssertEqual(pool.entries[0].id, poolSlotID)
        XCTAssertEqual(pool.entries[0].attachedFleetVehicleToken, nil)
        XCTAssertEqual(pool.entries[0].attachedDevice, "LEGACY")

        let keys = run.events.compactMap(\.templateKey)
        XCTAssertTrue(keys.contains(MissionRunLogTemplateKey.floatingReserveSwapEngaged))
        XCTAssertTrue(keys.contains(MissionRunReserveSwapPhaseLogTemplateKey.templateKey(phase: .rosterCommit, passed: true)))
    }

    func test_targeted_pool_swap_returns_poolSlotNotEligible_for_other_task_pool_berth() {
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
        let vacancyA = MissionRunAssignment(
            id: UUID(),
            taskId: tA.id,
            rosterDeviceId: pA.id,
            slotName: "A1",
            attachedDevice: "on",
            attachedFleetVehicleToken: "vacancy"
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancyA])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let poolOnB = UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(
                    id: poolOnB,
                    label: "PoolB",
                    attachedFleetVehicleToken: "live",
                    attachedDevice: ""
                ),
            ]),
            forTaskID: tB.id
        )
        let out = run.swapRosterAssignmentWithFloatingReservePoolSlot(
            assignmentID: vacancyA.id,
            taskID: tA.id,
            poolSlotID: poolOnB,
            triggerSource: "test"
        )
        XCTAssertEqual(out, .poolSlotNotEligible)
    }

    func test_targeted_pool_swap_returns_blockedBySessionPhase_when_session_completed() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "LEGACY",
            attachedFleetVehicleToken: nil
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let tid = task.id
        let poolSlotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(
                    id: poolSlotID,
                    label: "P1",
                    attachedFleetVehicleToken: "live",
                    attachedDevice: ""
                ),
            ]),
            forTaskID: tid
        )
        run.setSessionPhase(.completed)
        let out = run.swapRosterAssignmentWithFloatingReservePoolSlot(
            assignmentID: assignID,
            taskID: tid,
            poolSlotID: poolSlotID,
            triggerSource: "test"
        )
        XCTAssertEqual(out, .blockedBySessionPhase)
    }
}
