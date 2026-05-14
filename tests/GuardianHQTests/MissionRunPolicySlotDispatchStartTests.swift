import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunPolicySlotDispatchStartTests: XCTestCase {

    private func makeEnv(taskID: UUID, assignmentID: UUID) -> MissionRunEnvironment {
        var mission = Mission(name: "M", description: "", type: .mobile)
        mission.routeMacro.tasks = [MissionTask(id: taskID, name: "Alpha")]
        let row = MissionRunAssignment(
            id: assignmentID,
            taskId: taskID,
            rosterDeviceId: UUID(),
            slotName: "S1"
        )
        return MissionRunEnvironment(mission: mission, assignments: [row])
    }

    func test_planner_abort_mission_clear_maps_policy_aborting() {
        let tid = UUID()
        let aid = UUID()
        let issued = MissionRunIssuedCommand(
            assignmentID: aid,
            slotName: "S1",
            vehicleTokenKey: "k",
            dispatch: .catalogue(name: .fleetVehicleDoMissionClear, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        let next = MissionRunPolicySlotDispatchStart.commandedSlotStateIfDispatchLeavesMRE(
            issued: issued,
            effectiveTaskID: tid,
            abortWindDownIssuedTaskIDs: [],
            completeWindDownIssuedTaskIDs: [],
            sessionPhase: .executing
        )
        XCTAssertEqual(next, .policyAborting)
    }

    func test_local_operator_loiter_uses_abort_issued_set() {
        let tid = UUID()
        let issued = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "S1",
            vehicleTokenKey: "k",
            dispatch: .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty),
            issuer: .operator,
            issuerKey: MissionRunCommandIssuerKey.localOperator
        )
        XCTAssertEqual(
            MissionRunPolicySlotDispatchStart.commandedSlotStateIfDispatchLeavesMRE(
                issued: issued,
                effectiveTaskID: tid,
                abortWindDownIssuedTaskIDs: [tid],
                completeWindDownIssuedTaskIDs: [],
                sessionPhase: .executing
            ),
            .policyAborting
        )
        XCTAssertEqual(
            MissionRunPolicySlotDispatchStart.commandedSlotStateIfDispatchLeavesMRE(
                issued: issued,
                effectiveTaskID: tid,
                abortWindDownIssuedTaskIDs: [],
                completeWindDownIssuedTaskIDs: [tid],
                sessionPhase: .executing
            ),
            .policyCompleting
        )
    }

    func test_local_operator_loiter_without_wind_down_issued_is_nil() {
        let tid = UUID()
        let issued = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "S1",
            vehicleTokenKey: "k",
            dispatch: .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty),
            issuer: .operator,
            issuerKey: MissionRunCommandIssuerKey.localOperator
        )
        XCTAssertNil(
            MissionRunPolicySlotDispatchStart.commandedSlotStateIfDispatchLeavesMRE(
                issued: issued,
                effectiveTaskID: tid,
                abortWindDownIssuedTaskIDs: [],
                completeWindDownIssuedTaskIDs: [],
                sessionPhase: .executing
            )
        )
    }

    func test_mission_execute_upload_recipe_staging_vs_executing_phase() {
        let tid = UUID()
        let issued = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "S1",
            vehicleTokenKey: "k",
            dispatch: .recipe(
                name: FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName,
                parameters: .empty
            ),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        XCTAssertEqual(
            MissionRunPolicySlotDispatchStart.commandedSlotStateIfDispatchLeavesMRE(
                issued: issued,
                effectiveTaskID: tid,
                abortWindDownIssuedTaskIDs: [],
                completeWindDownIssuedTaskIDs: [],
                sessionPhase: .staging
            ),
            .staging
        )
        XCTAssertEqual(
            MissionRunPolicySlotDispatchStart.commandedSlotStateIfDispatchLeavesMRE(
                issued: issued,
                effectiveTaskID: tid,
                abortWindDownIssuedTaskIDs: [],
                completeWindDownIssuedTaskIDs: [],
                sessionPhase: .executing
            ),
            .executingMission
        )
    }

    func test_mission_execute_between_cycles_rtl_shape() {
        let tid = UUID()
        let issued = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "S1",
            vehicleTokenKey: "k",
            dispatch: .recipe(
                name: FleetMissionRecipeRegistrations.doReturnHomeRecipeName,
                parameters: .empty
            ),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        XCTAssertEqual(
            MissionRunPolicySlotDispatchStart.commandedSlotStateIfDispatchLeavesMRE(
                issued: issued,
                effectiveTaskID: tid,
                abortWindDownIssuedTaskIDs: [tid],
                completeWindDownIssuedTaskIDs: [],
                sessionPhase: .executing
            ),
            .betweenCycles
        )
    }

    func test_apply_dispatch_start_commanded_only_observed_idle_until_push() {
        let tid = UUID()
        let aid = UUID()
        let env = makeEnv(taskID: tid, assignmentID: aid)
        env.markMissionTaskAbortWindDownIssued(forTaskID: tid)
        let issued = MissionRunIssuedCommand(
            assignmentID: aid,
            slotName: "S1",
            vehicleTokenKey: "k",
            dispatch: .catalogue(name: .fleetVehicleDoMissionClear, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        env.applySlotPolicyDispatchStartIfNeeded(issued: issued)
        let lanes = env.assignments[0].slotLifecycleLanes
        XCTAssertEqual(lanes?.commanded, .policyAborting)
        XCTAssertEqual(lanes?.observed, .idle)
    }

    func test_dispatch_start_does_not_clobber_terminal_commanded() {
        let tid = UUID()
        let aid = UUID()
        let env = makeEnv(taskID: tid, assignmentID: aid)
        XCTAssertTrue(
            env.applySlotLifecycleLaneMutation(.setCommandedAndObservedToSame(assignmentID: aid, terminal: .policySucceeded))
        )
        env.markMissionTaskAbortWindDownIssued(forTaskID: tid)
        let issued = MissionRunIssuedCommand(
            assignmentID: aid,
            slotName: "S1",
            vehicleTokenKey: "k",
            dispatch: .catalogue(name: .fleetVehicleDoMissionClear, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        env.applySlotPolicyDispatchStartIfNeeded(issued: issued)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.commanded, .policySucceeded)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.observed, .policySucceeded)
    }
}
