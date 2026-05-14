import XCTest

@testable import GuardianHQ

final class MissionRosterVehicleClassCompatibilityTests: XCTestCase {
    func test_unknownExpected_neverWarns() {
        XCTAssertFalse(
            MissionRosterVehicleClassCompatibility.bindingShowsDifferentClassWarning(expected: .unknown, candidate: .uavCopter)
        )
        XCTAssertFalse(
            MissionRosterVehicleClassCompatibility.bindingShowsDifferentClassWarning(expected: .unknown, candidate: .unknown)
        )
    }

    func test_matchingGranular_neverWarns() {
        XCTAssertFalse(
            MissionRosterVehicleClassCompatibility.bindingShowsDifferentClassWarning(expected: .uavCopter, candidate: .uavCopter)
        )
    }

    func test_mismatchedUAVKinds_warns() {
        XCTAssertTrue(
            MissionRosterVehicleClassCompatibility.bindingShowsDifferentClassWarning(expected: .uavCopter, candidate: .uavFixedWing)
        )
    }

    func test_ugvWheeledTrackedPair_noWarning() {
        XCTAssertFalse(
            MissionRosterVehicleClassCompatibility.bindingShowsDifferentClassWarning(expected: .ugvWheeled, candidate: .ugvTracked)
        )
        XCTAssertFalse(
            MissionRosterVehicleClassCompatibility.bindingShowsDifferentClassWarning(expected: .ugvTracked, candidate: .ugvWheeled)
        )
    }
}
