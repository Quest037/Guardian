import XCTest
@testable import GuardianCore

/// Stage B1 registration coverage for ``FleetRecipesCatalogue``: name validation,
/// idempotency, composition-depth enforcement, retry-cap enforcement (with the
/// `relaxRetryCaps` opt-out), and namespace-prefix lookup.
@MainActor
final class FleetRecipesCatalogueRegistrationTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        FleetRecipesCatalogue.shared._testOnlyReset()
    }

    // MARK: Helpers

    private func minimalDescriptor(
        name rawName: String,
        contains: [String] = [],
        retry: FleetRecipeRetryPolicy = .catalogueDefault,
        relax: Bool = false
    ) -> FleetRecipeDescriptor {
        FleetRecipeDescriptor(
            name: FleetRecipeName.literal(rawName),
            humanLabel: rawName,
            humanDescription: "Test descriptor for \(rawName)",
            riskTier: .groundOnly,
            defaultRetryPolicy: retry,
            relaxRetryCaps: relax,
            containsRecipes: contains.map { FleetRecipeName.literal($0) }
        )
    }

    // MARK: Happy path

    func test_register_acceptsValidDescriptor() {
        let descriptor = minimalDescriptor(name: "recipe.fleet.calibrate.compass")
        let didRegister = FleetRecipesCatalogue.shared.register(descriptor)
        XCTAssertTrue(didRegister)
        XCTAssertNotNil(FleetRecipesCatalogue.shared.descriptor(for: descriptor.name))
    }

    func test_register_isIdempotent_lastWriteWins() {
        let v1 = minimalDescriptor(name: "recipe.fleet.calibrate.compass")
        let v2 = FleetRecipeDescriptor(
            name: FleetRecipeName.literal("recipe.fleet.calibrate.compass"),
            humanLabel: "Compass — Revised",
            humanDescription: "Second version.",
            riskTier: .groundOnly
        )
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(v1))
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(v2))
        XCTAssertEqual(
            FleetRecipesCatalogue.shared.descriptor(for: v1.name)?.humanLabel,
            "Compass — Revised"
        )
    }

    // MARK: Composition-depth enforcement

    func test_register_rejectsChildThatIsNotYetRegistered() {
        let parent = minimalDescriptor(
            name: "recipe.fleet.calibrate.suite",
            contains: ["recipe.fleet.calibrate.compass"]
        )
        XCTAssertFalse(FleetRecipesCatalogue.shared.register(parent))
        XCTAssertNil(FleetRecipesCatalogue.shared.descriptor(for: parent.name))
    }

    func test_register_acceptsCompositeWhenChildAlreadyRegistered() {
        let child = minimalDescriptor(name: "recipe.fleet.calibrate.compass")
        let parent = minimalDescriptor(
            name: "recipe.fleet.calibrate.suite",
            contains: ["recipe.fleet.calibrate.compass"]
        )
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(child))
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(parent))
    }

    func test_register_rejectsCompositeWhenChildIsAlsoComposite() {
        let leaf = minimalDescriptor(name: "recipe.fleet.calibrate.compass")
        let middle = minimalDescriptor(
            name: "recipe.fleet.calibrate.suite",
            contains: ["recipe.fleet.calibrate.compass"]
        )
        let outer = minimalDescriptor(
            name: "recipe.fleet.calibrate.megasuite",
            contains: ["recipe.fleet.calibrate.suite"]
        )
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(leaf))
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(middle))
        XCTAssertFalse(
            FleetRecipesCatalogue.shared.register(outer),
            "Composition depth must be capped at one level."
        )
    }

    // MARK: Retry-cap enforcement

    func test_register_rejectsDescriptorThatExceedsRetryCaps() {
        let overcap = FleetRecipeRetryPolicy(
            maxAttempts: FleetRecipeRetryPolicy.maxAttemptsCap + 1,
            delaySeconds: 0.25,
            retryableErrorKinds: [.noSession],
            retryOnTimeout: false
        )
        let descriptor = minimalDescriptor(
            name: "recipe.fleet.calibrate.compass",
            retry: overcap,
            relax: false
        )
        XCTAssertFalse(FleetRecipesCatalogue.shared.register(descriptor))
        XCTAssertNil(FleetRecipesCatalogue.shared.descriptor(for: descriptor.name))
    }

    func test_register_acceptsOvercapDescriptorWhenRelaxRetryCapsTrue() {
        let overcap = FleetRecipeRetryPolicy(
            maxAttempts: FleetRecipeRetryPolicy.maxAttemptsCap + 1,
            delaySeconds: 0.25,
            retryableErrorKinds: [.noSession],
            retryOnTimeout: false
        )
        let descriptor = minimalDescriptor(
            name: "recipe.fleet.calibrate.compass",
            retry: overcap,
            relax: true
        )
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(descriptor))
        XCTAssertNotNil(FleetRecipesCatalogue.shared.descriptor(for: descriptor.name))
    }

    // MARK: Lookup

    func test_lookup_byRawValue_acceptsValidStringsAndRejectsInvalid() {
        let descriptor = minimalDescriptor(name: "recipe.fleet.calibrate.compass")
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(descriptor))

        XCTAssertNotNil(
            FleetRecipesCatalogue.shared.descriptor(forRawValue: "recipe.fleet.calibrate.compass")
        )
        XCTAssertNil(
            FleetRecipesCatalogue.shared.descriptor(forRawValue: "recipe.fleet.calibrate.unknown")
        )
        XCTAssertNil(
            FleetRecipesCatalogue.shared.descriptor(forRawValue: "command.fleet.vehicle.do.arm")
        )
    }

    func test_lookup_byPrefix_filtersByNamespacePath() {
        let compass = minimalDescriptor(name: "recipe.fleet.calibrate.compass")
        let accel = minimalDescriptor(name: "recipe.fleet.calibrate.accelerometer")
        let armprobe = minimalDescriptor(name: "recipe.fleet.diagnose.armprobe")
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(compass))
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(accel))
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(armprobe))

        let calibrate = FleetRecipesCatalogue.shared
            .descriptors(underNamespacePrefix: ["fleet", "calibrate"])
            .map(\.name.rawValue)
            .sorted()
        XCTAssertEqual(
            calibrate,
            [
                "recipe.fleet.calibrate.accelerometer",
                "recipe.fleet.calibrate.compass",
            ]
        )

        let allFleet = FleetRecipesCatalogue.shared
            .descriptors(underNamespacePrefix: ["fleet"])
            .map(\.name.rawValue)
            .sorted()
        XCTAssertEqual(allFleet.count, 3)
    }

    // MARK: Test-only reset hygiene

    func test_testOnlyReset_clearsAllRegistrations() {
        let descriptor = minimalDescriptor(name: "recipe.fleet.calibrate.compass")
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(descriptor))
        FleetRecipesCatalogue.shared._testOnlyReset()
        XCTAssertNil(FleetRecipesCatalogue.shared.descriptor(for: descriptor.name))
    }
}
