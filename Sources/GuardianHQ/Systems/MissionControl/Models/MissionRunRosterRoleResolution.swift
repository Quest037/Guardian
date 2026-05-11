import Foundation

// MARK: - Log template keys

extension MissionRunLogTemplateKey {
    /// MC execution start: summarizes non-`.none` roster behavior roles (slot label → `role_id`).
    static let rosterBehaviorRolesSnapshot = "missioncontrol.mre.roster.behavior_roles_snapshot"
}

// MARK: - Resolved row (MC / MRE envelope slice)

/// One roster device’s behavior role, resolved for Mission Control / MRE (built-in catalog + plugin overlays / plugin full rows).
/// MC code should prefer this over re-walking ``Mission/rosterDevices`` and re-merging overlays ad hoc.
struct ResolvedRosterRole: Equatable, Sendable, Codable {
    /// ``RosterDevice/id``
    var rosterDeviceID: UUID
    /// ``RosterDevice/name`` at resolution time (for logs / export).
    var slotLabel: String
    /// Same as ``RosterDevice/behaviorRoleID`` (stable slug).
    var behaviorRoleID: String
    /// MRE JSON contract payload; `nil` when ``behaviorRoleID`` is the ``RosterRole/none`` slug.
    var mrePayload: RosterRoleMREPayload?
    /// Plugins that contributed overlays or the last catalog row for this slug (sorted at resolution time).
    var contributingPluginIDs: [GuardianPluginID]

    enum CodingKeys: String, CodingKey {
        case rosterDeviceID
        case slotLabel
        case behaviorRoleID
        case mrePayload
        case contributingPluginIDs
        case legacyRole = "role"
    }

    init(
        rosterDeviceID: UUID,
        slotLabel: String,
        behaviorRoleID: String,
        mrePayload: RosterRoleMREPayload?,
        contributingPluginIDs: [GuardianPluginID]
    ) {
        self.rosterDeviceID = rosterDeviceID
        self.slotLabel = slotLabel
        self.behaviorRoleID = behaviorRoleID
        self.mrePayload = mrePayload
        self.contributingPluginIDs = contributingPluginIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rosterDeviceID = try c.decode(UUID.self, forKey: .rosterDeviceID)
        slotLabel = try c.decode(String.self, forKey: .slotLabel)
        if let id = try c.decodeIfPresent(String.self, forKey: .behaviorRoleID) {
            behaviorRoleID = id
        } else if let r = try c.decodeIfPresent(RosterRole.self, forKey: .legacyRole) {
            behaviorRoleID = r.rawValue
        } else {
            behaviorRoleID = RosterRole.none.rawValue
        }
        mrePayload = try c.decodeIfPresent(RosterRoleMREPayload.self, forKey: .mrePayload)
        contributingPluginIDs = try c.decodeIfPresent([GuardianPluginID].self, forKey: .contributingPluginIDs) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rosterDeviceID, forKey: .rosterDeviceID)
        try c.encode(slotLabel, forKey: .slotLabel)
        try c.encode(behaviorRoleID, forKey: .behaviorRoleID)
        try c.encodeIfPresent(mrePayload, forKey: .mrePayload)
        try c.encode(contributingPluginIDs, forKey: .contributingPluginIDs)
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
        let id = device.behaviorRoleID
        let payload = RosterRoleCatalog.mrePayload(forBehaviorRoleID: id)
        let plugins = RosterRoleCatalog.contributingPlugins(forBehaviorRoleID: id)
        return ResolvedRosterRole(
            rosterDeviceID: device.id,
            slotLabel: device.name,
            behaviorRoleID: id,
            mrePayload: payload,
            contributingPluginIDs: plugins
        )
    }

    static func resolution(forRosterDeviceID id: UUID, mission: Mission) -> ResolvedRosterRole? {
        guard let device = mission.rosterDevices.first(where: { $0.id == id }) else { return nil }
        return resolve(device: device)
    }
}
