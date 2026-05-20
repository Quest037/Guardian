import XCTest
@testable import GuardianCore

final class MissionRunAssignmentSlotStateRosterChipHelpTests: XCTestCase {

    func test_roster_slot_chip_help_non_empty_and_distinct_from_display_title_for_all_cases() {
        for state in MissionRunAssignmentSlotState.allCases {
            let help = state.rosterSlotChipHelp
            XCTAssertFalse(help.isEmpty, "rosterSlotChipHelp empty for \(state)")
            XCTAssertNotEqual(
                help,
                state.displayTitle,
                "rosterSlotChipHelp should add operator detail beyond displayTitle for \(state)"
            )
            XCTAssertGreaterThanOrEqual(help.count, 24, "rosterSlotChipHelp too short for \(state)")
        }
    }

    func test_worstAmong_carries_roster_slot_chip_help_for_non_error_severity() {
        let a = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "Alpha",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .staging, observed: .idle)
        )
        let w = MissionControlAssignmentSlotRosterAttention.worstAmong(assignments: [a])
        XCTAssertEqual(w?.severity, .info)
        XCTAssertEqual(w?.title, "Staging")
        XCTAssertTrue(w?.help.contains("staging") == true)
        XCTAssertNotEqual(w?.help, w?.title)
    }
}
