import XCTest
@testable import GuardianHQ

final class MissionRunReserveSwapOperatorCopyTests: XCTestCase {
    func test_reserveSwapPoolPick_message_is_short_confirm_not_manual() {
        let m = MissionRunReserveSwapOperatorCopy.reserveSwapPoolPickConfirmMessage
        XCTAssertTrue(m.contains("arm check"))
        XCTAssertTrue(m.contains("pool row"))
        XCTAssertFalse(m.contains("Step 1"))
    }

    func test_reserveSwapPreflightFailure_prologue_states_roster_unchanged() {
        let p = MissionRunReserveSwapOperatorCopy.reserveSwapPreflightFailurePrologue
        XCTAssertTrue(p.contains("roster"))
        XCTAssertTrue(p.contains("arm check"))
    }

    func test_floating_outcome_failure_detail_is_non_empty_for_common_cases() {
        XCTAssertTrue(MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(.poolSlotNotEligible).contains("berth"))
        XCTAssertTrue(MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(.noEligiblePoolSlots).contains("berths"))
    }

    func test_toast_reserve_swap_return_rejected_includes_summary() {
        let s = MissionRunReserveSwapOperatorCopy.toastReserveSwapReturnRejected(.rejectedBatteryCritical)
        XCTAssertTrue(s.contains("battery critical"))
    }

    func test_post_commit_handoff_failure_toasts_are_non_empty() {
        XCTAssertFalse(MissionRunReserveSwapOperatorCopy.toastReserveSwapPostCommitDisplacedMissionClearFailed.isEmpty)
        XCTAssertFalse(MissionRunReserveSwapOperatorCopy.toastReserveSwapPostCommitVacancyMissionHandoffFailed.isEmpty)
        XCTAssertFalse(MissionRunReserveSwapOperatorCopy.toastReserveSwapPostCommitDisplacedWindDownFailed.isEmpty)
    }
}
