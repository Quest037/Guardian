import XCTest
@testable import GuardianHQ

final class MissionControlSquadConvoySetpointGeofenceUtilitiesTests: XCTestCase {

    func test_exclusion_polygon_blocks_setpoint_inside() {
        let fence = MissionGeofence(
            id: UUID(),
            name: "No-go",
            boundary: .exclusion,
            shape: .polygon,
            polygonVertices: [
                RouteCoordinate(lat: 0, lon: 0),
                RouteCoordinate(lat: 0, lon: 0.001),
                RouteCoordinate(lat: 0.001, lon: 0.001),
                RouteCoordinate(lat: 0.001, lon: 0),
            ]
        )
        let inside = RouteCoordinate(lat: 0.0005, lon: 0.0005)
        XCTAssertTrue(
            MissionControlSquadConvoySetpointGeofenceUtilities.setpointViolatesGeofences(
                coordinate: inside,
                geofences: [fence]
            )
        )
        let outside = RouteCoordinate(lat: 0.01, lon: 0.01)
        XCTAssertFalse(
            MissionControlSquadConvoySetpointGeofenceUtilities.setpointViolatesGeofences(
                coordinate: outside,
                geofences: [fence]
            )
        )
    }

    func test_inclusion_requires_point_inside_at_least_one_fence() {
        let fence = MissionGeofence(
            id: UUID(),
            name: "Keep-in",
            boundary: .inclusion,
            shape: .circle,
            circleCenter: RouteCoordinate(lat: 1, lon: 1),
            circleRadiusMeters: 100
        )
        XCTAssertFalse(
            MissionControlSquadConvoySetpointGeofenceUtilities.setpointViolatesGeofences(
                coordinate: RouteCoordinate(lat: 1, lon: 1),
                geofences: [fence]
            )
        )
        XCTAssertTrue(
            MissionControlSquadConvoySetpointGeofenceUtilities.setpointViolatesGeofences(
                coordinate: RouteCoordinate(lat: 2, lon: 2),
                geofences: [fence]
            )
        )
    }

    func test_filteredFormationTarget_holds_last_valid_on_violation() {
        let fence = MissionGeofence(
            id: UUID(),
            name: "No-go",
            boundary: .exclusion,
            shape: .circle,
            circleCenter: RouteCoordinate(lat: 0, lon: 0),
            circleRadiusMeters: 50
        )
        let safe = FormationFollowStream.Target(
            coord: RouteCoordinate(lat: 0.01, lon: 0.01),
            absoluteAltitudeM: 10,
            yawDeg: 90,
            pursuitForwardMS: nil,
            pursuitYawspeedDegS: nil
        )
        let unsafe = FormationFollowStream.Target(
            coord: RouteCoordinate(lat: 0, lon: 0),
            absoluteAltitudeM: 10,
            yawDeg: 90,
            pursuitForwardMS: nil,
            pursuitYawspeedDegS: nil
        )
        let filtered = MissionControlSquadConvoySetpointGeofenceUtilities.filteredFormationTarget(
            proposed: unsafe,
            lastValid: safe,
            geofences: [fence]
        )
        XCTAssertEqual(filtered.coord.lat, safe.coord.lat)
        XCTAssertEqual(filtered.coord.lon, safe.coord.lon)
    }
}
