import XCTest
@testable import GuardianHQ

final class MissionRunSlotEvidenceAutoMissionEndAckTests: XCTestCase {

    func test_rules_empty_rows_not_satisfied() {
        XCTAssertFalse(MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded([]))
    }

    func test_rules_all_policy_succeeded() {
        let a1 = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "A",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        )
        let a2 = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "B",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .executingMission)
        )
        XCTAssertTrue(MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded([a1, a2]))
    }

    func test_rules_merged_display_must_be_policy_succeeded() {
        let idle = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "A",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .idle, observed: .idle)
        )
        XCTAssertFalse(MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded([idle]))
    }

    @MainActor
    func test_auto_abort_ack_when_all_slots_succeeded_and_abort_issued() {
        let task = MissionTask(name: "Delta", enabled: true)
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
        run.noteMissionTaskEndAttempt(.abortMissionEnd, forTaskID: task.id)
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        XCTAssertEqual(run.taskAttemptingByTaskID[task.id], .abortMissionEnd)
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))

        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([row.id]))
        XCTAssertTrue(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))
        XCTAssertFalse(run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id))
        XCTAssertNil(run.taskAttemptingByTaskID[task.id])
        XCTAssertEqual(run.taskStateByTaskID[task.id], .aborted)
        XCTAssertNil(run.operatorTriageMarkedMissionTaskStateByTaskID[task.id])
        let batch = run.events.filter { $0.templateKey == MissionRunLogTemplateKey.slotEvidenceAutoAcknowledgedMissionEndBatch }
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.templateParams["abortTasks"], "Delta")
        XCTAssertEqual(batch.first?.templateParams["recoveryTasks"], "—")
    }

    @MainActor
    func test_auto_recovery_ack_when_complete_wind_down_issued() {
        let task = MissionTask(name: "Echo", enabled: true)
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
        run.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: task.id)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: task.id)
        XCTAssertEqual(run.taskAttemptingByTaskID[task.id], .recoveryMissionEnd)
        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([row.id]))
        XCTAssertTrue(run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id))
        XCTAssertFalse(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id))
        XCTAssertNil(run.taskAttemptingByTaskID[task.id])
        XCTAssertEqual(run.taskStateByTaskID[task.id], .completed)
        let batch = run.events.filter { $0.templateKey == MissionRunLogTemplateKey.slotEvidenceAutoAcknowledgedMissionEndBatch }
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.templateParams["abortTasks"], "—")
        XCTAssertEqual(batch.first?.templateParams["recoveryTasks"], "Echo")
    }

    @MainActor
    func test_auto_abort_skips_when_one_slot_not_succeeded() {
        let task = MissionTask(name: "Foxtrot", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let ok = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        )
        let bad = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W2",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .executingMission, observed: .executingMission)
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [ok, bad])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([ok.id]))
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))
    }

    @MainActor
    func test_auto_ack_skips_disabled_task_even_when_slots_succeeded() {
        let task = MissionTask(name: "OffPath", enabled: false)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([row.id]))
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))
    }

    @MainActor
    func test_auto_abort_consolidated_one_log_line_for_two_tasks_same_apply_call() {
        let tid1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let tid2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let t1 = MissionTask(id: tid1, name: "Alpha", enabled: true)
        let t2 = MissionTask(id: tid2, name: "Beta", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [t2, t1]))
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        let row1 = MissionRunAssignment(
            id: UUID(),
            taskId: tid1,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: lanes
        )
        let row2 = MissionRunAssignment(
            id: UUID(),
            taskId: tid2,
            rosterDeviceId: UUID(),
            slotName: "W2",
            slotLifecycleLanes: lanes
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row1, row2])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: tid1)
        run.markMissionTaskAbortWindDownIssued(forTaskID: tid2)
        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([row1.id, row2.id]))
        let batchKeys = run.events.map(\.templateKey).filter { $0 == MissionRunLogTemplateKey.slotEvidenceAutoAcknowledgedMissionEndBatch }
        XCTAssertEqual(batchKeys.count, 1)
        let p = run.events.first { $0.templateKey == MissionRunLogTemplateKey.slotEvidenceAutoAcknowledgedMissionEndBatch }?.templateParams
        XCTAssertEqual(p?["abortTasks"], "Alpha, Beta")
        XCTAssertEqual(p?["recoveryTasks"], "—")
    }

    @MainActor
    func test_auto_abort_idempotent_when_already_acked() {
        let task = MissionTask(name: "Hotel", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([row.id]))
        let c1 = run.events.count
        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([row.id]))
        XCTAssertEqual(run.events.count, c1)
    }

    func test_partial_fleet_predicate_empty_rows_not_blocking() {
        XCTAssertFalse(MissionRunSlotEvidenceAutoMissionEndAckRules.partialFleetBindingOrPolicyFailureBlocksAutoMissionEndAck([]))
    }

    func test_partial_fleet_predicate_detects_blocked_vehicle_among_successes() {
        let ok = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "A",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        )
        let blocked = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "B",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .blockedNoVehicle, observed: .idle)
        )
        XCTAssertTrue(MissionRunSlotEvidenceAutoMissionEndAckRules.partialFleetBindingOrPolicyFailureBlocksAutoMissionEndAck([ok, blocked]))
        XCTAssertFalse(MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded([ok, blocked]))
    }

    func test_partial_fleet_predicate_detects_policy_failed_among_successes() {
        let ok = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "A",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        )
        let failed = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "C",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policyFailed, observed: .policyFailed)
        )
        XCTAssertTrue(MissionRunSlotEvidenceAutoMissionEndAckRules.partialFleetBindingOrPolicyFailureBlocksAutoMissionEndAck([ok, failed]))
        XCTAssertFalse(MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded([ok, failed]))
    }

    @MainActor
    func test_auto_abort_skips_when_partial_fleet_one_blocked_no_vehicle() {
        let task = MissionTask(name: "India", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let ok1 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        )
        let ok2 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W2",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        )
        let blocked = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W3",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .blockedNoVehicle, observed: .idle)
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [ok1, ok2, blocked])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: task.id)
        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([ok1.id]))
        XCTAssertTrue(MissionRunSlotEvidenceAutoMissionEndAckRules.partialFleetBindingOrPolicyFailureBlocksAutoMissionEndAck(run.assignmentsBoundToMissionTask(taskID: task.id)))
        XCTAssertFalse(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))
        XCTAssertTrue(run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id))
    }

    func test_complete_mission_end_auto_ack_predicate_allows_mixed_success_and_failure() {
        let ok = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "A",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        )
        let failed = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "B",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policyFailed, observed: .policyFailed)
        )
        XCTAssertTrue(MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsSatisfiedForCompleteMissionEndAutoAck([ok, failed]))
        XCTAssertFalse(MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded([ok, failed]))
    }

    @MainActor
    func test_auto_recovery_ack_complete_intent_when_one_row_policy_failed() {
        let task = MissionTask(name: "Juliet", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let ok = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        )
        let failed = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "W2",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policyFailed, observed: .policyFailed)
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [ok, failed])
        run.status = .running
        run.setSessionPhase(.executing)
        run.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: task.id)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: task.id)
        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([ok.id]))
        XCTAssertTrue(run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id))
        XCTAssertEqual(run.taskStateByTaskID[task.id], .completed)
    }

    @MainActor
    func test_hub_pull_conformance_runs_while_run_status_recovery() {
        let sitlId = UUID()
        let rd = RosterDevice(name: "Alpha", slot: .primary, vehicleClass: .uavCopter)
        let task = MissionTask(name: "T", rosterDeviceIds: [rd.id])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assign = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd.id,
            slotName: rd.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlId).storageKey,
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policyCompleting, observed: .policyCompleting)
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlId, stackInstanceIndex: 0)
        guard let vid = resolvedFleetStreamVehicleID(assignment: assign, fleetLink: fleet, sitl: sitl) else {
            XCTFail("Expected resolved stream id for seeded SITL row")
            return
        }
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = Date()
        hub.isArmed = false
        hub.inAir = false
        hub.velocityNorthMS = 0
        hub.velocityEastMS = 0
        fleet.seedMissionRunTestSitlCleanupStream(vehicleID: vid, systemID: 1, hub: hub)

        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.status = .recovery
        run.setSessionPhase(.recovery)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: task.id)

        run.applySlotPolicyPullConformanceFromHubIfNeeded()

        let merged = MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: run.assignments[0].effectiveSlotLifecycleLanes)
        XCTAssertEqual(merged, .policySucceeded)
    }

    @MainActor
    func test_squad_scoped_complete_auto_ack_updates_squad_without_task_wide_issued() {
        let rd = RosterDevice(name: "W1", slot: .primary, vehicleClass: .uavCopter)
        let task = MissionTask(name: "SquadRetry", enabled: true, rosterDeviceIds: [rd.id])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [task])
        )
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        let row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd.id,
            slotName: rd.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(UUID()).storageKey,
            slotLifecycleLanes: lanes
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markSquadCompletePolicyWindDownDispatchIssued(forAssignmentID: row.id)
        XCTAssertFalse(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id))

        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([row.id]))

        XCTAssertTrue(run.squadMissionEndRecoveryCompletedByAssignmentIDs.contains(row.id))
        XCTAssertFalse(run.squadCompletePolicyWindDownIssuedAssignmentIDs.contains(row.id))
        XCTAssertTrue(run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id))
        run.refreshDerivedSquadStates()
        XCTAssertEqual(run.squadStateByAssignmentID[row.id], .completed)
    }

    @MainActor
    func test_squad_scoped_abort_auto_ack_without_task_wide_issued() {
        let rd = RosterDevice(name: "W1", slot: .primary, vehicleClass: .uavCopter)
        let task = MissionTask(name: "SquadAbort", enabled: true, rosterDeviceIds: [rd.id])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [task])
        )
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        let row = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd.id,
            slotName: rd.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(UUID()).storageKey,
            slotLifecycleLanes: lanes
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markSquadAbortPolicyWindDownDispatchIssued(forAssignmentID: row.id)
        XCTAssertFalse(run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id))

        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([row.id]))

        XCTAssertTrue(run.squadMissionEndAbortCompletedByAssignmentIDs.contains(row.id))
        XCTAssertFalse(run.squadAbortPolicyWindDownIssuedAssignmentIDs.contains(row.id))
        XCTAssertTrue(run.taskMissionEndAbortCompletedByTaskID.contains(task.id))
        run.refreshDerivedSquadStates()
        XCTAssertEqual(run.squadStateByAssignmentID[row.id], .aborted)
    }
}
