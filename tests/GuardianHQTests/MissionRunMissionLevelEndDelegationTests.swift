import XCTest

@testable import GuardianCore

/// Mission-level complete / abort entry points delegate to per-task scheduling APIs with task-state priority rules.
@MainActor
final class MissionRunMissionLevelEndDelegationTests: XCTestCase {

    func test_missionCompleteAfterCycle_skips_recovery_task_arms_other() {
        let rdA = RosterDevice(name: "Alpha", slot: .primary, vehicleClass: .uavCopter)
        let rdB = RosterDevice(name: "Bravo", slot: .primary, vehicleClass: .uavCopter)
        var rules = RouteRules()
        rules.missionCompletePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        let taskA = MissionTask(name: "LoopA", rosterDeviceIds: [rdA.id])
        let taskB = MissionTask(name: "LoopB", rosterDeviceIds: [rdB.id])
        let mission = Mission(
            id: UUID(),
            name: "Dual",
            description: "",
            type: .mobile,
            rosterDevices: [rdA, rdB],
            routeMacro: RouteMacro(tasks: [taskA, taskB], rules: rules)
        )
        var polA = MissionRunAssignmentPolicies()
        polA.completePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        var polB = MissionRunAssignmentPolicies()
        polB.completePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        let sitlA = UUID()
        let sitlB = UUID()
        let assignA = MissionRunAssignment(
            taskId: taskA.id,
            rosterDeviceId: rdA.id,
            slotName: rdA.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlA).storageKey,
            policies: polA
        )
        let assignB = MissionRunAssignment(
            taskId: taskB.id,
            rosterDeviceId: rdB.id,
            slotName: rdB.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlB).storageKey,
            policies: polB
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlA, stackInstanceIndex: 0)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlB, stackInstanceIndex: 1)
        let run = MissionRunEnvironment(mission: mission, assignments: [assignA, assignB])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.status = .running
        run.setSessionPhase(.executing)
        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            missionProvider: { mission }
        )
        run.captureExecutionContext(ctx)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: taskA.id)
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.taskStateByTaskID[taskA.id], .recovery)

        run.systems.scheduling.completeAfterCycle()

        XCTAssertEqual(run.gracefulStopKind, .completeAfterCycle)
        XCTAssertNil(run.pendingMissionTaskGracefulWindDownKindByTaskID[taskA.id])
        XCTAssertTrue(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskB.id))
    }

    func test_missionCompleteAfterCycle_all_tasks_recovery_enters_run_recovery_without_graceful_kind() {
        let rdA = RosterDevice(name: "Alpha", slot: .primary, vehicleClass: .uavCopter)
        let rdB = RosterDevice(name: "Bravo", slot: .primary, vehicleClass: .uavCopter)
        var rules = RouteRules()
        rules.missionCompletePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        let taskA = MissionTask(name: "A", rosterDeviceIds: [rdA.id])
        let taskB = MissionTask(name: "B", rosterDeviceIds: [rdB.id])
        let mission = Mission(
            id: UUID(),
            name: "Dual",
            description: "",
            type: .mobile,
            rosterDevices: [rdA, rdB],
            routeMacro: RouteMacro(tasks: [taskA, taskB], rules: rules)
        )
        var pol = MissionRunAssignmentPolicies()
        pol.completePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        let sitlA = UUID()
        let sitlB = UUID()
        let assignA = MissionRunAssignment(
            taskId: taskA.id,
            rosterDeviceId: rdA.id,
            slotName: rdA.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlA).storageKey,
            policies: pol
        )
        let assignB = MissionRunAssignment(
            taskId: taskB.id,
            rosterDeviceId: rdB.id,
            slotName: rdB.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlB).storageKey,
            policies: pol
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlA, stackInstanceIndex: 0)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlB, stackInstanceIndex: 1)
        let run = MissionRunEnvironment(mission: mission, assignments: [assignA, assignB])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.status = .running
        run.setSessionPhase(.executing)
        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            missionProvider: { mission }
        )
        run.captureExecutionContext(ctx)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: taskA.id)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: taskB.id)
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.taskStateByTaskID[taskA.id], .recovery)
        XCTAssertEqual(run.taskStateByTaskID[taskB.id], .recovery)

        run.systems.scheduling.completeAfterCycle()

        XCTAssertEqual(run.gracefulStopKind, .none)
        XCTAssertEqual(run.status, .recovery)
        XCTAssertEqual(run.sessionPhase, .recovery)
        XCTAssertEqual(run.completionKind, .operatorCompletedAfterCycle)
    }

    func test_missionCompleteNow_all_tasks_completed_enters_run_recovery_without_redispatch() {
        let rd = RosterDevice(name: "Solo", slot: .primary, vehicleClass: .uavCopter)
        var rules = RouteRules()
        rules.missionCompletePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        let task = MissionTask(name: "T", rosterDeviceIds: [rd.id])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [task], rules: rules)
        )
        var pol = MissionRunAssignmentPolicies()
        pol.completePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        let sitlId = UUID()
        let assign = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd.id,
            slotName: rd.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlId).storageKey,
            policies: pol
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlId, stackInstanceIndex: 0)
        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.status = .running
        run.setSessionPhase(.executing)
        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            missionProvider: { mission }
        )
        run.captureExecutionContext(ctx)
        run.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: task.id)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: task.id)
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
        var settled = assign
        settled.slotLifecycleLanes = lanes
        run.assignments = [settled]
        run.applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: Set([settled.id]))
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.taskStateByTaskID[task.id], .completed)

        run.systems.scheduling.completeNow()

        XCTAssertEqual(run.status, .recovery)
        XCTAssertEqual(run.sessionPhase, .recovery)
        XCTAssertEqual(run.completionKind, .operatorCompletedImmediate)
        XCTAssertFalse(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id))
    }

    func test_missionAbortAfterCycle_recovery_task_dispatches_abort_now() {
        let rd = RosterDevice(name: "Solo", slot: .primary, vehicleClass: .uavCopter)
        var rules = RouteRules()
        rules.missionAbortPreferenceChain = [MissionRunAbortTactic(kind: .returnToLaunch)]
        let task = MissionTask(name: "T", rosterDeviceIds: [rd.id])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [task], rules: rules)
        )
        var pol = MissionRunAssignmentPolicies()
        pol.abortPreferenceChain = [MissionRunAbortTactic(kind: .returnToLaunch)]
        let sitlId = UUID()
        let assign = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd.id,
            slotName: rd.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlId).storageKey,
            policies: pol
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlId, stackInstanceIndex: 0)
        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.status = .running
        run.setSessionPhase(.executing)
        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            missionProvider: { mission }
        )
        run.captureExecutionContext(ctx)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: task.id)
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.taskStateByTaskID[task.id], .recovery)

        run.systems.scheduling.abortAfterCycle()

        XCTAssertEqual(run.gracefulStopKind, .abortAfterCycle)
        XCTAssertEqual(run.taskAttemptingByTaskID[task.id], .abortMissionEnd)
    }

    func test_missionAbortNow_skips_operator_triaged_completed_task() {
        let rd = RosterDevice(name: "Solo", slot: .primary, vehicleClass: .uavCopter)
        var rules = RouteRules()
        rules.missionAbortPreferenceChain = [MissionRunAbortTactic(kind: .returnToLaunch)]
        let task = MissionTask(name: "T", rosterDeviceIds: [rd.id])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [task], rules: rules)
        )
        var pol = MissionRunAssignmentPolicies()
        pol.abortPreferenceChain = [MissionRunAbortTactic(kind: .returnToLaunch)]
        let sitlId = UUID()
        let assign = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: rd.id,
            slotName: rd.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlId).storageKey,
            policies: pol
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlId, stackInstanceIndex: 0)
        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.status = .running
        run.setSessionPhase(.executing)
        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            missionProvider: { mission }
        )
        run.captureExecutionContext(ctx)
        run.operatorMarkMissionTaskTriageState(taskID: task.id, state: .completed)
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.taskStateByTaskID[task.id], .completed)

        run.systems.scheduling.abortNow()

        XCTAssertEqual(run.sessionPhase, .executing)
        XCTAssertNil(run.completionKind)
        XCTAssertFalse(run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id))
    }

    func test_missionCompleteNow_sets_run_recovery_when_one_path_engaged() {
        let rdA = RosterDevice(name: "Alpha", slot: .primary, vehicleClass: .uavCopter)
        let rdB = RosterDevice(name: "Bravo", slot: .primary, vehicleClass: .uavCopter)
        var rules = RouteRules()
        rules.missionCompletePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        let taskA = MissionTask(name: "A", rosterDeviceIds: [rdA.id])
        let taskB = MissionTask(name: "B", rosterDeviceIds: [rdB.id])
        let mission = Mission(
            id: UUID(),
            name: "Dual",
            description: "",
            type: .mobile,
            rosterDevices: [rdA, rdB],
            routeMacro: RouteMacro(tasks: [taskA, taskB], rules: rules)
        )
        var pol = MissionRunAssignmentPolicies()
        pol.completePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        let sitlA = UUID()
        let sitlB = UUID()
        let assignA = MissionRunAssignment(
            taskId: taskA.id,
            rosterDeviceId: rdA.id,
            slotName: rdA.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlA).storageKey,
            policies: pol
        )
        let assignB = MissionRunAssignment(
            taskId: taskB.id,
            rosterDeviceId: rdB.id,
            slotName: rdB.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlB).storageKey,
            policies: pol
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlA, stackInstanceIndex: 0)
        sitl.seedMissionRunTestSitlRunningInstance(id: sitlB, stackInstanceIndex: 1)
        let run = MissionRunEnvironment(mission: mission, assignments: [assignA, assignB])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.status = .running
        run.setSessionPhase(.executing)
        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            missionProvider: { mission }
        )
        run.captureExecutionContext(ctx)
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskA.id)
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.taskStateByTaskID[taskA.id], .aborting)

        run.systems.scheduling.completeNow()

        XCTAssertEqual(run.status, .recovery)
        XCTAssertEqual(run.sessionPhase, .recovery)
        XCTAssertEqual(run.completionKind, .operatorCompletedImmediate)
        XCTAssertTrue(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskB.id))
        XCTAssertFalse(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskA.id))
    }
}
