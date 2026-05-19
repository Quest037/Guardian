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

    func test_entry_includes_brain_planner_overlay() {
        let brainId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let entry = Ros2BridgeVehiclePlan.entry(
            for: .init(
                vehicleID: "sysid:4",
                autopilotStack: .px4,
                vehicleType: .ugvWheeled,
                px4SitlInstance: 1,
                ros2SidecarDesired: true,
                brainPlannerOverlay: Ros2BrainPlannerSidecarOverlay(
                    brainId: brainId,
                    brainVersion: GuardianBrainVersion.fromLegacyInteger(4),
                    nav2ParamOverlayJSON: "{\"captured_from\":\"guardian_training_lab\"}",
                    aerostack2ParamOverlayJSON: nil
                )
            )
        )
        XCTAssertEqual(entry?.brainId, brainId.uuidString)
        XCTAssertEqual(entry?.brainVersion, "0.0.4")
        XCTAssertTrue(entry?.nav2ParamOverlayJSON?.contains("guardian_training_lab") == true)
    }

}
