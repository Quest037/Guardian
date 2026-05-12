import Foundation

// MARK: - Where the displaced active binding lands (swap-in commit)

/// **v1 shipped behaviour:** where the **prior primary / wingman binding** is written after a successful reserve **swap-in**
/// roster/pool commit — distinct from the operator tool ``MissionRunEnvironment/returnAssignmentToReservePool``, which
/// **appends** or **merges** pool rows when moving a squad aircraft into the floating pool without a paired vacancy exchange.
///
/// See **README.md** → **Floating reserve pool** → **Reserve swap disposition of replaced active** (binding destination).
enum MissionRunReserveSwapReplacedActiveReturnPathPolicy: Sendable {

    /// **Floating pool pick** (``MissionRunEnvironment/swapRosterAssignmentWithFloatingReservePoolSlot`` /
    /// ``swapRosterAssignmentWithRandomFloatingReserve`` → ``commitFloatingReservePoolPickToVacancy``): the vacancy takes
    /// the picked berth’s binding; the **same** ``MissionRunReservePoolSlot/id`` receives the vacancy’s prior binding
    /// (in-place exchange; **no** new pool row; **no** ``returnAssignmentToReservePool`` call inside that commit).
    static let floatingPoolSwapInWritesPriorBindingToConsumedBerth = true

    /// **Fixed template reserve** (``MissionRunEnvironment/swapRosterVacancyWithFixedTemplateReserveAssignment``):
    /// ``attachedFleetVehicleToken`` / ``attachedDevice`` **swap** between the **vacancy** assignment and the **reserve**
    /// assignment — the displaced active occupies the **source `.reserve` roster row** after commit.
    static let fixedReserveSwapInIsPairwiseRosterBindingExchange = true

    /// Operator **return to pool** from a squad slot uses ``returnAssignmentToReservePool`` (append / merge semantics).
    /// Swap-in commits do **not** route through that API today.
    static let operatorReturnToPoolUsesReturnAssignmentToReservePoolAPI = true
}
