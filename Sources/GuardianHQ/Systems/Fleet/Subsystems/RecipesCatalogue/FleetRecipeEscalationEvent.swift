import Foundation

// MARK: - Escalation event

/// Event emitted by ``FleetRecipeRunner`` when a step's matcher fires a
/// `.escalate(reason:allowedVerbs:)` control outcome. The runner suspends the
/// run until the escalation handler returns a ``FleetRecipeResumptionVerb`` —
/// Stage D's prompt router will plug in here; until then test cases and
/// in-process callers provide their own handler.
///
/// `Sendable` so it can cross actor boundaries when Stage D's router lands.
struct FleetRecipeEscalationEvent: Equatable, Sendable {

    /// Run that is escalating.
    let runID: FleetRecipeRunID

    /// Top-level recipe being executed.
    let recipe: FleetRecipeName

    /// Vehicle the run is targeting.
    let vehicleID: String

    /// Step that raised the escalation.
    let stepID: FleetRecipeStepID

    /// Reason the runner is escalating. Closed top-level shape with extensible
    /// inner kinds (see ``FleetRecipeEscalationReason``).
    let reason: FleetRecipeEscalationReason

    /// Verbs the matcher said the operator may use to resume. The runner
    /// **rejects** any verb outside this list — if a handler returns a
    /// disallowed verb the run is aborted with attribution.
    let allowedVerbs: [FleetRecipeResumptionVerb]

    /// The response the step most recently produced. Handlers surface this to
    /// the operator so they can see *why* the escalation fired (e.g. last
    /// calibration progress payload).
    let lastResponse: FleetCommandResponse
}

// MARK: - Handler typealias

/// Asynchronous decision producer for an escalation. The runner blocks the
/// escalating step until this closure returns; the verb must be a member of the
/// event's ``FleetRecipeEscalationEvent/allowedVerbs`` list or the run is aborted.
///
/// Marked `@MainActor` because:
/// 1. The runner itself is main-isolated;
/// 2. Stage D's prompt router will run on the main actor (it touches SwiftUI).
typealias FleetRecipeEscalationHandler = @MainActor (FleetRecipeEscalationEvent) async -> FleetRecipeResumptionVerb

// MARK: - Default handler

/// v1 fallback when no handler is supplied at run time. Returns `.abort` so the
/// run fails cleanly rather than hanging indefinitely waiting for an operator
/// the app cannot reach yet. Stage D installs a real router as the production
/// default.
enum FleetRecipeDefaultEscalationHandler {
    @MainActor
    static let abort: FleetRecipeEscalationHandler = { _ in .abort }
}
