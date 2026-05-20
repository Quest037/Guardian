import XCTest

@testable import GuardianCore

final class MissionRunSimHomeRestorePolicyTests: XCTestCase {
    func test_shouldSchedule_allGatesPass() {
        XCTAssertTrue(
            MissionRunSimHomeRestorePolicy.shouldScheduleAfterMarkCompleted(
                completionKind: .operatorCompletedImmediate,
                settingsEnabled: true,
                snapshotsNonEmpty: true,
                hasFleetAndSitl: true
            )
        )
    }

    func test_shouldSchedule_falseWhenStopOutcome() {
        XCTAssertFalse(
            MissionRunSimHomeRestorePolicy.shouldScheduleAfterMarkCompleted(
                completionKind: .operatorStoppedImmediate,
                settingsEnabled: true,
                snapshotsNonEmpty: true,
                hasFleetAndSitl: true
            )
        )
    }

    func test_shouldSchedule_falseWhenSettingsOff() {
        XCTAssertFalse(
            MissionRunSimHomeRestorePolicy.shouldScheduleAfterMarkCompleted(
                completionKind: .oneOffAutopilotFinished,
                settingsEnabled: false,
                snapshotsNonEmpty: true,
                hasFleetAndSitl: true
            )
        )
    }

    func test_shouldSchedule_falseWhenNoSnapshots() {
        XCTAssertFalse(
            MissionRunSimHomeRestorePolicy.shouldScheduleAfterMarkCompleted(
                completionKind: .operatorCompletedAfterCycle,
                settingsEnabled: true,
                snapshotsNonEmpty: false,
                hasFleetAndSitl: true
            )
        )
    }

    func test_shouldSchedule_falseWhenNoFleetContext() {
        XCTAssertFalse(
            MissionRunSimHomeRestorePolicy.shouldScheduleAfterMarkCompleted(
                completionKind: .operatorCompletedImmediate,
                settingsEnabled: true,
                snapshotsNonEmpty: true,
                hasFleetAndSitl: false
            )
        )
    }

    func test_lifecycleSimHomeRestoreBatch_catalogPatterns() {
        let key = MissionRunLogTemplateKey.lifecycleSimHomeRestoreBatch
        XCTAssertFalse((StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport) ?? "").isEmpty)
        XCTAssertFalse((StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom) ?? "").isEmpty)
        let plain = StructuredLogTemplateCatalog.storedMessage(
            forKey: key,
            templateParams: ["phase": "roster", "applied": "1", "skipped": "0", "candidates": "1"]
        )
        XCTAssertTrue(plain.contains("roster"))
    }

    func test_lifecycleSimCleanupRunStarted_catalogPatterns() {
        let key = MissionRunLogTemplateKey.lifecycleSimCleanupRunStarted
        XCTAssertFalse((StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport) ?? "").isEmpty)
        XCTAssertFalse((StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom) ?? "").isEmpty)
    }

    func test_lifecycleSimCleanupRunFinished_catalogPatterns() {
        let key = MissionRunLogTemplateKey.lifecycleSimCleanupRunFinished
        XCTAssertFalse((StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport) ?? "").isEmpty)
        XCTAssertFalse((StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom) ?? "").isEmpty)
    }
}
