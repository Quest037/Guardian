import XCTest
@testable import GuardianCore

@MainActor
final class GazeboWebsocketBridgeLogTrackerTests: XCTestCase {
    func test_consume_flagsWebsocketServerBindFailure() {
        let tracker = GazeboWebsocketBridgeLogTracker()
        XCTAssertFalse(tracker.serverBindFailed)
        tracker.consume("[Err] Unable to create websocket server")
        XCTAssertTrue(tracker.serverBindFailed)
    }

    func test_consume_flagsSceneInfoQueryFailure() {
        let tracker = GazeboWebsocketBridgeLogTracker()
        XCTAssertFalse(tracker.sceneInfoQueryFailed)
        tracker.consume("[Err] Failed to get the scene information for guardian_open_field world.")
        XCTAssertTrue(tracker.sceneInfoQueryFailed)
    }
}

@MainActor
final class GazeboSimSceneReadinessTrackerTests: XCTestCase {
    func test_consume_flagsScenePublishing() {
        let tracker = GazeboSimSceneReadinessTracker()
        XCTAssertFalse(tracker.scenePublishing)
        tracker.consume("[Msg] Publishing scene information on [/world/guardian_open_field/scene/info]")
        XCTAssertTrue(tracker.scenePublishing)
    }
}
