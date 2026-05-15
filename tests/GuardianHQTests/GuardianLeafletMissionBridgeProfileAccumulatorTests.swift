import XCTest

@testable import GuardianHQ

final class GuardianLeafletMissionBridgeProfileAccumulatorTests: XCTestCase {

    func test_summary_line_includes_counter_fields() {
        var acc = GuardianLeafletMissionBridgeProfileAccumulator()
        acc.recordUpdateNSView(vehicleMarkerCount: 4)
        acc.recordPayloadUnchangedSkip()
        acc.recordScriptBuilt(byteCount: 2048, vehicleMarkerCount: 4)
        acc.recordScriptEnqueued(byteCount: 2048)
        acc.recordCoalescerDuplicateSkip()
        acc.recordJavaScriptEval(byteCount: 2048)

        let line = acc.summaryLine()
        XCTAssertTrue(line.contains("updateNSView=1"))
        XCTAssertTrue(line.contains("payloadSkip=1"))
        XCTAssertTrue(line.contains("built=1"))
        XCTAssertTrue(line.contains("enqueued=1"))
        XCTAssertTrue(line.contains("coalesceSkip=1"))
        XCTAssertTrue(line.contains("evals=1"))
        XCTAssertTrue(line.contains("vehicles=4"))
    }

    func test_totals_accumulate_bytes() {
        var acc = GuardianLeafletMissionBridgeProfileAccumulator()
        acc.recordScriptBuilt(byteCount: 1000, vehicleMarkerCount: 2)
        acc.recordScriptBuilt(byteCount: 500, vehicleMarkerCount: 2)
        acc.recordJavaScriptEval(byteCount: 1500)
        XCTAssertEqual(acc.totalBuiltBytes, 1500)
        XCTAssertEqual(acc.totalEvalBytes, 1500)
        XCTAssertEqual(acc.lastBuiltBytes, 500)
    }
}
