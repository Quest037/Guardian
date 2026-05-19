import XCTest
@testable import GuardianHQ

@MainActor
final class GazeboWebViewportCameraBridgeTests: XCTestCase {
    func test_trigger_updatesTickAndJavaScriptExpression() {
        let bridge = GazeboWebViewportCameraBridge()
        let initial = bridge.tick

        bridge.trigger(.defaultView)
        XCTAssertNotEqual(bridge.tick, initial)
        XCTAssertEqual(bridge.javaScriptExpression, "window.guardianViewer.resetDefaultView()")

        bridge.trigger(.birdseye)
        XCTAssertEqual(bridge.javaScriptExpression, "window.guardianViewer.fitBirdseyeView()")
    }
}
