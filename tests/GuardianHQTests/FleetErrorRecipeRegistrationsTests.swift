import XCTest
@testable import GuardianCore

/// Stage C coverage for the errors subsystem registration entry point. First
/// authored recipe is `recipe.fleet.errors.fix.calibrationrequired` — the first
/// composite (invokeRecipe-bearing) recipe in the catalogue, so this suite
/// doubles as coverage for the recipe-invokes-recipe composition path.
///
/// `setUp` registers commands AND the calibration subsystem before each test
/// because the error recipe declares calibration recipes as `containsRecipes`
/// children, and `FleetRecipesCatalogue.register(...)` refuses descriptors
/// whose children aren't already registered.
@MainActor
final class FleetErrorRecipeRegistrationsTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        FleetRecipesCatalogue.shared._testOnlyReset()
        FleetRecipesCatalogueBootstrap._testOnlyResetIdempotencyFlag()
        FleetCommandsCatalogueBootstrap.ensureRegistered()
        // Calibration must register first so the error recipe's containsRecipes
        // children resolve at registration time. The catalogue rejects descriptors
        // whose children aren't already in the registry — bootstrap order pins this
        // contract in production but tests have to recreate it explicitly.
        FleetCalibrationRecipeRegistrations.registerAll()
    }

    // MARK: - recipe.fleet.errors.fix.calibrationrequired

    func test_registerAll_registersCalibrationRequired() {
        FleetErrorRecipeRegistrations.registerAll()

        let descriptor = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.errors.fix.calibrationrequired")

        XCTAssertNotNil(descriptor, "calibrationrequired must be registered after registerAll().")
        XCTAssertEqual(descriptor?.riskTier, .groundOnly, "Composite cal sweep — inherits groundOnly from every child.")
        XCTAssertEqual(
            descriptor?.cancelRecipe?.rawValue,
            "recipe.fleet.calibrate.cancel",
            "Recipe spends the bulk of its budget inside calibration procedures; calibrate cancel is the right cleanup."
        )
        XCTAssertEqual(
            descriptor?.appliesToSystems,
            ["compass", "accelerometer", "gyro", "preflight"]
        )
        XCTAssertTrue(
            descriptor?.parameters.isEmpty == true,
            "Recovery sweep takes no parameters — operator-or-process trigger only."
        )
    }

    func test_calibrationRequired_declaresAllFourChildrenInContainsRecipes() throws {
        FleetErrorRecipeRegistrations.registerAll()

        let descriptor = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.errors.fix.calibrationrequired")
        )
        XCTAssertTrue(descriptor.isComposite, "Recipe must be composite — first composite in the catalogue.")
        XCTAssertEqual(
            Set(descriptor.containsRecipes.map(\.rawValue)),
            [
                "recipe.fleet.calibrate.compass",
                "recipe.fleet.calibrate.accelerometer",
                "recipe.fleet.calibrate.gyro",
                "recipe.fleet.diagnose.armprobe",
            ]
        )
    }

    func test_calibrationRequired_bodyIsFourSequentialInvokeRecipeSteps() throws {
        FleetErrorRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.errors.fix.calibrationrequired")?
                .body
        )
        XCTAssertEqual(body.steps.count, 4, "Step graph: compass → accel → gyro → armprobe verify.")
        XCTAssertEqual(body.overallBudgetSeconds, 600, "Right at the parser cap — children sum to ~560s plus setup overhead.")

        let expected: [(stepID: String, recipe: String)] = [
            ("cal_compass",      "recipe.fleet.calibrate.compass"),
            ("cal_accel",        "recipe.fleet.calibrate.accelerometer"),
            ("cal_gyro",         "recipe.fleet.calibrate.gyro"),
            ("verify_armprobe",  "recipe.fleet.diagnose.armprobe"),
        ]
        for (index, entry) in expected.enumerated() {
            guard case .invokeRecipe(let id, let recipe, _, _) = body.steps[index] else {
                return XCTFail("Step \(index) must be invokeRecipe; got \(body.steps[index]).")
            }
            XCTAssertEqual(id.rawValue, entry.stepID, "Step \(index) ID mismatch.")
            XCTAssertEqual(recipe.rawValue, entry.recipe, "Step \(index) target recipe mismatch.")
        }
    }

    /// First three steps follow the same shape — success continues, anything
    /// else fails the parent with a populated detail. Last step's success path
    /// ends the recipe.
    func test_calibrationRequired_intermediateStepsContinueAndLastStepSucceeds() throws {
        FleetErrorRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.errors.fix.calibrationrequired")?
                .body
        )

        for index in 0..<3 {
            let matchers = body.steps[index].matchers
            XCTAssertEqual(matchers.count, 2, "Step \(index) matchers: success | any.")
            guard case .success = matchers[0].when, case .continueToNextStep = matchers[0].then else {
                return XCTFail("Step \(index) first matcher must be `success → continueToNextStep`; got \(matchers[0]).")
            }
            guard case .any = matchers[1].when, case .fail(let detail) = matchers[1].then else {
                return XCTFail("Step \(index) second matcher must be `any → fail(detail)`; got \(matchers[1]).")
            }
            let unwrapped = try XCTUnwrap(detail, "Step \(index) fail matcher must carry a non-nil detail.")
            XCTAssertFalse(unwrapped.isEmpty, "Step \(index) fail detail must be non-empty.")
        }

        let verifyMatchers = body.steps[3].matchers
        XCTAssertEqual(verifyMatchers.count, 2)
        guard case .success = verifyMatchers[0].when, case .succeed = verifyMatchers[0].then else {
            return XCTFail("Verify step success matcher must terminate the recipe with `succeed`; got \(verifyMatchers[0]).")
        }
        guard case .any = verifyMatchers[1].when, case .fail = verifyMatchers[1].then else {
            return XCTFail("Verify step any matcher must fail the recipe; got \(verifyMatchers[1]).")
        }
    }

    /// Locks the composition-depth invariant: every child this recipe invokes
    /// must itself be atomic (body has no `invokeRecipe` step). If a future
    /// edit introduces a recipe-of-recipe-of-recipe by accident, the parser
    /// rejects registration — this test catches the same violation up front.
    func test_calibrationRequired_allChildrenAreAtomic() throws {
        FleetErrorRecipeRegistrations.registerAll()

        let descriptor = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.errors.fix.calibrationrequired")
        )
        for childName in descriptor.containsRecipes {
            let child = try XCTUnwrap(
                FleetRecipesCatalogue.shared.descriptor(for: childName),
                "Child \(childName.rawValue) must be registered before the parent."
            )
            XCTAssertFalse(
                child.bodyInvokesAnyRecipe,
                "Child \(childName.rawValue) must be atomic (no invokeRecipe steps) — 1-level depth limit."
            )
            XCTAssertTrue(
                child.containsRecipes.isEmpty,
                "Child \(childName.rawValue) must declare empty containsRecipes — 1-level depth limit."
            )
        }
    }

    // MARK: - Subsystem-wide idempotency

    func test_registerAll_isIdempotent() {
        FleetErrorRecipeRegistrations.registerAll()
        let countAfterFirst = FleetRecipesCatalogue.shared
            .descriptors(underNamespacePrefix: ["fleet", "errors"]).count

        FleetErrorRecipeRegistrations.registerAll()
        let countAfterSecond = FleetRecipesCatalogue.shared
            .descriptors(underNamespacePrefix: ["fleet", "errors"]).count

        XCTAssertEqual(
            countAfterFirst,
            countAfterSecond,
            "Calling registerAll() twice must not double-register descriptors."
        )
        XCTAssertEqual(
            countAfterFirst,
            1,
            "Errors subsystem currently ships exactly 1 recipe: calibrationrequired. Update when new error-fix recipes land."
        )
    }
}
