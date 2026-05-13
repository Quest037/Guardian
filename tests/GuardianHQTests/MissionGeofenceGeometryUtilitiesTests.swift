import XCTest
@testable import GuardianHQ

final class MissionGeofenceGeometryUtilitiesTests: XCTestCase {

    private let geo = MissionGeofenceGeometryUtilities()

    func test_polygon_insufficient_vertices_underThree() {
        XCTAssertTrue(geo.polygonHasInsufficientVertices([]))
        XCTAssertTrue(geo.polygonHasInsufficientVertices([
            RouteCoordinate(lat: 0, lon: 0),
            RouteCoordinate(lat: 1, lon: 1),
        ]))
        XCTAssertFalse(geo.polygonHasInsufficientVertices([
            RouteCoordinate(lat: 0, lon: 0),
            RouteCoordinate(lat: 1, lon: 0),
            RouteCoordinate(lat: 0.5, lon: 0.5),
        ]))
    }

    func test_polygon_selfIntersection_bowtie_detected() {
        let baseLat = 37.0
        let baseLon = -122.0
        let d = 0.0002
        let bowtie = [
            RouteCoordinate(lat: baseLat, lon: baseLon),
            RouteCoordinate(lat: baseLat + d, lon: baseLon + d),
            RouteCoordinate(lat: baseLat + d, lon: baseLon),
            RouteCoordinate(lat: baseLat, lon: baseLon + d),
        ]
        XCTAssertTrue(geo.polygonSelfIntersectsWGS84(vertices: bowtie))
    }

    func test_polygon_square_noSelfIntersection() {
        let baseLat = 10.0
        let baseLon = 20.0
        let d = 0.0001
        let square = [
            RouteCoordinate(lat: baseLat, lon: baseLon),
            RouteCoordinate(lat: baseLat + d, lon: baseLon),
            RouteCoordinate(lat: baseLat + d, lon: baseLon + d),
            RouteCoordinate(lat: baseLat, lon: baseLon + d),
        ]
        XCTAssertFalse(geo.polygonSelfIntersectsWGS84(vertices: square))
    }

    func test_polygon_triangle_noSelfIntersection() {
        let verts = [
            RouteCoordinate(lat: 0, lon: 0),
            RouteCoordinate(lat: 0.001, lon: 0),
            RouteCoordinate(lat: 0.0005, lon: 0.001),
        ]
        XCTAssertFalse(geo.polygonSelfIntersectsWGS84(vertices: verts))
    }
}
