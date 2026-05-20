import XCTest

@testable import GuardianCore

/// Autopilot “mission finished” was previously gated on **all** active tasks; these tests pin per-task completion.
@MainActor
final class MissionRunPerTaskMissionCycleGateTests: XCTestCase {

    func test_missionCycleFinished_oneVehicleOnlyCompletesItsTask() {
        let sitlA = UUID()
        let sitlB = UUID()
        let rdA = RosterDevice(name: "Alpha", slot: .primary, vehicleClass: .uavCopter)
        let rdB = RosterDevice(name: "Bravo", slot: .primary, vehicleClass: .uavCopter)
        let wpA = RouteWaypoint()
        let wpB = RouteWaypoint()
        let taskA = MissionTask(
            name: "LoopA",
            waypoints: [wpA],
            cycles: 1,
            regularity: .continuous,
            rosterDeviceIds: [rdA.id]
        )
        let taskB = MissionTask(
            name: "LoopB",
            waypoints: [wpB],
            cycles: 1,
            regularity: .continuousWithDelay,
            rosterDeviceIds: [rdB.id]
        )
        let mission = Mission(
            id: UUID(),
            name: "Dual",
            description: "",
            type: .mobile,
            rosterDevices: [rdA, rdB],
            routeMacro: RouteMacro(tasks: [taskA, taskB])
        )
        let assignA = MissionRunAssignment(
            taskId: taskA.id,
            rosterDeviceId: rdA.id,
            slotName: rdA.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlA).storageKey
        )
        let assignB = MissionRunAssignment(
            taskId: taskB.id,
            rosterDeviceId: rdB.id,
            slotName: rdB.name,
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(sitlB).storageKey
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
        run.markTaskActiveInCurrentCycle(taskA.id)
        run.markTaskActiveInCurrentCycle(taskB.id)

        let squadsA = run.systems.planner.buildTaskSquadMissions(mission: mission, taskId: taskA.id)
        let squadsB = run.systems.planner.buildTaskSquadMissions(mission: mission, taskId: taskB.id)
        XCTAssertEqual(squadsA.count, 1, "precondition: single primary squad for task A")
        XCTAssertEqual(squadsB.count, 1, "precondition: single primary squad for task B")
        guard let vidA = resolvedFleetStreamVehicleID(
            assignment: squadsA[0].squad.primaryAssignment,
            fleetLink: fleet,
            sitl: sitl
        ),
            let vidB = resolvedFleetStreamVehicleID(
                assignment: squadsB[0].squad.primaryAssignment,
                fleetLink: fleet,
                sitl: sitl
            )
        else {
            XCTFail("Expected resolved stream ids for seeded SITL rows")
            return
        }

        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            missionProvider: { mission }
        )

        let d1 = run.systems.executor.handleEvent(.missionCycleFinished(vehicleID: vidA), context: ctx)
        XCTAssertEqual(d1, .progressed)
        XCTAssertEqual(run.taskCyclesCompletedByTaskID[taskA.id], 1)
        XCTAssertNil(run.taskCyclesCompletedByTaskID[taskB.id])
        XCTAssertTrue(run.activeCycleTaskIDs.contains(taskB.id))
        XCTAssertFalse(run.activeCycleTaskIDs.contains(taskA.id))
        XCTAssertEqual(run.status, .running)

        let d2 = run.systems.executor.handleEvent(.missionCycleFinished(vehicleID: vidB), context: ctx)
        XCTAssertEqual(d2, .completed(.oneOffAutopilotFinished))
        XCTAssertEqual(run.taskCyclesCompletedByTaskID[taskB.id], 1)
        XCTAssertTrue(run.activeCycleTaskIDs.isEmpty)
    }
}
