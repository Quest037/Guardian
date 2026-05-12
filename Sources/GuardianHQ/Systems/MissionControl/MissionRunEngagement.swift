import Foundation

/// Resolves ``MissionRunEngagementRules``. Rules apply unconditionally (no trigger gating).
enum MissionRunEngagementResolver {
    static func resolvedDisposition(
        for action: MissionRunEngagementAction,
        rules: MissionRunEngagementRules
    ) -> MissionRunEngagementDisposition {
        rules.perAction[action]?.disposition ?? .autonomous
    }
}

extension MissionRunEnvironment {
    func resolvedEngagementDisposition(for action: MissionRunEngagementAction) -> MissionRunEngagementDisposition {
        MissionRunEngagementResolver.resolvedDisposition(for: action, rules: policies.engagement)
    }

    /// Rules-of-engagement gate for reserve **reposition** fleet verbs (swap pipeline). Uses ``policies/engagement`` via
    /// ``resolvedEngagementDisposition(for:)`` — same editor surface as MCS / MC-R engagement rows.
    func repositionReserveFleetVerbEngagementGate(
        for verb: MissionRunReserveRepositionFleetVerb
    ) -> MissionRunReserveRepositionEngagementGateOutcome {
        let action = MissionRunReserveRepositionCommandEngagementPolicy.engagementAction(for: verb)
        let disposition = resolvedEngagementDisposition(for: action)
        return MissionRunReserveRepositionCommandEngagementPolicy.gateOutcome(disposition: disposition, action: action)
    }
}

extension MissionRunEngagementAction {
    /// Short label for MC-Setup engagement editor.
    var setupLabel: String {
        switch self {
        case .rtl: return "Return to launch"
        case .land: return "Land"
        case .forceDisarm: return "Force disarm"
        case .swapInReserve: return "Swap in reserve"
        }
    }
}

extension MissionRunEngagementDisposition {
    var setupMenuLabel: String {
        switch self {
        case .autonomous: return "Autonomous"
        case .ask: return "Ask operator"
        case .defer: return "Defer to operator"
        case .forbidden: return "Forbidden (operator only)"
        case .handoff: return "Handoff to operator"
        }
    }
}
