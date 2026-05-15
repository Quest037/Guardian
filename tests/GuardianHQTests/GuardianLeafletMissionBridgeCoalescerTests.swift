import XCTest

@testable import GuardianHQ

@MainActor
final class GuardianLeafletMissionBridgeCoalescerTests: XCTestCase {

    func test_rapid_enqueue_retains_latest_script_until_flush() {
        let coalescer = GuardianLeafletMissionBridgeCoalescer(coalesceInterval: 0)
        var applied: [String] = []
        coalescer.enqueue(script: "first") { applied.append($0) }
        coalescer.enqueue(script: "second") { applied.append($0) }
        XCTAssertEqual(coalescer.latestScript, "second")
        coalescer.flushPendingForTesting { applied.append($0) }
        XCTAssertEqual(applied, ["second"])
    }

    func test_identical_script_not_reapplied_after_flush() {
        let coalescer = GuardianLeafletMissionBridgeCoalescer(coalesceInterval: 0)
        var applyCount = 0
        coalescer.enqueue(script: "same") { _ in applyCount += 1 }
        coalescer.flushPendingForTesting { _ in applyCount += 1 }
        XCTAssertEqual(applyCount, 1)
        coalescer.enqueue(script: "same") { _ in applyCount += 1 }
        coalescer.flushPendingForTesting { _ in applyCount += 1 }
        XCTAssertEqual(applyCount, 1)
    }

    func test_noteWebViewReloaded_allows_reapply_of_same_script() {
        let coalescer = GuardianLeafletMissionBridgeCoalescer(coalesceInterval: 0)
        var applyCount = 0
        coalescer.enqueue(script: "same") { _ in applyCount += 1 }
        coalescer.flushPendingForTesting { _ in applyCount += 1 }
        coalescer.noteWebViewReloaded()
        coalescer.enqueue(script: "same") { _ in applyCount += 1 }
        coalescer.flushPendingForTesting { _ in applyCount += 1 }
        XCTAssertEqual(applyCount, 2)
    }

    func test_default_coalesce_interval_is_one_sixtieth_second() {
        XCTAssertEqual(
            GuardianLeafletMissionBridgeCoalescer.defaultCoalesceInterval,
            1.0 / 60.0,
            accuracy: 0.0001
        )
    }
}
