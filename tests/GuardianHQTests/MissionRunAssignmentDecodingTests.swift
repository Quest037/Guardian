import XCTest
@testable import GuardianHQ

final class MissionRunAssignmentDecodingTests: XCTestCase {
    /// Older persisted runs may include `simStartOverrideCoord`; it is no longer modeled and must not break decode.
    func test_decode_ignoresLegacySimStartOverrideKey() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "rosterDeviceId": "22222222-2222-2222-2222-222222222222",
          "slotName": "Alpha",
          "attachedDevice": "",
          "simStartOverrideCoord": {"lat": -33.0, "lon": 151.0}
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(MissionRunAssignment.self, from: data)
        XCTAssertEqual(decoded.slotName, "Alpha")
        XCTAssertEqual(decoded.id.uuidString, "11111111-1111-1111-1111-111111111111")
    }
}
