import XCTest
@testable import GuardianHQ

final class MissionRunReserveSwapPlanRecompilationPolicyTests: XCTestCase {

    func test_floatingReserveSwapPlanCompileSource_isStableTelemetryToken() {
        XCTAssertEqual(
            MissionRunReserveSwapPlanRecompilationPolicy.floatingReserveSwapPlanCompileSource,
            "missionControl.plan.floatingReserveSwap"
        )
    }

    func test_mutationCommitCallbacksLexicographicFlag_isLockedTrue() {
        XCTAssertTrue(MissionRunReserveSwapPlanRecompilationPolicy.mutationCommitCallbacksInvokedLexicographicByRegistrationKey)
    }
}
