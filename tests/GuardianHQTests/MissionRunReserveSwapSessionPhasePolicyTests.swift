import XCTest
@testable import GuardianHQ

final class MissionRunReserveSwapSessionPhasePolicyTests: XCTestCase {

    func test_allowsReserveSwapMutation_true_for_draftCompiledStagingExecuting() {
        XCTAssertTrue(MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: .draft))
        XCTAssertTrue(MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: .compiled))
        XCTAssertTrue(MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: .staging))
        XCTAssertTrue(MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: .executing))
    }

    func test_allowsReserveSwapMutation_false_for_recoveryCompletedAbortingAborted() {
        XCTAssertFalse(MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: .recovery))
        XCTAssertFalse(MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: .completed))
        XCTAssertFalse(MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: .aborting))
        XCTAssertFalse(MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: .aborted))
    }
}
