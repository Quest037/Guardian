import XCTest
@testable import GuardianCore

final class MissionRunPolicySlotPushEvidenceTests: XCTestCase {

    func test_issuer_eligible_only_abort_and_local_operator() {
        XCTAssertTrue(MissionRunPolicySlotPushEvidence.issuerEligibleForSlotPolicyPushEvidence(MissionRunCommandIssuerKey.plannerAbort))
        XCTAssertTrue(MissionRunPolicySlotPushEvidence.issuerEligibleForSlotPolicyPushEvidence(MissionRunCommandIssuerKey.localOperator))
        XCTAssertTrue(MissionRunPolicySlotPushEvidence.issuerEligibleForSlotPolicyPushEvidence(MissionRunCommandIssuerKey.completePolicyWindDown))
        XCTAssertFalse(MissionRunPolicySlotPushEvidence.issuerEligibleForSlotPolicyPushEvidence(MissionRunCommandIssuerKey.missionExecute))
        XCTAssertFalse(MissionRunPolicySlotPushEvidence.issuerEligibleForSlotPolicyPushEvidence(MissionRunCommandIssuerKey.plannerReserveSwapPostCommit))
    }

    func test_mission_clear_success_is_not_terminal() {
        let issued = issuedCommand(
            dispatch: .catalogue(name: .fleetVehicleDoMissionClear, parameters: .empty),
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        XCTAssertNil(MissionRunPolicySlotPushEvidence.terminalSlotStateIfAffected(issued: issued, success: true))
    }

    func test_mission_clear_failure_is_policy_failed() {
        let issued = issuedCommand(
            dispatch: .catalogue(name: .fleetVehicleDoMissionClear, parameters: .empty),
            issuerKey: MissionRunCommandIssuerKey.localOperator
        )
        XCTAssertEqual(MissionRunPolicySlotPushEvidence.terminalSlotStateIfAffected(issued: issued, success: false), .policyFailed)
    }

    func test_loiter_catalogue_maps_success_and_failure() {
        let issued = issuedCommand(
            dispatch: .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty),
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        XCTAssertEqual(MissionRunPolicySlotPushEvidence.terminalSlotStateIfAffected(issued: issued, success: true), .policySucceeded)
        XCTAssertEqual(MissionRunPolicySlotPushEvidence.terminalSlotStateIfAffected(issued: issued, success: false), .policyFailed)
    }

    func test_return_home_recipe_maps_success() {
        let issued = issuedCommand(
            dispatch: .recipe(name: FleetRecipeName.literal("recipe.fleet.do.return.home"), parameters: .empty),
            issuerKey: MissionRunCommandIssuerKey.localOperator
        )
        XCTAssertEqual(MissionRunPolicySlotPushEvidence.terminalSlotStateIfAffected(issued: issued, success: true), .policySucceeded)
    }

    func test_mission_upload_recipe_ignored_even_for_local_operator() {
        let issued = issuedCommand(
            dispatch: .recipe(name: FleetRecipeName.literal("recipe.fleet.do.mission.upload.start"), parameters: .empty),
            issuerKey: MissionRunCommandIssuerKey.localOperator
        )
        XCTAssertNil(MissionRunPolicySlotPushEvidence.terminalSlotStateIfAffected(issued: issued, success: true))
    }

    func test_vehicle_command_ignored() {
        let issued = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "A",
            vehicleTokenKey: "tok",
            command: .returnToLaunch,
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.localOperator
        )
        XCTAssertNil(MissionRunPolicySlotPushEvidence.terminalSlotStateIfAffected(issued: issued, success: true))
    }

    @MainActor
    func test_apply_push_updates_assignment_lanes() {
        let aid = UUID()
        let rosterId = UUID()
        let mission = Mission(name: "M", description: "", type: .mobile)
        let row = MissionRunAssignment(id: aid, rosterDeviceId: rosterId, slotName: "Alpha")
        let env = MissionRunEnvironment(mission: mission, assignments: [row])
        let issued = MissionRunIssuedCommand(
            assignmentID: aid,
            slotName: "Alpha",
            vehicleTokenKey: "tok",
            dispatch: .catalogue(name: .fleetVehicleDoPark, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        env.applySlotPolicyPushEvidence(issued: issued, success: true)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.observed, .policySucceeded)
        XCTAssertEqual(env.assignments[0].slotLifecycleLanes?.commanded, .policySucceeded)
    }

    private func issuedCommand(dispatch: MissionRunFleetDispatch, issuerKey: String) -> MissionRunIssuedCommand {
        MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "S",
            vehicleTokenKey: "tok",
            dispatch: dispatch,
            issuer: .missionControl,
            issuerKey: issuerKey
        )
    }
}
