import XCTest

@testable import GuardianHQ

final class GuardianMapViewportNudgeJavascriptTests: XCTestCase {
    func test_javascriptExpression_panRetainZoom() {
        let n = GuardianMapViewportNudge(sequence: 1, kind: .panRetainZoom(lat: -33.8, lon: 151.2))
        XCTAssertEqual(OSMMapView.javascriptExpression(for: n), "guardianPanToRetainZoom(-33.8,151.2);")
    }

    func test_javascriptExpression_fitBounds() {
        let n = GuardianMapViewportNudge(sequence: 2, kind: .fitBounds(points: [(1, 2), (3, 4)]))
        XCTAssertEqual(OSMMapView.javascriptExpression(for: n), "guardianFitBoundsForPoints([[1.0,2.0],[3.0,4.0]]);")
    }
}
