import XCTest
@testable import GuardianHQ

final class Ros2BridgeLocatorTests: XCTestCase {
    func test_microXrcePort_locked() {
        XCTAssertEqual(Ros2BridgeRuntime.microXrceUdpPort, 8888)
    }

    func test_bundledPackageSource_hasPythonModule() {
        guard let root = Ros2BridgeLocator.bundledPackageSourceURL() else {
            XCTFail("Ros2VehicleBridge not in test bundle")
            return
        }
        let module = root.appendingPathComponent("guardian_ros2_vehicle_bridge", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: module.path))
    }

    func test_resolveLaunchPlan_devFallback_whenNoMergedInstall() {
        // SPM test bundle may not include Ros2Runtime/install; plan should still resolve if /opt/ros exists.
        guard let plan = Ros2BridgeLocator.resolveLaunchPlan() else {
            throw XCTSkip("No bundled ROS runtime and no system ROS — skip")
        }
        XCTAssertFalse(plan.setupScriptPath.isEmpty)
        if plan.usesBundledMergedInstall {
            XCTAssertNil(plan.packageSourceDirectory)
            XCTAssertTrue(plan.setupScriptPath.contains("Ros2Runtime"))
        } else {
            XCTAssertNotNil(plan.packageSourceDirectory)
        }
    }
}
