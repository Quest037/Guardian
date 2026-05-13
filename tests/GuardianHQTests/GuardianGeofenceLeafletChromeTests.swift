import XCTest
@testable import GuardianHQ

final class GuardianGeofenceLeafletChromeTests: XCTestCase {

    func test_leafletChrome_jsonFragment_containsSemanticKeys() {
        let light = GuardianGeofenceLeafletChrome(colorScheme: .light)
        let j = light.jsonObjectFragmentEscapedForJS()
        XCTAssertTrue(j.contains("\"inclusionStroke\":\"#"))
        XCTAssertTrue(j.contains("\"inclusionFill\":\"rgba("))
        XCTAssertTrue(j.contains("\"exclusionStroke\":\"#"))
        XCTAssertTrue(j.contains("\"exclusionFill\":\"rgba("))
    }

    func test_leafletChrome_lightDiffersFromDark() {
        let light = GuardianGeofenceLeafletChrome(colorScheme: .light)
        let dark = GuardianGeofenceLeafletChrome(colorScheme: .dark)
        XCTAssertNotEqual(light.jsonObjectFragmentEscapedForJS(), dark.jsonObjectFragmentEscapedForJS())
    }
}
