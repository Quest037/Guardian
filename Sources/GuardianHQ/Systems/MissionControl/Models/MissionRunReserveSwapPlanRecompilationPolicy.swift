import Foundation

// MARK: - Reserve swap → plan recompile + assistant callbacks

/// Locked contract for **Mission Control plan** refresh after a **reserve → roster** commit (floating pool or fixed template reserve row).
///
/// Roster truth changes must flow through ``MissionControlStore/recompileMissionControlPlanAfterFloatingReserveSwap``,
/// which calls ``MissionRunPlannerSubsystem/compileInitialPlan`` so the same **plugin assistant** hooks as normal plan
/// builds observe the new ``MissionRunEnvironment/assignments`` + ``compiledPlan``. Use ``fixedRosterReserveSwapPlanCompileSource``
/// after ``MissionRunEnvironment/swapRosterVacancyWithFixedTemplateReserveAssignment`` so exports distinguish the commit kind.
enum MissionRunReserveSwapPlanRecompilationPolicy: Sendable {

    /// Passed to ``MissionRunPlannerSubsystem/compileInitialPlan(source:reason:)`` after a successful MCS floating-pool
    /// swap so revision history / exports / operator logs correlate with one stable token.
    static let floatingReserveSwapPlanCompileSource = "missionControl.plan.floatingReserveSwap"

    /// Same planner / mutation-commit hook path as ``floatingReserveSwapPlanCompileSource`` after a **template reserve roster row**
    /// ↔ active primary/wingman binding swap (Paladin consent or autonomous engagement).
    static let fixedRosterReserveSwapPlanCompileSource = "missionControl.plan.fixedRosterReserveSwap"

    /// ``MissionRunPlannerSubsystem/compileInitialPlan`` invokes registered **mutation commit** callbacks in
    /// **lexicographic registration key order** after mutating ``MissionRunEnvironment/compiledPlan`` (see
    /// ``MissionRunPlannerSubsystem`` `mutationCommitCallbacksByKey`).
    ///
    /// Plugins attach through ``MissionRunEnvironment/installAssistant(_:key:)`` when the assistant conforms to
    /// ``MissionRunPlanningMutationAssistant`` — ``missionRun(_:planning:fleetVehicles:didApply:)`` receives the
    /// ``MissionControlPlanChangeResult`` (plan + change set + revision). This is the v1 **post-recompile** channel
    /// for assistant-owned rollups keyed off roster / plan identity; it is **not** a single-product callback surface.
    static let mutationCommitCallbacksInvokedLexicographicByRegistrationKey = true
}
