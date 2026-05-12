import Foundation

/// Debounce and small helpers for MC-R **reserve auto-swap executor** (autonomous engagement + unique candidate + arm probe).
///
/// Distress signals and lifecycle gating live on ``MissionRunReserveAutoSuggestPolicy`` / ``MissionRunReserveAutoSwapLiveEvaluator``.
enum MissionRunReserveAutoSwapExecutorPolicy: Sendable {

    /// Minimum spacing between **executor** attempts for the same roster vacancy (preflight + commit can be expensive).
    static let defaultAttemptDebouncePerVacancySeconds: TimeInterval = 300

    static func debounceAllowsAttempt(
        lastAttemptAt: Date?,
        debounce: TimeInterval = defaultAttemptDebouncePerVacancySeconds,
        now: Date
    ) -> Bool {
        guard let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= debounce
    }
}
