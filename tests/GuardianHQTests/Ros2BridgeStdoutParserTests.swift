import XCTest
@testable import GuardianHQ

final class Ros2BridgeStdoutParserTests: XCTestCase {
    func test_parse_connection_state() {
        let line = #"{"type":"ros2_connection_state","vehicle_id":"sysid:1","state":"CONNECTED"}"#
        let event = Ros2BridgeStdoutParser.parse(line: line)
        XCTAssertEqual(event?.type, "ros2_connection_state")
        XCTAssertEqual(event?.vehicleID, "sysid:1")
        XCTAssertEqual(event?.state, .connected)
    }

    func test_parse_autonomy_planner() {
        let line = #"{"type":"ros2_autonomy_planner","vehicle_id":"sysid:2","planner":"nav2"}"#
        let event = Ros2BridgeStdoutParser.parse(line: line)
        XCTAssertEqual(event?.type, "ros2_autonomy_planner")
        XCTAssertEqual(event?.plannerKind, "nav2")
    }

    func test_parse_bridge_error() {
        let line = #"{"type":"ros2_bridge_error","message":"missing_rclpy"}"#
        let event = Ros2BridgeStdoutParser.parse(line: line)
        XCTAssertEqual(event?.type, "ros2_bridge_error")
        XCTAssertEqual(event?.message, "missing_rclpy")
    }
}
