import XCTest
@testable import GuardianCore

final class TrainingLabTransitMotionTests: XCTestCase {

    func test_segments_from_geodesic_path_nonEmpty() {
        let start = TrainingTaskPose(latitudeDeg: -35, longitudeDeg: 149, headingDeg: 0, absoluteAltitudeM: 10)
        let goal = TrainingTaskPose(latitudeDeg: -35.0004, longitudeDeg: 149.0005, headingDeg: 90, absoluteAltitudeM: 10)
        let path = TrainingGeodesicPathPlanner.plan(start: start, goal: goal)
        let segments = GuardianBrainPlannerSegmentSynthesis.segments(
            path: path,
            maxSpeedMS: TrainingLabTransitMotion.defaultMaxSpeedMS,
            initialHeadingDeg: start.headingDeg
        )
        XCTAssertFalse(segments.isEmpty)
    }
}
