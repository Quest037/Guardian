import XCTest

@testable import GuardianCore

final class MissionRunSquadFirstWaveLogTemplateTests: XCTestCase {

    func test_mission_squad_first_wave_released_catalog_patterns_exist() {
        let key = MissionRunLogTemplateKey.missionSquadFirstWaveReleased
        XCTAssertNotNil(StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport))
        XCTAssertNotNil(StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom))
    }

    func test_mission_squad_first_wave_released_interpolates_params() {
        let key = MissionRunLogTemplateKey.missionSquadFirstWaveReleased
        let msg = StructuredLogTemplateCatalog.storedMessage(
            forKey: key,
            templateParams: ["squad": "Dagger:1", "slotID": "00000000-0000-0000-0000-000000000001"]
        )
        XCTAssertTrue(msg.contains("Dagger:1"))
        XCTAssertFalse(msg.contains("missing log template"))
    }
}
