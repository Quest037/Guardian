import XCTest
@testable import GuardianCore

final class MissionRunReserveSwapPlanRecompilationPolicyTests: XCTestCase {

    func test_floatingReserveSwapPlanCompileSource_isStableTelemetryToken() {
        XCTAssertEqual(
            MissionRunReserveSwapPlanRecompilationPolicy.floatingReserveSwapPlanCompileSource,
            "missionControl.plan.floatingReserveSwap"
        )
    }

    func test_geofenceAugmentationPolicyPlanCompileSource_isStableTelemetryToken() {
        XCTAssertEqual(
            MissionRunReserveSwapPlanRecompilationPolicy.geofenceAugmentationPolicyPlanCompileSource,
            "missionControl.plan.geofenceAugmentationPolicy"
        )
    }

    func test_mutationCommitCallbacksLexicographicFlag_isLockedTrue() {
        XCTAssertTrue(MissionRunReserveSwapPlanRecompilationPolicy.mutationCommitCallbacksInvokedLexicographicByRegistrationKey)
    }
}
