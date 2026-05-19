import XCTest
@testable import GuardianHQ

@MainActor
final class GazeboWebViewportCameraBridgeTests: XCTestCase {
    func test_trigger_updatesTickAndJavaScriptExpression() {
        let bridge = GazeboWebViewportCameraBridge()
        let initial = bridge.tick

        bridge.trigger(.defaultView)
        XCTAssertNotEqual(bridge.tick, initial)
        XCTAssertTrue(bridge.javaScriptExpression.contains("resetDefaultView()"))
        XCTAssertTrue(bridge.javaScriptExpression.contains("sceneReady"))

        bridge.trigger(.birdseye)
        XCTAssertTrue(bridge.javaScriptExpression.contains("fitBirdseyeView()"))
    }
}
