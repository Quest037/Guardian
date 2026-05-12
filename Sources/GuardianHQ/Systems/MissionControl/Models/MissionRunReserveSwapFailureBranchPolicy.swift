import Foundation

// MARK: - Swap pipeline failure branches (policy)

/// Phases for the **live reserve swap-in** pipeline (``MissionRosterReservesToDo.md`` swap pipeline sections).
/// v1 policy in ``MissionRunReserveSwapFailureBranchPolicy`` applies when a **gate** in a phase fails
/// before an atomic roster/pool **commit** completes.
enum MissionRunReserveSwapPipelinePhase: String, CaseIterable, Equatable, Sendable {
    case pickReserve
    case swapTimeChecks
    case missionUpload
    case reposition
    case rosterCommit
}

/// What the executor / orchestration should do **after** a gate failure on the current reserve candidate.
enum MissionRunReserveSwapFailureDisposition: Equatable, Sendable {
    /// Re-run the failing gate (or the same phase entrypoint) on the **same** candidate.
    case retrySameCandidate
    /// Drop the current candidate and continue with the next ranked option (pool or fixed reserve).
    case tryNextCandidate
    /// Stop automatic attempts; surface a blocking operator decision (MC-R / MCS confirm pattern).
    case escalateToOperatorPrompt
    /// End the swap attempt without mutating **already-committed** run state; discard ephemeral phase state only.
    ///
    /// **Roster commit:** failures during or after ``rosterCommit`` always map here (no silent re-drive of commit).
    /// **Today’s** MCS pool swap primitive is already **single-shot** atomic before log — future multi-phase flows must
    /// keep mutations behind one commit barrier or explicitly document repair (e.g. ``MissionRunFloatingReserveSwapOutcome/poolClearFailed``).
    case abortSwapPreserveCommittedState
}

/// Locked **v1** failure branching for reserve swap-in gates (retry budget, next candidate, escalation, abort).
enum MissionRunReserveSwapFailureBranchPolicy {

    /// Automatic **replays** of the **same** gate on the **same** candidate after the first failure, **per gate**
    /// (not a whole-pipeline aggregate). Example: `2` ⇒ up to **three** executions (initial try + two replays).
    static let maxAutomaticRetriesAfterFirstFailureSameCandidatePerGate: Int = 2

    /// After ``consecutiveFailedGateAttemptsOnCurrentCandidate`` failures on the current candidate for ``phase``,
    /// returns the next orchestration step.
    ///
    /// - Parameters:
    ///   - phase: Failing pipeline phase. ``rosterCommit`` always yields ``abortSwapPreserveCommittedState``.
    ///   - consecutiveFailedGateAttemptsOnCurrentCandidate: Count of **consecutive** failed attempts for this gate
    ///     on this candidate, **including** the attempt that just failed (≥ 1).
    ///   - hasAnotherRankedCandidate: Whether enumeration still has at least one **other** viable candidate after
    ///     excluding the current one (e.g. another pool berth or fixed reserve row).
    ///   - operatorPromptChannelAvailable: When `false`, ``escalateToOperatorPrompt`` collapses to ``abortSwapPreserveCommittedState``
    ///     (unattended / Paladin-only paths without UI).
    static func disposition(
        phase: MissionRunReserveSwapPipelinePhase,
        consecutiveFailedGateAttemptsOnCurrentCandidate: Int,
        hasAnotherRankedCandidate: Bool,
        operatorPromptChannelAvailable: Bool
    ) -> MissionRunReserveSwapFailureDisposition {
        if phase == .rosterCommit {
            return .abortSwapPreserveCommittedState
        }

        guard consecutiveFailedGateAttemptsOnCurrentCandidate > 0 else {
            return .retrySameCandidate
        }

        let cap = 1 + maxAutomaticRetriesAfterFirstFailureSameCandidatePerGate
        if consecutiveFailedGateAttemptsOnCurrentCandidate < cap {
            return .retrySameCandidate
        }

        if hasAnotherRankedCandidate {
            return .tryNextCandidate
        }

        if operatorPromptChannelAvailable {
            return .escalateToOperatorPrompt
        }

        return .abortSwapPreserveCommittedState
    }
}
