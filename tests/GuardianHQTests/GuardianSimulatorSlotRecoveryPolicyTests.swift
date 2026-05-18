import XCTest
@testable import GuardianHQ

final class GuardianSimulatorSlotRecoveryPolicyTests: XCTestCase {
    func test_shouldOfferRetry_whenLinkedButPreflightPending() {
        let slot = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "sysid:1",
            linkReady: true,
            preflightPassed: nil,
            preflightDetail: nil
        )
        XCTAssertTrue(GuardianSimulatorSlotRecoveryPolicy.shouldOfferRetry(slot: slot))
    }

    func test_shouldOfferRetry_whenAwaitingLink() {
        let slot = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "sysid:1",
            linkReady: false,
            preflightPassed: nil,
            preflightDetail: "Awaiting telemetry."
        )
        XCTAssertTrue(GuardianSimulatorSlotRecoveryPolicy.shouldOfferRetry(slot: slot))
    }

    func test_shouldNotOfferRetry_whenPreflightPassed() {
        let slot = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "sysid:1",
            linkReady: true,
            preflightPassed: true,
            preflightDetail: nil
        )
        XCTAssertFalse(GuardianSimulatorSlotRecoveryPolicy.shouldOfferRetry(slot: slot))
    }

    func test_retryButtonTitle_awaitingUsesRetryLink() {
        XCTAssertEqual(
            GuardianSimulatorSlotRecoveryPolicy.retryButtonTitle(linkReady: false, phase: .connecting),
            "Retry link"
        )
    }
}
