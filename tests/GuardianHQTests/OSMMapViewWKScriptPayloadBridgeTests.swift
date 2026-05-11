import Foundation
@testable import GuardianHQ
import XCTest

final class OSMMapViewWKScriptPayloadBridgeTests: XCTestCase {
    func test_double_acceptsDouble() {
        XCTAssertEqual(OSMMapView.WKScriptPayloadBridge.double(12.5), 12.5)
    }

    func test_double_acceptsNSNumber() {
        XCTAssertEqual(OSMMapView.WKScriptPayloadBridge.double(NSNumber(value: 3.25)), 3.25)
    }

    func test_double_acceptsInt() {
        XCTAssertEqual(OSMMapView.WKScriptPayloadBridge.double(7), 7.0)
    }

    func test_int_acceptsInt() {
        XCTAssertEqual(OSMMapView.WKScriptPayloadBridge.int(4), 4)
    }

    func test_int_acceptsNSNumber() {
        XCTAssertEqual(OSMMapView.WKScriptPayloadBridge.int(NSNumber(value: 9)), 9)
    }
}
