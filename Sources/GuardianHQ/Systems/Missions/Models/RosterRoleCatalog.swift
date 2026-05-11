import Foundation

// MARK: - Source

/// Where a ``RosterRoleDefinition`` came from. Built-in rows use ``builtin``; plugin-sourced **full** rows use ``plugin`` (overlays use ``RosterRoleExtensionRegistry`` and merge into ``RosterRoleResolvedDefinition``).
enum RosterRoleDefinitionSource: String, Codable, Equatable, Sendable {
    case builtin
    case plugin
}

// MARK: - Weights (MRE blending knobs, 0…1)

/// Default weight knobs for Paladin / MRE policy blending (see README — Mission roster behavior roles).
struct RosterRoleWeights: Codable, Equatable, Sendable {
    var aggression: Double
    var tenacity: Double
    var cohesion: Double
    var roe_slack: Double
    var support_bias: Double

    init(
        aggression: Double,
        tenacity: Double,
        cohesion: Double,
        roe_slack: Double,
        support_bias: Double
    ) {
        self.aggression = Self.clamp(aggression)
        self.tenacity = Self.clamp(tenacity)
        self.cohesion = Self.clamp(cohesion)
        self.roe_slack = Self.clamp(roe_slack)
        self.support_bias = Self.clamp(support_bias)
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

// MARK: - MRE payload (JSON contract §7)

/// Versioned payload for Mission Control / MRE (see README — Mission roster behavior roles). Encode with `JSONEncoder`.
struct RosterRoleMREPayload: Codable, Equatable, Sendable {
    /// Bump when tag or weight semantics change.
    var role_schema: Int
    var role_id: String
    var tags: [String]
    var weights: RosterRoleWeights

    enum CodingKeys: String, CodingKey {
        case role_schema
        case role_id
        case tags
        case weights
    }
}

// MARK: - Definition

/// One catalog row: UI copy + machine tags + weights.
struct RosterRoleDefinition: Equatable, Sendable, Codable {
    /// Matches ``RosterRole/rawValue`` for built-ins.
    let role: RosterRole
    let displayName: String
    let blurb: String
    let tags: [String]
    let weights: RosterRoleWeights
    let schemaVersion: Int
    let source: RosterRoleDefinitionSource

    /// Sorted tags for stable JSON and tests.
    var sortedTags: [String] { tags.sorted() }
}

// MARK: - Catalog

/// Built-in roster behavior roles for mission templates (see README — Mission roster behavior roles).
enum RosterRoleCatalog {

    /// Catalog revision; increment when tag/weight meaning changes.
    static let schemaVersion: Int = 1

    private static let definitionsByRole: [RosterRole: RosterRoleDefinition] = {
        var map: [RosterRole: RosterRoleDefinition] = [:]
        for def in builtInDefinitions {
            map[def.role] = def
        }
        return map
    }()

    /// Built-in definitions only (excludes ``RosterRole/none``).
    static let builtInDefinitions: [RosterRoleDefinition] = [
        RosterRoleDefinition(
            role: .guardian,
            displayName: "Guardian",
            blurb: "Defend / screen a designated asset or choke; hold ground over pursuit.",
            tags: [
                "posture.defensive", "risk.low", "engage.retain", "formation.anchor_bias", "recovery.cover", "roe.conservative",
            ],
            weights: RosterRoleWeights(
                aggression: 0.25, tenacity: 0.75, cohesion: 0.70, roe_slack: 0.20, support_bias: 0.55
            ),
            schemaVersion: schemaVersion,
            source: .builtin
        ),
        RosterRoleDefinition(
            role: .scout,
            displayName: "Scout",
            blurb: "Sense forward; prefer evasion, early exit, and report-before-commit.",
            tags: [
                "posture.probe", "risk.medium", "engage.avoid", "sensor.forward", "formation.loose", "comms.report_first",
            ],
            weights: RosterRoleWeights(
                aggression: 0.25, tenacity: 0.35, cohesion: 0.40, roe_slack: 0.30, support_bias: 0.35
            ),
            schemaVersion: schemaVersion,
            source: .builtin
        ),
        RosterRoleDefinition(
            role: .marauder,
            displayName: "Marauder",
            blurb: "Strike / pressure; accept exposure for decisive effect.",
            tags: [
                "posture.offensive", "risk.high", "engage.press", "formation.aggressive_slot", "roe.proportional",
            ],
            weights: RosterRoleWeights(
                aggression: 0.85, tenacity: 0.65, cohesion: 0.45, roe_slack: 0.55, support_bias: 0.20
            ),
            schemaVersion: schemaVersion,
            source: .builtin
        ),
        RosterRoleDefinition(
            role: .relay,
            displayName: "Relay",
            blurb: "Extend link and awareness; favor geometry that keeps the stack connected.",
            tags: [
                "posture.support", "risk.low", "comms.mesh", "logistics.bridge", "formation.station_keep",
            ],
            weights: RosterRoleWeights(
                aggression: 0.20, tenacity: 0.45, cohesion: 0.50, roe_slack: 0.25, support_bias: 0.45
            ),
            schemaVersion: schemaVersion,
            source: .builtin
        ),
        RosterRoleDefinition(
            role: .shepherd,
            displayName: "Shepherd",
            blurb: "Formation integrity; keep squad inside timing and spacing envelopes.",
            tags: [
                "posture.support", "risk.low", "formation.tight", "engage.coordinate", "logistics.sync",
            ],
            weights: RosterRoleWeights(
                aggression: 0.35, tenacity: 0.55, cohesion: 0.90, roe_slack: 0.30, support_bias: 0.55
            ),
            schemaVersion: schemaVersion,
            source: .builtin
        ),
        RosterRoleDefinition(
            role: .warden,
            displayName: "Warden",
            blurb: "Overwatch + RoE bias; deconflict and throttle until the picture is clean.",
            tags: [
                "posture.overwatch", "risk.medium", "roe.strict", "engage.deconflict", "sensor.wide", "formation.flex",
            ],
            weights: RosterRoleWeights(
                aggression: 0.35, tenacity: 0.50, cohesion: 0.55, roe_slack: 0.15, support_bias: 0.45
            ),
            schemaVersion: schemaVersion,
            source: .builtin
        ),
        RosterRoleDefinition(
            role: .breacher,
            displayName: "Breacher",
            blurb: "Vanguard through hazard; clear corridor for the main body.",
            tags: [
                "posture.vanguard", "risk.high", "engage.commit", "formation.lead", "recovery.expendable_order",
            ],
            weights: RosterRoleWeights(
                aggression: 0.88, tenacity: 0.70, cohesion: 0.40, roe_slack: 0.45, support_bias: 0.25
            ),
            schemaVersion: schemaVersion,
            source: .builtin
        ),
        RosterRoleDefinition(
            role: .medic,
            displayName: "Medic",
            blurb: "Recover / sustain; escort, cover, and degraded-wingman support over scoring.",
            tags: [
                "posture.support", "recovery.primary", "risk.medium", "engage.minimize", "formation.escort", "logistics.sustain",
            ],
            weights: RosterRoleWeights(
                aggression: 0.20, tenacity: 0.60, cohesion: 0.75, roe_slack: 0.25, support_bias: 0.95
            ),
            schemaVersion: schemaVersion,
            source: .builtin
        ),
    ]

    static func definition(for role: RosterRole) -> RosterRoleDefinition? {
        guard role != .none else { return nil }
        return definitionsByRole[role]
    }

    /// Neutral weights when a device references an id with no catalog row (still emit ``RosterRoleMREPayload`` for traceability).
    private static let orphanWeights = RosterRoleWeights(
        aggression: 0.5, tenacity: 0.5, cohesion: 0.5, roe_slack: 0.5, support_bias: 0.5
    )

    @MainActor
    static func displayName(forBehaviorRoleID id: String) -> String {
        if id == RosterRole.none.rawValue { return "None" }
        if let row = RosterRolePluginCatalog.definition(for: id) { return row.displayName }
        if let r = RosterRole(rawValue: id), let def = definition(for: r) { return def.displayName }
        return id
    }

    @MainActor
    static func blurb(forBehaviorRoleID id: String) -> String? {
        if let row = RosterRolePluginCatalog.definition(for: id) { return row.blurb }
        if let r = RosterRole(rawValue: id) { return r.rosterCatalogBlurb }
        return nil
    }

    /// Built-in enum order, then plugin-only ids (not matching any ``RosterRole`` case), sorted.
    @MainActor
    static func missionUIPickerBehaviorRoleIDs() -> [String] {
        var ids = RosterRole.allCases.map(\.rawValue)
        let builtinSet = Set(ids)
        let extras = RosterRolePluginCatalog.allRegisteredIDs.filter { builtinSet.contains($0) == false }
        ids.append(contentsOf: extras.sorted())
        return ids
    }

    /// Reference drawer / docs: `none` first, then remaining ids sorted.
    @MainActor
    static func behaviorRoleReferenceOrderedIDs() -> [String] {
        var set = Set(RosterRole.allCases.map(\.rawValue))
        set.formUnion(RosterRolePluginCatalog.allRegisteredIDs)
        let rest = set.filter { $0 != RosterRole.none.rawValue }.sorted()
        return [RosterRole.none.rawValue] + rest
    }

    @MainActor
    static func contributingPlugins(forBehaviorRoleID id: String) -> [GuardianPluginID] {
        if let row = RosterRolePluginCatalog.definition(for: id) { return [row.pluginID] }
        if let r = RosterRole(rawValue: id), r != .none {
            return RosterRoleExtensionRegistry.resolvedDefinition(for: r)?.contributingPluginIDs ?? []
        }
        return []
    }

    /// Machine payload for MRE; `nil` only for ``RosterRole/none`` slug.
    ///
    /// **Precedence:** ``RosterRolePluginCatalog`` row for ``id`` (last write wins) overrides built-in + overlay merge
    /// for the same slug; otherwise built-in catalog + ``RosterRoleExtensionRegistry`` overlays; otherwise an orphan row.
    @MainActor
    static func mrePayload(forBehaviorRoleID id: String) -> RosterRoleMREPayload? {
        guard id != RosterRole.none.rawValue else { return nil }
        if let pluginRow = RosterRolePluginCatalog.definition(for: id) {
            return RosterRoleMREPayload(
                role_schema: pluginRow.schemaVersion,
                role_id: id,
                tags: pluginRow.sortedTags,
                weights: pluginRow.weights
            )
        }
        if let r = RosterRole(rawValue: id), r != .none,
           let resolved = RosterRoleExtensionRegistry.resolvedDefinition(for: r) {
            return RosterRoleMREPayload(
                role_schema: resolved.schemaVersion,
                role_id: id,
                tags: resolved.sortedTags,
                weights: resolved.weights
            )
        }
        return RosterRoleMREPayload(
            role_schema: schemaVersion,
            role_id: id,
            tags: [],
            weights: orphanWeights
        )
    }

    /// Machine payload for MRE / Paladin; `nil` when role is ``RosterRole/none``.
    /// Tags and weights follow ``mrePayload(forBehaviorRoleID:)`` precedence (plugin catalog wins on slug collision).
    @MainActor
    static func mrePayload(for role: RosterRole) -> RosterRoleMREPayload? {
        mrePayload(forBehaviorRoleID: role.rawValue)
    }
}

extension RosterRole {
    /// Picker / badge title (includes **None** for ``RosterRole/none``).
    var rosterCatalogDisplayName: String {
        if self == .none { return "None" }
        return RosterRoleCatalog.definition(for: self)?.displayName ?? rawValue.capitalized
    }

    /// Tooltip / inspector copy.
    var rosterCatalogBlurb: String? {
        RosterRoleCatalog.definition(for: self)?.blurb
    }
}
