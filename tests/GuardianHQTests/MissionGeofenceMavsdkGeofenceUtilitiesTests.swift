import Mavsdk
import XCTest
@testable import GuardianHQ

final class MissionGeofenceMavsdkGeofenceUtilitiesTests: XCTestCase {

    func test_polygon_fence_maps_to_mavsdk_polygon() {
        let fence = MissionGeofence(
            name: "box",
            boundary: .exclusion,
            shape: .polygon,
            polygonVertices: [
                RouteCoordinate(lat: -33.0, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.02),
            ],
            circleCenter: RouteCoordinate(),
            circleRadiusMeters: 50
        )
        let polys = MissionGeofenceMavsdkGeofenceUtilities.mavsdkPolygons(forGeofences: [fence])
        XCTAssertEqual(polys.count, 1)
        XCTAssertEqual(polys[0].fenceType, .exclusion)
        XCTAssertGreaterThanOrEqual(polys[0].points.count, 4)
    }

    func test_encode_decode_roundTrip_matches_mavsdk() throws {
        let fence = MissionGeofence.newCircle(name: "c", center: RouteCoordinate(lat: -34.0, lon: 150.0))
        let polys = MissionGeofenceMavsdkGeofenceUtilities.mavsdkPolygons(forGeofences: [fence])
        XCTAssertEqual(polys.count, 1)
        let json = try FleetVehicleCommandGeofencePolygonPayload.encodePolygonsToJSON(polygons: polys)
        let decoded = try FleetVehicleCommandGeofencePolygonPayload.decodePolygons(fromJSON: json)
        XCTAssertEqual(decoded.count, polys.count)
        XCTAssertEqual(decoded[0].points.count, polys[0].points.count)
    }
}
