import Foundation
import XCTest

@testable import GuardianHQ

@MainActor
final class MissionRunReserveSwapCandidateEnumerationTests: XCTestCase {

    func test_enumerate_candidates_empty_when_vacancy_not_on_task() {
        let tA = MissionTask(name: "A")
        let tB = MissionTask(name: "B")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [tA, tB])
        )
        let assignA = MissionRunAssignment(
            id: UUID(),
            taskId: tA.id,
            rosterDeviceId: UUID(),
            slotName: "P",
            attachedDevice: "X",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [assignA])
        XCTAssertTrue(run.enumerateReserveSwapCandidates(vacancyAssignmentID: assignA.id, taskID: tB.id).isEmpty)
    }

    func test_enumerate_pool_only_matches_class_filtered_available_entries() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .unknown)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "LIVE",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        let tid = task.id
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "A", attachedDevice: "poolA"),
                MissionRunReservePoolSlot(label: "B", attachedDevice: "poolB"),
            ]),
            forTaskID: tid
        )
        let expected = run.availableReservePoolEntries(forTaskID: tid, classCompatibleWithAssignmentId: vacancy.id).count
        let candidates = run.enumerateReserveSwapCandidates(vacancyAssignmentID: vacancy.id, taskID: tid)
        XCTAssertEqual(candidates.count, expected)
        XCTAssertTrue(candidates.allSatisfy {
            if case .floatingPool(let t, _) = $0 { return t == tid }
            return false
        })
    }

    func test_enumerate_includes_fixed_roster_reserve_on_same_task() {
        let primaryID = UUID()
        let reserveID = UUID()
        let task = MissionTask(
            name: "Alpha",
            rosterDeviceIds: [primaryID, reserveID]
        )
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
            attachedDevice: "On station",
            attachedFleetVehicleToken: nil
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let reserveAssignment = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: reserveID,
            slotName: "Reserve",
            attachedDevice: "Bench sim",
            attachedFleetVehicleToken: "live"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy, reserveAssignment])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let tid = task.id
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!, label: "Pool1", attachedDevice: "p1"),
            ]),
            forTaskID: tid
        )
        let candidates = run.enumerateReserveSwapCandidates(vacancyAssignmentID: vacancy.id, taskID: tid)
        XCTAssertEqual(candidates.count, 2, "pool + fixed reserve")
        XCTAssertEqual(candidates.filter { if case .fixedRosterReserve = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(candidates.filter { if case .floatingPool = $0 { return true }; return false }.count, 1)
    }

    func test_enumerate_excludes_fixed_reserve_wrong_fleet_class() {
        let primaryID = UUID()
        let reserveID = UUID()
        let task = MissionTask(name: "Alpha", rosterDeviceIds: [primaryID, reserveID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .uavCopter),
                RosterDevice(id: reserveID, name: "Bench", slot: .reserve, vehicleClass: .uavCopter),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "Primary",
            attachedDevice: "X",
            attachedFleetVehicleToken: nil
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavFixedWing)
        let reserveAssignment = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: reserveID,
            slotName: "Reserve",
            attachedDevice: "Sim",
            attachedFleetVehicleToken: "live"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy, reserveAssignment])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let candidates = run.enumerateReserveSwapCandidates(vacancyAssignmentID: vacancy.id, taskID: task.id)
        XCTAssertTrue(candidates.allSatisfy {
            if case .fixedRosterReserve = $0 { return false }
            return true
        }, "fixed-wing live reserve must not match copter vacancy")
    }

    func test_enumerate_fixed_reserves_sorted_by_slot_name() {
        let primaryID = UUID()
        let reserveA = UUID()
        let reserveZ = UUID()
        let task = MissionTask(name: "Alpha", rosterDeviceIds: [primaryID, reserveA, reserveZ])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .unknown),
                RosterDevice(id: reserveA, name: "A", slot: .reserve, vehicleClass: .unknown),
                RosterDevice(id: reserveZ, name: "Z", slot: .reserve, vehicleClass: .unknown),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "Primary",
            attachedDevice: "X",
            attachedFleetVehicleToken: nil
        )
        let ra = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: reserveZ,
            slotName: "Zebra reserve",
            attachedDevice: "z",
            attachedFleetVehicleToken: nil
        )
        let rb = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: reserveA,
            slotName: "Alpha reserve",
            attachedDevice: "a",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy, ra, rb])
        let rosterNames = run.enumerateReserveSwapCandidates(vacancyAssignmentID: vacancy.id, taskID: task.id).compactMap { c -> String? in
            guard case .fixedRosterReserve(let a) = c else { return nil }
            return a.slotName
        }
        XCTAssertEqual(rosterNames, ["Alpha reserve", "Zebra reserve"])
    }

    func test_enumerate_wingman_vacancy_orders_fixed_reserves_tied_primary_then_auto() {
        let primaryID = UUID()
        let wingID = UUID()
        let reserveTiedID = UUID()
        let reserveAutoID = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [primaryID, wingID, reserveTiedID, reserveAutoID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .unknown),
                RosterDevice(id: wingID, name: "Wing", slot: .wingman, vehicleClass: .unknown, leaderRosterDeviceId: primaryID),
                RosterDevice(id: reserveTiedID, name: "Bench tied", slot: .reserve, vehicleClass: .unknown, leaderRosterDeviceId: primaryID),
                RosterDevice(id: reserveAutoID, name: "Bench auto", slot: .reserve, vehicleClass: .unknown, leaderRosterDeviceId: nil),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let wingVacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: wingID,
            slotName: "Wing",
            attachedDevice: "w",
            attachedFleetVehicleToken: nil
        )
        let aTied = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: reserveTiedID,
            slotName: "Zebra tied",
            attachedDevice: "t",
            attachedFleetVehicleToken: nil
        )
        let aAuto = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: reserveAutoID,
            slotName: "Alpha auto",
            attachedDevice: "a",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [wingVacancy, aTied, aAuto])
        let names = run.enumerateReserveSwapCandidates(vacancyAssignmentID: wingVacancy.id, taskID: task.id).compactMap { c -> String? in
            guard case .fixedRosterReserve(let a) = c else { return nil }
            return a.slotName
        }
        XCTAssertEqual(names, ["Zebra tied", "Alpha auto"])
    }

    func test_enumerate_wingman_vacancy_orders_reserve_tied_other_primary_after_auto() {
        let p1 = UUID()
        let p2 = UUID()
        let wing = UUID()
        let rSame = UUID()
        let rOther = UUID()
        let rAuto = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [p1, p2, wing, rSame, rOther, rAuto])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: p1, name: "P1", slot: .primary, vehicleClass: .unknown),
                RosterDevice(id: p2, name: "P2", slot: .primary, vehicleClass: .unknown),
                RosterDevice(id: wing, name: "W", slot: .wingman, vehicleClass: .unknown, leaderRosterDeviceId: p1),
                RosterDevice(id: rSame, name: "RS", slot: .reserve, vehicleClass: .unknown, leaderRosterDeviceId: p1),
                RosterDevice(id: rOther, name: "RO", slot: .reserve, vehicleClass: .unknown, leaderRosterDeviceId: p2),
                RosterDevice(id: rAuto, name: "RA", slot: .reserve, vehicleClass: .unknown, leaderRosterDeviceId: nil),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let wingVacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: wing,
            slotName: "Wing",
            attachedDevice: "w",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(
            mission: mission,
            assignments: [
                wingVacancy,
                MissionRunAssignment(id: UUID(), taskId: task.id, rosterDeviceId: rOther, slotName: "Res other primary", attachedDevice: "o", attachedFleetVehicleToken: nil),
                MissionRunAssignment(id: UUID(), taskId: task.id, rosterDeviceId: rAuto, slotName: "Res auto", attachedDevice: "a", attachedFleetVehicleToken: nil),
                MissionRunAssignment(id: UUID(), taskId: task.id, rosterDeviceId: rSame, slotName: "Res same primary", attachedDevice: "s", attachedFleetVehicleToken: nil),
            ]
        )
        let names = run.enumerateReserveSwapCandidates(vacancyAssignmentID: wingVacancy.id, taskID: task.id).compactMap { c -> String? in
            guard case .fixedRosterReserve(let a) = c else { return nil }
            return a.slotName
        }
        XCTAssertEqual(names, ["Res same primary", "Res auto", "Res other primary"])
    }

    func test_enumerate_wingman_infer_single_primary_when_leader_unset() {
        let primaryID = UUID()
        let wingID = UUID()
        let reserveTiedID = UUID()
        let reserveAutoID = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [primaryID, wingID, reserveTiedID, reserveAutoID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .unknown),
                RosterDevice(id: wingID, name: "Wing", slot: .wingman, vehicleClass: .unknown, leaderRosterDeviceId: nil),
                RosterDevice(id: reserveTiedID, name: "Bench tied", slot: .reserve, vehicleClass: .unknown, leaderRosterDeviceId: primaryID),
                RosterDevice(id: reserveAutoID, name: "Bench auto", slot: .reserve, vehicleClass: .unknown, leaderRosterDeviceId: nil),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let wingVacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: wingID,
            slotName: "Wing",
            attachedDevice: "w",
            attachedFleetVehicleToken: nil
        )
        let aTied = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: reserveTiedID,
            slotName: "Tied",
            attachedDevice: "t",
            attachedFleetVehicleToken: nil
        )
        let aAuto = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: reserveAutoID,
            slotName: "Auto",
            attachedDevice: "a",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [wingVacancy, aTied, aAuto])
        let names = run.enumerateReserveSwapCandidates(vacancyAssignmentID: wingVacancy.id, taskID: task.id).compactMap { c -> String? in
            guard case .fixedRosterReserve(let a) = c else { return nil }
            return a.slotName
        }
        XCTAssertEqual(names, ["Tied", "Auto"])
    }

    func test_enumerate_default_ordering_pool_slots_before_fixed_roster_reserve() {
        let primaryID = UUID()
        let reserveID = UUID()
        let poolSlotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let task = MissionTask(name: "Alpha", rosterDeviceIds: [primaryID, reserveID])
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
            attachedDevice: "On station",
            attachedFleetVehicleToken: nil
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let reserveAssignment = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: reserveID,
            slotName: "Reserve",
            attachedDevice: "Bench sim",
            attachedFleetVehicleToken: "live"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy, reserveAssignment])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let tid = task.id
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(id: poolSlotID, label: "Pool1", attachedDevice: "p1"),
            ]),
            forTaskID: tid
        )
        let ordered = run.enumerateReserveSwapCandidates(vacancyAssignmentID: vacancy.id, taskID: tid, ordering: .poolSlotsFirst)
        XCTAssertEqual(ordered.count, 2)
        guard case .floatingPool(_, let firstPool) = ordered[0] else {
            return XCTFail("expected pool first")
        }
        XCTAssertEqual(firstPool.id, poolSlotID)
        guard case .fixedRosterReserve(let fixed) = ordered[1] else {
            return XCTFail("expected fixed reserve second")
        }
        XCTAssertEqual(fixed.id, reserveAssignment.id)
    }

    func test_enumerate_fixed_r_first_orders_roster_reserve_before_pool() {
        let primaryID = UUID()
        let reserveID = UUID()
        let poolSlotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let task = MissionTask(name: "Alpha", rosterDeviceIds: [primaryID, reserveID])
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
            attachedDevice: "On station",
            attachedFleetVehicleToken: nil
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let reserveAssignment = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: reserveID,
            slotName: "Reserve",
            attachedDevice: "Bench sim",
            attachedFleetVehicleToken: "live"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy, reserveAssignment])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let tid = task.id
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(id: poolSlotID, label: "Pool1", attachedDevice: "p1"),
            ]),
            forTaskID: tid
        )
        let ordered = run.enumerateReserveSwapCandidates(vacancyAssignmentID: vacancy.id, taskID: tid, ordering: .fixedRosterReservesFirst)
        XCTAssertEqual(ordered.count, 2)
        guard case .fixedRosterReserve(let fixed) = ordered[0] else {
            return XCTFail("expected fixed reserve first for autonomy ordering")
        }
        XCTAssertEqual(fixed.id, reserveAssignment.id)
        guard case .floatingPool(_, let pool) = ordered[1] else {
            return XCTFail("expected pool second")
        }
        XCTAssertEqual(pool.id, poolSlotID)
    }
}
