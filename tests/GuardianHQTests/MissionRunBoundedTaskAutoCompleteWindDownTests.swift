import XCTest

@testable import GuardianCore

/// Finite repeating tasks used to rely on operator ``completeMissionTaskAfterCycle`` to seed pending graceful
/// delivery; without it, ``planNextAutoCycleStartsForSquads`` could keep issuing MAVLink missions after the
/// aggregated cycle cap while recovery UI derived from cycle counts alone.
@MainActor
final class MissionRunBoundedTaskAutoCompleteWindDownTests: XCTestCase {

    func test_finite_continuous_task_auto_issues_complete_wind_down_after_final_cycle() {
        let sitl = UUID()
        let rd = RosterDevice(name: "P1", slot: .primary, vehicleClass: .uavCopter)
        let wp = RouteWaypoint()
        let task = MissionTask(
            name: "Loop",
            waypoints: [wp],
            cycles: 2,
            regularity: .continuous,
            rosterDeviceIds: [rd.id]
        )
        let mission = Mission(
            id: UUID(),
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
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitl).storageKey
        )
        let fleet = FleetLinkService()
        let sitlSvc = SitlService()
        sitlSvc.attachFleetLink(fleet)
        sitlSvc.seedMissionRunTestSitlRunningInstance(id: sitl, stackInstanceIndex: 0)
        guard let vid = resolvedFleetStreamVehicleID(assignment: assign, fleetLink: fleet, sitl: sitlSvc) else {
            XCTFail("Expected stream id")
            return
        }
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = -37.0
        hub.longitudeDeg = 145.0
        fleet.seedMissionRunTestSitlCleanupStream(vehicleID: vid, systemID: 1, hub: hub)

        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        run.attachServices(fleetLink: fleet, sitl: sitlSvc)
        run.status = .running
        run.setSessionPhase(.executing)
        run.markTaskActiveInCurrentCycle(task.id)
        let squads = run.systems.planner.buildTaskSquadMissions(mission: mission, taskId: task.id)
        XCTAssertEqual(squads.count, 1)
        run.markSquadActiveInCurrentCycle(squads[0].squad.primaryAssignment.id)

        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleet,
            sitl: sitlSvc,
            missionProvider: { mission }
        )

        XCTAssertFalse(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id))
        let afterFirst = run.systems.executor.handleEvent(.missionCycleFinished(vehicleID: vid), context: ctx)
        XCTAssertEqual(afterFirst, .progressed)
        XCTAssertEqual(run.taskCyclesCompletedByTaskID[task.id], 1)
        XCTAssertFalse(run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id))
        XCTAssertFalse(
            run.events.contains { $0.templateKey == MissionRunLogTemplateKey.missionTaskCompleteGracefulDispatched },
            "complete-policy wind-down should not fire before the final aggregated cycle"
        )

        run.markSquadActiveInCurrentCycle(squads[0].squad.primaryAssignment.id)
        let afterSecond = run.systems.executor.handleEvent(.missionCycleFinished(vehicleID: vid), context: ctx)
        XCTAssertEqual(afterSecond, .completed(.oneOffAutopilotFinished))
        XCTAssertEqual(run.status, .recovery)
        XCTAssertEqual(run.sessionPhase, .recovery)
        XCTAssertEqual(run.completionKind, .oneOffAutopilotFinished)
        XCTAssertTrue(
            run.events.contains { $0.templateKey == MissionRunLogTemplateKey.missionTaskCompleteGracefulDispatched },
            "expected auto-seeded complete-after-cycle delivery (complete-policy) once aggregated cycles hit the cap"
        )
    }
}
