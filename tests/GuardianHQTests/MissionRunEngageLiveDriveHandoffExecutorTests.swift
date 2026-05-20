import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunEngageLiveDriveHandoffExecutorTests: XCTestCase {

    func test_cancelPendingExecutorBatchesForOperatorLiveDriveEngage_clears_all_tagged_pending_batches_and_logs() {
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
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "A",
            attachedFleetVehicleToken: "legacy:1"
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            missionProvider: { mission }
        )
        run.captureExecutionContext(ctx)

        let cmd = MissionRunIssuedCommand(
            assignmentID: assignID,
            slotName: "Primary",
            vehicleTokenKey: "legacy:1",
            command: .arm,
            issuer: .missionControl,
            issuerKey: "test"
        )
        run.systems.executor.enqueueCommandBatch(
            MissionRunQueuedCommandBatch(tag: .missionStart, dispatch: .afterMissionCycle, commands: [cmd]),
            context: ctx,
            replacingTags: []
        )
        run.systems.executor.enqueueCommandBatch(
            MissionRunQueuedCommandBatch(tag: .abort, dispatch: .at(Date().addingTimeInterval(3600)), commands: [cmd]),
            context: ctx,
            replacingTags: []
        )
        XCTAssertEqual(run.systems.executor.pendingCommandBatchesSnapshot.count, 2)

        let beforeEventCount = run.events.count
        let removed = run.cancelPendingExecutorBatchesForOperatorLiveDriveEngage(assignment: roster)
        XCTAssertEqual(removed, 2)
        XCTAssertTrue(run.systems.executor.pendingCommandBatchesSnapshot.isEmpty)
        XCTAssertEqual(run.events.count, beforeEventCount + 1)
        XCTAssertEqual(
            run.events.last?.templateKey,
            MissionRunLogTemplateKey.executorPendingBatchesCancelledForLiveDriveEngage
        )
    }

    func test_cancelPendingExecutorBatchesForOperatorLiveDriveEngage_no_log_when_queue_empty() {
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
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "A",
            attachedFleetVehicleToken: "legacy:1"
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
        let before = run.events.count
        let removed = run.cancelPendingExecutorBatchesForOperatorLiveDriveEngage(assignment: roster)
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(run.events.count, before)
    }

    func test_executor_pending_batches_cancelled_log_template_registered_in_catalog() {
        let key = MissionRunLogTemplateKey.executorPendingBatchesCancelledForLiveDriveEngage
        XCTAssertNotNil(
            StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport),
            "Missing plainExport catalog entry for \(key)"
        )
        XCTAssertNotNil(
            StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom),
            "Missing MCR catalog entry for \(key)"
        )
    }
}
