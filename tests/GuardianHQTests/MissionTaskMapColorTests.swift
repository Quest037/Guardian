import XCTest
@testable import GuardianHQ

final class MissionTaskMapColorTests: XCTestCase {
    func test_hslCssToSRGBUnit_hueZero_matchesCssHsl08862() {
        let (r, g, b) = MissionTaskMapColor.hslCssToSRGBUnit(hueDegrees: 0, saturation: 0.88, lightness: 0.62)
        XCTAssertEqual(r, 0.954_4, accuracy: 0.0005)
        XCTAssertEqual(g, 0.285_6, accuracy: 0.0005)
        XCTAssertEqual(b, 0.285_6, accuracy: 0.0005)
    }

    func test_hueDegrees_taskIndexOne_matchesGoldenAngle() {
        XCTAssertEqual(MissionTaskMapColor.hueDegrees(forTaskIndex: 1), 137.508, accuracy: 0.000_001)
    }
}
