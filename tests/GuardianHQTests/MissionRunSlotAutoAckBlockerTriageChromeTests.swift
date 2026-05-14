import XCTest
@testable import GuardianHQ

final class MissionRunSlotAutoAckBlockerTriageChromeTests: XCTestCase {

    func test_rail_token_blocked_no_vehicle_is_danger() {
        XCTAssertEqual(
            MissionRunSlotAutoAckBlockerTriageChrome.railToken(for: .blockedNoVehicle),
            .danger
        )
    }

    func test_rail_token_policy_succeeded_is_success() {
        XCTAssertEqual(
            MissionRunSlotAutoAckBlockerTriageChrome.railToken(for: .policySucceeded),
            .success
        )
    }

    func test_rail_token_idle_is_neutral() {
        XCTAssertEqual(MissionRunSlotAutoAckBlockerTriageChrome.railToken(for: .idle), .neutral)
    }

    func test_rail_token_policy_aborting_is_warning() {
        XCTAssertEqual(
            MissionRunSlotAutoAckBlockerTriageChrome.railToken(for: .policyAborting),
            .warning
        )
    }
}
