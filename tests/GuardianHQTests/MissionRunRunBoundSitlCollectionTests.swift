import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunRunBoundSitlCollectionTests: XCTestCase {

    func test_allSitlInstanceUUIDsBoundOnRun_collects_roster_and_pool_dedupes() {
        let uRoster = UUID()
        let uPool = UUID()
        let uDup = UUID()
        let task = MissionTask(name: "T", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let rosterRow = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "P1",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(uRoster).storageKey
        )
        let secondRoster = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "P2",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(uDup).storageKey
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [rosterRow, secondRoster])
        let poolSlotA = MissionRunReservePoolSlot(
            label: "A",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(uPool).storageKey
        )
        let poolSlotDup = MissionRunReservePoolSlot(
            label: "B",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(uDup).storageKey
        )
        run.setReservePool(MissionRunReservePool(entries: [poolSlotA, poolSlotDup]), forTaskID: task.id)

        let ids = run.allSitlInstanceUUIDsBoundOnRun()
        XCTAssertEqual(ids, [uRoster, uDup, uPool])
    }

    func test_allSitlInstanceUUIDsBoundOnRun_ignores_live_token() {
        let task = MissionTask(name: "T", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "P1",
            attachedFleetVehicleToken: FleetMissionVehicleToken.live.storageKey
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        XCTAssertTrue(run.allSitlInstanceUUIDsBoundOnRun().isEmpty)
    }
}
