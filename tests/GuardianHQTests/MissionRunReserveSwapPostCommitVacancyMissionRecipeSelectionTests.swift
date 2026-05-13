import XCTest
@testable import GuardianHQ

final class MissionRunReserveSwapPostCommitVacancyMissionRecipeSelectionTests: XCTestCase {

    func test_handoffMissionStartItemIndex_nilWhenCurrentNil() {
        XCTAssertNil(
            MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection.handoffMissionStartItemIndex(
                hubMissionProgressCurrent: nil,
                hubMissionProgressTotal: 10
            )
        )
    }

    func test_handoffMissionStartItemIndex_nilWhenCurrentZeroOrNegative() {
        XCTAssertNil(
            MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection.handoffMissionStartItemIndex(
                hubMissionProgressCurrent: 0,
                hubMissionProgressTotal: 5
            )
        )
        XCTAssertNil(
            MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection.handoffMissionStartItemIndex(
                hubMissionProgressCurrent: -1,
                hubMissionProgressTotal: 5
            )
        )
    }

    func test_handoffMissionStartItemIndex_positiveWhenTotalUnknown() {
        XCTAssertEqual(
            MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection.handoffMissionStartItemIndex(
                hubMissionProgressCurrent: 3,
                hubMissionProgressTotal: nil
            ),
            2
        )
    }

    func test_handoffMissionStartItemIndex_curOneMapsToZero() {
        XCTAssertEqual(
            MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection.handoffMissionStartItemIndex(
                hubMissionProgressCurrent: 1,
                hubMissionProgressTotal: 10
            ),
            0
        )
    }

    func test_handoffMissionStartItemIndex_clampsToTotalMinusOne() {
        XCTAssertEqual(
            MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection.handoffMissionStartItemIndex(
                hubMissionProgressCurrent: 99,
                hubMissionProgressTotal: 5
            ),
            4
        )
    }

    func test_handoffMissionStartItemIndex_usesCurrentWhenWithinRange() {
        XCTAssertEqual(
            MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection.handoffMissionStartItemIndex(
                hubMissionProgressCurrent: 2,
                hubMissionProgressTotal: 10
            ),
            1
        )
    }
}
