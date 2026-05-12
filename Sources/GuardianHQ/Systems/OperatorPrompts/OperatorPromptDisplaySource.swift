import Foundation

// MARK: - OperatorPromptDisplaySource

/// Operator-facing **who surfaced this prompt** — distinct from ``OperatorPromptOrigin``,
/// which drives **routing** policy. Render this (or its ``operatorFacingShortLabel``)
/// on MC-R / Live Drive strips, the Decisions drawer, and sticky toast chrome so
/// publishers do not duplicate issuer strings in `body` / `contextFacts`.
enum OperatorPromptDisplaySource: Equatable, Hashable, Sendable {

    /// Core Mission Control stack — default on ``OperatorPromptEvent/init(fromRecipeEscalation:)`` when the
    /// publisher does not override (e.g. generic recipe-lift tests). **MC-R mission-run** recipe escalations use
    /// ``mre`` instead so the same strip as engagement prompts shows **Mission run** for non-assistant mission context.
    case missionControl

    /// Mission run environment / rules-of-engagement path without a named plugin assistant.
    case mre

    /// Headless or plugin assistant. ``operatorPromptBackgroundHex`` is **plugin-owned** RGB (`#RRGGBB` or `RRGGBB`);
    /// Mission Control never supplies a default for a specific plugin — pass `nil` only when intentionally falling back to severity banner fills.
    case assistant(pluginID: String, displayName: String, operatorPromptBackgroundHex: String?)
}

extension OperatorPromptDisplaySource {

    /// Short label for captions — not a full sentence.
    var operatorFacingShortLabel: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .mre: return "Mission run"
        case .assistant(_, let displayName, _): return displayName
        }
    }
}
