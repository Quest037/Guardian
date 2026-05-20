import XCTest
@testable import GuardianCore

@MainActor
final class Ros2BridgeStdoutParserNav2PlanTests: XCTestCase {
    func test_parses_nav2_plan_path() {
        let json = """
        {"type":"ros2_nav2_plan_path","request_id":"A1B2C3D4-E5F6-4789-ABCD-EF1234567890","vehicle_id":"sysid:1","ok":true,"source":"geodesic_fallback","points":[{"lat":-35.0,"lon":149.0},{"lat":-35.0001,"lon":149.0001}]}
        """
        let event = Ros2BridgeStdoutParser.parse(line: json)
        XCTAssertEqual(event?.type, "ros2_nav2_plan_path")
        let payload = event?.nav2PlanPath
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.vehicleID, "sysid:1")
        XCTAssertTrue(payload?.ok == true)
        XCTAssertEqual(payload?.source, "geodesic_fallback")
        XCTAssertEqual(payload?.points.count, 2)
    }
}
