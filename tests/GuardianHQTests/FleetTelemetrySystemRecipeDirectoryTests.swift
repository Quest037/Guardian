import XCTest
@testable import GuardianCore

/// Stage C coverage for the per-system recipe directory on
/// ``FleetTelemetryFieldCatalog``. The directory is read by the future Vehicle
/// Inspector wizard (Stage E) to render per-system action menus; this suite
/// pins the v1 mapping and the validator that catches authoring typos at app
/// start.
@MainActor
final class FleetTelemetrySystemRecipeDirectoryTests: XCTestCase {

    // MARK: - Per-system lookup

    func test_recipes_forCompass_returnsThreeCalibrateAndOneErrorFix() {
        let entry = FleetTelemetryFieldCatalog.recipes(forSystem: .compass)
        XCTAssertEqual(
            entry.calibrate.map(\.rawValue),
            [
                "recipe.fleet.calibrate.compass",
                "recipe.fleet.calibrate.compass.motor",
                "recipe.fleet.calibrate.compass.declination",
            ]
        )
        XCTAssertEqual(
            entry.errorFix.map(\.rawValue),
            ["recipe.fleet.errors.fix.calibrationrequired"]
        )
    }

    func test_recipes_forAccelerometer_returnsBothPasses() {
        let entry = FleetTelemetryFieldCatalog.recipes(forSystem: .accelerometer)
        XCTAssertEqual(entry.calibrate.map(\.rawValue), ["recipe.fleet.calibrate.accelerometer"])
        XCTAssertEqual(entry.errorFix.map(\.rawValue), ["recipe.fleet.errors.fix.calibrationrequired"])
    }

    func test_recipes_forGyrometer_returnsGyroAndComposite() {
        let entry = FleetTelemetryFieldCatalog.recipes(forSystem: .gyrometer)
        XCTAssertEqual(entry.calibrate.map(\.rawValue), ["recipe.fleet.calibrate.gyro"])
        XCTAssertEqual(entry.errorFix.map(\.rawValue), ["recipe.fleet.errors.fix.calibrationrequired"])
    }

    func test_recipes_forBattery_returnsThreeParamDrivenCalibrationsNoErrorFixYet() {
        let entry = FleetTelemetryFieldCatalog.recipes(forSystem: .battery)
        XCTAssertEqual(
            entry.calibrate.map(\.rawValue),
            [
                "recipe.fleet.calibrate.battery.voltage",
                "recipe.fleet.calibrate.battery.current",
                "recipe.fleet.calibrate.battery.capacity",
            ]
        )
        XCTAssertTrue(entry.errorFix.isEmpty, "Battery has no error-fix recipe in v1.")
    }

    func test_recipes_forBarometer_returnsBaroAndTempCalibration() {
        let entry = FleetTelemetryFieldCatalog.recipes(forSystem: .barometer)
        XCTAssertEqual(
            entry.calibrate.map(\.rawValue),
            [
                "recipe.fleet.calibrate.baro",
                "recipe.fleet.calibrate.baro.temperature",
            ]
        )
    }

    func test_recipes_forRc_returnsRcAndRcTrim() {
        let entry = FleetTelemetryFieldCatalog.recipes(forSystem: .rc)
        XCTAssertEqual(
            entry.calibrate.map(\.rawValue),
            ["recipe.fleet.calibrate.rc", "recipe.fleet.calibrate.rc.trim"]
        )
    }

    func test_recipes_forEkf_returnsLevelAndComposite() {
        let entry = FleetTelemetryFieldCatalog.recipes(forSystem: .ekf)
        XCTAssertEqual(entry.calibrate.map(\.rawValue), ["recipe.fleet.calibrate.level"])
        XCTAssertEqual(entry.errorFix.map(\.rawValue), ["recipe.fleet.errors.fix.calibrationrequired"])
    }

    /// Systems without authored recipes in v1 (passive sensors / derived
    /// estimator state) must still resolve uniformly to `.empty` so callers
    /// don't need to special-case the miss.
    func test_recipes_forSystemsWithoutRecipes_returnEmptyEntry() {
        for system in [
            FleetCalibrationSystemID.gps,
            FleetCalibrationSystemID.localPosition,
            FleetCalibrationSystemID.homePosition,
        ] {
            let entry = FleetTelemetryFieldCatalog.recipes(forSystem: system)
            XCTAssertEqual(entry, FleetTelemetryFieldCatalog.SystemRecipes.empty, "\(system.rawValue) must resolve to .empty.")
        }
    }

    /// Unknown system IDs (string-backed, plugins can mint new ones) must
    /// resolve to `.empty` so Stage E's menu renderer renders nothing rather
    /// than crashing.
    func test_recipes_forUnknownSystemID_returnsEmpty() {
        let unknown = FleetCalibrationSystemID(rawValue: "plugin.example.unknown.system")
        XCTAssertEqual(FleetTelemetryFieldCatalog.recipes(forSystem: unknown), .empty)
    }

    // MARK: - Reference validator

    func test_validate_againstFullyKnownSet_returnsEmpty() {
        // Build the "fully known" set by hand from the directory itself so the
        // test pins the directory's contract independently from whatever the
        // recipes catalogue happens to have registered at the moment.
        var known: Set<FleetRecipeName> = []
        for entry in FleetTelemetryFieldCatalog.systemRecipes.values {
            entry.calibrate.forEach { known.insert($0) }
            entry.errorFix.forEach { known.insert($0) }
        }
        let misses = FleetTelemetryFieldCatalog.validateRecipeReferences(knownRecipes: known)
        XCTAssertTrue(misses.isEmpty, "Directory validates clean against its own citation set; got \(misses).")
    }

    func test_validate_againstEmptySet_reportsEveryCitedRecipe() {
        let misses = FleetTelemetryFieldCatalog.validateRecipeReferences(knownRecipes: [])
        let expectedCount = FleetTelemetryFieldCatalog.systemRecipes.values
            .reduce(0) { $0 + $1.calibrate.count + $1.errorFix.count }
        XCTAssertEqual(misses.count, expectedCount, "Validator must report every citation when no recipes are known.")
    }

    func test_validate_classifiesCalibrateAndErrorFixRoles() {
        let misses = FleetTelemetryFieldCatalog.validateRecipeReferences(knownRecipes: [])
        let compassMisses = misses.filter { $0.system == .compass }

        let calibrateNames = compassMisses
            .filter { $0.role == .calibrate }
            .map(\.recipe.rawValue)
        XCTAssertEqual(
            Set(calibrateNames),
            [
                "recipe.fleet.calibrate.compass",
                "recipe.fleet.calibrate.compass.motor",
                "recipe.fleet.calibrate.compass.declination",
            ]
        )

        let errorFixNames = compassMisses
            .filter { $0.role == .errorFix }
            .map(\.recipe.rawValue)
        XCTAssertEqual(errorFixNames, ["recipe.fleet.errors.fix.calibrationrequired"])
    }

    func test_validate_emitsDeterministicOrderingByName() {
        let misses = FleetTelemetryFieldCatalog.validateRecipeReferences(knownRecipes: [])
        // Sort key is `(system.rawValue, recipe.rawValue)`. Verify the output is
        // already in that order without re-sorting.
        let sorted = misses.sorted { lhs, rhs in
            if lhs.system.rawValue != rhs.system.rawValue {
                return lhs.system.rawValue < rhs.system.rawValue
            }
            return lhs.recipe.rawValue < rhs.recipe.rawValue
        }
        XCTAssertEqual(misses, sorted, "Validator must return misses sorted by (system, recipe) so logs are stable.")
    }

    /// End-to-end coverage of the bootstrap path: after `ensureRegistered()`
    /// runs, every citation in the directory must resolve. A failure here
    /// means the directory or a subsystem registration drifted apart.
    func test_validate_againstLiveBootstrappedCatalogue_returnsEmpty() {
        FleetRecipesCatalogue.shared._testOnlyReset()
        FleetRecipesCatalogueBootstrap._testOnlyResetIdempotencyFlag()
        FleetCommandsCatalogueBootstrap.ensureRegistered()
        FleetRecipesCatalogueBootstrap.ensureRegistered()

        let misses = FleetTelemetryFieldCatalog
            .validateRecipeReferences(against: FleetRecipesCatalogue.shared)
        XCTAssertTrue(
            misses.isEmpty,
            "Directory citations must resolve against the bootstrapped catalogue; got \(misses)."
        )
    }

    // MARK: - Inspector resolver

    /// Resolved descriptor order must match the directory's authored order so
    /// the Vehicle Inspector's `Calibrate` menu lists recipes in a stable,
    /// reviewed sequence rather than dictionary-iteration order.
    func test_resolveDescriptors_preservesAuthoredOrder() {
        bootstrapLiveCatalogue()

        let resolved = FleetTelemetryFieldCatalog.resolveDescriptors(
            forSystem: .compass,
            against: FleetRecipesCatalogue.shared
        )
        XCTAssertEqual(
            resolved.calibrate.map(\.name.rawValue),
            [
                "recipe.fleet.calibrate.compass",
                "recipe.fleet.calibrate.compass.motor",
                "recipe.fleet.calibrate.compass.declination",
            ],
            "Resolver must preserve the directory's authored order."
        )
        XCTAssertEqual(
            resolved.errorFix.map(\.name.rawValue),
            ["recipe.fleet.errors.fix.calibrationrequired"]
        )
    }

    /// Systems the directory marks `.empty` (passive sensors) must surface
    /// `ResolvedSystemRecipes.empty` so the inspector renders its neutral
    /// placeholder rather than empty menus.
    func test_resolveDescriptors_forEmptyDirectorySystem_returnsEmpty() {
        bootstrapLiveCatalogue()

        for system in [
            FleetCalibrationSystemID.gps,
            FleetCalibrationSystemID.localPosition,
            FleetCalibrationSystemID.homePosition,
        ] {
            let resolved = FleetTelemetryFieldCatalog.resolveDescriptors(
                forSystem: system,
                against: FleetRecipesCatalogue.shared
            )
            XCTAssertEqual(resolved, .empty, "\(system.rawValue) must resolve to .empty.")
            XCTAssertTrue(resolved.isEmpty)
        }
    }

    /// Resolver must soft-degrade when a directory citation does not resolve
    /// — bootstrap-time validation has already faulted, the inspector menu
    /// just drops the entry so the rest of the row keeps working.
    func test_resolveDescriptors_dropsUnregisteredCitations() {
        // Reset to an empty catalogue, register only the compass calibrate
        // recipe out of the three the directory cites, then resolve.
        FleetRecipesCatalogue.shared._testOnlyReset()
        FleetRecipesCatalogueBootstrap._testOnlyResetIdempotencyFlag()

        let compassDescriptor = FleetRecipeDescriptor(
            name: .literal("recipe.fleet.calibrate.compass"),
            humanLabel: "Calibrate compass",
            humanDescription: "Stub",
            riskTier: .groundOnly
        )
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(compassDescriptor))

        let resolved = FleetTelemetryFieldCatalog.resolveDescriptors(
            forSystem: .compass,
            against: FleetRecipesCatalogue.shared
        )
        XCTAssertEqual(
            resolved.calibrate.map(\.name.rawValue),
            ["recipe.fleet.calibrate.compass"],
            "Resolver must keep registered citations and drop unregistered ones."
        )
        XCTAssertTrue(
            resolved.errorFix.isEmpty,
            "Unregistered errorFix citation must drop, not surface a synthetic descriptor."
        )
    }

    /// Unknown system IDs (plugin-minted, future systems) must resolve to
    /// `.empty` against the live catalogue. This covers the inspector path
    /// where a plugin contributes a calibration item that the v1 telemetry
    /// directory doesn't know about yet.
    func test_resolveDescriptors_forUnknownSystem_returnsEmpty() {
        bootstrapLiveCatalogue()
        let unknown = FleetCalibrationSystemID(rawValue: "plugin.example.unknown.system")
        let resolved = FleetTelemetryFieldCatalog.resolveDescriptors(
            forSystem: unknown,
            against: FleetRecipesCatalogue.shared
        )
        XCTAssertEqual(resolved, .empty)
    }

    /// Live-catalogue coverage of every system the directory authoritatively
    /// covers — guards against silent regressions in the resolver path
    /// (descriptor wiring, catalogue registration, directory keys) that the
    /// other tests might miss because they isolate one system at a time.
    func test_resolveDescriptors_acrossEverySystem_matchesDirectoryCount() {
        bootstrapLiveCatalogue()

        for (system, entry) in FleetTelemetryFieldCatalog.systemRecipes {
            let resolved = FleetTelemetryFieldCatalog.resolveDescriptors(
                forSystem: system,
                against: FleetRecipesCatalogue.shared
            )
            XCTAssertEqual(
                resolved.calibrate.count,
                entry.calibrate.count,
                "Resolved calibrate count must match directory for \(system.rawValue)."
            )
            XCTAssertEqual(
                resolved.errorFix.count,
                entry.errorFix.count,
                "Resolved errorFix count must match directory for \(system.rawValue)."
            )
        }
    }

    // MARK: - Helpers

    private func bootstrapLiveCatalogue() {
        FleetRecipesCatalogue.shared._testOnlyReset()
        FleetRecipesCatalogueBootstrap._testOnlyResetIdempotencyFlag()
        FleetCommandsCatalogueBootstrap.ensureRegistered()
        FleetRecipesCatalogueBootstrap.ensureRegistered()
    }
}
