import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunMCRLiveGeofenceFleetPushTests: XCTestCase {

    func test_mcrUploadResolvedGeofences_noRosterRows_returnsZeroAttempted() async {
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [])
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [])
        let fleet = FleetLinkService()
        let sitl = SitlService()
        let out = await run.mcrUploadResolvedGeofencesToAllFleetAssignments(fleetLink: fleet, sitl: sitl)
        XCTAssertEqual(out.attempted, 0)
        XCTAssertEqual(out.succeeded, 0)
    }

    func test_mcrUploadResolvedGeofences_legacyBindingWithoutFleetToken_skipsSlot() async {
        let task = MissionTask(name: "T")
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "P1",
            attachedDevice: "legacy callsign only",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        let fleet = FleetLinkService()
        let sitl = SitlService()
        let out = await run.mcrUploadResolvedGeofencesToAllFleetAssignments(fleetLink: fleet, sitl: sitl)
        XCTAssertEqual(out.attempted, 0)
        XCTAssertEqual(out.succeeded, 0)
    }
}
