import XCTest

@testable import GuardianHQ

final class MissionRunCompletionKindSimHomeRestorePolicyTests: XCTestCase {
    func test_qualifies_operatorCompletePaths_and_oneOff() {
        XCTAssertTrue(MissionRunCompletionKind.operatorCompletedImmediate.qualifiesForSimHomeRestoreAfterSuccessfulMissionRun)
        XCTAssertTrue(MissionRunCompletionKind.operatorCompletedAfterCycle.qualifiesForSimHomeRestoreAfterSuccessfulMissionRun)
        XCTAssertTrue(MissionRunCompletionKind.oneOffAutopilotFinished.qualifiesForSimHomeRestoreAfterSuccessfulMissionRun)
    }

    func test_qualifies_false_for_operatorStopPaths() {
        XCTAssertFalse(MissionRunCompletionKind.operatorStoppedImmediate.qualifiesForSimHomeRestoreAfterSuccessfulMissionRun)
        XCTAssertFalse(MissionRunCompletionKind.operatorStoppedAfterCycle.qualifiesForSimHomeRestoreAfterSuccessfulMissionRun)
    }

    func test_nilCompletionKind_treatedAsIneligible_atCallSite() {
        let kind: MissionRunCompletionKind? = nil
        XCTAssertFalse(kind?.qualifiesForSimHomeRestoreAfterSuccessfulMissionRun ?? false)
    }
}
