import XCTest

@testable import GuardianHQ

@MainActor
final class ToastCenterTests: XCTestCase {

    func test_show_clearsAfterDuration() async throws {
        let center = ToastCenter()
        center.show("Ack", style: .info, duration: 0.35)
        XCTAssertEqual(center.current?.text, "Ack")
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertNil(center.current)
    }

    func test_dismiss_clearsImmediatelyAndInvalidatesPendingAutoDismiss() async throws {
        let center = ToastCenter()
        center.show("Tap away", style: .success, duration: 2)
        center.dismiss()
        XCTAssertNil(center.current)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(center.current)
    }

    /// Rapid identical ``ToastCenter/show`` must not starve auto-dismiss by bumping generation every time.
    func test_duplicateIdenticalVisibleToast_onlyReschedulesDeadline() async throws {
        let center = ToastCenter()
        center.show("Same line", style: .warning, duration: 0.4)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNotNil(center.current)
        center.show("Same line", style: .warning, duration: 0.4)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotNil(center.current)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(center.current)
    }

    func test_differentMessage_replacesAndStartsFreshDismiss() async throws {
        let center = ToastCenter()
        center.show("First", style: .info, duration: 0.5)
        try await Task.sleep(nanoseconds: 100_000_000)
        center.show("Second", style: .error, duration: 0.35)
        XCTAssertEqual(center.current?.text, "Second")
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertNil(center.current)
    }
}
