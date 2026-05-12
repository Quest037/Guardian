import Foundation

// MARK: - Mission run log keys (Paladin reserve swap)

extension MissionRunLogTemplateKey {
    /// Paladin (or another assistant using the same issuer) proposed a fixed-reserve → active swap; engagement rules allow prompting.
    static let paladinReserveSwapProposed = "paladin.mre.reserve_swap.proposed"
    /// Engagement rules treat swap-in-reserve as **autonomous** — no operator prompt; proposal logged only.
    static let paladinReserveSwapEngagementAutonomous = "paladin.mre.reserve_swap.engagement_autonomous"
    /// Engagement rules **forbid** swap-in-reserve — proposal rejected without prompt.
    static let paladinReserveSwapEngagementForbidden = "paladin.mre.reserve_swap.engagement_forbidden"
    /// Operator answered (or timeout resolved) the Mission Control engagement prompt for a headless-issuer fixed-reserve swap.
    static let paladinReserveSwapPromptResolved = "paladin.mre.reserve_swap.prompt_resolved"
    /// Roster commit succeeded after operator consent (or autonomous engagement).
    static let paladinReserveSwapCommitted = "paladin.mre.reserve_swap.committed"
    /// Roster commit was attempted but did not succeed (stale roster, dedupe, operational gate, etc.).
    static let paladinReserveSwapCommitRejected = "paladin.mre.reserve_swap.commit_rejected"
}
