import XCTest
@testable import GuardianCore

final class MissionRunOperatorContinueAfterParkLogTemplateTests: XCTestCase {

    func test_operatorContinueAfterPark_templateKeys_registeredInCatalog() {
        for key in [
            MissionRunLogTemplateKey.operatorContinueAfterParkQueued,
            MissionRunLogTemplateKey.operatorContinueAfterParkUnavailable,
            MissionRunLogTemplateKey.operatorPolicyWindDownJoltEscalation,
            MissionRunLogTemplateKey.operatorPolicyWindDownJoltRedispatched,
            MissionRunLogTemplateKey.operatorPolicyWindDownJoltParkStabilizationFailed,
        ] {
            XCTAssertNotNil(
                StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport),
                key
            )
            XCTAssertNotNil(
                StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom),
                key
            )
        }
    }

    func test_operatorContinueAfterParkQueued_storedMessage_interpolates() {
        let msg = StructuredLogTemplateCatalog.storedMessage(
            forKey: MissionRunLogTemplateKey.operatorContinueAfterParkQueued,
            templateParams: [
                "slot": "Echo:1",
                "slotID": UUID().uuidString,
                "intent": "Retry recovery",
            ]
        )
        XCTAssertTrue(msg.contains("Retry recovery"))
        XCTAssertTrue(msg.contains("Echo:1"))
    }
}
