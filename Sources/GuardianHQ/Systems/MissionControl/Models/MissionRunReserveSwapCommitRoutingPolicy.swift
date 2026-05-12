import Foundation

// MARK: - Reserve swap commit routing (pool vs fixed reserve)

/// Identifies **which** reserve supply is committed onto a roster **vacancy** (swap-in commit phase).
enum MissionRunReserveSwapCommitReserveSource: Equatable, Sendable {
    /// Filled floating pool berth (``MissionRunReservePoolSlot/id``).
    case floatingPoolBerth(slotID: UUID)
    /// Template ``MissionRosterSlotRole/reserve`` roster row (``MissionRunAssignment/id``).
    case fixedTemplateReserveRosterRow(assignmentID: UUID)
}

/// Mission Control API that performs (or will perform) the **token** commit for a reserve swap-in.
enum MissionRunReserveSwapCommitExecutionSurface: Equatable, Sendable {
    /// Today’s pool-only primitive: ``MissionRunEnvironment/swapRosterAssignmentWithRandomFloatingReserve`` + atomic step
    /// order in ``MissionRunReserveRosterCommitAtomicityPolicy``.
    case swapRosterAssignmentWithRandomFloatingReserve
    /// Fixed template **reserve** roster row: ``MissionRunEnvironment/swapRosterVacancyWithFixedTemplateReserveAssignment``.
    /// A unified ``commitReserveSwapIn(…)`` API may wrap pool + fixed later; v1 ships the dedicated roster↔roster primitive.
    case commitReserveSwapInPending
}

/// Routes reserve **source** → the executor surface (shipped vs planned) so UI / plugin assistants / automation share one vocabulary.
enum MissionRunReserveSwapCommitRoutingPolicy {

    static func executionSurface(for reserveSource: MissionRunReserveSwapCommitReserveSource) -> MissionRunReserveSwapCommitExecutionSurface {
        switch reserveSource {
        case .floatingPoolBerth:
            return .swapRosterAssignmentWithRandomFloatingReserve
        case .fixedTemplateReserveRosterRow:
            return .commitReserveSwapInPending
        }
    }
}
