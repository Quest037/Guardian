import XCTest
@testable import GuardianHQ

final class OperatorPromptDisplaySourceTests: XCTestCase {

    func test_operatorFacingShortLabel_missionControl() {
        XCTAssertEqual(OperatorPromptDisplaySource.missionControl.operatorFacingShortLabel, "Mission Control")
    }

    func test_operatorFacingShortLabel_mre() {
        XCTAssertEqual(OperatorPromptDisplaySource.mre.operatorFacingShortLabel, "Mission run")
    }

    func test_operatorFacingShortLabel_assistantUsesDisplayName() {
        let s = OperatorPromptDisplaySource.assistant(
            pluginID: "plugin.test.example",
            displayName: "Example",
            operatorPromptBackgroundHex: "aabbcc"
        )
        XCTAssertEqual(s.operatorFacingShortLabel, "Example")
    }

    func test_hexRGB_normalizesHashAndCase() {
        XCTAssertEqual(OperatorPromptHexRGB.normalizedRGBHex6("#DBDE9B"), "dbde9b")
        XCTAssertEqual(OperatorPromptHexRGB.normalizedRGBHex6("  b996d3 "), "b996d3")
        XCTAssertNil(OperatorPromptHexRGB.normalizedRGBHex6("gggggg"))
        XCTAssertNil(OperatorPromptHexRGB.normalizedRGBHex6("abc"))
    }

    func test_missionRunStackPromptCardBackgroundHex6_isSixChars() {
        XCTAssertEqual(OperatorPromptChrome.missionRunStackPromptCardBackgroundHex6.count, 6)
        XCTAssertNotNil(
            OperatorPromptHexRGB.rgbUInt8Components(hex6: OperatorPromptChrome.missionRunStackPromptCardBackgroundHex6)
        )
    }

    func test_usesPastelIssuerOperatorPromptCardFill_mreAndAssistantWithHex() {
        XCTAssertTrue(OperatorPromptDisplaySource.missionControl.usesPastelIssuerOperatorPromptCardFill)
        XCTAssertTrue(OperatorPromptDisplaySource.mre.usesPastelIssuerOperatorPromptCardFill)
        XCTAssertTrue(
            OperatorPromptDisplaySource.assistant(
                pluginID: "p",
                displayName: "A",
                operatorPromptBackgroundHex: "#aabbcc"
            ).usesPastelIssuerOperatorPromptCardFill
        )
        XCTAssertFalse(
            OperatorPromptDisplaySource.assistant(
                pluginID: "p",
                displayName: "A",
                operatorPromptBackgroundHex: nil
            ).usesPastelIssuerOperatorPromptCardFill
        )
    }
}
