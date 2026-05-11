import XCTest
@testable import GuardianHQ

/// Stage F: plugin-owned fleet descriptors must match ``GuardianPluginManifest`` publish claims.
@MainActor
final class PluginNamespaceCatalogueRegistrationTests: XCTestCase {

    private var savedPaladinManifest: GuardianPluginManifest?

    override func setUp() async throws {
        try await super.setUp()
        GuardianPluginBootstrap.ensureRegistered()
        savedPaladinManifest = GuardianPluginRegistry.shared.manifest(for: .paladin)
    }

    override func tearDown() async throws {
        if let savedPaladinManifest {
            GuardianPluginRegistry.shared.ingestBuiltInRegistration(
                manifest: savedPaladinManifest,
                sidebarItems: []
            )
        }
        savedPaladinManifest = nil
        try await super.tearDown()
    }

    func test_commands_register_rejectsPluginOwnedCommandOutsidePublishTree() {
        let token = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let name = "command.fleet.vehicle.do.stagef.outsidetree.\(token)"
        let descriptor = FleetCommandDescriptor(
            name: FleetCommandName.literal(name),
            humanLabel: "Stage F probe",
            humanDescription: "Test",
            declaredResponseKinds: .standardDo,
            riskTier: .safeInLiveMission,
            pluginID: .paladin
        )
        XCTAssertFalse(
            FleetCommandsCatalogue.shared.register(descriptor),
            "Paladin publish claims are under command.plugin.paladin; fleet-shaped names must be rejected."
        )
    }

    func test_commands_register_acceptsWhenManifestClaimCoversName() {
        let suffix = Self.uniquePaladinCommandRaw(suffix: "ok")
        GuardianPluginRegistry.shared.ingestBuiltInRegistration(
            manifest: GuardianPluginManifest(
                pluginID: .paladin,
                displayName: "Paladin",
                shortDescription: "Mission Control assistant: execution handoff, prompts, and Paladin-authored log lines.",
                publishedCommandNamespaces: ["command.plugin.paladin"]
            ),
            sidebarItems: []
        )
        defer {
            if let savedPaladinManifest {
                GuardianPluginRegistry.shared.ingestBuiltInRegistration(
                    manifest: savedPaladinManifest,
                    sidebarItems: []
                )
            }
        }
        let descriptor = FleetCommandDescriptor(
            name: FleetCommandName.literal(suffix),
            humanLabel: "Stage F probe",
            humanDescription: "Test",
            declaredResponseKinds: .standardDo,
            riskTier: .safeInLiveMission,
            pluginID: .paladin
        )
        XCTAssertTrue(FleetCommandsCatalogue.shared.register(descriptor))
    }

    func test_commands_register_rejectsWhenNameOutsideClaim() {
        GuardianPluginRegistry.shared.ingestBuiltInRegistration(
            manifest: GuardianPluginManifest(
                pluginID: .paladin,
                displayName: "Paladin",
                shortDescription: "Test",
                publishedCommandNamespaces: ["command.plugin.paladin.experimental"]
            ),
            sidebarItems: []
        )
        let descriptor = FleetCommandDescriptor(
            name: FleetCommandName.literal("command.plugin.paladin.do.outside"),
            humanLabel: "Wrong branch",
            humanDescription: "Test",
            declaredResponseKinds: .standardDo,
            riskTier: .safeInLiveMission,
            pluginID: .paladin
        )
        XCTAssertFalse(FleetCommandsCatalogue.shared.register(descriptor))
    }

    func test_recipes_register_rejectsPluginOwnedRecipeOutsidePublishTree() {
        FleetRecipesCatalogue.shared._testOnlyReset()
        let token = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let name = "recipe.fleet.test.paladinpublishreject.\(token)"
        let descriptor = FleetRecipeDescriptor(
            name: FleetRecipeName.literal(name),
            humanLabel: "Stage F probe",
            humanDescription: "Test",
            riskTier: .groundOnly,
            pluginID: .paladin
        )
        XCTAssertFalse(FleetRecipesCatalogue.shared.register(descriptor))
    }

    func test_recipes_register_acceptsWhenManifestClaimCoversName() {
        FleetRecipesCatalogue.shared._testOnlyReset()
        let suffix = Self.uniquePaladinRecipeRaw(suffix: "ok")
        GuardianPluginRegistry.shared.ingestBuiltInRegistration(
            manifest: GuardianPluginManifest(
                pluginID: .paladin,
                displayName: "Paladin",
                shortDescription: "Mission Control assistant: execution handoff, prompts, and Paladin-authored log lines.",
                publishedRecipeNamespaces: ["recipe.plugin.paladin"]
            ),
            sidebarItems: []
        )
        defer {
            if let savedPaladinManifest {
                GuardianPluginRegistry.shared.ingestBuiltInRegistration(
                    manifest: savedPaladinManifest,
                    sidebarItems: []
                )
            }
        }
        let descriptor = FleetRecipeDescriptor(
            name: FleetRecipeName.literal(suffix),
            humanLabel: "Stage F probe",
            humanDescription: "Test",
            riskTier: .groundOnly,
            pluginID: .paladin
        )
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(descriptor))
    }

    private static func uniquePaladinCommandRaw(suffix: String) -> String {
        let token = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        return "command.plugin.paladin.do.stagef.\(suffix).\(token)"
    }

    private static func uniquePaladinRecipeRaw(suffix: String) -> String {
        let token = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        return "recipe.plugin.paladin.stagef.\(suffix).\(token)"
    }
}
