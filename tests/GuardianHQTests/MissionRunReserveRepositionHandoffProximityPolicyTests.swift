import XCTest

@testable import GuardianHQ

final class MissionRunReserveRepositionHandoffProximityPolicyTests: XCTestCase {

    func test_locked_defaults_validate() {
        let v = MissionRunReserveRepositionHandoffProximityPolicy.validateLockedDefaults()
        XCTAssertTrue(v.isValid, v.rejectionReason ?? "")
    }

    func test_defaults_are_strictly_positive() {
        XCTAssertGreaterThan(MissionRunReserveRepositionHandoffProximityPolicy.defaultHorizontalCloseEnoughMeters, 0)
        XCTAssertGreaterThan(MissionRunReserveRepositionHandoffProximityPolicy.defaultVerticalCloseEnoughMeters, 0)
        XCTAssertGreaterThan(MissionRunReserveRepositionHandoffProximityPolicy.defaultRepositionPhaseTimeoutSeconds, 0)
    }
}
