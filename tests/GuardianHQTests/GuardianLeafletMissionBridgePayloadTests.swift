import XCTest

@testable import GuardianHQ

final class GuardianLeafletMissionBridgePayloadTests: XCTestCase {

    func test_vehicle_markers_participate_in_payload_equatable() {
        let base = samplePayload()
        let moved = samplePayload(
            vehicleMarkers: [
                MapVehicleMarker(
                    id: "v1",
                    lat: 2,
                    lon: 3,
                    label: "V",
                    colorHex: "#fff",
                    selected: false,
                    draggable: false
                ),
            ]
        )
        XCTAssertEqual(base, base)
        XCTAssertNotEqual(base, moved)
    }

    func test_identical_payloads_produce_identical_javascript() {
        let a = samplePayload()
        let b = samplePayload()
        XCTAssertEqual(a, b)
        XCTAssertEqual(OSMMapView.javascriptExpression(for: a), OSMMapView.javascriptExpression(for: b))
    }

    func test_javascript_includes_stable_marker_id_literal() {
        let assignmentID = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
        let payload = samplePayload(
            vehicleMarkers: [
                MapVehicleMarker(
                    id: MapVehicleMarkerIdentity.missionRunAssignment(assignmentID),
                    lat: 1,
                    lon: 2,
                    label: "A",
                    colorHex: "#111111",
                    selected: true,
                    draggable: false,
                    headingDeg: 90
                ),
            ]
        )
        let js = OSMMapView.javascriptExpression(for: payload)
        XCTAssertTrue(js.contains(assignmentID.uuidString))
        XCTAssertTrue(js.contains("\"heading\":90"))
    }

    private func samplePayload(
        vehicleMarkers: [MapVehicleMarker] = []
    ) -> GuardianLeafletMissionBridgePayload {
        GuardianLeafletMissionBridgePayload(
            home: nil,
            allTasksCoords: [],
            taskPathIDs: [],
            selectedTaskWaypoints: [],
            selectedWaypointIndex: nil,
            vehicleMarkers: vehicleMarkers,
            mapStyle: .standard,
            recenterNonce: 0,
            headingPreview: nil,
            cameraPreview: nil,
            followedVehicleMarkerID: nil,
            contextMenuPolicy: .disabled,
            preserveView: true,
            isEditingTask: false,
            missionPointMarkers: [],
            missionPointPlacementArmed: false,
            mcsReservePoolHomePlacementArmed: false,
            geofenceOverlays: [],
            geofenceLeafletChrome: GuardianGeofenceLeafletChrome(colorScheme: .dark),
            geofenceMapLayerPointerSelectsFence: false
        )
    }
}
