import XCTest
@testable import GuardianHQ

@MainActor
final class MCRLiveTaskTriageProgressCardPresentationResolverTests: XCTestCase {

    func test_presentation_prefers_coordinator_row_over_makeRowSnapshot() {
        let rd = UUID()
        let task = MissionTask(
            name: "Alpha",
            enabled: true,
            rosterDeviceIds: [rd]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assign = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Alpha:1"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        let fleet = FleetLinkService()
        let sitl = SitlService()
        let coordinator = MCRLiveTaskListSnapshotCoordinator()
        coordinator.apply(run: run, mission: mission, fleetLink: fleet, sitl: sitl, now: Date())

        let fromCoordinator = coordinator.presentations.first(where: { $0.taskID == task.id })
        XCTAssertNotNil(fromCoordinator)

        let resolved = MCRLiveTaskTriageProgressCardPresentationResolver.presentation(
            coordinator: coordinator,
            run: run,
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            task: task,
            taskIndex: 0,
            now: Date()
        )
        XCTAssertEqual(resolved, fromCoordinator)
    }
}
