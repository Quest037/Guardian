import XCTest
@testable import GuardianHQ

final class MissionSquadConvoySpacingPolicyTests: XCTestCase {

    func test_lockedSpacing_convoy_ugv_uses_tight_test_gap() {
        let spacing = MissionSquadConvoySpacingPolicy.lockedSpacing(
            taskPattern: .convoy,
            primaryGranularClass: .ugvWheeled
        )
        XCTAssertEqual(spacing.alongTrackMetersPerOrdinal, 3)
        XCTAssertEqual(spacing.lateralLaneMeters, 0)
    }

    func test_lockedSpacing_convoy_uav_uses_uav_default() {
        let spacing = MissionSquadConvoySpacingPolicy.lockedSpacing(
            taskPattern: .convoy,
            primaryGranularClass: .uavCopter
        )
        XCTAssertEqual(spacing.alongTrackMetersPerOrdinal, 25)
    }

    func test_lockedSpacing_singlePath_ugv_uses_tight_test_gap() {
        let spacing = MissionSquadConvoySpacingPolicy.lockedSpacing(
            taskPattern: .singlePath,
            primaryGranularClass: .ugvWheeled
        )
        XCTAssertEqual(spacing.alongTrackMetersPerOrdinal, 3)
    }
}
