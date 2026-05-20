import Combine
import XCTest

@testable import GuardianCore

@MainActor
final class GuardianMapModelApplyMapContentTests: XCTestCase {

    private func sampleMarker(id: String = "v1") -> MapVehicleMarker {
        MapVehicleMarker(
            id: id,
            lat: 1,
            lon: 2,
            label: "V",
            colorHex: "#ffffff",
            selected: false,
            draggable: false
        )
    }

    func test_applyMapContent_emits_single_objectWillChange() {
        let model = GuardianMapModel()
        var publishCount = 0
        let cancellable = model.objectWillChange.sink { _ in publishCount += 1 }
        defer { cancellable.cancel() }

        var geo = GuardianRouteMapGeometry.empty
        geo.preserveView = false
        model.applyMapContent(routeGeometry: geo, vehicleMarkers: [sampleMarker()])
        XCTAssertEqual(publishCount, 1)
    }

    func test_separate_route_and_marker_assignments_emit_two_changes() {
        let model = GuardianMapModel()
        var publishCount = 0
        let cancellable = model.objectWillChange.sink { _ in publishCount += 1 }
        defer { cancellable.cancel() }

        var geo = GuardianRouteMapGeometry.empty
        geo.preserveView = false
        model.routeGeometry = geo
        model.vehicleMarkers = [sampleMarker()]
        XCTAssertEqual(publishCount, 2)
    }

    func test_applyVehicleMarkersOnly_skips_publish_when_markers_unchanged() {
        let model = GuardianMapModel()
        var geo = GuardianRouteMapGeometry.empty
        geo.preserveView = true
        let markers = [sampleMarker()]
        model.applyMapContent(routeGeometry: geo, vehicleMarkers: markers)

        var publishCount = 0
        let cancellable = model.objectWillChange.sink { _ in publishCount += 1 }
        defer { cancellable.cancel() }

        model.applyVehicleMarkersOnly(markers)
        XCTAssertEqual(publishCount, 0)
    }

    func test_applyVehicleMarkersOnly_single_publish_when_route_unchanged() {
        let model = GuardianMapModel()
        var geo = GuardianRouteMapGeometry.empty
        geo.preserveView = true
        model.applyMapContent(routeGeometry: geo, vehicleMarkers: [sampleMarker()])

        var publishCount = 0
        let cancellable = model.objectWillChange.sink { _ in publishCount += 1 }
        defer { cancellable.cancel() }

        let moved = MapVehicleMarker(
            id: "v1",
            lat: 9,
            lon: 8,
            label: "V",
            colorHex: "#ffffff",
            selected: false,
            draggable: false
        )
        model.applyVehicleMarkersOnly([moved])
        XCTAssertEqual(publishCount, 1)
        XCTAssertEqual(model.vehicleMarkers, [moved])
        XCTAssertEqual(model.routeGeometry, geo)
    }

    func test_applyMapContent_no_op_when_content_unchanged() {
        let model = GuardianMapModel()
        var publishCount = 0
        let cancellable = model.objectWillChange.sink { _ in publishCount += 1 }
        defer { cancellable.cancel() }

        var geo = GuardianRouteMapGeometry.empty
        geo.preserveView = false
        let markers = [sampleMarker()]
        model.applyMapContent(routeGeometry: geo, vehicleMarkers: markers)
        XCTAssertEqual(publishCount, 1)
        model.applyMapContent(routeGeometry: geo, vehicleMarkers: markers)
        XCTAssertEqual(publishCount, 1)
    }
}
