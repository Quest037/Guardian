import XCTest

@testable import GuardianCore

final class MissionRunReserveSwapPhaseLogTemplateKeyTests: XCTestCase {

    func test_all_keys_unique_and_count() {
        let keys = MissionRunReserveSwapPhaseLogTemplateKey.allTemplateKeys()
        XCTAssertEqual(keys.count, MissionRunReserveSwapPipelinePhase.allCases.count * 2)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func test_expected_key_shape() {
        let k = MissionRunReserveSwapPhaseLogTemplateKey.templateKey(phase: .swapTimeChecks, passed: false)
        XCTAssertEqual(k, "missioncontrol.mre.reserve.phase.swap_time_checks.fail")
        let post = MissionRunReserveSwapPhaseLogTemplateKey.templateKey(phase: .postCommitHandoff, passed: true)
        XCTAssertEqual(post, "missioncontrol.mre.reserve.phase.post_commit_handoff.pass")
    }

    func test_catalog_has_pattern_for_every_key() {
        for key in MissionRunReserveSwapPhaseLogTemplateKey.allTemplateKeys() {
            XCTAssertNotNil(
                StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport),
                "Missing catalog entry for \(key)"
            )
            XCTAssertNotNil(
                StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom),
                "Missing MCR pattern for \(key)"
            )
        }
    }

    func test_template_params_include_phase_and_correlation() {
        let mr = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let mt = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let vac = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        let rsv = UUID(uuidString: "30000000-0000-0000-0000-000000000004")!
        let pool = UUID(uuidString: "30000000-0000-0000-0000-000000000005")!
        let c = MissionRunReserveRecipeRunnerCorrelation(
            missionRunID: mr,
            missionTaskID: mt,
            vacancyAssignmentID: vac,
            reserveStreamAssignmentID: rsv,
            reservePoolSlotID: pool,
            vehicleID: "v1"
        )
        let p = MissionRunReserveSwapPhaseLogTemplateKey.templateParams(
            phase: .missionUpload,
            correlation: c,
            detail: "ok",
            recipeRaw: "recipe.fleet.diagnose.armprobe"
        )
        XCTAssertEqual(p["phase"], "mission_upload")
        XCTAssertEqual(p["missionRunID"], mr.uuidString)
        XCTAssertEqual(p["recipe"], "recipe.fleet.diagnose.armprobe")
    }
}
