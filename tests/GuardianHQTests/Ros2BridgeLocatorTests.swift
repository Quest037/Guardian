import XCTest
@testable import GuardianHQ

final class Ros2BridgeLocatorTests: XCTestCase {
    func test_bashLaunchGuardianBridgeModule_uses_ros_python3_not_hardcoded_system_path() {
        let fragment = Ros2BridgeLocator.bashLaunchGuardianBridgeModule(
            configFilePath: "/tmp/vehicles.yaml",
            packageSourceRoot: "/tmp/guardian_ros2_vehicle_bridge"
        )
        XCTAssertTrue(fragment.contains("exec python3 -m guardian_ros2_vehicle_bridge.multi_vehicle_bridge"))
        XCTAssertFalse(fragment.contains("Python3.framework"))
        XCTAssertTrue(fragment.contains("GUARDIAN_PYTHON"))
    }
}
