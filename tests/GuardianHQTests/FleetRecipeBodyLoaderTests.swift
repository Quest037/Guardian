import XCTest
@testable import GuardianHQ

/// Stage C loader-plumbing coverage for ``FleetRecipeBodyLoader``.
///
/// The loader is the bridge between hybrid-shape subsystem registrations (Swift
/// descriptors) and per-recipe JSON body files. Catalogue-level structural
/// validation (matchers, branch targets, registered references, regex compile,
/// budget caps) is intentionally *not* the loader's job — that runs inside
/// ``FleetRecipesCatalogue/register(_:)`` once the descriptor lands. These tests
/// therefore only pin the three loader-owned outcomes: success, parse-decode
/// failure, and resource-missing failure.
///
/// Fixtures live under `Tests/GuardianHQTests/Fixtures/` and are exposed via the
/// test target's own `Bundle.module` (declared as `.copy("Fixtures")` in
/// `Package.swift`).
@MainActor
final class FleetRecipeBodyLoaderTests: XCTestCase {

    /// Test-target fixtures subdirectory inside `Bundle.module`. Mirrors the
    /// production layout where each subsystem owns a uniquely-named bodies
    /// directory (`CalibrationBodies`, `ErrorBodies`); the test target just uses
    /// `Fixtures` so SPM's flat-bundle layout never collides with the main
    /// target's bodies directories.
    private static let fixturesSubdirectory = "Fixtures"

    // MARK: - Success

    func test_load_succeedsForValidResource() throws {
        let recipeName = try FleetRecipeName(validating: "recipe.fleet.test.validbody")

        let outcome = FleetRecipeBodyLoader.load(
            recipeName: recipeName,
            inSubdirectory: Self.fixturesSubdirectory,
            bundle: .module
        )

        switch outcome {
        case .success(let body):
            XCTAssertEqual(body.entryStepID.rawValue, "calibrate")
            XCTAssertEqual(body.steps.count, 1)
            XCTAssertEqual(body.overallBudgetSeconds, 60)
        case .failure(let error):
            XCTFail("Expected a decoded body from the valid fixture; got \(error.description).")
        }
    }

    // MARK: - Parse failure

    func test_load_returnsParseFailedForMalformedJSON() throws {
        let recipeName = try FleetRecipeName(validating: "recipe.fleet.test.malformedbody")

        let outcome = FleetRecipeBodyLoader.load(
            recipeName: recipeName,
            inSubdirectory: Self.fixturesSubdirectory,
            bundle: .module
        )

        switch outcome {
        case .success(let body):
            XCTFail("Malformed JSON must not decode; got body with \(body.steps.count) steps.")
        case .failure(let error):
            guard case .parseFailed(let failingName, let errors) = error else {
                XCTFail("Expected .parseFailed; got \(error.description).")
                return
            }
            XCTAssertEqual(failingName, recipeName)
            XCTAssertFalse(errors.errors.isEmpty, "Parser must surface at least one error.")
            if let first = errors.errors.first {
                if case .decodeFailed = first {
                    // Expected: malformed JSON fails at the decode layer.
                } else {
                    XCTFail("Expected .decodeFailed parse error; got \(first.description).")
                }
            }
        }
    }

    // MARK: - Resource missing

    func test_load_returnsResourceNotFoundWhenAbsent() throws {
        let recipeName = try FleetRecipeName(validating: "recipe.fleet.test.doesnotexist")

        let outcome = FleetRecipeBodyLoader.load(
            recipeName: recipeName,
            inSubdirectory: Self.fixturesSubdirectory,
            bundle: .module
        )

        switch outcome {
        case .success:
            XCTFail("Loader must fail when the resource is absent.")
        case .failure(let error):
            guard case .resourceNotFound(let failingName, let subdir) = error else {
                XCTFail("Expected .resourceNotFound; got \(error.description).")
                return
            }
            XCTAssertEqual(failingName, recipeName)
            XCTAssertEqual(subdir, Self.fixturesSubdirectory)
        }
    }

}
