import Foundation

// MARK: - Weight deltas (plugin overlays)

/// Optional per-knob deltas applied on top of the built-in row. Sums from all overlays are clamped
/// to ``maxAbsTotalDeltaPerKnob`` before being added to the base weight, then the result is clamped to 0…1.
struct RosterRoleWeightDeltas: Equatable, Sendable {
    var aggression: Double?
    var tenacity: Double?
    var cohesion: Double?
    var roe_slack: Double?
    var support_bias: Double?

    /// Cap on the combined delta from all plugins for a single knob (`RosterRolesToDo.md` §8).
    static let maxAbsTotalDeltaPerKnob: Double = 0.25

    var hasAnyDelta: Bool {
        [aggression, tenacity, cohesion, roe_slack, support_bias].contains { $0 != nil }
    }
}

// MARK: - Overlay

/// One plugin’s additive contribution to a built-in ``RosterRole``. Re-registering the same
/// ``pluginID`` + ``targetRole`` replaces the previous overlay from that plugin.
struct RosterRolePluginOverlay: Equatable, Sendable {
    let pluginID: GuardianPluginID
    let targetRole: RosterRole
    let additiveTags: [String]
    let weightDeltas: RosterRoleWeightDeltas?
}

// MARK: - Resolved row (built-in + merged overlays)

/// Effective catalog row after applying registered plugin overlays (tags union, bounded weight deltas).
struct RosterRoleResolvedDefinition: Equatable, Sendable {
    let role: RosterRole
    let displayName: String
    let blurb: String
    let tags: [String]
    let weights: RosterRoleWeights
    let schemaVersion: Int
    /// Plugins that contributed a non-empty overlay (sorted by ``GuardianPluginID/rawValue``).
    let contributingPluginIDs: [GuardianPluginID]

    var sortedTags: [String] { Array(Set(tags)).sorted() }
}

// MARK: - Registry

/// Built-in plugins register roster behavior overlays here during ``GuardianPluginBootstrap/ensureRegistered()``
/// (or tests). ``RosterRoleCatalog/mrePayload(for:)`` uses merged tags and weights; UI display names stay
/// built-in unless a future phase adds copy overrides.
@MainActor
enum RosterRoleExtensionRegistry {

    private static var overlaysByRole: [RosterRole: [RosterRolePluginOverlay]] = [:]

    /// Replaces any prior overlay from ``overlay.pluginID`` for ``overlay.targetRole``.
    static func registerOverlay(_ overlay: RosterRolePluginOverlay) {
        guard overlay.targetRole != .none else { return }
        var list = overlaysByRole[overlay.targetRole] ?? []
        list.removeAll { $0.pluginID == overlay.pluginID }
        list.append(overlay)
        overlaysByRole[overlay.targetRole] = list
    }

    /// Built-in base plus merged overlays for ``role``. `nil` for ``RosterRole/none`` or unknown roles.
    static func resolvedDefinition(for role: RosterRole) -> RosterRoleResolvedDefinition? {
        guard role != .none, let base = RosterRoleCatalog.definition(for: role) else { return nil }
        let overlays = (overlaysByRole[role] ?? []).sorted { $0.pluginID.rawValue < $1.pluginID.rawValue }

        var tagSet = Set(base.tags)
        for o in overlays {
            tagSet.formUnion(o.additiveTags)
        }

        let weights = mergeWeights(base: base.weights, overlays: overlays)

        let contributing = overlays.filter { !$0.additiveTags.isEmpty || ($0.weightDeltas?.hasAnyDelta == true) }
        let contributingIDs = Array(Set(contributing.map(\.pluginID))).sorted { $0.rawValue < $1.rawValue }

        return RosterRoleResolvedDefinition(
            role: role,
            displayName: base.displayName,
            blurb: base.blurb,
            tags: Array(tagSet),
            weights: weights,
            schemaVersion: base.schemaVersion,
            contributingPluginIDs: contributingIDs
        )
    }

    static func _testOnlyReset() {
        overlaysByRole = [:]
    }

    private static func mergeWeights(base: RosterRoleWeights, overlays: [RosterRolePluginOverlay]) -> RosterRoleWeights {
        let cap = RosterRoleWeightDeltas.maxAbsTotalDeltaPerKnob
        func merged(_ baseKP: WritableKeyPath<RosterRoleWeights, Double>, _ deltaKP: KeyPath<RosterRoleWeightDeltas, Double?>) -> Double {
            let sum = overlays.compactMap { overlay -> Double? in
                guard let d = overlay.weightDeltas else { return nil }
                return d[keyPath: deltaKP]
            }.reduce(0, +)
            let clampedSum = min(cap, max(-cap, sum))
            let raw = base[keyPath: baseKP] + clampedSum
            return min(1, max(0, raw))
        }
        return RosterRoleWeights(
            aggression: merged(\.aggression, \.aggression),
            tenacity: merged(\.tenacity, \.tenacity),
            cohesion: merged(\.cohesion, \.cohesion),
            roe_slack: merged(\.roe_slack, \.roe_slack),
            support_bias: merged(\.support_bias, \.support_bias)
        )
    }
}
