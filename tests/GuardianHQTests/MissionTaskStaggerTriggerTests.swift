import XCTest

@testable import GuardianHQ

final class MissionTaskStaggerTriggerTests: XCTestCase {

    func test_fixed_interval_step_uses_authored_delay() {
        let task = MissionTask(
            staggerTrigger: .fixedInterval,
            staggerIntervalValue: 30,
            staggerIntervalUnit: .secs
        )
        let mission = Mission(id: UUID(), name: "M", description: "", type: .mobile)
        let step = MissionTaskStaggerPolicy.firstWaveStepSeconds(
            task: task,
            mission: mission,
            squads: []
        )
        XCTAssertEqual(step, 30, accuracy: 0.01)
    }

    func test_operator_gate_excludes_subsequent_primaries_from_first_wave() {
        let task = MissionTask(staggerTrigger: .operatorFirstWaveGate)
        XCTAssertTrue(MissionTaskStaggerPolicy.includesSquadInAutomaticFirstWave(task: task, squadIndex: 0))
        XCTAssertFalse(MissionTaskStaggerPolicy.includesSquadInAutomaticFirstWave(task: task, squadIndex: 1))
    }

    func test_waypoint_index_clamped_on_normalize() {
        var task = MissionTask(
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 0, lon: 0)),
                RouteWaypoint(coord: RouteCoordinate(lat: 1, lon: 1)),
            ] as [RouteWaypoint],
            staggerTrigger: .waypointReached,
            staggerWaypointIndex: 99
        )
        XCTAssertEqual(task.staggerWaypointIndex, 1)
    }

    func test_waypoint_stagger_gate_crosses_once_at_index_plus_one() {
        XCTAssertFalse(
            MissionTaskStaggerPolicy.shouldAutoReleaseNextDeferredFirstWaveSquad(
                previousProgress: -1,
                currentProgress: 0,
                missionProgressTotal: 10,
                staggerWaypointIndex: 2
            )
        )
        XCTAssertFalse(
            MissionTaskStaggerPolicy.shouldAutoReleaseNextDeferredFirstWaveSquad(
                previousProgress: 1,
                currentProgress: 2,
                missionProgressTotal: 10,
                staggerWaypointIndex: 2
            )
        )
        XCTAssertTrue(
            MissionTaskStaggerPolicy.shouldAutoReleaseNextDeferredFirstWaveSquad(
                previousProgress: 2,
                currentProgress: 3,
                missionProgressTotal: 10,
                staggerWaypointIndex: 2
            )
        )
        XCTAssertFalse(
            MissionTaskStaggerPolicy.shouldAutoReleaseNextDeferredFirstWaveSquad(
                previousProgress: 3,
                currentProgress: 4,
                missionProgressTotal: 10,
                staggerWaypointIndex: 2
            )
        )
    }
}
