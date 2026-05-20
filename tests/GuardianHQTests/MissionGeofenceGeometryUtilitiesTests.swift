import XCTest
@testable import GuardianCore

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

    func test_point_inside_polygon_square_center() {
        let baseLat = 10.0
        let baseLon = 20.0
        let d = 0.0001
        let square = [
            RouteCoordinate(lat: baseLat, lon: baseLon),
            RouteCoordinate(lat: baseLat + d, lon: baseLon),
            RouteCoordinate(lat: baseLat + d, lon: baseLon + d),
            RouteCoordinate(lat: baseLat, lon: baseLon + d),
        ]
        let inside = RouteCoordinate(lat: baseLat + d * 0.5, lon: baseLon + d * 0.5)
        XCTAssertTrue(geo.pointInsidePolygonHorizontallyWGS84(point: inside, polygonVertices: square))
    }

    func test_point_outside_polygon_square_corner_far() {
        let baseLat = 10.0
        let baseLon = 20.0
        let d = 0.0001
        let square = [
            RouteCoordinate(lat: baseLat, lon: baseLon),
            RouteCoordinate(lat: baseLat + d, lon: baseLon),
            RouteCoordinate(lat: baseLat + d, lon: baseLon + d),
            RouteCoordinate(lat: baseLat, lon: baseLon + d),
        ]
        let outside = RouteCoordinate(lat: baseLat + 1.0, lon: baseLon + 1.0)
        XCTAssertFalse(geo.pointInsidePolygonHorizontallyWGS84(point: outside, polygonVertices: square))
    }
}
