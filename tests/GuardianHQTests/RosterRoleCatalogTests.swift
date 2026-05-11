import XCTest
@testable import GuardianHQ

@MainActor
final class RosterRoleCatalogTests: XCTestCase {

    func test_builtInRoles_haveDefinitionsExceptNone() {
        for role in RosterRole.allCases where role != .none {
            XCTAssertNotNil(
                RosterRoleCatalog.definition(for: role),
                "Missing catalog definition for \(role.rawValue)"
            )
        }
        XCTAssertNil(RosterRoleCatalog.definition(for: .none))
    }

    func test_tags_nonEmpty_forEachBehaviorRole() {
        for role in RosterRole.allCases where role != .none {
            let tags = RosterRoleCatalog.definition(for: role)!.tags
            XCTAssertFalse(tags.isEmpty, role.rawValue)
        }
    }

    func test_weights_clamped() {
        for role in RosterRole.allCases where role != .none {
            let w = RosterRoleCatalog.definition(for: role)!.weights
            for key in [w.aggression, w.tenacity, w.cohesion, w.roe_slack, w.support_bias] {
                XCTAssertGreaterThanOrEqual(key, 0)
                XCTAssertLessThanOrEqual(key, 1)
            }
        }
    }

    func test_mrePayload_nilForNone() {
        XCTAssertNil(RosterRoleCatalog.mrePayload(for: .none))
    }

    func test_mrePayload_roundTripsJSON() throws {
        let payload = try XCTUnwrap(RosterRoleCatalog.mrePayload(for: .medic))
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(RosterRoleMREPayload.self, from: data)
        XCTAssertEqual(decoded.role_schema, RosterRoleCatalog.schemaVersion)
        XCTAssertEqual(decoded.role_id, "medic")
        XCTAssertTrue(decoded.tags.contains("recovery.primary"))
        XCTAssertEqual(decoded.weights.support_bias, 0.95, accuracy: 0.0001)
    }

    func test_rosterDevice_decode_unknownRole_preservesSlug() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"A","role":"future.plugin.role","slot":"primary","vehicleClass":"unknown"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let device = try JSONDecoder().decode(RosterDevice.self, from: data)
        XCTAssertEqual(device.behaviorRoleID, "future.plugin.role")
    }

    func test_rosterDevice_decode_knownRole() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000002","name":"B","role":"warden","slot":"wingman","vehicleClass":"unknown"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let device = try JSONDecoder().decode(RosterDevice.self, from: data)
        XCTAssertEqual(device.behaviorRoleID, "warden")
    }
}
