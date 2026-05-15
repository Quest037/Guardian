import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunAssignmentLiveProjectionTests: XCTestCase {
    func test_reserveSwapStripRole_inactiveWithoutPick() {
        let tid = UUID()
        let devId = UUID()
        let task = MissionTask(id: tid, name: "Alpha", enabled: true)
        let roster = RosterDevice(id: devId, name: "P1", slot: .primary, vehicleClass: .uavCopter)
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [roster],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(taskId: tid, rosterDeviceId: devId, slotName: "P1")
        let fleet = FleetLinkService()
        let sitl = SitlService()
        let p = MissionRunAssignmentLiveProjection.make(
            assignment: assignment,
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            liveReserveSwapPick: nil,
            focusedLiveTaskID: nil
        )
        XCTAssertEqual(p.reserveSwapStripRole, .inactive)
    }

    func test_reserveSwapStripRole_pickVacancy_matchesVacancyAssignment() {
        let tid = UUID()
        let vacId = UUID()
        let devId = UUID()
        let task = MissionTask(id: tid, name: "Alpha", enabled: true)
        let roster = RosterDevice(id: devId, name: "Vac", slot: .primary, vehicleClass: .uavCopter)
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [roster],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(id: vacId, taskId: tid, rosterDeviceId: devId, slotName: "Vac")
        let pick = LiveReserveSwapPickContext(vacancyAssignmentID: vacId, taskID: tid)
        let fleet = FleetLinkService()
        let sitl = SitlService()
        let p = MissionRunAssignmentLiveProjection.make(
            assignment: vacancy,
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            liveReserveSwapPick: pick,
            focusedLiveTaskID: nil
        )
        XCTAssertEqual(p.reserveSwapStripRole, .pickVacancy)
    }

    func test_reserveSwapStripRole_pickBenchReserve_forReserveRosterSlot() {
        let tid = UUID()
        let vacId = UUID()
        let vacDev = UUID()
        let benchDev = UUID()
        let task = MissionTask(id: tid, name: "Alpha", enabled: true)
        let rosterVac = RosterDevice(id: vacDev, name: "Vac", slot: .primary, vehicleClass: .uavCopter)
        let rosterBench = RosterDevice(id: benchDev, name: "Bench", slot: .reserve, vehicleClass: .uavCopter)
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rosterVac, rosterBench],
            routeMacro: RouteMacro(tasks: [task])
        )
        let benchAssignment = MissionRunAssignment(taskId: tid, rosterDeviceId: benchDev, slotName: "R1")
        let pick = LiveReserveSwapPickContext(vacancyAssignmentID: vacId, taskID: tid)
        let fleet = FleetLinkService()
        let sitl = SitlService()
        let p = MissionRunAssignmentLiveProjection.make(
            assignment: benchAssignment,
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            liveReserveSwapPick: pick,
            focusedLiveTaskID: nil
        )
        XCTAssertEqual(p.reserveSwapStripRole, .pickBenchReserve)
    }
}
