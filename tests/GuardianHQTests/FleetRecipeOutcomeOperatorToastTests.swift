import XCTest
@testable import GuardianCore

final class FleetRecipeOutcomeOperatorToastTests: XCTestCase {

    func test_success_is_short() {
        let trace = FleetRecipeAuditTrace(
            runID: FleetRecipeRunID(),
            recipe: .literal("recipe.fleet.test.toast"),
            vehicleID: "V1"
        )
        let outcome = FleetRecipeOutcome.succeeded(
            detail: "Recipe completed (step.foo) with lots of internal text",
            payload: .empty,
            trace: trace
        )
        let p = FleetRecipeOutcomeOperatorToast.presentation(recipeHumanLabel: "Compass calibration", outcome: outcome)
        XCTAssertEqual(p.message, "Compass calibration — done.")
        XCTAssertEqual(p.style, .success)
    }

    func test_cancelled_is_neutral_stopped() {
        let trace = FleetRecipeAuditTrace(
            runID: FleetRecipeRunID(),
            recipe: .literal("recipe.fleet.test.toast"),
            vehicleID: "V1"
        )
        let outcome = FleetRecipeOutcome.failed(
            failingCommandPath: [],
            lastResponse: nil,
            detail: "cancelled",
            trace: trace
        )
        let p = FleetRecipeOutcomeOperatorToast.presentation(recipeHumanLabel: "Barometer calibration", outcome: outcome)
        XCTAssertEqual(p.message, "Stopped.")
        XCTAssertEqual(p.style, .info)
    }

    func test_operator_aborted_like_cancel() {
        let trace = FleetRecipeAuditTrace(
            runID: FleetRecipeRunID(),
            recipe: .literal("recipe.fleet.test.toast"),
            vehicleID: "V1"
        )
        let outcome = FleetRecipeOutcome.failed(
            failingCommandPath: [.literal("s")],
            lastResponse: nil,
            detail: "Operator aborted at escalation (s).",
            trace: trace
        )
        let p = FleetRecipeOutcomeOperatorToast.presentation(recipeHumanLabel: "Gyro calibration", outcome: outcome)
        XCTAssertEqual(p.message, "Stopped.")
        XCTAssertEqual(p.style, .info)
    }

    func test_other_failure_keeps_label() {
        let trace = FleetRecipeAuditTrace(
            runID: FleetRecipeRunID(),
            recipe: .literal("recipe.fleet.test.toast"),
            vehicleID: "V1"
        )
        let outcome = FleetRecipeOutcome.failed(
            failingCommandPath: [],
            lastResponse: nil,
            detail: "No descriptor registered for recipe.fleet.missing.",
            trace: trace
        )
        let p = FleetRecipeOutcomeOperatorToast.presentation(recipeHumanLabel: "Level calibration", outcome: outcome)
        XCTAssertEqual(p.message, "Level calibration — couldn't complete.")
        XCTAssertEqual(p.style, .error)
    }
}
