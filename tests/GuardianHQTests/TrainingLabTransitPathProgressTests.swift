import XCTest

@testable import GuardianCore

final class TrainingLabTransitPathProgressTests: XCTestCase {
    /// Detour away from goal must still register as forward progress along the route.
    func test_along_track_increases_on_detour_not_straight_line_to_goal() {
        let start = RouteCoordinate(lat: -35.0, lon: 149.0)
        let detour = RouteCoordinate(lat: -35.05, lon: 149.0)
        let goal = RouteCoordinate(lat: -35.001, lon: 149.001)
        let path = [start, detour, goal]

        let atStart = TrainingLabTransitPathProgress.alongTrackProgressM(
            latitudeDeg: start.lat,
            longitudeDeg: start.lon,
            path: path
        ) ?? 0
        let atDetour = TrainingLabTransitPathProgress.alongTrackProgressM(
            latitudeDeg: detour.lat,
            longitudeDeg: detour.lon,
            path: path
        ) ?? 0
        let straightToGoalM = MissionTelemetryGeo.horizontalDistanceM(
            lat1: detour.lat,
            lon1: detour.lon,
            lat2: goal.lat,
            lon2: goal.lon
        )

        XCTAssertGreaterThan(atDetour, atStart + 100)
        XCTAssertGreaterThan(straightToGoalM, 4_000)
    }
}
