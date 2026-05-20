import XCTest
@testable import GuardianCore

/// ``MissionRunEnvironment/rollupMissionTaskStateFromSquadStates`` — multi-primary task rollup / auto-pipeline
/// (``MRESquadsToDo.md`` — **Auto pipeline**).
@MainActor
final class MissionRunMultiSquadRollupAutoPipelineTests: XCTestCase {

    func test_roll_up_nil_when_single_squad_aggregate() {
        XCTAssertNil(MissionRunEnvironment.rollupMissionTaskStateFromSquadStates([.executing]))
    }

    func test_roll_up_all_abort_directed_not_all_aborted_is_aborting() {
        XCTAssertEqual(
            MissionRunEnvironment.rollupMissionTaskStateFromSquadStates([.aborting, .aborted, .aborting]),
            .aborting
        )
    }

    func test_roll_up_all_aborted_is_aborted() {
        XCTAssertEqual(
            MissionRunEnvironment.rollupMissionTaskStateFromSquadStates([.aborted, .aborted]),
            .aborted
        )
    }

    func test_roll_up_mixed_abort_paths_ignored_when_recovery_present() {
        XCTAssertEqual(
            MissionRunEnvironment.rollupMissionTaskStateFromSquadStates([.aborting, .recovery, .completed]),
            .recovery
        )
    }

    func test_roll_up_mixed_abort_paths_ignored_when_only_completed_remain() {
        XCTAssertEqual(
            MissionRunEnvironment.rollupMissionTaskStateFromSquadStates([.aborted, .completed, .completed]),
            .completed
        )
    }

    func test_roll_up_mixed_abort_paths_ignored_when_executing_remains() {
        XCTAssertEqual(
            MissionRunEnvironment.rollupMissionTaskStateFromSquadStates([.aborting, .executing, .ready]),
            .executing
        )
    }

    func test_roll_up_two_completed_only() {
        XCTAssertEqual(
            MissionRunEnvironment.rollupMissionTaskStateFromSquadStates([.completed, .completed]),
            .completed
        )
    }

    func test_roll_up_between_maps_to_executing() {
        XCTAssertEqual(
            MissionRunEnvironment.rollupMissionTaskStateFromSquadStates([.between, .ready]),
            .executing
        )
    }

    func test_roll_up_finite_race_one_recovery_two_executing_stays_executing() {
        XCTAssertEqual(
            MissionRunEnvironment.rollupMissionTaskStateFromSquadStates([.recovery, .executing, .executing]),
            .executing
        )
    }

    func test_roll_up_finite_race_all_recovery_is_recovery() {
        XCTAssertEqual(
            MissionRunEnvironment.rollupMissionTaskStateFromSquadStates([.recovery, .recovery, .recovery]),
            .recovery
        )
    }

    func test_roll_up_recovery_two_completed_is_recovery() {
        XCTAssertEqual(
            MissionRunEnvironment.rollupMissionTaskStateFromSquadStates([.recovery, .completed, .completed]),
            .recovery
        )
    }
}
