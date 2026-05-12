import Foundation

// MARK: - Reserve reposition fleet verbs ↔ RoE

/// Fleet-side verbs issued to the **reserve** during **reposition** (swap pipeline — move reserve into position).
enum MissionRunReserveRepositionFleetVerb: String, Equatable, Codable, CaseIterable, Sendable {
    /// Cancel RTL / exit return-home on the reserve before joining the vacancy.
    case cancelReturnToLaunchOnReserve
    /// Guided goto / fly-to toward the geometry target (formation offset or rally point).
    case guidedGotoOrReposition
    /// Loiter / hold at the handoff anchor.
    case loiterHold
}

/// Outcome of applying run-level **Rules of engagement** to a reposition verb (``MissionRunEngagementRules`` / ``MissionRunEngagementDisposition``).
enum MissionRunReserveRepositionEngagementGateOutcome: Equatable, Sendable {
    /// Dispatch may proceed without an engagement prompt for this verb.
    case allowImmediateDispatch
    /// ``MissionRunEngagementDisposition/forbidden`` — do not dispatch; surface as a reposition gate failure.
    case blockForbidden(invokedAction: MissionRunEngagementAction, reason: String)
    /// ``ask`` / ``defer`` / ``handoff`` — publish ``OperatorPromptOrigin/mreEngagementAsk`` or ``mreEngagementHandoff`` (executor wiring) before dispatch.
    case requiresOperatorEngagement(invokedAction: MissionRunEngagementAction, disposition: MissionRunEngagementDisposition)
}

/// Maps reserve **reposition** verbs to ``MissionRunEngagementAction`` and classifies ``MissionRunEngagementDisposition``.
///
/// **v1 mapping:** RTL-class cancel uses ``MissionRunEngagementAction/rtl``; guided moves and loiter use
/// ``MissionRunEngagementAction/swapInReserve`` (umbrella for the swap-in reposition phase). Finer per-verb RoE
/// keys can split later without changing executor dispatch mechanics.
enum MissionRunReserveRepositionCommandEngagementPolicy {

    static let forbiddenReason = "Engagement rules forbid this action for the current mission run."

    static func engagementAction(for verb: MissionRunReserveRepositionFleetVerb) -> MissionRunEngagementAction {
        switch verb {
        case .cancelReturnToLaunchOnReserve:
            return .rtl
        case .guidedGotoOrReposition, .loiterHold:
            return .swapInReserve
        }
    }

    static func gateOutcome(
        disposition: MissionRunEngagementDisposition,
        action: MissionRunEngagementAction
    ) -> MissionRunReserveRepositionEngagementGateOutcome {
        switch disposition {
        case .autonomous:
            return .allowImmediateDispatch
        case .forbidden:
            return .blockForbidden(invokedAction: action, reason: forbiddenReason)
        case .ask, .defer, .handoff:
            return .requiresOperatorEngagement(invokedAction: action, disposition: disposition)
        }
    }
}
