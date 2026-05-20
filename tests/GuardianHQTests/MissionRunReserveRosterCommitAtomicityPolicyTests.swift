import XCTest

@testable import GuardianCore

final class MissionRunReserveRosterCommitAtomicityPolicyTests: XCTestCase {

    func test_ordered_step_count_matches_case_iterable() {
        XCTAssertEqual(
            MissionRunReserveRosterCommitAtomicityPolicy.floatingPoolOrderedStepCount,
            MissionRunReserveFloatingPoolRosterCommitStep.allCases.count
        )
        XCTAssertEqual(MissionRunReserveFloatingPoolRosterCommitStep.allCases.count, 3)
    }

    func test_step_descriptions_cover_all_steps() {
        for step in MissionRunReserveFloatingPoolRosterCommitStep.allCases {
            let s = MissionRunReserveRosterCommitAtomicityPolicy.floatingPoolCommitStepDescriptions[step]
            XCTAssertNotNil(s)
            XCTAssertFalse(s?.isEmpty ?? true, "\(step)")
        }
    }
}
