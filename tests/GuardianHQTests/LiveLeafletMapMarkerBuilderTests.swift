import XCTest

@testable import GuardianHQ

@MainActor
final class LiveLeafletMapMarkerBuilderTests: XCTestCase {

    // MARK: - Motion digest

    func test_motion_digest_stable_for_quantized_coordinates() {
        let samples = [
            LiveLeafletMapMarkerMotionSample(
                id: "a",
                lat: -37.813627891,
                lon: 144.963057612,
                headingDeg: 90.0049
            ),
        ]
        let d1 = LiveLeafletMapMarkerMotionDigest.make(from: samples)
        let d2 = LiveLeafletMapMarkerMotionDigest.make(from: [
            LiveLeafletMapMarkerMotionSample(
                id: "a",
                lat: -37.8136278914,
                lon: 144.9630576123,
                headingDeg: 90.0051
            ),
        ])
        XCTAssertEqual(d1, d2)
    }

    func test_motion_digest_changes_when_position_moves_past_quantization() {
        let base = LiveLeafletMapMarkerMotionSample(id: "row", lat: 1.0, lon: 2.0, headingDeg: 0)
        let moved = LiveLeafletMapMarkerMotionSample(id: "row", lat: 1.00002, lon: 2.0, headingDeg: 0)
        XCTAssertNotEqual(
            LiveLeafletMapMarkerMotionDigest.make(from: [base]),
            LiveLeafletMapMarkerMotionDigest.make(from: [moved])
        )
    }

    func test_motion_digest_from_markers_ignores_image_data_url() {
        var m1 = MapVehicleMarker(id: "x", lat: 1, lon: 2, label: "S", colorHex: "#000000", selected: false, draggable: false)
        m1.imageDataURL = "data:image/png;base64,AAA"
        var m2 = MapVehicleMarker(id: "x", lat: 1, lon: 2, label: "S", colorHex: "#000000", selected: false, draggable: false)
        m2.imageDataURL = "data:image/png;base64,BBB"
        XCTAssertEqual(
            LiveLeafletMapMarkerMotionDigest.make(from: [m1]),
            LiveLeafletMapMarkerMotionDigest.make(from: [m2])
        )
    }

    // MARK: - Builder edges

    func test_build_empty_when_roster_unbound_and_no_hub() {
        let mission = Mission(id: UUID(), name: "M", description: "", type: .mobile)
        let assign = MissionRunAssignment(id: UUID(), rosterDeviceId: UUID(), slotName: "S")
        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        let inputs = LiveLeafletMapMarkerBuildInputs(
            rosterAssignments: run.assignments,
            mission: mission,
            reservePoolsByTaskID: [:],
            fleetLink: FleetLinkService(),
            sitl: SitlService(),
            rosterScope: LiveLeafletMapMarkerRosterScope(taskFocusID: nil),
            floatingReservePoolScope: LiveLeafletMapFloatingReservePoolScope(taskIDs: []),
            presentation: LiveLeafletMapMarkerPresentationState(),
            reservePoolPresentation: LiveLeafletMapReservePoolPresentationState()
        )
        let result = LiveLeafletMapMarkerBuilder.build(inputs: inputs)
        XCTAssertTrue(result.markers.isEmpty)
        XCTAssertEqual(result.motionDigest, "")
    }

    func test_build_roster_marker_with_seeded_hub() {
        let sitlId = UUID()
        let assignID = UUID()
        let rd = RosterDevice(id: UUID(), name: "P1", vehicleClass: .uavCopter)
        let task = MissionTask(name: "T", enabled: true, waypoints: [])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assign = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd.id,
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
        hub.latitudeDeg = -37.8
        hub.longitudeDeg = 144.9
        hub.headingDeg = 45
        fleet.seedMissionRunTestSitlCleanupStream(vehicleID: vid, systemID: 1, hub: hub)

        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        let inputs = LiveLeafletMapMarkerBuildInputs.liveDriveMissionOverlay(
            run: run,
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            focusedTaskID: nil,
            ldStreamVehicleID: vid
        )
        let cache = LiveLeafletMapMarkerCache(maxEntries: 8)
        let result = LiveLeafletMapMarkerBuilder.build(inputs: inputs, imageCache: cache)
        XCTAssertEqual(result.markers.count, 1)
        XCTAssertEqual(result.markers[0].id, MapVehicleMarkerIdentity.missionRunAssignment(assignID))
        XCTAssertEqual(result.markers[0].lat, -37.8)
        XCTAssertEqual(result.markers[0].glyphKind, .uavArrow)
        XCTAssertNil(result.markers[0].imageDataURL)
        XCTAssertFalse(result.motionDigest.isEmpty)
        XCTAssertEqual(cache.statistics.encodes, 0)
    }

    func test_second_build_with_moved_coordinates_does_not_touch_image_cache() {
        let sitlId = UUID()
        let assignID = UUID()
        let rd = RosterDevice(id: UUID(), name: "P1", vehicleClass: .uavCopter)
        let task = MissionTask(name: "T", enabled: true, waypoints: [])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assign = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd.id,
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

        func seedHub(lat: Double, lon: Double) {
            var hub = FleetHubVehicleTelemetry.empty
            hub.latitudeDeg = lat
            hub.longitudeDeg = lon
            fleet.seedMissionRunTestSitlCleanupStream(vehicleID: vid, systemID: 1, hub: hub)
        }

        seedHub(lat: 10, lon: 20)
        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        let cache = LiveLeafletMapMarkerCache(maxEntries: 8)
        let inputs = LiveLeafletMapMarkerBuildInputs.liveDriveMissionOverlay(
            run: run,
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            focusedTaskID: nil,
            ldStreamVehicleID: vid
        )

        let first = LiveLeafletMapMarkerBuilder.build(inputs: inputs, imageCache: cache)
        XCTAssertEqual(cache.statistics.encodes, 0)

        seedHub(lat: 10.00002, lon: 20)
        let second = LiveLeafletMapMarkerBuilder.build(inputs: inputs, imageCache: cache)

        XCTAssertNotEqual(first.motionDigest, second.motionDigest)
        XCTAssertEqual(second.markers[0].lat, 10.00002)
        XCTAssertEqual(cache.statistics.encodes, 0)
        XCTAssertEqual(cache.statistics.hits, 0)
    }

    func test_roster_marker_selected_assignment_shows_map_label_without_ld_highlight() {
        let sitlId = UUID()
        let assignID = UUID()
        let rd = RosterDevice(id: UUID(), name: "P1", vehicleClass: .uavCopter)
        let task = MissionTask(name: "T", enabled: true, waypoints: [])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assign = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd.id,
            slotName: "Echo-1",
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
        hub.latitudeDeg = -37.8
        hub.longitudeDeg = 144.9
        fleet.seedMissionRunTestSitlCleanupStream(vehicleID: vid, systemID: 1, hub: hub)

        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        let inputs = LiveLeafletMapMarkerBuildInputs.missionControlLiveOverview(
            run: run,
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            isolateMapToSelectedTask: false,
            triageFocusedTaskID: nil,
            presentation: LiveLeafletMapMarkerPresentationState(selectedAssignmentID: assignID),
            reservePoolPresentation: LiveLeafletMapReservePoolPresentationState()
        )
        let result = LiveLeafletMapMarkerBuilder.build(inputs: inputs)
        XCTAssertEqual(result.markers.count, 1)
        XCTAssertTrue(result.markers[0].selected)
        XCTAssertTrue(result.markers[0].showLabel)
        XCTAssertEqual(result.markers[0].label, "Echo-1")
    }

    func test_utilities_namespace_build_matches_builder() {
        let mission = Mission(id: UUID(), name: "M", description: "", type: .mobile)
        let inputs = LiveLeafletMapMarkerBuildInputs(
            rosterAssignments: [],
            mission: mission,
            reservePoolsByTaskID: [:],
            fleetLink: FleetLinkService(),
            sitl: SitlService(),
            rosterScope: LiveLeafletMapMarkerRosterScope(taskFocusID: nil),
            floatingReservePoolScope: LiveLeafletMapFloatingReservePoolScope(taskIDs: []),
            presentation: LiveLeafletMapMarkerPresentationState(),
            reservePoolPresentation: LiveLeafletMapReservePoolPresentationState()
        )
        let viaUtilities = Utilities.liveLeafletMap.buildMapVehicleMarkersLive(inputs: inputs)
        let direct = LiveLeafletMapMarkerBuilder.build(inputs: inputs)
        XCTAssertEqual(viaUtilities, direct)
    }
}
