import Foundation

// MARK: - Log template keys

extension MissionRunLogTemplateKey {
    /// MC execution start: summarizes non-`.none` roster behavior roles (slot label → `role_id`).
    static let rosterBehaviorRolesSnapshot = "missioncontrol.mre.roster.behavior_roles_snapshot"
}

// MARK: - Resolved row (MC / MRE envelope slice)

/// One roster device’s behavior role, resolved for Mission Control / MRE (built-in catalog + plugin overlays).
/// MC code should prefer this over re-walking ``Mission/rosterDevices`` and re-merging overlays ad hoc.
struct ResolvedRosterRole: Equatable, Sendable, Codable {
    /// ``RosterDevice/id``
    var rosterDeviceID: UUID
    /// ``RosterDevice/name`` at resolution time (for logs / export).
    var slotLabel: String
    var role: RosterRole
    /// MRE JSON contract payload; `nil` when ``role`` is ``RosterRole/none``.
    var mrePayload: RosterRoleMREPayload?
    /// Plugins that contributed overlays for this role (sorted at resolution time).
    var contributingPluginIDs: [GuardianPluginID]

    enum CodingKeys: String, CodingKey {
        case rosterDeviceID
        case slotLabel
        case role
        case mrePayload
        case contributingPluginIDs
    }
}

// MARK: - Resolver

@MainActor
enum MissionRunRosterRoleResolver {

    /// Resolves every device on the mission roster (including `.none` rows for completeness).
    static func resolutions(for mission: Mission) -> [UUID: ResolvedRosterRole] {
        Dictionary(uniqueKeysWithValues: mission.rosterDevices.map { device in
            (device.id, resolve(device: device))
        })
    }

    static func resolve(device: RosterDevice) -> ResolvedRosterRole {
        let payload = RosterRoleCatalog.mrePayload(for: device.role)
        let plugins = RosterRoleExtensionRegistry.resolvedDefinition(for: device.role)?.contributingPluginIDs ?? []
        return ResolvedRosterRole(
            rosterDeviceID: device.id,
            slotLabel: device.name,
            role: device.role,
            mrePayload: payload,
            contributingPluginIDs: plugins
        )
    }

    static func resolution(forRosterDeviceID id: UUID, mission: Mission) -> ResolvedRosterRole? {
        guard let device = mission.rosterDevices.first(where: { $0.id == id }) else { return nil }
        return resolve(device: device)
    }
}
