import XCTest
@testable import GuardianCore

final class MissionRunRecipeOutcomeCorrelationTests: XCTestCase {

    func test_matches_when_recipe_and_vehicle_align() throws {
        let recipe = try FleetRecipeName(validating: "recipe.fleet.do.return.home")
        let issued = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "S",
            vehicleTokenKey: "tok",
            dispatch: .recipe(name: recipe, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        let outcome = FleetRecipeOutcome.succeeded(
            detail: nil,
            payload: .empty,
            trace: FleetRecipeAuditTrace(runID: FleetRecipeRunID(), recipe: recipe, vehicleID: "v-1")
        )
        XCTAssertTrue(
            MissionRunRecipeOutcomeCorrelation.outcomeTraceMatchesIssuedRecipeDispatch(
                issued: issued,
                outcome: outcome,
                resolvedFleetVehicleID: "v-1"
            )
        )
    }

    func test_mismatch_vehicle_id() throws {
        let recipe = try FleetRecipeName(validating: "recipe.fleet.do.return.home")
        let issued = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "S",
            vehicleTokenKey: "tok",
            dispatch: .recipe(name: recipe, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        let outcome = FleetRecipeOutcome.succeeded(
            detail: nil,
            payload: .empty,
            trace: FleetRecipeAuditTrace(runID: FleetRecipeRunID(), recipe: recipe, vehicleID: "other")
        )
        XCTAssertFalse(
            MissionRunRecipeOutcomeCorrelation.outcomeTraceMatchesIssuedRecipeDispatch(
                issued: issued,
                outcome: outcome,
                resolvedFleetVehicleID: "v-1"
            )
        )
    }

    func test_mismatch_recipe_name() throws {
        let rtl = try FleetRecipeName(validating: "recipe.fleet.do.return.home")
        let park = try FleetRecipeName(validating: "recipe.fleet.vehicle.do.park")
        let issued = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "S",
            vehicleTokenKey: "tok",
            dispatch: .recipe(name: rtl, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        let outcome = FleetRecipeOutcome.succeeded(
            detail: nil,
            payload: .empty,
            trace: FleetRecipeAuditTrace(runID: FleetRecipeRunID(), recipe: park, vehicleID: "v-1")
        )
        XCTAssertFalse(
            MissionRunRecipeOutcomeCorrelation.outcomeTraceMatchesIssuedRecipeDispatch(
                issued: issued,
                outcome: outcome,
                resolvedFleetVehicleID: "v-1"
            )
        )
    }
}
