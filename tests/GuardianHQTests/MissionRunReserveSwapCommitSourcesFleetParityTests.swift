import Foundation
import XCTest

@testable import GuardianHQ

/// Both floating pool and fixed template reserve swap-in commits under the **same** ``FleetLinkService`` + ``SitlService``
/// attachment pattern used across mission-run reserve tests (``seedMissionRunTestLiveVehicle``).
@MainActor
final class MissionRunReserveSwapCommitSourcesFleetParityTests: XCTestCase {

    private func makeAttachedFleet() -> (fleet: FleetLinkService, sitl: SitlService) {
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        return (fleet, sitl)
    }

    private func samplePrimaryReserveMission() -> Mission {
        let tid = UUID()
        let primaryDevice = RosterDevice(name: "Lead", role: .none, slot: .primary)
        let reserveDevice = RosterDevice(name: "Bench", role: .none, slot: .reserve)
        let task = MissionTask(
            id: tid,
            name: "Alpha",
            enabled: true,
            rosterDeviceIds: [primaryDevice.id, reserveDevice.id]
        )
        return Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [primaryDevice, reserveDevice],
            routeMacro: RouteMacro(tasks: [task])
        )
    }

    func test_commit_routing_policy_surfaces_for_pool_berth_vs_fixed_reserve_row() {
        let poolID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let rowID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
        XCTAssertEqual(
            MissionRunReserveSwapCommitRoutingPolicy.executionSurface(for: .floatingPoolBerth(slotID: poolID)),
            .swapRosterAssignmentWithRandomFloatingReserve
        )
        XCTAssertEqual(
            MissionRunReserveSwapCommitRoutingPolicy.executionSurface(for: .fixedTemplateReserveRosterRow(assignmentID: rowID)),
            .commitReserveSwapInPending
        )
    }

    func test_floating_pool_targeted_commit_succeeds_with_attached_fleet_services() {
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
        let (fleet, sitl) = makeAttachedFleet()
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
            triggerSource: "test.parity.pool"
        )
        guard case .success(let used, _) = out else {
            XCTFail("expected success, got \(out)")
            return
        }
        XCTAssertEqual(used, poolSlotID)
        XCTAssertEqual(run.assignments[0].attachedFleetVehicleToken, "live")
        let pool = run.reservePool(forTaskID: tid)
        XCTAssertEqual(pool.entries[0].id, poolSlotID)
        XCTAssertEqual(pool.entries[0].attachedFleetVehicleToken, nil)
        XCTAssertEqual(pool.entries[0].attachedDevice, "LEGACY")
    }

    func test_fixed_template_reserve_commit_succeeds_with_attached_fleet_services() {
        let mission = samplePrimaryReserveMission()
        let tid = mission.routeMacro.tasks[0].id
        let primaryDevice = mission.rosterDevices.first { $0.slot == .primary }!
        let reserveDevice = mission.rosterDevices.first { $0.slot == .reserve }!

        let primaryAssignment = MissionRunAssignment(
            taskId: tid,
            rosterDeviceId: primaryDevice.id,
            slotName: primaryDevice.name,
            attachedDevice: "",
            attachedFleetVehicleToken: "live"
        )
        let reserveAssignment = MissionRunAssignment(
            taskId: tid,
            rosterDeviceId: reserveDevice.id,
            slotName: reserveDevice.name,
            attachedDevice: "Reserve bench",
            attachedFleetVehicleToken: nil
        )
        let (fleet, sitl) = makeAttachedFleet()
        let run = MissionRunEnvironment(
            missionId: mission.id,
            missionName: mission.name,
            assignments: [primaryAssignment, reserveAssignment]
        )
        run.updateTemplate(mission)
        run.attachServices(fleetLink: fleet, sitl: sitl)

        let outcome = run.swapRosterVacancyWithFixedTemplateReserveAssignment(
            vacancyAssignmentID: primaryAssignment.id,
            reserveAssignmentID: reserveAssignment.id,
            taskID: tid,
            triggerSource: "test.parity.fixed"
        )
        XCTAssertEqual(outcome, .success)

        let p = run.assignments.first { $0.id == primaryAssignment.id }!
        let r = run.assignments.first { $0.id == reserveAssignment.id }!
        XCTAssertNil(p.attachedFleetVehicleToken)
        XCTAssertEqual(p.attachedDevice, "Reserve bench")
        XCTAssertEqual(r.attachedFleetVehicleToken, "live")
        XCTAssertEqual(r.attachedDevice, "")
    }
}
