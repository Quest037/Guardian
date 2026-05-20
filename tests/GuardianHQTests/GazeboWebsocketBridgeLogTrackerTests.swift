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

    func test_consume_flagsSceneInfoQueryFailure_withAnsiColorCodes() {
        let tracker = GazeboWebsocketBridgeLogTracker()
        tracker.consume(
            "\u{001B}[1;31m[Err] [WebsocketServer.cc:865] \u{001B}[0m\u{001B}[1;31mFailed to get the scene information for \u{001B}[0m\u{001B}[1;31mguardian_micro_map_test\u{001B}[0m\u{001B}[1;31m world.\u{001B}[0m"
        )
        XCTAssertTrue(tracker.sceneInfoQueryFailed)
    }

    func test_resetForRetry_clearsFlags() {
        let tracker = GazeboWebsocketBridgeLogTracker()
        tracker.consume("[Err] Unable to create websocket server")
        tracker.consume("[Err] Failed to get the scene information for foo world.")
        tracker.resetForRetry()
        XCTAssertFalse(tracker.serverBindFailed)
        XCTAssertFalse(tracker.sceneInfoQueryFailed)
    }
}

@MainActor
final class GazeboSimSceneReadinessTrackerTests: XCTestCase {
    func test_consume_flagsScenePublishing() {
        let tracker = GazeboSimSceneReadinessTracker()
        XCTAssertFalse(tracker.scenePublishing)
        tracker.consume("[Msg] Publishing scene information on [/world/guardian_open_field/scene/info]")
        XCTAssertTrue(tracker.scenePublishing)
        XCTAssertEqual(tracker.matchedWorldName, "guardian_open_field")
    }

    func test_consume_flagsScenePublishing_withAnsiPrefixes() {
        let tracker = GazeboSimSceneReadinessTracker()
        tracker.consume(
            "\u{001B}[1;32m[Msg]\u{001B}[0m Publishing scene information on [/world/guardian_micro_map_test/scene/info]"
        )
        XCTAssertTrue(tracker.scenePublishing)
        XCTAssertEqual(tracker.matchedWorldName, "guardian_micro_map_test")
    }

    func test_extractWorldName_fromSceneInfoLine() {
        let name = GazeboSimSceneReadinessTracker.extractWorldName(
            fromSceneInfoLine: "Publishing scene information on [/world/guardian_micro_map_test/scene/info]"
        )
        XCTAssertEqual(name, "guardian_micro_map_test")
    }

    func test_consume_flagsScenePublishing_fromWorldInitializedLine() {
        let tracker = GazeboSimSceneReadinessTracker()
        tracker.consume("[Msg] World [guardian_micro_map_test] initialized with [1ms] physics profile.")
        XCTAssertTrue(tracker.scenePublishing)
        XCTAssertEqual(tracker.matchedWorldName, "guardian_micro_map_test")
    }
}

final class GazeboChildLogLineTests: XCTestCase {
    func test_plain_stripsAnsiEscapes() {
        let raw = "\u{001B}[1;31mFailed\u{001B}[0m"
        XCTAssertEqual(GazeboChildLogLine.plain(raw), "Failed")
    }
}

final class GazeboTransportSceneReadinessTests: XCTestCase {
    func test_sceneInfoTopicPath() {
        XCTAssertEqual(
            GazeboTransportSceneReadiness.sceneInfoTopicPath(worldName: "guardian_micro_map_test"),
            "/world/guardian_micro_map_test/scene/info"
        )
    }
}

final class GazeboTransportScenePublisherParseTests: XCTestCase {
    func test_sceneInfoTopicHasPublisher_parsesHarmonicTopicInfo() {
        let sample = """
        Publishers [Address, Message Type]:
          tcp://127.0.0.1:57604, gz.msgs.Scene
        Subscribers [Address, Message Type]:
        """
        XCTAssertTrue(sample.contains("Publishers"))
        XCTAssertTrue(sample.contains("gz.msgs.Scene"))
    }
}
