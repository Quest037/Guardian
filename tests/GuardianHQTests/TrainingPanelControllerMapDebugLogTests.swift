import XCTest
@testable import GuardianCore

@MainActor
final class TrainingPanelControllerMapDebugLogTests: XCTestCase {
    func test_logMap_capsAtMaxLines() {
        let controller = TrainingPanelController()
        for index in 0 ..< (WorldBuilderMapDebugLog.maxLines + 10) {
            controller.logMap("line \(index)")
        }
        XCTAssertEqual(controller.mapDebugLines.count, WorldBuilderMapDebugLog.maxLines)
        XCTAssertTrue(controller.mapDebugLines.last?.contains("line \(WorldBuilderMapDebugLog.maxLines + 9)") == true)
    }

    func test_logMap_prefixesTimestamp() {
        let controller = TrainingPanelController()
        controller.logMap("probe")
        XCTAssertEqual(controller.mapDebugLines.count, 1)
        XCTAssertTrue(controller.mapDebugLines[0].hasPrefix("["))
        XCTAssertTrue(controller.mapDebugLines[0].contains("] probe"))
    }
}
