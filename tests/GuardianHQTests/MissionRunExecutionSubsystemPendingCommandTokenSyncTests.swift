import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunExecutionSubsystemPendingCommandTokenSyncTests: XCTestCase {

    func test_synchronizePendingCommandBatches_updates_vehicle_token_when_assignment_binding_changes() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        var roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "A",
            attachedFleetVehicleToken: "tokenBefore"
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.captureExecutionContext(
            MissionRunExecutionContext(
                mission: mission,
                fleetLink: fleet,
                sitl: sitl,
                missionProvider: { mission }
            )
        )
        let cmd = MissionRunIssuedCommand(
            assignmentID: assignID,
            slotName: "Primary",
            vehicleTokenKey: "tokenBefore",
            command: .arm,
            issuer: .missionControl,
            issuerKey: "test"
        )
        let batch = MissionRunQueuedCommandBatch(
            tag: .missionStart,
            dispatch: .afterMissionCycle,
            commands: [cmd]
        )
        run.systems.executor.enqueueCommandBatch(
            batch,
            context: MissionRunExecutionContext(
                mission: mission,
                fleetLink: fleet,
                sitl: sitl,
                missionProvider: { mission }
            ),
            replacingTags: []
        )
        XCTAssertEqual(run.systems.executor.pendingCommandBatchesSnapshot.count, 1)
        XCTAssertEqual(run.systems.executor.pendingCommandBatchesSnapshot[0].commands[0].vehicleTokenKey, "tokenBefore")

        roster.attachedFleetVehicleToken = "tokenAfter"
        roster.attachedDevice = "B"
        run.assignments = [roster]

        run.systems.executor.synchronizePendingCommandBatchesWithAssignmentFleetTokens()

        XCTAssertEqual(run.systems.executor.pendingCommandBatchesSnapshot[0].commands[0].vehicleTokenKey, "tokenAfter")
        XCTAssertEqual(run.systems.executor.pendingCommandBatchesSnapshot[0].commands[0].id, cmd.id)
    }
}
