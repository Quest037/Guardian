import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunRunCompletionExecutorCancellationTests: XCTestCase {

    func test_cancelPendingCommandBatchesAndFleetHintsAfterRunCompleted_clears_all_tags_and_logs() {
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

        fleet.setLiveDriveControlSessionVehicle("legacy:1")

        let before = run.events.count
        run.cancelPendingCommandBatchesAndFleetHintsAfterRunCompleted()
        XCTAssertTrue(run.systems.executor.pendingCommandBatchesSnapshot.isEmpty)
        XCTAssertEqual(run.events.count, before + 1)
        XCTAssertEqual(
            run.events.last?.templateKey,
            MissionRunLogTemplateKey.executorPendingBatchesCancelledForRunCompleted
        )
    }

    func test_cancelPendingCommandBatchesAndFleetHintsAfterRunCompleted_no_log_when_queue_empty() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let run = MissionRunEnvironment(mission: mission, assignments: [])
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
        run.cancelPendingCommandBatchesAndFleetHintsAfterRunCompleted()
        XCTAssertEqual(run.events.count, before)
    }

    func test_executor_mission_start_batch_suppressed_when_run_completed() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: UUID(),
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
        run.status = .completed
        run.setSessionPhase(.completed)

        let cmd = MissionRunIssuedCommand(
            assignmentID: assignID,
            slotName: "Primary",
            vehicleTokenKey: "legacy:1",
            command: .arm,
            issuer: .missionControl,
            issuerKey: "test"
        )
        let before = run.events.count
        run.systems.executor.enqueueCommandBatch(
            MissionRunQueuedCommandBatch(tag: .missionStart, dispatch: .afterMissionCycle, commands: [cmd]),
            context: ctx,
            replacingTags: []
        )
        XCTAssertTrue(run.systems.executor.pendingCommandBatchesSnapshot.isEmpty)
        XCTAssertEqual(run.events.count, before + 1)
        XCTAssertEqual(
            run.events.last?.templateKey,
            MissionRunLogTemplateKey.executorMissionStartBatchSuppressedRunCompleted
        )
    }

    func test_executor_abort_batch_enqueue_not_suppressed_when_run_completed() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: UUID(),
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
        run.status = .completed
        run.setSessionPhase(.completed)

        let cmd = MissionRunIssuedCommand(
            assignmentID: assignID,
            slotName: "Primary",
            vehicleTokenKey: "legacy:1",
            command: .arm,
            issuer: .missionControl,
            issuerKey: "test"
        )
        run.systems.executor.enqueueCommandBatch(
            MissionRunQueuedCommandBatch(tag: .abort, dispatch: .afterMissionCycle, commands: [cmd]),
            context: ctx,
            replacingTags: []
        )
        XCTAssertEqual(run.systems.executor.pendingCommandBatchesSnapshot.count, 1)
    }

    func test_cancelAllScheduledTasks_clears_one_off_deferred_execution_state() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [])
        let future = Date().addingTimeInterval(3600)
        run.systems.scheduling.setDeferredOneOffExecution(
            MissionOneOffDeferredExecution(executeAt: future, countdownStartedAt: Date())
        )
        XCTAssertNotNil(run.oneOffDeferredExecution)
        run.systems.scheduling.cancelAllScheduledTasks()
        XCTAssertNil(run.oneOffDeferredExecution)
    }

    func test_executor_pending_batches_cancelled_run_completed_log_template_registered_in_catalog() {
        let key = MissionRunLogTemplateKey.executorPendingBatchesCancelledForRunCompleted
        XCTAssertNotNil(
            StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport),
            "Missing plainExport catalog entry for \(key)"
        )
        XCTAssertNotNil(
            StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom),
            "Missing MCR catalog entry for \(key)"
        )
    }

    func test_executor_mission_start_suppressed_log_template_registered_in_catalog() {
        let key = MissionRunLogTemplateKey.executorMissionStartBatchSuppressedRunCompleted
        XCTAssertNotNil(StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport))
        XCTAssertNotNil(StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom))
    }

    func test_guardian_sitl_kill_pass_log_template_registered_in_catalog() {
        let key = MissionRunLogTemplateKey.guardianSitlKillPassAfterRunCompleted
        XCTAssertNotNil(
            StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport),
            "Missing plainExport catalog entry for \(key)"
        )
        XCTAssertNotNil(
            StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom),
            "Missing MCR catalog entry for \(key)"
        )
    }

    func test_lifecycle_sim_cleanup_kill_batch_log_template_registered_in_catalog() {
        let key = MissionRunLogTemplateKey.lifecycleSimCleanupKillBatch
        XCTAssertNotNil(StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .plainExport))
        XCTAssertNotNil(StructuredLogTemplateCatalog.pattern(forKey: key, presentation: .missionControlRoom))
    }

    func test_guardian_sitl_motion_stop_pass_log_template_registered_in_catalog() {
        let key = MissionRunLogTemplateKey.guardianSitlMotionStopPassAfterRunCompleted
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
