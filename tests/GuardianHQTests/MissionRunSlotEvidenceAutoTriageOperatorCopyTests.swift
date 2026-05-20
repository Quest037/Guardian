import XCTest
@testable import GuardianCore

final class MissionRunSlotEvidenceAutoTriageOperatorCopyTests: XCTestCase {

    func test_batch_log_template_registered_in_catalog() {
        let key = MissionRunLogTemplateKey.slotEvidenceAutoAcknowledgedMissionEndBatch
        XCTAssertNotNil(StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport))
        XCTAssertNotNil(StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom))
    }

    func test_toastConsolidated_abort_only() {
        let s = MissionRunSlotEvidenceAutoTriageOperatorCopy.toastConsolidated(
            abortTaskNames: ["North"],
            recoveryTaskNames: []
        )
        XCTAssertTrue(s.contains("North"))
        XCTAssertTrue(s.contains("abort wind-down"))
        XCTAssertFalse(s.contains("complete wind-down"))
    }

    func test_toastConsolidated_recovery_only() {
        let s = MissionRunSlotEvidenceAutoTriageOperatorCopy.toastConsolidated(
            abortTaskNames: [],
            recoveryTaskNames: ["South"]
        )
        XCTAssertTrue(s.contains("South"))
        XCTAssertTrue(s.contains("complete wind-down"))
    }

    func test_toastConsolidated_both_kinds() {
        let s = MissionRunSlotEvidenceAutoTriageOperatorCopy.toastConsolidated(
            abortTaskNames: ["A"],
            recoveryTaskNames: ["B"]
        )
        XCTAssertTrue(s.contains("abort wind-down for A"))
        XCTAssertTrue(s.contains("complete wind-down for B"))
    }

    func test_toastManualTriage_completed() {
        let s = MissionRunSlotEvidenceAutoTriageOperatorCopy.toastManualTriage(taskName: "North", state: .completed)
        XCTAssertTrue(s.contains("North"))
        XCTAssertTrue(s.contains("complete wind-down"))
    }

    func test_toastManualTriage_aborted() {
        let s = MissionRunSlotEvidenceAutoTriageOperatorCopy.toastManualTriage(taskName: "South", state: .aborted)
        XCTAssertTrue(s.contains("South"))
        XCTAssertTrue(s.contains("abort wind-down"))
    }
}
