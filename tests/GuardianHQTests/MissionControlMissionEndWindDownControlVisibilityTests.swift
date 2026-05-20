import XCTest
@testable import GuardianCore

final class MissionControlMissionEndWindDownControlVisibilityTests: XCTestCase {
    func test_squad_executing_shows_abort_and_complete() {
        XCTAssertTrue(MissionControlMissionEndWindDownControlVisibility.showsAbortOptions(for: MissionSquadState.executing))
        XCTAssertTrue(MissionControlMissionEndWindDownControlVisibility.showsCompleteOptions(for: MissionSquadState.executing))
    }

    func test_squad_recovery_shows_abort_only() {
        XCTAssertTrue(MissionControlMissionEndWindDownControlVisibility.showsAbortOptions(for: MissionSquadState.recovery))
        XCTAssertFalse(MissionControlMissionEndWindDownControlVisibility.showsCompleteOptions(for: MissionSquadState.recovery))
    }

    func test_squad_completed_shows_abort_only() {
        XCTAssertTrue(MissionControlMissionEndWindDownControlVisibility.showsAbortOptions(for: MissionSquadState.completed))
        XCTAssertFalse(MissionControlMissionEndWindDownControlVisibility.showsCompleteOptions(for: MissionSquadState.completed))
    }

    func test_squad_aborting_and_aborted_hide_all() {
        for state in [MissionSquadState.aborting, MissionSquadState.aborted] {
            XCTAssertFalse(MissionControlMissionEndWindDownControlVisibility.showsAbortOptions(for: state))
            XCTAssertFalse(MissionControlMissionEndWindDownControlVisibility.showsCompleteOptions(for: state))
        }
    }

    func test_task_executing_shows_abort_and_complete() {
        XCTAssertTrue(MissionControlMissionEndWindDownControlVisibility.showsAbortOptions(for: MissionTaskState.executing))
        XCTAssertTrue(MissionControlMissionEndWindDownControlVisibility.showsCompleteOptions(for: MissionTaskState.executing))
    }

    func test_task_recovery_shows_abort_only() {
        XCTAssertTrue(MissionControlMissionEndWindDownControlVisibility.showsAbortOptions(for: MissionTaskState.recovery))
        XCTAssertFalse(MissionControlMissionEndWindDownControlVisibility.showsCompleteOptions(for: MissionTaskState.recovery))
    }

    func test_task_aborting_and_aborted_hide_all() {
        for state in [MissionTaskState.aborting, MissionTaskState.aborted] {
            XCTAssertFalse(MissionControlMissionEndWindDownControlVisibility.showsAbortOptions(for: state))
            XCTAssertFalse(MissionControlMissionEndWindDownControlVisibility.showsCompleteOptions(for: state))
        }
    }

    func test_task_path_cards_hide_when_matching_graceful_pending() {
        XCTAssertFalse(
            MissionControlMissionEndWindDownControlVisibility.showsTaskPathAbortWindDownCard(
                protocolShowsAbort: true,
                taskPending: .abortAfterCycle,
                anySquadGracefulPending: false
            )
        )
        XCTAssertTrue(
            MissionControlMissionEndWindDownControlVisibility.showsTaskPathAbortWindDownCard(
                protocolShowsAbort: true,
                taskPending: .completeAfterCycle,
                anySquadGracefulPending: false
            )
        )
        XCTAssertFalse(
            MissionControlMissionEndWindDownControlVisibility.showsTaskPathCompleteWindDownCard(
                protocolShowsComplete: true,
                taskPending: .completeAfterCycle,
                anySquadGracefulPending: false
            )
        )
        XCTAssertFalse(
            MissionControlMissionEndWindDownControlVisibility.showsTaskPathCompleteWindDownCard(
                protocolShowsComplete: true,
                taskPending: .abortAfterCycle,
                anySquadGracefulPending: false
            )
        )
    }

    func test_task_path_cards_hidden_when_any_squad_graceful_pending() {
        XCTAssertFalse(
            MissionControlMissionEndWindDownControlVisibility.showsTaskPathAbortWindDownCard(
                protocolShowsAbort: true,
                taskPending: nil,
                anySquadGracefulPending: true
            )
        )
        XCTAssertFalse(
            MissionControlMissionEndWindDownControlVisibility.showsTaskPathCompleteWindDownCard(
                protocolShowsComplete: true,
                taskPending: nil,
                anySquadGracefulPending: true
            )
        )
    }

    func test_scheduled_end_policy_notice_title() {
        XCTAssertEqual(
            MissionControlMissionEndWindDownControlVisibility.scheduledEndPolicyNoticeTitle(for: .abortAfterCycle),
            "Scheduled abort policy"
        )
        XCTAssertEqual(
            MissionControlMissionEndWindDownControlVisibility.scheduledEndPolicyNoticeTitle(for: .completeAfterCycle),
            "Scheduled complete policy"
        )
    }

    func test_resolved_scheduled_graceful_notice_kind_prefers_task_then_abort() {
        XCTAssertEqual(
            MissionControlMissionEndWindDownControlVisibility.resolvedScheduledGracefulNoticeKind(
                taskPending: .completeAfterCycle,
                squadPendings: [.abortAfterCycle]
            ),
            .completeAfterCycle
        )
        XCTAssertEqual(
            MissionControlMissionEndWindDownControlVisibility.resolvedScheduledGracefulNoticeKind(
                taskPending: nil,
                squadPendings: [.abortAfterCycle, .completeAfterCycle]
            ),
            .abortAfterCycle
        )
        XCTAssertNil(
            MissionControlMissionEndWindDownControlVisibility.resolvedScheduledGracefulNoticeKind(
                taskPending: nil,
                squadPendings: []
            )
        )
    }

    func test_squad_cards_hide_when_matching_graceful_pending() {
        XCTAssertFalse(
            MissionControlMissionEndWindDownControlVisibility.showsSquadAbortWindDownCard(
                protocolShowsAbort: true,
                squadPending: .abortAfterCycle,
                taskPending: nil
            )
        )
        XCTAssertFalse(
            MissionControlMissionEndWindDownControlVisibility.showsSquadAbortWindDownCard(
                protocolShowsAbort: true,
                squadPending: nil,
                taskPending: .abortAfterCycle
            )
        )
        XCTAssertFalse(
            MissionControlMissionEndWindDownControlVisibility.showsSquadCompleteWindDownCard(
                protocolShowsComplete: true,
                squadPending: .completeAfterCycle,
                taskPending: nil
            )
        )
        XCTAssertFalse(
            MissionControlMissionEndWindDownControlVisibility.showsSquadCompleteWindDownCard(
                protocolShowsComplete: true,
                squadPending: nil,
                taskPending: .completeAfterCycle
            )
        )
        XCTAssertFalse(
            MissionControlMissionEndWindDownControlVisibility.showsSquadCompleteWindDownCard(
                protocolShowsComplete: true,
                squadPending: nil,
                taskPending: .abortAfterCycle
            )
        )
    }
}
