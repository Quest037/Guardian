import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunReserveSwapDisplacedMissionClearTests: XCTestCase {

    func test_catalogue_mission_clear_nil_without_parsable_token() {
        let row = MissionRunAssignment(
            id: UUID(),
            rosterDeviceId: UUID(),
            slotName: "pool",
            attachedFleetVehicleToken: "not-a-valid-storage-key"
        )
        XCTAssertNil(MissionRunPlannerSubsystem.catalogueMissionClearCommand(forAssignment: row))
    }

    func test_catalogue_mission_clear_uses_custom_issuer_key() {
        let sitlID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let row = MissionRunAssignment(
            id: UUID(),
            rosterDeviceId: UUID(),
            slotName: "pool",
            attachedFleetVehicleToken: "sitl:\(sitlID.uuidString)"
        )
        let cmd = MissionRunPlannerSubsystem.catalogueMissionClearCommand(
            forAssignment: row,
            issuerKey: MissionRunCommandIssuerKey.plannerReserveSwapPostCommit
        )
        XCTAssertEqual(cmd?.issuerKey, MissionRunCommandIssuerKey.plannerReserveSwapPostCommit)
        XCTAssertEqual(cmd?.dispatch, .catalogue(name: .fleetVehicleDoMissionClear, parameters: .empty))
    }

    func test_catalogue_mission_clear_matches_abort_plan_leading_command() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task], rules: RouteRules())
        )
        let aid = UUID()
        let row = MissionRunAssignment(
            id: aid,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedFleetVehicleToken: "live"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        _ = run.systems.planner.buildAbortPlan(trigger: .now)
        let abortFirst = run.systems.planner.lastBuiltAbortPlan?.entries.first(where: { $0.assignmentID == aid })?.issuedCommands.first
        let direct = MissionRunPlannerSubsystem.catalogueMissionClearCommand(forAssignment: row)
        XCTAssertEqual(abortFirst?.dispatch, direct?.dispatch)
        XCTAssertEqual(abortFirst?.assignmentID, direct?.assignmentID)
        XCTAssertEqual(abortFirst?.vehicleTokenKey, direct?.vehicleTokenKey)
        XCTAssertEqual(abortFirst?.issuerKey, MissionRunCommandIssuerKey.plannerAbort)
    }

    func test_displaced_mission_clear_phase_template_key_slug() {
        let k = MissionRunReserveSwapPhaseLogTemplateKey.templateKey(phase: .displacedMissionClear, passed: true)
        XCTAssertEqual(k, "missioncontrol.mre.reserve.phase.displaced_mission_clear.pass")
    }

    func test_begin_post_commit_logs_skip_displaced_clear_when_not_live_executing() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task], rules: RouteRules())
        )
        let vacId = UUID()
        let poolId = UUID()
        let vac = MissionRunAssignment(
            id: vacId,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedFleetVehicleToken: "live"
        )
        let displaced = MissionRunAssignment(
            id: poolId,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "pool",
            attachedFleetVehicleToken: "sitl:\(UUID().uuidString)"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vac, displaced])
        XCTAssertEqual(run.status, .setup)
        let cor = MissionRunReserveRecipeRunnerCorrelation(
            missionRunID: run.id,
            missionTaskID: task.id,
            vacancyAssignmentID: vacId,
            reserveStreamAssignmentID: poolId,
            reservePoolSlotID: poolId,
            vehicleID: "v1"
        )
        run.beginPostCommitReserveSwapHandoffPipeline(correlation: cor, triggerSource: "unit.test")
        let displacedLogs = run.events.filter {
            $0.templateKey == MissionRunReserveSwapPhaseLogTemplateKey.templateKey(phase: .displacedMissionClear, passed: true)
        }
        XCTAssertEqual(displacedLogs.count, 1)
        XCTAssertTrue(displacedLogs[0].templateParams["detail"]?.contains("Skipped") == true)
    }

    func test_post_commit_handoff_enqueues_batch_with_ack_context_when_live_executing() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task], rules: RouteRules())
        )
        let vacId = UUID()
        let poolId = UUID()
        let sitlTok = UUID()
        let vac = MissionRunAssignment(
            id: vacId,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedFleetVehicleToken: "live"
        )
        let displaced = MissionRunAssignment(
            id: poolId,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "pool",
            attachedFleetVehicleToken: "sitl:\(sitlTok.uuidString)"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vac, displaced])
        run.status = .running
        run.setSessionPhase(.executing)
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.captureExecutionContext(
            MissionRunExecutionContext(
                mission: mission,
                fleetLink: fleet,
                sitl: sitl,
                missionProvider: { mission }
            )
        )
        let cor = MissionRunReserveRecipeRunnerCorrelation(
            missionRunID: run.id,
            missionTaskID: task.id,
            vacancyAssignmentID: vacId,
            reserveStreamAssignmentID: poolId,
            reservePoolSlotID: poolId,
            vehicleID: "v1"
        )
        run.beginPostCommitReserveSwapHandoffPipeline(correlation: cor, triggerSource: "unit.test")
        XCTAssertEqual(run.systems.executor.lastEnqueuedReserveSwapPostCommitAckContext?.correlation.missionRunID, run.id)
        XCTAssertEqual(run.systems.executor.lastEnqueuedReserveSwapPostCommitAckContext?.triggerSource, "unit.test")
        XCTAssertFalse(run.systems.executor.lastEnqueuedReserveSwapPostCommitAckContext?.correlation.vacancyAssignmentID.uuidString.isEmpty ?? true)
    }

    func test_displaced_fleet_wind_down_phase_template_key_slug() {
        let k = MissionRunReserveSwapPhaseLogTemplateKey.templateKey(phase: .displacedFleetWindDown, passed: true)
        XCTAssertEqual(k, "missioncontrol.mre.reserve.phase.displaced_fleet_wind_down.pass")
    }
}
