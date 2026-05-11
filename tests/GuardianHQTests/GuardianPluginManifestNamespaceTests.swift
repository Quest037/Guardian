import XCTest
@testable import GuardianHQ

final class GuardianPluginManifestNamespaceTests: XCTestCase {

    func test_fleetNamespaceTail_strips_guardian_prefix() {
        XCTAssertEqual(GuardianPluginID.paladin.fleetNamespaceTail, "plugin.paladin")
        XCTAssertEqual(GuardianPluginID.theme.fleetNamespaceTail, "plugin.theme")
    }

    func test_manifest_empty_claims_valid() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test"
        )
        XCTAssertNil(m.namespaceClaimValidationError())
    }

    func test_manifest_command_root_valid() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            publishedCommandNamespaces: ["command.plugin.paladin"]
        )
        XCTAssertNil(m.namespaceClaimValidationError())
    }

    func test_manifest_command_deeper_prefix_valid() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            publishedCommandNamespaces: ["command.plugin.paladin.experimental"]
        )
        XCTAssertNil(m.namespaceClaimValidationError())
    }

    func test_manifest_command_wrong_tree_invalid() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            publishedCommandNamespaces: ["command.fleet.vehicle"]
        )
        XCTAssertNotNil(m.namespaceClaimValidationError())
    }

    func test_manifest_recipe_root_valid() {
        let m = GuardianPluginManifest(
            pluginID: .theme,
            displayName: "Theme",
            shortDescription: "Test",
            publishedRecipeNamespaces: ["recipe.plugin.theme"]
        )
        XCTAssertNil(m.namespaceClaimValidationError())
    }

    func test_manifest_invalid_shape() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            publishedCommandNamespaces: ["fleet.vehicle"]
        )
        XCTAssertNotNil(m.namespaceClaimValidationError())
    }

    func test_manifest_invoked_fleet_command_valid() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            invokedCommandNamespaces: ["command.fleet.vehicle.arm"]
        )
        XCTAssertNil(m.namespaceClaimValidationError())
    }

    func test_manifest_invoked_recipe_valid() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            invokedRecipeNamespaces: ["recipe.fleet.calibrate.compass"]
        )
        XCTAssertNil(m.namespaceClaimValidationError())
    }

    func test_manifest_invoked_command_list_wrong_top_level_invalid() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            invokedCommandNamespaces: ["recipe.fleet.foo"]
        )
        XCTAssertNotNil(m.namespaceClaimValidationError())
    }

    func test_manifest_invoked_recipe_list_wrong_top_level_invalid() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            invokedRecipeNamespaces: ["command.fleet.foo"]
        )
        XCTAssertNotNil(m.namespaceClaimValidationError())
    }

    // MARK: Publish prefix matching (catalogue uses these rules)

    func test_allowsPublishing_command_exactPrefix() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            publishedCommandNamespaces: ["command.plugin.paladin"]
        )
        XCTAssertTrue(m.allowsPublishing(commandRaw: "command.plugin.paladin"))
    }

    func test_allowsPublishing_command_deeperName() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            publishedCommandNamespaces: ["command.plugin.paladin"]
        )
        XCTAssertTrue(m.allowsPublishing(commandRaw: "command.plugin.paladin.do.stagef.catalogue"))
    }

    func test_allowsPublishing_command_rejectsAdjacentPrefixWithoutDot() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            publishedCommandNamespaces: ["command.plugin.paladin"]
        )
        XCTAssertFalse(m.allowsPublishing(commandRaw: "command.plugin.paladinx.do.arm"))
    }

    func test_allowsPublishing_command_emptyClaims() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test"
        )
        XCTAssertFalse(m.allowsPublishing(commandRaw: "command.plugin.paladin.do.arm"))
    }

    func test_allowsPublishing_recipe_deeperName() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            publishedRecipeNamespaces: ["recipe.plugin.paladin"]
        )
        XCTAssertTrue(m.allowsPublishing(recipeRaw: "recipe.plugin.paladin.stagef.catalogue"))
    }

    func test_allowsInvoking_command_prefix() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            invokedCommandNamespaces: ["command.fleet.vehicle"]
        )
        XCTAssertTrue(m.allowsInvoking(commandRaw: "command.fleet.vehicle.do.arm"))
        XCTAssertFalse(m.allowsInvoking(commandRaw: "command.plugin.paladin.do.x"))
    }

    func test_allowsInvoking_recipe_prefix() {
        let m = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Test",
            invokedRecipeNamespaces: ["recipe.fleet.calibrate"]
        )
        XCTAssertTrue(m.allowsInvoking(recipeRaw: "recipe.fleet.calibrate.compass"))
    }

    func test_builtInPaladinManifest_has_empty_fleet_namespace_claim_arrays() {
        let m = GuardianPluginBootstrap.builtInPaladinManifest()
        XCTAssertNil(m.namespaceClaimValidationError())
        XCTAssertEqual(m.publishedCommandNamespaces, [])
        XCTAssertEqual(m.publishedRecipeNamespaces, [])
        XCTAssertEqual(m.invokedCommandNamespaces, [])
        XCTAssertEqual(m.invokedRecipeNamespaces, [])
    }
}
