import XCTest
@testable import GuardianCore

final class TrainingPathOverlayDebugLineTests: XCTestCase {
    func test_path_with_geodesic_fallback_while_nav2_starting() {
        let line = TrainingPanelController.pathOverlayDebugLine(
            source: .geodesicFallback,
            nav2StackReady: false,
            nav2StackStatus: "starting",
            hasPath: true
        )
        XCTAssertEqual(line, "Path overlay: Python fallback — Nav2 starting (up to ~2 min)")
    }

    func test_path_with_nav2_when_stack_ready() {
        let line = TrainingPanelController.pathOverlayDebugLine(
            source: .nav2,
            nav2StackReady: true,
            nav2StackStatus: "ready",
            hasPath: true
        )
        XCTAssertEqual(line, "Path overlay: Nav2")
    }

    func test_no_path_after_nav2_timeout() {
        let line = TrainingPanelController.pathOverlayDebugLine(
            source: .unavailable,
            nav2StackReady: false,
            nav2StackStatus: "timeout",
            hasPath: false
        )
        XCTAssertEqual(line, "Path overlay: none (Nav2 failed — planner service timeout)")
    }
}
