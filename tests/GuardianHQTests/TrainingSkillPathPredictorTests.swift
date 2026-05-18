import XCTest
@testable import GuardianHQ

final class TrainingSkillPathPredictorTests: XCTestCase {
    func test_reverseSegment_movesBehindStartAlongHeading() {
        let start = TrainingTaskPose(
            latitudeDeg: -35,
            longitudeDeg: 149,
            headingDeg: 0,
            absoluteAltitudeM: 10
        )
        let segments = [TrainingControlSegment.reverse(0.5, durationS: 4)]
        let path = TrainingSkillPathPredictor.predictedPath(start: start, segments: segments)
        XCTAssertGreaterThanOrEqual(path.count, 2)
        let end = path.last!
        XCTAssertLessThan(end.lat, start.latitudeDeg, accuracy: 0.0001)
    }

    func test_predictedPath_hasAtLeastStartAndEnd() {
        let start = TrainingTaskPose(
            latitudeDeg: -35,
            longitudeDeg: 149,
            headingDeg: 90,
            absoluteAltitudeM: 10
        )
        let segments = [
            TrainingControlSegment.forward(0.4, durationS: 2),
            TrainingControlSegment.yaw(15, durationS: 1),
        ]
        let path = TrainingSkillPathPredictor.predictedPath(start: start, segments: segments)
        XCTAssertGreaterThanOrEqual(path.count, 2)
    }
}
