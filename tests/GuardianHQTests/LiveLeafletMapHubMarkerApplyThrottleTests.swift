import XCTest

@testable import GuardianHQ

@MainActor
final class LiveLeafletMapHubMarkerApplyThrottleTests: XCTestCase {

    func test_zero_hz_applies_every_request_immediately() {
        let throttle = LiveLeafletMapHubMarkerApplyThrottle(maxHz: 0)
        var count = 0
        throttle.requestCoalesced { count += 1 }
        throttle.requestCoalesced { count += 1 }
        XCTAssertEqual(count, 2)
    }

    func test_coalesces_rapid_requests_to_single_flush_with_latest_value() async {
        let throttle = LiveLeafletMapHubMarkerApplyThrottle(maxHz: 20)
        var value = 0
        throttle.requestCoalesced { value = 1 }
        throttle.requestCoalesced { value = 2 }
        XCTAssertEqual(value, 0)
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(value, 2)
    }

    func test_flush_immediately_bypasses_pending_coalesce() async {
        let throttle = LiveLeafletMapHubMarkerApplyThrottle(maxHz: 5)
        var value = 0
        throttle.requestCoalesced { value = 1 }
        throttle.flushImmediately { value = 99 }
        XCTAssertEqual(value, 99)
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(value, 99)
    }

    func test_resolved_max_hz_defaults_to_ten() {
        XCTAssertEqual(LiveLeafletMapHubMarkerApplyThrottlePolicy.defaultMaxHz, 10)
    }
}
