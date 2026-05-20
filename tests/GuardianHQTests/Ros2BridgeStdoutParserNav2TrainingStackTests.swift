import XCTest
@testable import GuardianCore

final class Ros2BridgeStdoutParserNav2TrainingStackTests: XCTestCase {
    func test_parses_nav2_training_stack_ready() {
        let line = #"{"type":"ros2_nav2_training_stack","status":"ready"}"#
        let event = Ros2BridgeStdoutParser.parse(line: line)
        XCTAssertEqual(event?.type, "ros2_nav2_training_stack")
        XCTAssertEqual(event?.trainingStackStatus, "ready")
    }

    func test_parses_nav2_training_stack_restarting() {
        let line = #"{"type":"ros2_nav2_training_stack","status":"restarting","message":"attempt_2"}"#
        let event = Ros2BridgeStdoutParser.parse(line: line)
        XCTAssertEqual(event?.trainingStackStatus, "restarting")
        XCTAssertEqual(event?.message, "attempt_2")
    }
}
