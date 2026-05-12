import XCTest

@testable import GuardianHQ

final class MissionRunReserveSwapReplacedActiveReturnPathPolicyTests: XCTestCase {

    func test_v1_return_path_flags_document_shipped_commit_shapes() {
        XCTAssertTrue(MissionRunReserveSwapReplacedActiveReturnPathPolicy.floatingPoolSwapInWritesPriorBindingToConsumedBerth)
        XCTAssertTrue(MissionRunReserveSwapReplacedActiveReturnPathPolicy.fixedReserveSwapInIsPairwiseRosterBindingExchange)
        XCTAssertTrue(MissionRunReserveSwapReplacedActiveReturnPathPolicy.operatorReturnToPoolUsesReturnAssignmentToReservePoolAPI)
    }
}
