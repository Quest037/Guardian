import XCTest
@testable import GuardianHQ

final class GuardianMovementCapabilitiesTests: XCTestCase {

    func test_ugvWheeled_supportsReverse_notStrafe() {
        XCTAssertTrue(GuardianMovementCapabilities.supports(.reverse, vehicleType: .ugvWheeled))
        XCTAssertFalse(GuardianMovementCapabilities.supports(.strafe, vehicleType: .ugvWheeled))
    }

    func test_ugvWheeled_supportsThreePointReverse() {
        XCTAssertTrue(GuardianMovementCapabilities.supports(.threePointReverse, vehicleType: .ugvWheeled))
        XCTAssertFalse(GuardianMovementCapabilities.supports(.threePointReverse, vehicleType: .uavCopter))
    }

    func test_uavCopter_supportsStrafe() {
        XCTAssertTrue(GuardianMovementCapabilities.supports(.strafe, vehicleType: .uavCopter))
    }

    func test_ugvTracked_supportsReverse_notStrafe() {
        XCTAssertTrue(GuardianMovementCapabilities.supports(.reverse, vehicleType: .ugvTracked))
        XCTAssertFalse(GuardianMovementCapabilities.supports(.strafe, vehicleType: .ugvTracked))
    }
}
