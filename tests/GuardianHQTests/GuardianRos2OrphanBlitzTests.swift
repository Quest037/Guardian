import XCTest
@testable import GuardianHQ

final class GuardianRos2OrphanBlitzTests: XCTestCase {
    func test_pgrepPatterns_includeGuardianRosAndBridgeMarkers() {
        let patterns = GuardianRos2OrphanBlitz.allPgrepPatternsForTesting()
        let joined = patterns.joined(separator: "\n")
        XCTAssertTrue(joined.contains(".guardian/ros/humble"))
        XCTAssertTrue(joined.contains("guardian_ros2_vehicle_bridge"))
        XCTAssertTrue(joined.contains("nav2_training.launch.py"))
        XCTAssertTrue(joined.contains("GUARDIAN_ROS2_BRIDGE_CONFIG"))
    }

    func test_pgrepPatterns_includeHomeRoboStackPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let patterns = GuardianRos2OrphanBlitz.allPgrepPatternsForTesting()
        XCTAssertTrue(
            patterns.contains(where: { $0.contains(home) && $0.contains(".guardian/ros/humble") })
        )
    }
}
