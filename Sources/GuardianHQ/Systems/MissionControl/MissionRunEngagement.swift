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
