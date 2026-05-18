import XCTest
@testable import GuardianHQ

final class Ros2BridgeVehiclePlanTests: XCTestCase {
    func test_rosNamespace_instanceZero_empty() {
        XCTAssertEqual(Ros2BridgeVehiclePlan.rosNamespace(px4SitlInstance: 0), "")
        XCTAssertEqual(Ros2BridgeVehiclePlan.rosNamespace(px4SitlInstance: nil), "")
    }

    func test_rosNamespace_multiInstance() {
        XCTAssertEqual(Ros2BridgeVehiclePlan.rosNamespace(px4SitlInstance: 2), "px4_2")
    }

    func test_entry_px4_requires_ros2_sidecar_desired() {
        XCTAssertNil(
            Ros2BridgeVehiclePlan.entry(
                for: .init(
                    vehicleID: "sysid:1",
                    autopilotStack: .px4,
                    vehicleType: .uavCopter,
                    px4SitlInstance: 1,
                    ros2SidecarDesired: false
                )
            )
        )
    }

    func test_entry_px4_only() {
        let px4 = Ros2BridgeVehiclePlan.entry(
            for: .init(
                vehicleID: "sysid:1",
                autopilotStack: .px4,
                vehicleType: .uavCopter,
                px4SitlInstance: 1,
                ros2SidecarDesired: true
            )
        )
        XCTAssertEqual(px4?.stack, "px4")
        XCTAssertEqual(px4?.vehicleClass, "uav_copter")
        XCTAssertEqual(px4?.rosNamespace, "px4_1")
        XCTAssertEqual(px4?.autonomyPlanner, "aerostack2")

        XCTAssertNil(
            Ros2BridgeVehiclePlan.entry(
                for: .init(
                    vehicleID: "sysid:2",
                    autopilotStack: .ardupilot,
                    vehicleType: .ugvWheeled,
                    px4SitlInstance: nil
                )
            )
        )
    }

    func test_entry_ugv_planner_nav2() {
        let entry = Ros2BridgeVehiclePlan.entry(
            for: .init(
                vehicleID: "sysid:2",
                autopilotStack: .px4,
                vehicleType: .ugvWheeled,
                px4SitlInstance: 0,
                ros2SidecarDesired: true
            )
        )
        XCTAssertEqual(entry?.autonomyPlanner, "nav2")
    }

}
