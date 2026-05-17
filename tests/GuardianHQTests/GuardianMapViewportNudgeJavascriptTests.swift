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

    func test_javascriptExpression_fitBounds_formationContent() {
        let n = GuardianMapViewportNudge(
            sequence: 4,
            kind: .fitBounds(points: [(1, 2), (3, 4)], style: .formationContent)
        )
        XCTAssertEqual(
            OSMMapView.javascriptExpression(for: n),
            "guardianFitBoundsForFormationContent([[1.0,2.0],[3.0,4.0]]);"
        )
    }

    func test_javascriptExpression_panToZoom() {
        let n = GuardianMapViewportNudge(sequence: 3, kind: .panToZoom(lat: -37.8, lon: 145.0, zoom: 15))
        XCTAssertEqual(OSMMapView.javascriptExpression(for: n), "guardianPanToZoom(-37.8,145.0,15.0);")
    }
}
