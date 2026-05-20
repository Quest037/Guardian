import XCTest
@testable import GuardianCore

final class MissionRunReserveSwapReplacedActiveDispositionPolicyTests: XCTestCase {

    func test_pool_successfulSwapRequiresReturnWhenPriorBinding() {
        XCTAssertTrue(
            MissionRunReserveSwapReplacedActivePoolDispositionPolicy.successfulSwapRequiresReturnToPoolWhenPriorSlotHadBinding
        )
    }

    func test_pool_returnRejectionsSurfaceWithoutPartialCommit() {
        XCTAssertTrue(
            MissionRunReserveSwapReplacedActivePoolDispositionPolicy.poolReturnRejectionsSurfaceToOperatorWithoutPartialRosterCommit
        )
    }

    func test_fleet_useCatalogueAndRecipeDispatchOnly() {
        XCTAssertTrue(MissionRunReserveSwapReplacedActiveFleetWindDownPolicy.useMissionControlCatalogueAndRecipeDispatchOnly)
    }

    func test_fleet_preferCompleteChainWhenOrderly() {
        XCTAssertTrue(
            MissionRunReserveSwapReplacedActiveFleetWindDownPolicy.preferCompletePreferenceWindDownForOrderlySwapOut(true)
        )
        XCTAssertFalse(
            MissionRunReserveSwapReplacedActiveFleetWindDownPolicy.preferCompletePreferenceWindDownForOrderlySwapOut(false)
        )
    }

    func test_fleet_abortClassUsesAbortPlanStack() {
        XCTAssertTrue(MissionRunReserveSwapReplacedActiveFleetWindDownPolicy.abortClassWindDownUsesAbortPlanStack)
    }

    func test_telemetry_focusVacancyFirst() {
        XCTAssertTrue(
            MissionRunReserveSwapReplacedActiveTelemetryHandoffPolicy.focusMissionControlRunningOnVacancyAssignmentFirst
        )
    }

    func test_telemetry_retainReplacedOnMap() {
        XCTAssertTrue(
            MissionRunReserveSwapReplacedActiveTelemetryHandoffPolicy.retainReplacedVehicleOnMapUntilWindDownCompletesOrLinkLost
        )
    }
}
