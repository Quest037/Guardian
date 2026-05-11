import XCTest
@testable import GuardianHQ

@MainActor
final class RosterRoleExtensionRegistryTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        RosterRoleExtensionRegistry._testOnlyReset()
    }

    override func tearDown() async throws {
        RosterRoleExtensionRegistry._testOnlyReset()
        try await super.tearDown()
    }

    func test_twoPlugins_overlaySameRole_mergeTagsAndCapWeightDeltas() throws {
        let pluginA = try GuardianPluginID(validating: "guardian.plugin.roster.merge.a")
        let pluginB = try GuardianPluginID(validating: "guardian.plugin.roster.merge.b")

        RosterRoleExtensionRegistry.registerOverlay(
            RosterRolePluginOverlay(
                pluginID: pluginA,
                targetRole: .medic,
                additiveTags: ["plugin.merge.a.tag"],
                weightDeltas: RosterRoleWeightDeltas(
                    aggression: 0.20,
                    tenacity: nil,
                    cohesion: nil,
                    roe_slack: nil,
                    support_bias: nil
                )
            )
        )
        RosterRoleExtensionRegistry.registerOverlay(
            RosterRolePluginOverlay(
                pluginID: pluginB,
                targetRole: .medic,
                additiveTags: ["plugin.merge.b.tag"],
                weightDeltas: RosterRoleWeightDeltas(
                    aggression: 0.20,
                    tenacity: nil,
                    cohesion: nil,
                    roe_slack: nil,
                    support_bias: nil
                )
            )
        )

        let resolved = try XCTUnwrap(RosterRoleExtensionRegistry.resolvedDefinition(for: .medic))
        XCTAssertTrue(resolved.tags.contains("recovery.primary"), "Built-in tags preserved")
        XCTAssertTrue(resolved.tags.contains("plugin.merge.a.tag"))
        XCTAssertTrue(resolved.tags.contains("plugin.merge.b.tag"))
        XCTAssertEqual(Set(resolved.contributingPluginIDs), Set([pluginA, pluginB]))

        // Base medic aggression 0.2; sum of deltas 0.4 clamped to 0.25 → 0.45
        XCTAssertEqual(resolved.weights.aggression, 0.45, accuracy: 0.0001)
        XCTAssertEqual(resolved.weights.support_bias, 0.95, accuracy: 0.0001)

        let payload = try XCTUnwrap(RosterRoleCatalog.mrePayload(for: .medic))
        XCTAssertTrue(payload.tags.contains("plugin.merge.a.tag"))
        XCTAssertTrue(payload.tags.contains("plugin.merge.b.tag"))
        XCTAssertEqual(payload.weights.aggression, 0.45, accuracy: 0.0001)
    }

    func test_registerOverlay_samePluginReplacesPrior() throws {
        let pluginA = try GuardianPluginID(validating: "guardian.plugin.roster.replace.a")

        RosterRoleExtensionRegistry.registerOverlay(
            RosterRolePluginOverlay(
                pluginID: pluginA,
                targetRole: .scout,
                additiveTags: ["first.tag"],
                weightDeltas: nil
            )
        )
        RosterRoleExtensionRegistry.registerOverlay(
            RosterRolePluginOverlay(
                pluginID: pluginA,
                targetRole: .scout,
                additiveTags: ["second.tag"],
                weightDeltas: nil
            )
        )

        let resolved = try XCTUnwrap(RosterRoleExtensionRegistry.resolvedDefinition(for: .scout))
        XCTAssertFalse(resolved.tags.contains("first.tag"))
        XCTAssertTrue(resolved.tags.contains("second.tag"))
        XCTAssertEqual(resolved.contributingPluginIDs, [pluginA])
    }
}
