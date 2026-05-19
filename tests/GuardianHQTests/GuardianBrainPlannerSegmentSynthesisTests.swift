import XCTest

@testable import GuardianHQ

final class GuardianBrainPlannerSegmentSynthesisTests: XCTestCase {
    func test_segments_follows_path_with_forward_legs() {
        let start = TrainingTaskLayoutFactory.layout(kind: .reverseIntoSlot, spawn: .default).start
        let goal = TrainingTaskLayoutFactory.defaultTargetSlot(spawn: .default)
        let path = TrainingGeodesicPathPlanner.plan(start: start, goal: goal, stepM: 3.0)
        let segments = GuardianBrainPlannerSegmentSynthesis.segments(
            path: path,
            maxSpeedMS: 0.5,
            initialHeadingDeg: start.headingDeg
        )
        XCTAssertFalse(segments.isEmpty)
        XCTAssertTrue(segments.contains { $0.bodyForwardMS > 0 })
    }

}
