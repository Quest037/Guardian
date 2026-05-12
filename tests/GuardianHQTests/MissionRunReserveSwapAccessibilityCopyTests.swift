import XCTest

@testable import GuardianHQ

final class MissionRunReserveSwapAccessibilityCopyTests: XCTestCase {

    func test_floatingPoolMapMarker_eligible_pick_mentions_task_and_berth() {
        let s = MissionRunReserveSwapAccessibilityCopy.floatingPoolMapMarker(
            taskName: "Alpha",
            berthLabel: "R1",
            swapPickActiveOnTask: true,
            markerIsEligiblePickTarget: true,
            browsingThisBerthOnTask: false
        )
        XCTAssertTrue(s.contains("Alpha"))
        XCTAssertTrue(s.contains("R1"))
        XCTAssertTrue(s.contains("eligible"))
    }

    func test_floatingPoolMapMarker_browsing_appends_overlay_phrase() {
        let s = MissionRunReserveSwapAccessibilityCopy.floatingPoolMapMarker(
            taskName: "Bravo",
            berthLabel: "R2",
            swapPickActiveOnTask: false,
            markerIsEligiblePickTarget: false,
            browsingThisBerthOnTask: true
        )
        XCTAssertTrue(s.contains("overlay"))
    }

    func test_roster_vacancy_during_swap_pick_mentions_vacancy_and_swap() {
        let s = MissionRunReserveSwapAccessibilityCopy.rosterVacancyDuringReserveSwapPick(
            taskName: "Charlie",
            slotName: "Primary"
        )
        XCTAssertTrue(s.contains("Vacancy"))
        XCTAssertTrue(s.contains("Primary"))
        XCTAssertTrue(s.contains("Charlie"))
        XCTAssertTrue(s.contains("Reserve swap-in"))
    }

    func test_reserve_swap_pick_empty_strip_joins_title_and_subtitle() {
        let s = MissionRunReserveSwapAccessibilityCopy.reserveSwapPickEmptyStrip(
            title: "No eligible reserves",
            subtitle: "Bind a reserve."
        )
        XCTAssertTrue(s.hasPrefix("No eligible reserves"))
        XCTAssertTrue(s.contains("Bind a reserve."))
    }
}
