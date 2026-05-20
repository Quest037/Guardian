import XCTest

@testable import GuardianCore

@MainActor
final class LiveDriveMapMarkerMotionDigestTests: XCTestCase {

    func test_freestyle_motion_digest_uses_quantized_hub_coordinates() {
        let sample = LiveLeafletMapMarkerMotionSample(
            id: MapVehicleMarkerIdentity.fleetHubVehicle("vid-1"),
            lat: -37.813627891,
            lon: 144.963057612,
            headingDeg: 90.0049
        )
        let d1 = LiveLeafletMapMarkerMotionDigest.make(from: [sample])
        let d2 = LiveLeafletMapMarkerMotionDigest.make(from: [
            LiveLeafletMapMarkerMotionSample(
                id: MapVehicleMarkerIdentity.fleetHubVehicle("vid-1"),
                lat: -37.8136278914,
                lon: 144.9630576123,
                headingDeg: 90.0051
            ),
        ])
        XCTAssertEqual(d1, d2)
    }

    func test_mission_overlay_build_motion_digest_excludes_image_payload() {
        let sitlId = UUID()
        let assignID = UUID()
        let mission = Mission(id: UUID(), name: "M", description: "", type: .mobile)
        let assign = MissionRunAssignment(
            id: assignID,
            rosterDeviceId: UUID(),
            slotName: "Primary",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlId).storageKey
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlId, stackInstanceIndex: 0)
        guard let vid = resolvedFleetStreamVehicleID(assignment: assign, fleetLink: fleet, sitl: sitl) else {
            XCTFail("Expected stream id")
            return
        }
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = 10
        hub.longitudeDeg = 20
        hub.headingDeg = 45
        fleet.seedMissionRunTestSitlCleanupStream(vehicleID: vid, systemID: 1, hub: hub)

        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        let result = MissionControlLiveDriveMapOverlay.buildLiveMap(
            run: run,
            mission: mission,
            focusedTaskID: nil,
            ldStreamVehicleID: vid,
            fleetLink: fleet,
            sitl: sitl
        )
        XCTAssertFalse(result.motionDigest.isEmpty)
        XCTAssertFalse(result.motionDigest.contains("data:image"))
    }
}
