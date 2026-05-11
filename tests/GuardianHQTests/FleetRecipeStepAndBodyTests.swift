import XCTest
@testable import GuardianHQ

/// Stage B1 coverage for the DSL surface types: `FleetRecipeStepID`, `FleetRecipeStep`,
/// `FleetRecipeControlOutcome`, and `FleetRecipeBody`. Codable round-trips + the
/// closed validation rules on the in-body identifier.
final class FleetRecipeStepAndBodyTests: XCTestCase {

    // MARK: FleetRecipeStepID

    func test_stepID_validNames_accepted() throws {
        let valid = [
            "calibrate",
            "verify_telemetry",
            "branchOnDecline",
            "a",
            "step_1",
        ]
        for raw in valid {
            XCTAssertTrue(FleetRecipeStepID.isValidRawValue(raw), "Expected '\(raw)' valid")
            XCTAssertNoThrow(try FleetRecipeStepID(validating: raw))
        }
    }

    func test_stepID_invalidNames_rejected() {
        let invalid = [
            "",
            "1startsWithDigit",
            "has space",
            "has-dash",
            "has.dot",
            "with/slash",
            String(repeating: "a", count: FleetRecipeStepID.maximumLength + 1),
        ]
        for raw in invalid {
            XCTAssertFalse(FleetRecipeStepID.isValidRawValue(raw), "Expected '\(raw)' invalid")
            XCTAssertThrowsError(try FleetRecipeStepID(validating: raw))
        }
    }

    // MARK: FleetRecipeControlOutcome codable

    func test_controlOutcomes_codableRoundTripsForEveryCase() throws {
        let inputs: [FleetRecipeControlOutcome] = [
            .continueToNextStep,
            .branch(stepID: FleetRecipeStepID.literal("verify")),
            .retry,
            .succeed,
            .fail(detail: "some detail"),
            .fail(detail: nil),
            .escalate(
                reason: .operatorActionRequired(kind: .rotateDrone),
                allowedVerbs: [.retry, .abort]
            ),
        ]
        for value in inputs {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(FleetRecipeControlOutcome.self, from: data)
            XCTAssertEqual(value, decoded, "Round-trip mismatch for outcome \(value)")
        }
    }

    // MARK: FleetRecipeStep codable

    func test_invokeCommandStep_codableRoundTrip() throws {
        let step = FleetRecipeStep.invokeCommand(
            id: FleetRecipeStepID.literal("calibrate"),
            command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
            parameters: FleetRecipeParameters(values: ["axis": .string("x")]),
            retry: nil,
            matchers: [
                FleetRecipeStepMatcher(when: .success(), then: .continueToNextStep),
                FleetRecipeStepMatcher(when: .any, then: .fail(detail: nil)),
            ]
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(FleetRecipeStep.self, from: data)
        XCTAssertEqual(step, decoded)
    }

    func test_invokeRecipeStep_codableRoundTrip() throws {
        let step = FleetRecipeStep.invokeRecipe(
            id: FleetRecipeStepID.literal("calibrate"),
            recipe: FleetRecipeName.literal("recipe.fleet.calibrate.compass"),
            parameters: .empty,
            matchers: [FleetRecipeStepMatcher(when: .success(), then: .succeed)]
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(FleetRecipeStep.self, from: data)
        XCTAssertEqual(step, decoded)
    }

    func test_step_idAccessor_works() {
        let cmd = FleetRecipeStep.invokeCommand(
            id: FleetRecipeStepID.literal("a"),
            command: FleetCommandName.literal("command.fleet.vehicle.do.arm"),
            matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
        )
        XCTAssertEqual(cmd.id.rawValue, "a")
        XCTAssertEqual(cmd.matchers.count, 1)
    }

    // MARK: FleetRecipeBody codable

    func test_body_codableRoundTrip() throws {
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("calibrate"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("calibrate"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                    matchers: [
                        FleetRecipeStepMatcher(when: .success(), then: .succeed),
                        FleetRecipeStepMatcher(when: .any, then: .fail(detail: nil)),
                    ]
                ),
            ],
            overallBudgetSeconds: 90
        )
        let data = try JSONEncoder().encode(body)
        let decoded = try JSONDecoder().decode(FleetRecipeBody.self, from: data)
        XCTAssertEqual(decoded.entryStepID, body.entryStepID)
        XCTAssertEqual(decoded.steps.count, body.steps.count)
        XCTAssertEqual(decoded.overallBudgetSeconds, 90)
    }

    func test_body_defaultBudgetUsedWhenAbsent() throws {
        let json = #"""
        {
            "entryStepID": "calibrate",
            "steps": [
                {
                    "kind": "invokeCommand",
                    "id": "calibrate",
                    "command": "command.fleet.vehicle.do.calibrate.compass",
                    "matchers": [{ "when": { "kind": "any" }, "then": { "kind": "succeed" } }]
                }
            ]
        }
        """#
        let decoded = try JSONDecoder().decode(FleetRecipeBody.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.overallBudgetSeconds, FleetRecipeBody.defaultOverallBudgetSeconds)
    }
}
