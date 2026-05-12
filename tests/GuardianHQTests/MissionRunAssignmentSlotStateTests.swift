import XCTest
@testable import GuardianHQ

final class MissionRunAssignmentSlotStateTests: XCTestCase {

    func test_codable_round_trips_all_cases() throws {
        for state in MissionRunAssignmentSlotState.allCases {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(MissionRunAssignmentSlotState.self, from: data)
            XCTAssertEqual(decoded, state)
        }
    }

    func test_display_title_non_empty_for_all_cases() {
        for state in MissionRunAssignmentSlotState.allCases {
            XCTAssertFalse(state.displayTitle.isEmpty, "Missing displayTitle for \(state)")
        }
    }

    /// Pins ``MissionRunAssignmentSlotState/displayTitle`` v1 operator copy (``TaskRosterAssignmentStatesToDo.md`` §2 UX lock).
    func test_display_title_v1_operator_chip_copy() {
        let table: [MissionRunAssignmentSlotState: String] = [
            .idle: "Idle",
            .staging: "Staging",
            .executingMission: "On mission",
            .betweenCycles: "Between cycles",
            .policyAborting: "Abort in progress",
            .policyCompleting: "Recovery in progress",
            .policySucceeded: "Policy complete",
            .policyFailed: "Policy failed",
            .blockedNoVehicle: "No vehicle bound",
            .notApplicableEmptySlot: "Empty slot",
            .supersededReassigned: "Reassigned",
        ]
        for state in MissionRunAssignmentSlotState.allCases {
            XCTAssertEqual(state.displayTitle, table[state], "displayTitle drift for \(state)")
        }
    }

    func test_slot_state_lanes_codable_round_trip() throws {
        let lanes = MissionRunAssignmentSlotStateLanes(
            commanded: .policyAborting,
            observed: .executingMission
        )
        let data = try JSONEncoder().encode(lanes)
        let decoded = try JSONDecoder().decode(MissionRunAssignmentSlotStateLanes.self, from: data)
        XCTAssertEqual(decoded, lanes)
    }

    func test_merge_policy_aborting_commanded_wins_over_stale_executing_observed() {
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .policyAborting, observed: .executingMission)
        XCTAssertEqual(MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: lanes), .policyAborting)
    }

    func test_merge_policy_completing_commanded_wins_over_stale_observed() {
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .policyCompleting, observed: .idle)
        XCTAssertEqual(MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: lanes), .policyCompleting)
    }

    func test_merge_terminal_commanded_wins_even_if_observed_executing() {
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .executingMission)
        XCTAssertEqual(MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: lanes), .policySucceeded)
    }

    func test_merge_observed_failure_surfaces_when_commanded_still_executing() {
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .executingMission, observed: .policyFailed)
        XCTAssertEqual(MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: lanes), .policyFailed)
    }

    func test_merge_observed_blocked_surfaces_when_commanded_idle() {
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .idle, observed: .blockedNoVehicle)
        XCTAssertEqual(MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: lanes), .blockedNoVehicle)
    }

    func test_merge_observed_failure_does_not_override_commanded_policy_aborting() {
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .policyAborting, observed: .policyFailed)
        XCTAssertEqual(MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: lanes), .policyAborting)
    }
}
