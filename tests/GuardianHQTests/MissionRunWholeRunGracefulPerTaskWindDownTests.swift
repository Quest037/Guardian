import XCTest

@testable import GuardianHQ

/// Whole-run “complete after cycle” arms one pending row per task; idle tasks (not in ``activeCycleTaskIDs``) should
/// begin recovery wind-down immediately instead of waiting for other tasks’ autopilot cycles.
@MainActor
final class MissionRunWholeRunGracefulPerTaskWindDownTests: XCTestCase {

    func test_completeAfterCycle_delivers_idle_task_immediately() {
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
        run.markTaskActiveInCurrentCycle(taskA.id)

        run.systems.scheduling.completeAfterCycle()

        XCTAssertEqual(run.gracefulStopKind, .completeAfterCycle)
        XCTAssertEqual(run.pendingMissionTaskGracefulWindDownKindByTaskID[taskA.id], .completeAfterCycle)
        XCTAssertNil(run.pendingMissionTaskGracefulWindDownKindByTaskID[taskB.id])
        XCTAssertTrue(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskB.id))
        XCTAssertFalse(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskA.id))
    }

    func test_completeMissionTaskAfterCycle_cancels_between_cycle_deferral_and_dispatches_immediately() {
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
        let future = Date().addingTimeInterval(600)
        run.mutateTaskStartDeferral(
            forTaskID: task.id,
            value: MissionTaskStartDeferral(startAt: future, totalDelay: 600)
        )
        run.systems.scheduling.completeMissionTaskAfterCycle(target: .task(task.id))
        XCTAssertNil(run.taskStartDeferralByTaskID[task.id])
        XCTAssertNil(run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id])
        XCTAssertTrue(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id))
    }

    /// Per-task graceful complete must not call whole-run finalize when another path is idle (no in-flight cycle):
    /// suppression was previously keyed off any issued/pending task wind-down, not ``gracefulStopKind``.
    func test_perTaskGracefulComplete_unboundedMission_otherTaskIdle_doesNotEnterWholeRunRecovery() {
        let rdA = RosterDevice(name: "Alpha", slot: .primary, vehicleClass: .uavCopter)
        let rdB = RosterDevice(name: "Bravo", slot: .primary, vehicleClass: .uavCopter)
        var rules = RouteRules()
        rules.missionCompletePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]
        let wpA = RouteWaypoint()
        let wpB = RouteWaypoint()
        let taskA = MissionTask(
            name: "LoopA",
            waypoints: [wpA],
            cycles: 0,
            regularity: .continuous,
            rosterDeviceIds: [rdA.id]
        )
        let taskB = MissionTask(
            name: "LoopB",
            waypoints: [wpB],
            cycles: 0,
            regularity: .continuous,
            rosterDeviceIds: [rdB.id]
        )
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
        run.markTaskActiveInCurrentCycle(taskA.id)
        XCTAssertTrue(run.systems.scheduling.completeMissionTaskAfterCycle(target: .task(taskA.id)))

        let squadsA = run.systems.planner.buildTaskSquadMissions(mission: mission, taskId: taskA.id)
        guard let vidA = resolvedFleetStreamVehicleID(
            assignment: squadsA[0].squad.primaryAssignment,
            fleetLink: fleet,
            sitl: sitl
        ) else {
            XCTFail("Expected resolved stream id for task A")
            return
        }

        let decision = run.systems.executor.handleEvent(.missionCycleFinished(vehicleID: vidA), context: ctx)

        XCTAssertEqual(decision, .progressed)
        XCTAssertEqual(run.gracefulStopKind, .none)
        XCTAssertEqual(run.status, .running)
        XCTAssertEqual(run.sessionPhase, .executing)
        XCTAssertTrue(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskA.id))
        XCTAssertFalse(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskB.id))
    }
}
