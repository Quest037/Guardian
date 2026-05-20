import XCTest
@testable import GuardianCore

final class TrainingSkillScorerTests: XCTestCase {
    func test_evaluate_success_atGoal() {
        let goal = TrainingTaskPose(
            latitudeDeg: -35,
            longitudeDeg: 149,
            headingDeg: 90,
            absoluteAltitudeM: 0
        )
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = -35.00001
        hub.longitudeDeg = 149.00001
        hub.headingDeg = 90
        let score = TrainingSkillScorer.evaluate(
            hub: hub,
            goal: goal,
            episodeDurationS: 12,
            constraintViolations: []
        )
        XCTAssertTrue(score.succeeded)
        XCTAssertTrue(score.positionErrorM < 2)
    }

    func test_evaluate_fails_whenForwardForbiddenViolated() {
        let goal = TrainingTaskPose(
            latitudeDeg: -35,
            longitudeDeg: 149,
            headingDeg: 0,
            absoluteAltitudeM: 0
        )
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = -35
        hub.longitudeDeg = 149
        hub.headingDeg = 0
        let score = TrainingSkillScorer.evaluate(
            hub: hub,
            goal: goal,
            episodeDurationS: 5,
            constraintViolations: [.driveForward]
        )
        XCTAssertFalse(score.succeeded)
    }
}
