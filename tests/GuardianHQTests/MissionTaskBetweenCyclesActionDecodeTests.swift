import XCTest

@testable import GuardianHQ

final class MissionTaskBetweenCyclesActionDecodeTests: XCTestCase {

    func test_decode_betweenCycles_land_normalizesToRTL() throws {
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
            "executionMethod": "group",
            "regularity": "continuous",
            "betweenCycles": "land",
            "pattern": "patrol",
            "spaceBindings": [] as [Any],
            "startDelayValue": 0.0,
            "startDelayUnit": "secs",
        ]
        let data = try XCTUnwrap(JSONSerialization.data(withJSONObject: dict))
        let task = try JSONDecoder().decode(MissionTask.self, from: data)
        XCTAssertEqual(task.betweenCycles, .returnToLaunch)
    }

    func test_decode_betweenCycles_none_normalizesToRTL() throws {
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
            "executionMethod": "group",
            "regularity": "continuous",
            "betweenCycles": "none",
            "pattern": "patrol",
            "spaceBindings": [] as [Any],
            "startDelayValue": 0.0,
            "startDelayUnit": "secs",
        ]
        let data = try XCTUnwrap(JSONSerialization.data(withJSONObject: dict))
        let task = try JSONDecoder().decode(MissionTask.self, from: data)
        XCTAssertEqual(task.betweenCycles, .returnToLaunch)
    }

    func test_displayTitle_returnToLaunch_isReturnToLaunch() {
        XCTAssertEqual(MissionTaskBetweenCyclesAction.returnToLaunch.displayTitle, "Return to Launch")
    }

    func test_decode_betweenCycles_park_roundTrips() throws {
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
            "executionMethod": "group",
            "regularity": "continuous",
            "betweenCycles": "park",
            "pattern": "patrol",
            "spaceBindings": [] as [Any],
            "startDelayValue": 0.0,
            "startDelayUnit": "secs",
        ]
        let data = try XCTUnwrap(JSONSerialization.data(withJSONObject: dict))
        let task = try JSONDecoder().decode(MissionTask.self, from: data)
        XCTAssertEqual(task.betweenCycles, .park)
    }
}
