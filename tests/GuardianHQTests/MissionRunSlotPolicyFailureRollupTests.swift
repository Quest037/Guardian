import XCTest
@testable import GuardianHQ

final class MissionRunSlotPolicyFailureRollupTests: XCTestCase {

    func test_all_failure_classes_block_task_auto_triage_v1() {
        for c in MissionRunSlotPolicyFailureClass.allCases {
            XCTAssertFalse(MissionRunSlotPolicyFailureRollup.allowsTaskLevelAutoTriageRollup(c))
        }
    }

    func test_failureClass_forSlotTerminal_policyFailed_and_blocked() {
        XCTAssertEqual(
            MissionRunSlotPolicyFailureRollup.failureClass(forSlotTerminal: .policyFailed),
            .fleetWindDownStepRejected
        )
        XCTAssertEqual(
            MissionRunSlotPolicyFailureRollup.failureClass(forSlotTerminal: .blockedNoVehicle),
            .noVehicleBoundForSlotRow
        )
        XCTAssertNil(MissionRunSlotPolicyFailureRollup.failureClass(forSlotTerminal: .policySucceeded))
        XCTAssertNil(MissionRunSlotPolicyFailureRollup.failureClass(forSlotTerminal: .policyAborting))
    }

    func test_failureClassIfPolicyFailedIssued_matches_push_evidence_failures() {
        let missionClear = issuedCommand(
            dispatch: .catalogue(name: .fleetVehicleDoMissionClear, parameters: .empty),
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        XCTAssertEqual(
            MissionRunSlotPolicyFailureRollup.failureClassIfPolicyFailedIssued(missionClear),
            .fleetWindDownStepRejected
        )

        let loiter = issuedCommand(
            dispatch: .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty),
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        XCTAssertEqual(
            MissionRunSlotPolicyFailureRollup.failureClassIfPolicyFailedIssued(loiter),
            .fleetWindDownStepRejected
        )

        let rtl = issuedCommand(
            dispatch: .recipe(name: FleetRecipeName.literal("recipe.fleet.do.return.home"), parameters: .empty),
            issuerKey: MissionRunCommandIssuerKey.localOperator
        )
        XCTAssertEqual(
            MissionRunSlotPolicyFailureRollup.failureClassIfPolicyFailedIssued(rtl),
            .fleetWindDownStepRejected
        )
    }

    func test_failureClassIfPolicyFailedIssued_nil_when_dispatch_not_policy_terminal_on_failure() {
        let ignoredRecipe = issuedCommand(
            dispatch: .recipe(name: FleetRecipeName.literal("recipe.fleet.do.mission.upload.start"), parameters: .empty),
            issuerKey: MissionRunCommandIssuerKey.localOperator
        )
        XCTAssertNil(MissionRunSlotPolicyFailureRollup.failureClassIfPolicyFailedIssued(ignoredRecipe))

        let ineligibleIssuer = issuedCommand(
            dispatch: .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty),
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        XCTAssertNil(MissionRunSlotPolicyFailureRollup.failureClassIfPolicyFailedIssued(ineligibleIssuer))
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
