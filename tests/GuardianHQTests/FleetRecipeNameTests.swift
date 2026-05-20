import XCTest
@testable import GuardianCore

/// Stage B1 namespace-validation coverage for the Layer 1 recipe identifier. Mirrors
/// the Layer 0 test shape (`FleetCommandNameTests`) so the two namespaces stay in
/// lockstep on lexical rules. Recipes deliberately do **not** carry a reserved verb
/// segment — that distinction is a Layer 0 concept.
final class FleetRecipeNameTests: XCTestCase {

    // MARK: Positive cases

    func test_validNames_acceptedByConstructor() throws {
        let valid = [
            "recipe.fleet.calibrate.compass",
            "recipe.fleet.calibrate.accelerometer",
            "recipe.fleet.calibrate.gyro",
            "recipe.fleet.calibrate.baro",
            "recipe.fleet.calibrate.level",
            "recipe.fleet.diagnose.armprobe",
            "recipe.fleet.errors.fix.compass.interference",
            "recipe.plugin.paladin.calibrate.fastcompass",
            "recipe.mc.run.preflight",
        ]
        for raw in valid {
            XCTAssertNoThrow(
                try FleetRecipeName(validating: raw),
                "Expected '\(raw)' to validate."
            )
            XCTAssertTrue(
                FleetRecipeName.isValidRawValue(raw),
                "Expected '\(raw)' to be a valid raw value."
            )
        }
    }

    func test_decomposition_returnsSubsystemAndSpecifier() throws {
        let name = try FleetRecipeName(validating: "recipe.fleet.calibrate.compass.motor")
        XCTAssertEqual(name.subsystem, "fleet")
        XCTAssertEqual(name.specifier, ["calibrate", "compass", "motor"])
    }

    func test_isUnderNamespacePrefix_matchesExpectedClaims() throws {
        let name = try FleetRecipeName(validating: "recipe.fleet.calibrate.compass")
        XCTAssertTrue(name.isUnderNamespacePrefix(["fleet"]))
        XCTAssertTrue(name.isUnderNamespacePrefix(["fleet", "calibrate"]))
        XCTAssertTrue(name.isUnderNamespacePrefix(["fleet", "calibrate", "compass"]))
        XCTAssertFalse(name.isUnderNamespacePrefix(["fleet", "diagnose"]))
        XCTAssertFalse(name.isUnderNamespacePrefix(["plugin", "paladin"]))
        XCTAssertFalse(name.isUnderNamespacePrefix(["fleet", "calibrate", "compass", "extra"]))
    }

    func test_codable_roundTripsThroughJSON() throws {
        let original = try FleetRecipeName(validating: "recipe.fleet.calibrate.compass")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FleetRecipeName.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }

    // MARK: Negative cases

    func test_invalidNames_rejectedByValidator() {
        let invalid: [String] = [
            "",
            "recipe",
            "recipe.",
            ".recipe.fleet.calibrate.compass",
            "recipe.fleet.calibrate.compass.",
            "recipe..fleet.calibrate.compass",
            "fleet.calibrate.compass",                  // missing "recipe." prefix
            "Recipe.Fleet.Calibrate.Compass",            // uppercase
            "recipe.fleet",                              // missing specifier
            "recipe.fleet.calibrate/compass",            // illegal character
            "recipe.fleet calibrate compass",            // whitespace illegal
        ]
        for raw in invalid {
            XCTAssertFalse(
                FleetRecipeName.isValidRawValue(raw),
                "Expected '\(raw)' to be rejected but it passed validation."
            )
            XCTAssertThrowsError(
                try FleetRecipeName(validating: raw),
                "Expected '\(raw)' to throw."
            ) { error in
                guard case FleetRecipeNameError.invalidFormat(let echoed) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(echoed, raw)
            }
        }
    }

    func test_maximumLength_rejected() {
        let oversize = "recipe." + String(repeating: "a", count: FleetRecipeName.maximumLength)
        XCTAssertFalse(FleetRecipeName.isValidRawValue(oversize))
    }
}
