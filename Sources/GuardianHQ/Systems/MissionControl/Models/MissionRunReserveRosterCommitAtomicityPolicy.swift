import Foundation

// MARK: - Reserve roster commit atomicity (pool swap-in)

/// Ordered **internal** steps for a **single** floating-pool ↔ roster **binding exchange** on ``MissionRunEnvironment``.
/// Mirrors ``MissionRunEnvironment/commitFloatingReservePoolPickToVacancy`` so future ``commitReserveSwapIn`` (pool + fixed reserve)
/// reuses the same **no extra pool rows** contract.
///
/// **Atomicity:** the roster vacancy row and the chosen pool berth are updated together in one synchronous call before
/// returning ``MissionRunFloatingReserveSwapOutcome/success``; failures before that write leave prior state.
enum MissionRunReserveFloatingPoolRosterCommitStep: Int, CaseIterable, Equatable, Sendable {
    /// ``floatingReserveSwapPreCommitDedupeAndOperationalHold`` on the pick, plus vacating-binding gates when present.
    case preCommitValidation = 0
    /// One batch: vacancy ``assignments`` row takes the pool berth’s binding; that same pool berth takes the vacancy’s prior binding (or clears).
    case exchangeVacancyAndPoolBerthBindings = 1
    /// ``appendLogEvent`` + ``refreshDerivedTaskStates``.
    case publishDerivedStateAndLog = 2
}

/// v1 **contract** text for roster/pool token maps during reserve swap-in commit (all vehicle classes).
enum MissionRunReserveRosterCommitAtomicityPolicy {

    /// Human-readable ordering; keep in sync with ``MissionRunReserveFloatingPoolRosterCommitStep``.
    static let floatingPoolCommitStepDescriptions: [MissionRunReserveFloatingPoolRosterCommitStep: String] = [
        .preCommitValidation: "Pre-commit dedupe, written-off, duplicate token, operational draw on reserve pick, and vacating roster binding eligibility when present.",
        .exchangeVacancyAndPoolBerthBindings: "Roster vacancy row receives the picked pool berth’s binding; that same pool berth receives the prior roster binding (no new pool slots).",
        .publishDerivedStateAndLog: "Emit swap log line and refresh derived task states.",
    ]

    /// Count of ordered steps (tests pin this to the swap primitive’s phase count).
    static var floatingPoolOrderedStepCount: Int {
        MissionRunReserveFloatingPoolRosterCommitStep.allCases.count
    }
}
