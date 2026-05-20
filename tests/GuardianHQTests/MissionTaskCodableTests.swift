import XCTest

@testable import GuardianCore

final class MissionTaskCodableTests: XCTestCase {

    func test_encode_omits_executionMethod_key() throws {
        let task = MissionTask(name: "Alpha", regularity: .onceAtStart)
        let data = try JSONEncoder().encode(task)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["executionMethod"])
    }

    func test_decode_ignores_legacy_executionMethod_key() throws {
        let id = UUID()
        let dict: [String: Any] = [
            "id": id.uuidString,
            "name": "T",
            "enabled": true,
            "waypoints": [] as [Any],
            "loopMode": "none",
            "cycles": 1,
            "regularityDelayValue": 1.0,
            "regularityDelayUnit": "mins",
            "executionMethod": "staggered",
            "regularity": "onceAtStart",
            "betweenCycles": "returnToLaunch",
            "pattern": "patrol",
            "spaceBindings": [] as [Any],
            "startDelayValue": 0.0,
            "startDelayUnit": "secs",
        ]
        let data = try XCTUnwrap(JSONSerialization.data(withJSONObject: dict))
        let task = try JSONDecoder().decode(MissionTask.self, from: data)
        XCTAssertEqual(task.id, id)
        XCTAssertEqual(task.name, "T")
    }
}
