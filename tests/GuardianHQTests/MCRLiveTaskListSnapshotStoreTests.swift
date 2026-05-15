import XCTest
@testable import GuardianHQ

@MainActor
final class MCRLiveTaskListSnapshotStoreTests: XCTestCase {
    func test_setPresentationsIfChanged_skipsNoOpPublish() {
        let coordinator = MCRLiveTaskListSnapshotCoordinator()
        XCTAssertTrue(coordinator.presentations.isEmpty)

        let snap = MCRLiveTaskListRowSnapshot(
            taskID: UUID(),
            taskIndex: 0,
            taskName: "Alpha",
            taskEnabled: true,
            taskState: .ready,
            slotAttention: nil,
            attemptingState: nil,
            cyclesLineText: nil,
            waypointsLineText: "Waypoints: —",
            showPerSquadBars: false,
            inlineTaskDeferralOnSquadRow: false,
            squadRows: [],
            showMissionProgressBar: true,
            missionProgressFraction: 0,
            triageCombinedBarFraction: 0,
            inTaskStartDeferral: false,
            liveTaskStartDeferral: nil,
            showStandaloneDeferralBlock: false,
            taskStartDeferralForStandaloneBlock: nil,
            footerKind: .none
        )
        let row = MCRLiveTaskListRowPresentation(taskID: snap.taskID, taskIndex: 0, snapshot: snap)

        coordinator.setPresentationsIfChanged([row])
        XCTAssertEqual(coordinator.presentations.count, 1)

        coordinator.setPresentationsIfChanged([row])
        XCTAssertEqual(coordinator.presentations.count, 1)
    }

    func test_apply_clearsPresentationsWhenMissionNil() {
        let task = MissionTask(name: "T", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let run = MissionRunEnvironment(mission: mission)
        let fleetLink = FleetLinkService()
        let sitl = SitlService()
        let coordinator = MCRLiveTaskListSnapshotCoordinator()
        coordinator.apply(run: run, mission: mission, fleetLink: fleetLink, sitl: sitl, now: Date())
        XCTAssertEqual(coordinator.presentations.count, 1)
        coordinator.apply(run: run, mission: nil, fleetLink: fleetLink, sitl: sitl, now: Date())
        XCTAssertTrue(coordinator.presentations.isEmpty)
    }

    func test_deriveLiveTaskProgressCore_disabledTask_missionFractionZero() {
        let task = MissionTask(name: "T", enabled: false)
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        run.status = .running
        let fleetLink = FleetLinkService()
        let sitl = SitlService()
        let now = Date()
        let core = MCRLiveTaskListProgressFormatting.deriveLiveTaskProgressCore(
            run: run,
            fleetLink: fleetLink,
            sitl: sitl,
            task: task,
            mission: mission,
            now: now
        )
        XCTAssertEqual(core.missionProgressFraction, 0, accuracy: 0.0001)
        XCTAssertFalse(core.inTaskStartDeferral)
        XCTAssertEqual(core.triageCombinedBarFraction, core.missionProgressFraction)
    }

    func test_makeTaskLiveProjection_reflectsTriageDeferredFirstWaveAndWindDown() {
        let deviceId = UUID()
        let task = MissionTask(name: "Alpha", rosterDeviceIds: [deviceId])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: deviceId, name: "Slot A")],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(taskId: task.id, rosterDeviceId: deviceId, slotName: "Slot A")
        let run = MissionRunEnvironment(mission: mission, assignments: [assignment])
        run.status = .running
        run.setSessionPhase(.executing)
        run.operatorMarkMissionTaskTriageState(taskID: task.id, state: .aborted)
        run.registerDeferredFirstWaveSquads(taskID: task.id, assignmentIDs: [assignment.id])
        run.systems.scheduling.abortMissionTaskAfterCycle(target: .task(task.id))

        let p = MCRLiveTaskListProgressFormatting.makeTaskLiveProjection(run: run, mission: mission, task: task, now: Date())
        XCTAssertEqual(p.taskID, task.id)
        XCTAssertEqual(p.operatorTriageMarkedState, .aborted)
        XCTAssertEqual(p.deferredFirstWaveSquadAssignmentIDs, [assignment.id])
        XCTAssertTrue(p.showDeferredFirstWaveRelease)
        XCTAssertEqual(p.pendingGracefulWindDownKind, .abortAfterCycle)
    }

    func test_makeTaskLiveProjection_embedsPrimarySquadSlicesInOrderWithDeferredFirstWaveFlags() {
        let d1 = UUID()
        let d2 = UUID()
        let task = MissionTask(name: "Layer", regularity: .continuous, rosterDeviceIds: [d1, d2])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: d1, name: "P1", slot: .primary),
                RosterDevice(id: d2, name: "P2", slot: .primary)
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: d1,
            slotName: "P1",
            attachedFleetVehicleToken: "v1"
        )
        let a2 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: d2,
            slotName: "P2",
            attachedFleetVehicleToken: "v2"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        run.registerDeferredFirstWaveSquads(taskID: task.id, assignmentIDs: [a1.id])
        let now = Date()
        let p = MCRLiveTaskListProgressFormatting.makeTaskLiveProjection(run: run, mission: mission, task: task, now: now)
        XCTAssertEqual(p.primarySquadSlices.count, 2)
        XCTAssertEqual(Set(p.primarySquadSlices.map(\.assignmentID)), Set([a1.id, a2.id]))
        let s1 = p.primarySquadSlices.first(where: { $0.assignmentID == a1.id })!
        let s2 = p.primarySquadSlices.first(where: { $0.assignmentID == a2.id })!
        XCTAssertTrue(s1.inDeferredFirstWaveQueue)
        XCTAssertFalse(s2.inDeferredFirstWaveQueue)
    }

    func test_makeRowSnapshot_inlineTaskDeferral_suppressesDeferralFooter() {
        let deviceId = UUID()
        let task = MissionTask(name: "Solo", rosterDeviceIds: [deviceId])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: deviceId, name: "P1", slot: .primary)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: deviceId,
            slotName: "P1",
            attachedFleetVehicleToken: "legacy:inline-deferral"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [assignment])
        run.status = .running
        let now = Date()
        let startAt = now.addingTimeInterval(120)
        run.mutateTaskStartDeferral(
            forTaskID: task.id,
            value: MissionTaskStartDeferral(startAt: startAt, totalDelay: 120)
        )
        let fleetLink = FleetLinkService()
        let sitl = SitlService()
        let snap = MCRLiveTaskListProgressFormatting.makeRowSnapshot(
            run: run,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            task: task,
            taskIndex: 0,
            now: now
        )
        XCTAssertTrue(snap.inlineTaskDeferralOnSquadRow)
        XCTAssertEqual(snap.footerKind, .none)
    }

    func test_squadProgressFraction_finite_cycles_blends_hub_while_in_cycle() {
        let deviceId = UUID()
        let task = MissionTask(
            name: "Lance",
            enabled: true,
            cycles: 1,
            regularity: .continuous,
            rosterDeviceIds: [deviceId]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: deviceId, name: "P1", slot: .primary)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(taskId: task.id, rosterDeviceId: deviceId, slotName: "P1")
        let run = MissionRunEnvironment(mission: mission, assignments: [assignment])
        run.markSquadActiveInCurrentCycle(assignment.id)
        var hub = FleetHubVehicleTelemetry.empty
        hub.missionProgressCurrent = 3
        hub.missionProgressTotal = 4
        let fracRun = MCRLiveTaskListProgressFormatting.squadProgressFraction(
            run: run,
            assignmentID: assignment.id,
            task: task,
            hub: hub
        )
        XCTAssertEqual(fracRun, 0.75, accuracy: 0.0001)

        let slice = MissionRunSquadLiveSlice(
            assignmentID: assignment.id,
            squadIndex: 0,
            rawSquadState: .executing,
            squadCyclesCompleted: 0,
            activeInSquadCycle: true,
            inDeferredFirstWaveQueue: false,
            activeStartDeferral: nil
        )
        let fracSlice = MCRLiveTaskListProgressFormatting.squadProgressFraction(slice: slice, task: task, hub: hub)
        XCTAssertEqual(fracSlice, 0.75, accuracy: 0.0001)
    }

    func test_squadProgressFraction_finite_cycles_between_cycles_no_hub_uses_completed_cycles_only() {
        let deviceId = UUID()
        let task = MissionTask(
            name: "Lance",
            enabled: true,
            cycles: 2,
            regularity: .continuous,
            rosterDeviceIds: [deviceId]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: deviceId, name: "P1", slot: .primary)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(taskId: task.id, rosterDeviceId: deviceId, slotName: "P1")
        let run = MissionRunEnvironment(mission: mission, assignments: [assignment])
        run.markSquadActiveInCurrentCycle(assignment.id)
        _ = run.recordSquadCycleCompletions(assignmentIDs: [assignment.id], mission: mission)
        run.removeSquadFromActiveCycle(assignment.id)
        var hub = FleetHubVehicleTelemetry.empty
        hub.missionProgressCurrent = 1
        hub.missionProgressTotal = 2
        let frac = MCRLiveTaskListProgressFormatting.squadProgressFraction(
            run: run,
            assignmentID: assignment.id,
            task: task,
            hub: hub
        )
        XCTAssertEqual(frac, 0.5, accuracy: 0.0001)
    }
}
