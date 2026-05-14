import XCTest
@testable import GuardianHQ

final class MissionGeofenceCodableTests: XCTestCase {

    func test_missionGeofence_polygon_roundTrip() throws {
        let original = MissionGeofence.newPolygon(name: "Alpha", around: RouteCoordinate(lat: -33.8, lon: 151.2))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MissionGeofence.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.shape, .polygon)
        XCTAssertEqual(decoded.polygonVertices.count, 3)
    }

    func test_missionGeofence_circle_roundTrip() throws {
        var original = MissionGeofence.newCircle(name: "Bravo", center: RouteCoordinate(lat: 1, lon: 2))
        original.boundary = .exclusion
        original.circleRadiusMeters = 99
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MissionGeofence.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.boundary, .exclusion)
        XCTAssertEqual(decoded.circleRadiusMeters, 99)
    }

    func test_mission_embeds_missionAndTaskGeofences_roundTrip() throws {
        var task = MissionTask(name: "T1")
        task.geofences = [
            MissionGeofence.newCircle(name: "Task fence", center: RouteCoordinate(lat: 10, lon: 20)),
        ]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task]),
            missionGeofences: [MissionGeofence.newPolygon(name: "Mission fence", around: RouteCoordinate(lat: 0, lon: 0))]
        )
        let data = try JSONEncoder().encode(mission)
        let decoded = try JSONDecoder().decode(Mission.self, from: data)
        XCTAssertEqual(decoded.missionGeofences.count, 1)
        XCTAssertEqual(decoded.missionGeofences.first?.name, "Mission fence")
        XCTAssertEqual(decoded.routeMacro.tasks.count, 1)
        XCTAssertEqual(decoded.routeMacro.tasks[0].geofences.count, 1)
        XCTAssertEqual(decoded.routeMacro.tasks[0].geofences.first?.name, "Task fence")
    }

    func test_missionGeofence_decode_without_altitude_keys_uses_defaults() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Z","boundary":"inclusion","shape":"circle","polygonVertices":[],"circleCenter":{"lat":0,"lon":0},"circleRadiusMeters":10}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let fence = try JSONDecoder().decode(MissionGeofence.self, from: data)
        XCTAssertEqual(fence.minAltitudeMeters, 0)
        XCTAssertEqual(fence.maxAltitudeMeters, 120)
        XCTAssertEqual(fence.altitudeUnits, .meters)
        XCTAssertEqual(fence.altitudeReference, .relativeHome)
    }

    func test_missionGeofence_altitude_snake_case_keys_roundTrip() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000002","name":"Band","boundary":"inclusion","shape":"circle","polygonVertices":[],"circleCenter":{"lat":1,"lon":2},"circleRadiusMeters":50,"min_altitude":30,"max_altitude":120,"altitude_units":"m","altitude_reference":"AGL"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(MissionGeofence.self, from: data)
        XCTAssertEqual(decoded.minAltitudeMeters, 30)
        XCTAssertEqual(decoded.maxAltitudeMeters, 120)
        XCTAssertEqual(decoded.altitudeUnits, .meters)
        XCTAssertEqual(decoded.altitudeReference, .agl)
        let out = try JSONEncoder().encode(decoded)
        let again = try JSONDecoder().decode(MissionGeofence.self, from: out)
        XCTAssertEqual(again, decoded)
    }
}
