import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunRosterRoleResolutionTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        RosterRoleExtensionRegistry._testOnlyReset()
    }

    override func tearDown() async throws {
        RosterRoleExtensionRegistry._testOnlyReset()
        try await super.tearDown()
    }

    func test_resolutions_mapsDevicesAndMrePayload() {
        let idMedic = UUID()
        let idNone = UUID()
        var mission = Mission(name: "Roster test", description: "", type: .mobile)
        mission.rosterDevices = [
            RosterDevice(id: idMedic, name: "Lead", role: .medic, slot: .primary),
            RosterDevice(id: idNone, name: "Reserve", role: .none, slot: .reserve),
        ]
        let map = MissionRunRosterRoleResolver.resolutions(for: mission)
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map[idMedic]?.mrePayload?.role_id, "medic")
        XCTAssertTrue(map[idMedic]?.mrePayload?.tags.contains("recovery.primary") == true)
        XCTAssertNil(map[idNone]?.mrePayload)
        XCTAssertEqual(map[idNone]?.role, RosterRole.none)
    }

    func test_resolutions_includesMergedPluginTagsInMrePayload() throws {
        let plugin = try GuardianPluginID(validating: "guardian.plugin.roster.mc.test")
        RosterRoleExtensionRegistry.registerOverlay(
            RosterRolePluginOverlay(
                pluginID: plugin,
                targetRole: .scout,
                additiveTags: ["plugin.mc.probe.extra"],
                weightDeltas: nil
            )
        )
        var mission = Mission(name: "Overlay test", description: "", type: .mobile)
        let rid = UUID()
        mission.rosterDevices = [RosterDevice(id: rid, name: "S", role: .scout, slot: .primary)]
        let resolved = try XCTUnwrap(MissionRunRosterRoleResolver.resolution(forRosterDeviceID: rid, mission: mission))
        XCTAssertTrue(resolved.mrePayload?.tags.contains("plugin.mc.probe.extra") == true)
        XCTAssertEqual(resolved.contributingPluginIDs, [plugin])
    }

    func test_resolvedRosterRole_roundTripsCodable() throws {
        var mission = Mission(name: "Codable", description: "", type: .mobile)
        let rid = UUID()
        mission.rosterDevices = [RosterDevice(id: rid, name: "W", role: .warden, slot: .primary)]
        let original = try XCTUnwrap(MissionRunRosterRoleResolver.resolution(forRosterDeviceID: rid, mission: mission))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ResolvedRosterRole.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
