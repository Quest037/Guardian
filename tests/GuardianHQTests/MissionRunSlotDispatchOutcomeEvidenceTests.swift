import XCTest
@testable import GuardianCore

@MainActor
final class MissionRunSlotDispatchOutcomeEvidenceTests: XCTestCase {

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

    func test_mission_upload_success_syncs_observed_to_commanded() {
        let tid = UUID()
        let aid = UUID()
        let env = makeEnv(taskID: tid, assignmentID: aid)
        env.setSessionPhase(.executing)
        let issued = MissionRunIssuedCommand(
            assignmentID: aid,
            slotName: "S1",
            vehicleTokenKey: "k",
            dispatch: .recipe(
                name: FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName,
                parameters: .empty
            ),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        env.applySlotPolicyDispatchStartIfNeeded(issued: issued)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.commanded, .executingMission)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.observed, .idle)
        env.applySlotDispatchOutcomeEvidence(issued: issued, success: true)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.observed, .executingMission)
    }

    func test_mission_upload_failure_sets_observed_policy_failed() {
        let tid = UUID()
        let aid = UUID()
        let env = makeEnv(taskID: tid, assignmentID: aid)
        env.setSessionPhase(.executing)
        let issued = MissionRunIssuedCommand(
            assignmentID: aid,
            slotName: "S1",
            vehicleTokenKey: "k",
            dispatch: .recipe(
                name: FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName,
                parameters: .empty
            ),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        env.applySlotPolicyDispatchStartIfNeeded(issued: issued)
        env.applySlotDispatchOutcomeEvidence(issued: issued, success: false)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.commanded, .executingMission)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.observed, .policyFailed)
    }

    func test_between_cycles_catalogue_failure_sets_observed_policy_failed() {
        let tid = UUID()
        let aid = UUID()
        let env = makeEnv(taskID: tid, assignmentID: aid)
        let issued = MissionRunIssuedCommand(
            assignmentID: aid,
            slotName: "S1",
            vehicleTokenKey: "k",
            dispatch: .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        env.applySlotPolicyDispatchStartIfNeeded(issued: issued)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.commanded, .betweenCycles)
        env.applySlotDispatchOutcomeEvidence(issued: issued, success: false)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.observed, .policyFailed)
    }

    func test_policy_push_still_takes_precedence_over_non_policy_sync() {
        let tid = UUID()
        let aid = UUID()
        let env = makeEnv(taskID: tid, assignmentID: aid)
        env.markMissionTaskAbortWindDownIssued(forTaskID: tid)
        let issued = MissionRunIssuedCommand(
            assignmentID: aid,
            slotName: "S1",
            vehicleTokenKey: "k",
            dispatch: .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty),
            issuer: .operator,
            issuerKey: MissionRunCommandIssuerKey.localOperator
        )
        env.applySlotPolicyDispatchStartIfNeeded(issued: issued)
        env.applySlotDispatchOutcomeEvidence(issued: issued, success: false)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.commanded, .policyFailed)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.observed, .policyFailed)
    }
}
