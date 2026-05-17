import XCTest
@testable import GuardianHQ

final class FormationsPlaygroundLogExportTests: XCTestCase {
    func test_plainText_ordersOldestFirst_andIncludesFields() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(5)
        let lines = [
            FormationsPlaygroundLogLine(
                timestamp: t1,
                vehicleLabel: "W1",
                state: .movingToPosition,
                message: "second"
            ),
            FormationsPlaygroundLogLine(
                timestamp: t0,
                vehicleLabel: "Primary",
                state: .inPosition,
                message: "first"
            ),
        ]
        let text = FormationsPlaygroundLogExport.plainText(from: lines)
        XCTAssertTrue(text.contains("Primary · inPosition: first"))
        XCTAssertTrue(text.contains("W1 · movingToPosition: second"))
        XCTAssertLessThan(text.range(of: "first")!.lowerBound, text.range(of: "second")!.lowerBound)
    }

    func test_plainText_emptyWhenNoLines() {
        XCTAssertEqual(FormationsPlaygroundLogExport.plainText(from: []), "")
    }
}
