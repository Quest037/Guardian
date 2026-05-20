import XCTest
@testable import GuardianCore

final class GuardianVehicleMotionActuatorRoutingTests: XCTestCase {
    func test_px4_ugv_usesThrottleSteering() {
        let kind = GuardianVehicleMotionActuatorRouting.kind(stack: .px4, universalClass: .ugv)
        XCTAssertEqual(kind, .px4GroundThrottleSteering)
    }

    func test_ardupilot_ugv_usesBodyVelocity() {
        let kind = GuardianVehicleMotionActuatorRouting.kind(stack: .ardupilot, universalClass: .ugv)
        XCTAssertEqual(kind, .offboardBodyVelocity)
    }

    func test_px4_uav_usesBodyVelocity() {
        let kind = GuardianVehicleMotionActuatorRouting.kind(stack: .px4, universalClass: .uav)
        XCTAssertEqual(kind, .offboardBodyVelocity)
    }
}
