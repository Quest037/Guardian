import Foundation
import XCTest

@testable import GuardianCore

final class MissionRunReserveAutoSwapExecutorPolicyTests: XCTestCase {

    func test_debounce_allows_first_attempt() {
        let now = Date()
        XCTAssertTrue(
            MissionRunReserveAutoSwapExecutorPolicy.debounceAllowsAttempt(lastAttemptAt: nil, now: now)
        )
    }

    func test_debounce_blocks_within_window() {
        let now = Date()
        XCTAssertFalse(
            MissionRunReserveAutoSwapExecutorPolicy.debounceAllowsAttempt(
                lastAttemptAt: now.addingTimeInterval(-60),
                debounce: 300,
                now: now
            )
        )
    }

    func test_debounce_allows_after_window() {
        let now = Date()
        XCTAssertTrue(
            MissionRunReserveAutoSwapExecutorPolicy.debounceAllowsAttempt(
                lastAttemptAt: now.addingTimeInterval(-400),
                debounce: 300,
                now: now
            )
        )
    }
}
