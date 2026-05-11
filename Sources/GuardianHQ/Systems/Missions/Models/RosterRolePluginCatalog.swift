import Foundation

/// One plugin-registered **full** roster behavior catalog row (open `role_id`). Re-registering the same
/// ``id`` from any plugin replaces the previous entry (**last write wins**).
struct RosterRolePluginCatalogEntry: Equatable, Sendable {
    let id: String
    let displayName: String
    let blurb: String
    let tags: [String]
    let weights: RosterRoleWeights
    let schemaVersion: Int
    /// Plugin that performed the last successful ``RosterRolePluginCatalog/register`` for this ``id``.
    let pluginID: GuardianPluginID

    var sortedTags: [String] { Array(Set(tags)).sorted() }
}

/// Plugin-owned behavior role definitions keyed by stable ``RosterRolePluginCatalogEntry/id``.
///
/// Built-in enum roles stay in ``RosterRoleCatalog`` unless a plugin registers the same ``id`` here,
/// in which case this registry wins for display + MRE payload (see ``RosterRoleCatalog/mrePayload(forBehaviorRoleID:)``).
@MainActor
enum RosterRolePluginCatalog {

    private static var rowsByID: [String: RosterRolePluginCatalogEntry] = [:]

    /// Replaces any prior row with the same ``entry/id`` (including from another plugin).
    static func register(_ entry: RosterRolePluginCatalogEntry) {
        guard entry.id != RosterRole.none.rawValue else { return }
        rowsByID[entry.id] = entry
    }

    static func definition(for id: String) -> RosterRolePluginCatalogEntry? {
        rowsByID[id]
    }

    static var allRegisteredIDs: [String] {
        rowsByID.keys.sorted()
    }

    static func _testOnlyReset() {
        rowsByID = [:]
    }
}
