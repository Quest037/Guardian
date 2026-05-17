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
        XCTAssertEqual(polys[0].points.count, 3, "Open triangle ring for MAVSDK fence upload (no repeated closing vertex)")
    }

    func test_circle_fence_maps_to_mavsdk_circle_not_polygon() {
        let fence = MissionGeofence.newCircle(name: "c", center: RouteCoordinate(lat: -34.0, lon: 150.0))
        XCTAssertTrue(MissionGeofenceMavsdkGeofenceUtilities.mavsdkPolygons(forGeofences: [fence]).isEmpty)
        let circles = MissionGeofenceMavsdkGeofenceUtilities.mavsdkCircles(forGeofences: [fence])
        XCTAssertEqual(circles.count, 1)
        XCTAssertEqual(circles[0].fenceType, .inclusion)
        XCTAssertEqual(circles[0].point.latitudeDeg, -34.0, accuracy: 1e-9)
        XCTAssertEqual(circles[0].point.longitudeDeg, 150.0, accuracy: 1e-9)
        XCTAssertEqual(Double(circles[0].radius), 150.0, accuracy: 0.01)
    }

    func test_missionGeofences_roundTrip_fromGeofencePolygonsJSON() throws {
        let fence = MissionGeofence(
            name: "box",
            boundary: .exclusion,
            shape: .polygon,
            polygonVertices: [
                RouteCoordinate(lat: -33.0, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.02),
            ]
        )
        let json = try MissionGeofenceMavsdkGeofenceUtilities.encodeGeofencePolygonsJSON(forGeofences: [fence])
        let decoded = try MissionGeofenceMavsdkGeofenceUtilities.missionGeofences(fromGeofencePolygonsJSON: json)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].boundary, .exclusion)
        XCTAssertEqual(decoded[0].shape, .polygon)
        XCTAssertEqual(decoded[0].polygonVertices.count, 3)
    }

    func test_missionGeofences_roundTrip_fromGeofencePolygonsJSON() throws {
        let fence = MissionGeofence(
            name: "box",
            boundary: .exclusion,
            shape: .polygon,
            polygonVertices: [
                RouteCoordinate(lat: -33.0, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.02),
            ]
        )
        let json = try MissionGeofenceMavsdkGeofenceUtilities.encodeGeofencePolygonsJSON(forGeofences: [fence])
        let decoded = try MissionGeofenceMavsdkGeofenceUtilities.missionGeofences(fromGeofencePolygonsJSON: json)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].boundary, .exclusion)
        XCTAssertEqual(decoded[0].shape, .polygon)
        XCTAssertEqual(decoded[0].polygonVertices.count, 3)
    }

    func test_encode_decode_roundTrip_geofence_wire_payload() throws {
        let fence = MissionGeofence.newCircle(name: "c", center: RouteCoordinate(lat: -34.0, lon: 150.0))
        let wire = MissionGeofenceMavsdkGeofenceUtilities.geofenceUploadPayload(forGeofences: [fence])
        XCTAssertTrue(wire.polygons.isEmpty)
        XCTAssertEqual(wire.circles.count, 1)
        let json = try wire.encodeToJSON()
        let decoded = try FleetVehicleCommandGeofenceUploadPayload.decode(fromJSON: json)
        XCTAssertEqual(decoded.circles.count, wire.circles.count)
        XCTAssertEqual(decoded.circles[0].radiusMeters, wire.circles[0].radiusMeters, accuracy: 0.01)
        let roundCircles = decoded.circles.map(\.mavsdkCircle)
        XCTAssertEqual(roundCircles[0].radius, wire.circles[0].mavsdkCircle.radius)
    }

    func test_polygon_with_repeated_closing_vertex_maps_to_open_ring() {
        let a = RouteCoordinate(lat: -33.0, lon: 151.0)
        let b = RouteCoordinate(lat: -33.01, lon: 151.0)
        let c = RouteCoordinate(lat: -33.01, lon: 151.02)
        let fence = MissionGeofence(
            name: "closed-ui-ring",
            boundary: .inclusion,
            shape: .polygon,
            polygonVertices: [a, b, c, a],
            circleCenter: RouteCoordinate(),
            circleRadiusMeters: 50
        )
        let polys = MissionGeofenceMavsdkGeofenceUtilities.mavsdkPolygons(forGeofences: [fence])
        XCTAssertEqual(polys.count, 1)
        XCTAssertEqual(polys[0].points.count, 3)
    }

    func test_px4_geofence_filter_drops_inclusion_when_home_outside_polygon() {
        let fence = MissionGeofence(
            name: "keep",
            boundary: .inclusion,
            shape: .polygon,
            polygonVertices: [
                RouteCoordinate(lat: -33.0, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.02),
            ],
            circleCenter: RouteCoordinate(),
            circleRadiusMeters: 50
        )
        let home = RouteCoordinate(lat: -34.0, lon: 150.0)
        let (filtered, omitted) = MissionGeofenceMavsdkGeofenceUtilities.fencesFilteredForPX4GeofenceUpload(fences: [fence], home: home)
        XCTAssertEqual(omitted, 1)
        XCTAssertTrue(filtered.isEmpty)
    }

    func test_px4_geofence_filter_keeps_inclusion_when_home_inside_polygon() {
        let fence = MissionGeofence(
            name: "keep",
            boundary: .inclusion,
            shape: .polygon,
            polygonVertices: [
                RouteCoordinate(lat: -33.0, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.02),
            ],
            circleCenter: RouteCoordinate(),
            circleRadiusMeters: 50
        )
        let home = RouteCoordinate(lat: (-33.0 - 33.01 - 33.01) / 3.0, lon: (151.0 + 151.0 + 151.02) / 3.0)
        let (filtered, omitted) = MissionGeofenceMavsdkGeofenceUtilities.fencesFilteredForPX4GeofenceUpload(fences: [fence], home: home)
        XCTAssertEqual(omitted, 0)
        XCTAssertEqual(filtered.count, 1)
    }

    func test_px4_geofence_filter_keeps_exclusion_when_home_outside_exclusion_polygon() {
        let fence = MissionGeofence(
            name: "no-go",
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
        let home = RouteCoordinate(lat: -34.0, lon: 150.0)
        let (filtered, omitted) = MissionGeofenceMavsdkGeofenceUtilities.fencesFilteredForPX4GeofenceUpload(fences: [fence], home: home)
        XCTAssertEqual(omitted, 0)
        XCTAssertEqual(filtered.count, 1)
    }

    func test_px4_geofence_filter_nil_home_passes_through() {
        let fence = MissionGeofence.newCircle(name: "c", center: RouteCoordinate(lat: -34.0, lon: 150.0))
        let (filtered, omitted) = MissionGeofenceMavsdkGeofenceUtilities.fencesFilteredForPX4GeofenceUpload(fences: [fence], home: nil)
        XCTAssertEqual(omitted, 0)
        XCTAssertEqual(filtered.count, 1)
    }

    func test_px4_geofence_filter_home_prefers_hub_coordinates_over_route_macro() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.homeLatitudeDeg = 50.1
        hub.homeLongitudeDeg = -1.2
        let route = RouteCoordinate(lat: 40.0, lon: 2.0)
        let chosen = MissionGeofenceMavsdkGeofenceUtilities.px4GeofenceFilterHome(routeMacroHome: route, hub: hub)
        XCTAssertNotNil(chosen)
        XCTAssertEqual(chosen!.lat, 50.1, accuracy: 1e-9)
        XCTAssertEqual(chosen!.lon, -1.2, accuracy: 1e-9)
    }

    func test_px4_geofence_filter_home_falls_back_to_route_macro_when_hub_home_incomplete() {
        let route = RouteCoordinate(lat: 40.0, lon: 2.0)
        var hub = FleetHubVehicleTelemetry.empty
        hub.homeLatitudeDeg = 50.1
        hub.homeLongitudeDeg = nil
        let chosenPartial = MissionGeofenceMavsdkGeofenceUtilities.px4GeofenceFilterHome(routeMacroHome: route, hub: hub)
        XCTAssertNotNil(chosenPartial)
        XCTAssertEqual(chosenPartial!.lat, 40.0, accuracy: 1e-9)

        let chosenNilHub = MissionGeofenceMavsdkGeofenceUtilities.px4GeofenceFilterHome(routeMacroHome: route, hub: nil)
        XCTAssertNotNil(chosenNilHub)
        XCTAssertEqual(chosenNilHub!.lat, 40.0, accuracy: 1e-9)
    }

    func test_encode_polygon_geofence_omits_altitude_on_fleet_wire() throws {
        var fence = MissionGeofence(
            name: "box",
            boundary: .inclusion,
            shape: .polygon,
            polygonVertices: [
                RouteCoordinate(lat: -33.0, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.0),
                RouteCoordinate(lat: -33.01, lon: 151.02),
            ],
            circleCenter: RouteCoordinate(),
            circleRadiusMeters: 50
        )
        fence.minAltitudeMeters = 10
        fence.maxAltitudeMeters = 100
        fence.altitudeReference = .msl
        let json = try MissionGeofenceMavsdkGeofenceUtilities.encodeGeofencePolygonsJSON(forGeofences: [fence])
        XCTAssertTrue(json.contains("\"polygons\""))
        XCTAssertFalse(json.contains("min_altitude_meters"))
        XCTAssertFalse(json.contains("max_altitude_meters"))
        XCTAssertFalse(json.contains("mavlink_frame"))
        XCTAssertFalse(json.contains("vertex_altitude_z_meters"))
        XCTAssertFalse(json.contains("altitude_reference"))
        let wire = try FleetVehicleCommandGeofenceUploadPayload.decode(fromJSON: json)
        XCTAssertEqual(wire.polygons.count, 1)
        XCTAssertTrue(wire.circles.isEmpty)
        XCTAssertEqual(wire.polygons[0].points.count, 3)
    }

    func test_decode_geofence_polygon_ignores_stale_altitude_keys_on_wire() throws {
        let json = """
        {"circles":[],"polygons":[{"fenceType":"inclusion","min_altitude_meters":5,"max_altitude_meters":50,"mavlink_frame":11,"points":[{"latitudeDeg":-33,"longitudeDeg":151,"altitude_m":999},{"latitudeDeg":-33.01,"longitudeDeg":151},{"latitudeDeg":-33.01,"longitudeDeg":151.02}]}]}
        """
        let wire = try FleetVehicleCommandGeofenceUploadPayload.decode(fromJSON: json)
        XCTAssertEqual(wire.polygons.count, 1)
        XCTAssertEqual(wire.polygons[0].points.count, 3)
        XCTAssertEqual(wire.polygons[0].points[0].latitudeDeg, -33, accuracy: 1e-9)
        XCTAssertEqual(wire.polygons[0].points[0].longitudeDeg, 151, accuracy: 1e-9)
        let reencoded = try wire.encodeToJSON()
        XCTAssertFalse(reencoded.contains("min_altitude_meters"))
        XCTAssertFalse(reencoded.contains("altitude_m"))
    }

    func test_encode_from_mission_geofence_omits_altitude_on_fleet_wire() throws {
        var fence = MissionGeofence.newCircle(name: "c", center: RouteCoordinate(lat: -34.0, lon: 150.0))
        fence.altitudeReference = .relativeHome
        fence.minAltitudeMeters = 30
        fence.maxAltitudeMeters = 120
        let json = try MissionGeofenceMavsdkGeofenceUtilities.encodeGeofencePolygonsJSON(forGeofences: [fence])
        XCTAssertTrue(json.contains("\"circles\""))
        XCTAssertFalse(json.contains("mavlink_frame"))
        XCTAssertFalse(json.contains("min_altitude_meters"))
        XCTAssertFalse(json.contains("max_altitude_meters"))
        XCTAssertFalse(json.contains("vertex_altitude_z_meters"))
        let wire = try FleetVehicleCommandGeofenceUploadPayload.decode(fromJSON: json)
        XCTAssertEqual(wire.circles.count, 1)
        XCTAssertTrue(wire.polygons.isEmpty)
        XCTAssertEqual(wire.circles[0].latitudeDeg, -34.0, accuracy: 1e-9)
        XCTAssertEqual(wire.circles[0].longitudeDeg, 150.0, accuracy: 1e-9)
        XCTAssertGreaterThan(wire.circles[0].radiusMeters, 0)
    }
}
