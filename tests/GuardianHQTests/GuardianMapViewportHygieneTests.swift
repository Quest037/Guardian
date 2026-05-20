import Combine
import XCTest

@testable import GuardianCore

@MainActor
final class GuardianMapViewportHygieneTests: XCTestCase {

    func test_consumeViewportNudge_clears_pending_nudge() {
        let model = GuardianMapModel(preserveView: true)
        model.focusMapPanRetainZoom(lat: 1, lon: 2)
        XCTAssertNotNil(model.viewportNudge)
        model.consumeViewportNudge()
        XCTAssertNil(model.viewportNudge)
    }

    func test_focusMap_methods_do_not_bump_recenterNonce() {
        let model = GuardianMapModel(preserveView: true)
        model.recenter()
        let afterRecenter = model.recenterNonce
        model.focusMapFitBounds(points: [(0, 0), (1, 1)])
        model.focusMapPanRetainZoom(lat: 0.5, lon: 0.5)
        model.focusMapPanToZoom(lat: 0.5, lon: 0.5, zoom: 12)
        XCTAssertEqual(model.recenterNonce, afterRecenter)
        XCTAssertNotNil(model.viewportNudge)
    }

    func test_applyVehicleMarkersOnly_no_op_when_markers_unchanged() {
        let model = GuardianMapModel(preserveView: true)
        let marker = MapVehicleMarker(
            id: "v1",
            lat: 1,
            lon: 2,
            label: "V",
            colorHex: "#fff",
            selected: false,
            draggable: false
        )
        model.applyMapContent(routeGeometry: .empty, vehicleMarkers: [marker])
        var publishCount = 0
        let cancellable = model.objectWillChange.sink { _ in publishCount += 1 }
        defer { cancellable.cancel() }
        model.applyVehicleMarkersOnly([marker])
        XCTAssertEqual(publishCount, 0)
    }
}
