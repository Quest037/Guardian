import XCTest

@testable import GuardianHQ

final class McsReservePoolHomeMapBatchLogTemplateCatalogTests: XCTestCase {

    func test_catalog_has_patterns_for_mcs_reserve_pool_home_map_batch() {
        let key = MissionRunLogTemplateKey.mcsReservePoolHomeMapBatch
        XCTAssertNotNil(
            StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport),
            "Missing export catalog entry for \(key)"
        )
        XCTAssertNotNil(
            StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom),
            "Missing MCR catalog entry for \(key)"
        )
    }

    func test_stored_message_interpolates_sent_and_coordinates() {
        let key = MissionRunLogTemplateKey.mcsReservePoolHomeMapBatch
        let msg = StructuredLogTemplateCatalog.storedMessage(
            forKey: key,
            templateParams: [
                "taskID": "30000000-0000-0000-0000-000000000001",
                "sent": "3",
                "latDeg": "-33.123456",
                "lonDeg": "151.000001",
                "modeNote": "",
            ]
        )
        XCTAssertTrue(msg.contains("3"), msg)
        XCTAssertTrue(msg.contains("-33.123456"), msg)
        XCTAssertTrue(msg.contains("151.000001"), msg)
        XCTAssertFalse(msg.contains("{{modeNote}}"), msg)
    }

    func test_stored_message_interpolates_mode_note_for_reapply() {
        let key = MissionRunLogTemplateKey.mcsReservePoolHomeMapBatch
        let msg = StructuredLogTemplateCatalog.storedMessage(
            forKey: key,
            templateParams: [
                "taskID": "30000000-0000-0000-0000-000000000001",
                "sent": "1",
                "latDeg": "0.0",
                "lonDeg": "0.0",
                "modeNote": " (reapply)",
            ]
        )
        XCTAssertTrue(msg.contains("(reapply)"), msg)
    }
}
