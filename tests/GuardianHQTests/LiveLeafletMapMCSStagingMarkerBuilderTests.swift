import XCTest

@testable import GuardianHQ

@MainActor
final class LiveLeafletMapMCSStagingMarkerBuilderTests: XCTestCase {

    func test_staging_motion_digest_includes_pending_sim_sync_flag() {
        var synced = MapVehicleMarker(id: "a", lat: 1, lon: 2, label: "S", colorHex: "#000000", selected: false, draggable: false)
        synced.pendingSimSync = false
        var pending = MapVehicleMarker(id: "b", lat: 3, lon: 4, label: "P", colorHex: "#000000", selected: false, draggable: false)
        pending.pendingSimSync = true
        let digest = LiveLeafletMapMCSStagingMarkerMotionDigest.make(from: [pending, synced])
        XCTAssertTrue(digest.contains("a:1.00000:2.00000:0"))
        XCTAssertTrue(digest.contains("b:3.00000:4.00000:1"))
    }

    func test_build_empty_when_no_bound_assignments() {
        let mission = Mission(id: UUID(), name: "M", description: "", type: .mobile)
        let run = MissionRunEnvironment(mission: mission)
        let inputs = LiveLeafletMapMCSStagingMarkerBuildInputs.missionControlSetupStaging(
            run: run,
            mission: mission,
            fleetLink: FleetLinkService(),
            sitl: SitlService(),
            selectedAssignmentID: nil,
            selectedReservePoolTaskID: nil,
            selectedReservePoolSlotID: nil,
            rosterSimDragByAssignmentID: [:],
            poolSimDragByMarkerID: [:]
        )
        let result = LiveLeafletMapMCSStagingMarkerBuilder.build(inputs: inputs)
        XCTAssertTrue(result.markers.isEmpty)
        XCTAssertEqual(result.motionDigest, "")
    }

    func test_build_sitl_roster_marker_with_seeded_hub() {
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
        hub.latitudeDeg = -33.8
        hub.longitudeDeg = 151.2
        fleet.seedMissionRunTestSitlCleanupStream(vehicleID: vid, systemID: 1, hub: hub)

        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        let inputs = LiveLeafletMapMCSStagingMarkerBuildInputs.missionControlSetupStaging(
            run: run,
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            selectedAssignmentID: assignID,
            selectedReservePoolTaskID: nil,
            selectedReservePoolSlotID: nil,
            rosterSimDragByAssignmentID: [:],
            poolSimDragByMarkerID: [:]
        )
        let cache = LiveLeafletMapMarkerCache(maxEntries: 8)
        let result = LiveLeafletMapMCSStagingMarkerBuilder.build(inputs: inputs, imageCache: cache)
        XCTAssertEqual(result.markers.count, 1)
        XCTAssertEqual(result.markers[0].label, "Primary (SIM)")
        XCTAssertTrue(result.markers[0].draggable)
        XCTAssertEqual(cache.statistics.encodes, 1)
    }
}
