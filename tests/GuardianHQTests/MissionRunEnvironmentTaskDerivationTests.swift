import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunEnvironmentTaskDerivationTests: XCTestCase {

    private func environment(task: MissionTask) -> MissionRunEnvironment {
        if !task.rosterDeviceIds.isEmpty {
            let mission = Mission(
                name: "M",
                description: "",
                type: .mobile,
                routeMacro: RouteMacro(tasks: [task])
            )
            return MissionRunEnvironment(mission: mission)
        }
        let rd = RosterDevice(name: "RosterPrimary", slot: .primary, vehicleClass: .uavCopter)
        let boundTask = MissionTask(
            id: task.id,
            name: task.name,
            enabled: task.enabled,
            waypoints: task.waypoints,
            loopMode: task.loopMode,
            cycles: task.cycles,
            regularityDelayValue: task.regularityDelayValue,
            regularityDelayUnit: task.regularityDelayUnit,
            regularity: task.regularity,
            betweenCycles: task.betweenCycles,
            pattern: task.pattern,
            staggerTrigger: task.staggerTrigger,
            staggerIntervalValue: task.staggerIntervalValue,
            staggerIntervalUnit: task.staggerIntervalUnit,
            staggerWaypointIndex: task.staggerWaypointIndex,
            rosterDeviceIds: [rd.id],
            startDelayValue: task.startDelayValue,
            startDelayUnit: task.startDelayUnit,
            abortPreferenceChainOverride: task.abortPreferenceChainOverride,
            completePreferenceChainOverride: task.completePreferenceChainOverride,
            reserveSwapPreferenceChainOverride: task.reserveSwapPreferenceChainOverride,
            geofences: task.geofences
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [boundTask])
        )
        let assign = MissionRunAssignment(
            taskId: boundTask.id,
            rosterDeviceId: rd.id,
            slotName: rd.name,
            attachedFleetVehicleToken: "test:tok"
        )
        return MissionRunEnvironment(mission: mission, assignments: [assign])
    }

    func test_disabled_task_derives_ready() {
        let task = MissionTask(name: "Off", enabled: false)
        let run = environment(task: task)
        run.status = .running
        run.setSessionPhase(.executing)
        run.markTaskActiveInCurrentCycle(task.id)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .ready)
    }

    func test_operator_triage_pin_aborted_overrides_executing() {
        let task = MissionTask(name: "Alpha", enabled: true)
        let run = environment(task: task)
        run.status = .running
        run.setSessionPhase(.executing)
        run.markTaskActiveInCurrentCycle(task.id)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .executing)

        run.operatorMarkMissionTaskTriageState(taskID: task.id, state: .aborted)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborted)
    }

    func test_abort_wind_down_issued_then_acknowledge_moves_triage_sets() {
        let task = MissionTask(name: "Bravo", enabled: true)
        let run = environment(task: task)
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborting)
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))

        run.acknowledgeTaskMissionEndAbort(taskID: task.id)
        XCTAssertTrue(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborted)
    }

    func test_prepareMissionTaskForOperatorRestart_clears_ack_sets_and_triage() {
        let task = MissionTask(name: "Charlie", enabled: true)
        let run = environment(task: task)
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        run.acknowledgeTaskMissionEndAbort(taskID: task.id)
        XCTAssertTrue(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))

        run.prepareMissionTaskForOperatorRestart(taskID: task.id)
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))
        XCTAssertFalse(run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id))
        XCTAssertNil(run.operatorTriageMarkedMissionTaskStateByTaskID[task.id])
    }

    /// §4: merged slot success matches §3 auto-ack predicate; settled task state can show terminal **before** ack-set mutation.
    func test_abort_terminal_derived_from_slot_rollup_without_ack_set() {
        let task = MissionTask(name: "SlotAbort", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let lanesPending = MissionRunAssignmentSlotStateLanes(commanded: .executingMission, observed: .executingMission)
        let row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: lanesPending
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborting)
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))

        var updated = row
        updated.slotLifecycleLanes = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        run.assignments = [updated]
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborted)
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))
    }

    func test_recovery_terminal_derived_from_slot_rollup_without_ack_set() {
        let task = MissionTask(name: "SlotRecovery", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let lanesPending = MissionRunAssignmentSlotStateLanes(commanded: .executingMission, observed: .executingMission)
        let row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: lanesPending
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: task.id)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .recovery)
        XCTAssertFalse(run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id))

        var updated = row
        updated.slotLifecycleLanes = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        run.assignments = [updated]
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.taskStateByTaskID[task.id], .completed)
        XCTAssertFalse(run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id))
    }

    func test_session_aborting_uses_slot_rollup_when_abort_issued() {
        let task = MissionTask(name: "SessionAbort", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .executingMission, observed: .executingMission)
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        run.setSessionPhase(.aborting)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborting)

        var updated = row
        updated.slotLifecycleLanes = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        run.assignments = [updated]
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborted)
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))
    }

    func test_session_recovery_uses_slot_rollup_when_complete_wind_down_issued() {
        let task = MissionTask(name: "SessionRecovery", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .executingMission, observed: .executingMission)
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: task.id)
        run.setSessionPhase(.recovery)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .recovery)

        var updated = row
        updated.slotLifecycleLanes = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        run.assignments = [updated]
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.taskStateByTaskID[task.id], .completed)
        XCTAssertFalse(run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id))
    }

    func test_promote_session_aborted_when_all_enabled_tasks_have_abort_slot_evidence_without_ack_sets() {
        let t1 = MissionTask(name: "T1", enabled: true)
        let t2 = MissionTask(name: "T2", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [t1, t2]))
        let lanesOk = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        let r1 = MissionRunAssignment(
            taskId: t1.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: lanesOk
        )
        let r2 = MissionRunAssignment(
            taskId: t2.id,
            rosterDeviceId: UUID(),
            slotName: "W2",
            slotLifecycleLanes: lanesOk
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [r1, r2])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: t1.id)
        run.markMissionTaskAbortWindDownIssued(forTaskID: t2.id)
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(t1.id))
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(t2.id))

        run.setSessionPhase(.aborting)
        XCTAssertEqual(run.sessionPhase, .aborted)
    }

    func test_session_stays_aborting_when_one_enabled_task_missing_abort_slot_evidence() {
        let t1 = MissionTask(name: "T1", enabled: true)
        let t2 = MissionTask(name: "T2", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [t1, t2]))
        let lanesOk = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        let lanesBad = MissionRunAssignmentSlotStateLanes(commanded: .executingMission, observed: .executingMission)
        let r1 = MissionRunAssignment(
            taskId: t1.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: lanesOk
        )
        let r2 = MissionRunAssignment(
            taskId: t2.id,
            rosterDeviceId: UUID(),
            slotName: "W2",
            slotLifecycleLanes: lanesBad
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [r1, r2])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: t1.id)
        run.markMissionTaskAbortWindDownIssued(forTaskID: t2.id)
        run.setSessionPhase(.aborting)
        XCTAssertEqual(run.sessionPhase, .aborting)
    }

    func test_operator_triage_aborted_overrides_complete_wind_down_slot_roll_up() {
        let task = MissionTask(name: "TriageAbort", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        let row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: lanes
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: task.id)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .completed)

        run.operatorMarkMissionTaskTriageState(taskID: task.id, state: .aborted)
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborted)
        XCTAssertEqual(run.operatorTriageMarkedMissionTaskStateByTaskID[task.id], .aborted)
    }

    func test_pure_continuous_between_cycles_derives_executing_not_between() {
        let task = MissionTask(name: "Loop", enabled: true, cycles: 0, regularity: .continuous)
        let run = environment(task: task)
        let mission = run.template!
        run.status = .running
        run.setSessionPhase(.executing)
        _ = run.recordSquadCycleCompletions(assignmentIDs: [run.assignments[0].id], mission: mission)
        XCTAssertFalse(run.activeCycleTaskIDs.contains(task.id))
        XCTAssertEqual(run.taskStateByTaskID[task.id], MissionTaskState.executing)
    }

    func test_single_squad_continuous_with_delay_off_cycle_derives_executing() {
        let task = MissionTask(
            name: "DelayLoop",
            enabled: true,
            cycles: 0,
            regularityDelayValue: 30,
            regularityDelayUnit: .secs,
            regularity: .continuousWithDelay
        )
        let run = environment(task: task)
        let mission = run.template!
        run.status = .running
        run.setSessionPhase(.executing)
        _ = run.recordSquadCycleCompletions(assignmentIDs: [run.assignments[0].id], mission: mission)
        XCTAssertEqual(run.taskStateByTaskID[task.id], MissionTaskState.executing)
    }
}
