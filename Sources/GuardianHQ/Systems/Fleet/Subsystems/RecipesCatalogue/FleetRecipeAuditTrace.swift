import Foundation

// MARK: - Audit entry

/// One step's contribution to a ``FleetRecipeAuditTrace`` — exactly one entry is
/// appended per *dispatched* step (including retries done via the `.retry` control
/// outcome). Retry-policy auto-retries inside a single dispatch are collapsed into
/// the entry's `attempt` count.
///
/// `Sendable` so the trace can cross actor boundaries when Stage D's prompt router
/// or downstream UI surfaces consume it.
struct FleetRecipeAuditEntry: Equatable, Sendable {

    /// Step ID that produced this entry (always present).
    let stepID: FleetRecipeStepID

    /// Whether the step invoked a Layer 0 command (`.command`) or a child recipe
    /// (`.recipe`).
    let kind: Kind

    enum Kind: Equatable, Sendable {
        /// `.invokeCommand` step; raw value is the underlying command name.
        case command(FleetCommandName)
        /// `.invokeRecipe` step; raw value is the child recipe name.
        case recipe(FleetRecipeName)
    }

    /// Number of underlying attempts spent on this step before reaching the
    /// recorded response. `1` means the first dispatch succeeded (no auto-retries);
    /// values `> 1` include retry-policy retries.
    let attempt: Int

    /// Normalised response that the matchers branched on. For `.invokeRecipe`
    /// steps this is the synthetic response synthesised from the child outcome.
    let response: FleetCommandResponse

    /// Control outcome the matchers produced for this response. `nil` indicates
    /// "no matcher fired" — the runner treated this as an implicit fail.
    let controlOutcome: FleetRecipeControlOutcome?

    /// Wall-clock time the entry was appended (after the response was observed).
    let timestamp: Date

    init(
        stepID: FleetRecipeStepID,
        kind: Kind,
        attempt: Int,
        response: FleetCommandResponse,
        controlOutcome: FleetRecipeControlOutcome?,
        timestamp: Date = Date()
    ) {
        self.stepID = stepID
        self.kind = kind
        self.attempt = attempt
        self.response = response
        self.controlOutcome = controlOutcome
        self.timestamp = timestamp
    }

    /// Loggable summary line — small, fits in `OSLog`.
    var loggable: String {
        let kindLabel: String
        switch kind {
        case .command(let name): kindLabel = "command \(name.rawValue)"
        case .recipe(let name): kindLabel = "recipe \(name.rawValue)"
        }
        let outcomeLabel: String
        switch response.outcome {
        case .succeeded: outcomeLabel = "succeeded"
        case .error(let kind): outcomeLabel = "error.\(kind.rawValue)"
        case .cancelled: outcomeLabel = "cancelled"
        case .timeout: outcomeLabel = "timeout"
        }
        return "step \(stepID.rawValue) attempt \(attempt) [\(kindLabel)] -> \(outcomeLabel)"
    }
}

// MARK: - Audit trace

/// Ordered append-only log of every dispatched step in a recipe run. Attached to
/// the run's final ``FleetRecipeOutcome`` so callers can render per-step UI
/// (progress, failure narrative, debugging) without re-querying the runner.
///
/// The trace is **flat** — `.invokeRecipe` steps produce a single entry for the
/// child outcome rather than nesting the child's own trace. v1 keeps things
/// straightforward; Stage E wizard rendering can re-fetch child traces if it
/// genuinely needs the nested view.
struct FleetRecipeAuditTrace: Equatable, Sendable {

    /// Run identifier (one trace per run).
    let runID: FleetRecipeRunID

    /// Top-level recipe being executed.
    let recipe: FleetRecipeName

    /// Vehicle that the recipe ran against.
    let vehicleID: String

    /// Ordered entries — first dispatched step first.
    private(set) var entries: [FleetRecipeAuditEntry]

    /// Wall-clock instant the run started.
    let startedAt: Date

    init(runID: FleetRecipeRunID, recipe: FleetRecipeName, vehicleID: String, startedAt: Date = Date()) {
        self.runID = runID
        self.recipe = recipe
        self.vehicleID = vehicleID
        self.entries = []
        self.startedAt = startedAt
    }

    mutating func append(_ entry: FleetRecipeAuditEntry) {
        entries.append(entry)
    }

    /// The failing step path on failure — by v1 design just the most recent
    /// dispatched step's ID. (Layer 1 doesn't currently nest paths; Stage E's
    /// wizard treats the last entry as the failing-step source of truth.)
    var failingStepPath: [FleetRecipeStepID] {
        guard let last = entries.last else { return [] }
        return [last.stepID]
    }
}
