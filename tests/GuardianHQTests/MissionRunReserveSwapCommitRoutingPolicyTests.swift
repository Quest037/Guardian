import XCTest

@testable import GuardianHQ

final class MissionRunReserveSwapCommitRoutingPolicyTests: XCTestCase {

    func test_pool_berth_uses_shipped_primitive() {
        let s = MissionRunReserveSwapCommitRoutingPolicy.executionSurface(
            for: .floatingPoolBerth(slotID: UUID())
        )
        XCTAssertEqual(s, .swapRosterAssignmentWithRandomFloatingReserve)
    }

    func test_fixed_reserve_rows_route_to_pending_unified_api() {
        let s = MissionRunReserveSwapCommitRoutingPolicy.executionSurface(
            for: .fixedTemplateReserveRosterRow(assignmentID: UUID())
        )
        XCTAssertEqual(s, .commitReserveSwapInPending)
    }
}
