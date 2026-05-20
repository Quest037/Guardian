import XCTest
@testable import GuardianCore

final class FleetNav2TrainingStackStatusPolicyTests: XCTestCase {
    func test_bridge_stdout_does_not_drive_operator_nav2_status() {
        XCTAssertFalse(FleetNav2TrainingStackStatusPolicy.applyBridgeStdoutStatusToUI)
    }
}
