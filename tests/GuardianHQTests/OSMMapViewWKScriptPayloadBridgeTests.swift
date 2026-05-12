import XCTest

@testable import GuardianHQ

final class OSMMapViewWKScriptPayloadBridgeTests: XCTestCase {
    func test_optionalString_nilAndNSNull() {
        XCTAssertNil(OSMMapView.WKScriptPayloadBridge.optionalString(nil))
        XCTAssertNil(OSMMapView.WKScriptPayloadBridge.optionalString(NSNull()))
    }

    func test_optionalString_swiftString() {
        XCTAssertEqual(OSMMapView.WKScriptPayloadBridge.optionalString("assignment-id"), "assignment-id")
    }

    func test_optionalString_nsString() {
        let nss: NSString = "550e8400-e29b-41d4-a716-446655440000"
        XCTAssertEqual(OSMMapView.WKScriptPayloadBridge.optionalString(nss), "550e8400-e29b-41d4-a716-446655440000")
    }
}
