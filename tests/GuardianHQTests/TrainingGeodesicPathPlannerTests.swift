import XCTest
@testable import GuardianCore

@MainActor
final class TrainingGeodesicPathPlannerTests: XCTestCase {
    func test_plan_includes_endpoints() {
        let start = TrainingTaskPose(
            latitudeDeg: -35.0,
            longitudeDeg: 149.0,
            headingDeg: 0,
            absoluteAltitudeM: 0
        )
        let goal = TrainingTaskPose(
            latitudeDeg: -35.0002,
            longitudeDeg: 149.0003,
            headingDeg: 90,
            absoluteAltitudeM: 0
        )
        let path = TrainingGeodesicPathPlanner.plan(start: start, goal: goal, stepM: 5)
        XCTAssertGreaterThanOrEqual(path.count, 2)
        XCTAssertEqual(path.first?.lat, start.latitudeDeg)
        XCTAssertEqual(path.last?.lat, goal.latitudeDeg)
    }
}
