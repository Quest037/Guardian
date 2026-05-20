import XCTest
@testable import GuardianCore

@MainActor
final class RosterRolePluginCatalogTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        RosterRoleExtensionRegistry._testOnlyReset()
    }

    override func tearDown() async throws {
        RosterRoleExtensionRegistry._testOnlyReset()
        try await super.tearDown()
    }

    func test_register_sameId_lastWriteWins_displayName() throws {
        let pluginA = try GuardianPluginID(validating: "guardian.plugin.roster.lww.a")
        let pluginB = try GuardianPluginID(validating: "guardian.plugin.roster.lww.b")
        let weights = RosterRoleWeights(
            aggression: 0.1, tenacity: 0.2, cohesion: 0.3, roe_slack: 0.4, support_bias: 0.5
        )
        RosterRolePluginCatalog.register(
            RosterRolePluginCatalogEntry(
                id: "plugin.custom.role",
                displayName: "First",
                blurb: "A",
                tags: ["a.tag"],
                weights: weights,
                schemaVersion: 1,
                pluginID: pluginA
            )
        )
        RosterRolePluginCatalog.register(
            RosterRolePluginCatalogEntry(
                id: "plugin.custom.role",
                displayName: "Second",
                blurb: "B",
                tags: ["b.tag"],
                weights: weights,
                schemaVersion: 2,
                pluginID: pluginB
            )
        )
        XCTAssertEqual(RosterRoleCatalog.displayName(forBehaviorRoleID: "plugin.custom.role"), "Second")
        XCTAssertEqual(RosterRoleCatalog.blurb(forBehaviorRoleID: "plugin.custom.role"), "B")
        let payload = try XCTUnwrap(RosterRoleCatalog.mrePayload(forBehaviorRoleID: "plugin.custom.role"))
        XCTAssertTrue(payload.tags.contains("b.tag"))
        XCTAssertFalse(payload.tags.contains("a.tag"))
        XCTAssertEqual(payload.role_schema, 2)
    }

    func test_register_rejectsNoneSlug() throws {
        let plugin = try GuardianPluginID(validating: "guardian.plugin.roster.none.reject")
        let weights = RosterRoleWeights(
            aggression: 0.5, tenacity: 0.5, cohesion: 0.5, roe_slack: 0.5, support_bias: 0.5
        )
        RosterRolePluginCatalog.register(
            RosterRolePluginCatalogEntry(
                id: RosterRole.none.rawValue,
                displayName: "Bad",
                blurb: "",
                tags: [],
                weights: weights,
                schemaVersion: 1,
                pluginID: plugin
            )
        )
        XCTAssertNil(RosterRolePluginCatalog.definition(for: RosterRole.none.rawValue))
    }
}
