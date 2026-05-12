import XCTest
@testable import GuardianHQ

/// Bootstrap coverage for the Layer 1 recipe catalogue. Mirrors the Layer 0
/// bootstrap test shape. Subsystem entry points (calibration, errors, mission, move+park)
/// are wired into the bootstrap; tests pin the idempotency
/// contract plus the per-subsystem counts so accidental content additions or
/// regressions are caught alongside the matching docs update.
@MainActor
final class FleetRecipesCatalogueBootstrapTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        FleetRecipesCatalogue.shared._testOnlyReset()
        FleetRecipesCatalogueBootstrap._testOnlyResetIdempotencyFlag()
        // Subsystem `registerAll()` runs body validation against the live commands
        // registry; bootstrap is idempotent so the across-suite cost is one pass.
        FleetCommandsCatalogueBootstrap.ensureRegistered()
    }

    func test_ensureRegistered_isIdempotent() {
        FleetRecipesCatalogueBootstrap.ensureRegistered()
        let countAfterFirst = FleetRecipesCatalogue.shared.descriptors.count
        FleetRecipesCatalogueBootstrap.ensureRegistered()
        let countAfterSecond = FleetRecipesCatalogue.shared.descriptors.count
        XCTAssertEqual(
            countAfterFirst,
            countAfterSecond,
            "Bootstrap must be idempotent — second call should be a no-op."
        )
    }

    func test_ensureRegistered_invokesSubsystemEntryPoints() {
        // The bootstrap is the only call site for the subsystem entry points; if any
        // gets accidentally unwired the per-subsystem suites still pass on their own
        // but the wiring through the bootstrap regresses. This test exercises the
        // full path and checks the namespace partitions are all addressable.
        //
        // Note: the diagnose namespace is currently authored alongside the calibration
        // subsystem (see `FleetCalibrationRecipeRegistrations.registerAll()`), so the
        // partition lives in the calibration registrations file but the namespace
        // count is tracked separately here.
        FleetRecipesCatalogueBootstrap.ensureRegistered()

        let calibration = FleetRecipesCatalogue.shared
            .descriptors(underNamespacePrefix: ["fleet", "calibrate"])
        let diagnose = FleetRecipesCatalogue.shared
            .descriptors(underNamespacePrefix: ["fleet", "diagnose"])
        let errors = FleetRecipesCatalogue.shared
            .descriptors(underNamespacePrefix: ["fleet", "errors"])
        let mission = FleetRecipesCatalogue.shared
            .descriptors(underNamespacePrefix: ["fleet", "do", "mission"])
        let returnHomeNav = FleetRecipesCatalogue.shared
            .descriptors(underNamespacePrefix: ["fleet", "do", "return"])

        XCTAssertEqual(
            calibration.count,
            22,
            "Calibration subsystem ships 22 recipes spanning every `do.calibrate.*` command: " +
            "cancel + 5 core sensor cals + 7 additional sensor cals + 3 v1 discoverability shells + 6 param-driven cals. " +
            "Update this count when new calibration recipes land."
        )
        XCTAssertEqual(
            diagnose.count,
            3,
            "Diagnose namespace ships 3 recipes: cancel + armprobe + armprobe.hold. Update this count when new diagnose recipes land."
        )
        XCTAssertEqual(
            errors.count,
            1,
            "Errors subsystem ships 1 recipe: calibrationrequired (composite cal sweep + arm-probe verify). Update when new error-fix recipes land."
        )
        XCTAssertEqual(
            mission.count,
            2,
            "Mission subsystem ships 2 recipes under fleet.do.mission.*: recipe.fleet.do.mission.upload.start and recipe.fleet.do.mission.upload.start.item for MRE post-commit handoff. Update when new mission recipes land."
        )
        XCTAssertEqual(
            returnHomeNav.count,
            1,
            "Mission registrations also ship recipe.fleet.do.return.home under fleet.do.return.* (RTL via catalogue). Update when new return-home recipes land."
        )
    }
}
