import Foundation

// MARK: - Control outcome

/// What the recipe runner should do when a matcher fires.
///
/// Closed enum — every new flow primitive forces the runner state machine, the
/// authoring docs, and Stage D's escalation router to reason about a new case, so
/// additions are deliberate.
///
/// Recipes' overall outcome is binary (locked decision): the runner reduces every
/// step's control outcome to either `succeeded` or `failed(failingCommandPath,
/// lastResponse)` at the recipe boundary. `escalate` is **not** a third outcome —
/// it suspends the runner until resolved via a resumption verb.
enum FleetRecipeControlOutcome: Equatable, Hashable, Sendable {
    /// Proceed to the step that physically follows this one in the recipe body
    /// (i.e. the next index in `FleetRecipeBody.steps`).
    case continueToNextStep

    /// Jump to the step with the given ID. Parser-time validation guarantees the
    /// target exists in the same body. Backward jumps are permitted (loops),
    /// bounded by the recipe's overall budget.
    case branch(stepID: FleetRecipeStepID)

    /// Re-invoke the same step. Counts against the step's retry policy; if no
    /// retries remain the runner treats this as the underlying response and falls
    /// through to the next matcher.
    case retry

    /// Recipe completes successfully. Subsequent matchers and steps are skipped.
    case succeed

    /// Recipe fails with the supplied detail. The runner attaches the failing
    /// step's path automatically.
    case fail(detail: String?)

    /// Recipe escalates — runner suspends and routes the supplied reason +
    /// `allowedVerbs` through the Stage D prompt channel. Resumption proceeds
    /// according to the verb the operator chose.
    case escalate(reason: FleetRecipeEscalationReason, allowedVerbs: [FleetRecipeResumptionVerb])
}

// MARK: - Codable

extension FleetRecipeControlOutcome: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind
        case stepID
        case detail
        case reason
        case allowedVerbs
    }

    private enum Kind: String, Codable {
        case continueToNextStep
        case branch
        case retry
        case succeed
        case fail
        case escalate
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .continueToNextStep:
            self = .continueToNextStep
        case .branch:
            self = .branch(stepID: try c.decode(FleetRecipeStepID.self, forKey: .stepID))
        case .retry:
            self = .retry
        case .succeed:
            self = .succeed
        case .fail:
            self = .fail(detail: try c.decodeIfPresent(String.self, forKey: .detail))
        case .escalate:
            self = .escalate(
                reason: try c.decode(FleetRecipeEscalationReason.self, forKey: .reason),
                allowedVerbs: try c.decode([FleetRecipeResumptionVerb].self, forKey: .allowedVerbs)
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .continueToNextStep:
            try c.encode(Kind.continueToNextStep, forKey: .kind)
        case .branch(let stepID):
            try c.encode(Kind.branch, forKey: .kind)
            try c.encode(stepID, forKey: .stepID)
        case .retry:
            try c.encode(Kind.retry, forKey: .kind)
        case .succeed:
            try c.encode(Kind.succeed, forKey: .kind)
        case .fail(let detail):
            try c.encode(Kind.fail, forKey: .kind)
            if let detail {
                try c.encode(detail, forKey: .detail)
            }
        case .escalate(let reason, let allowedVerbs):
            try c.encode(Kind.escalate, forKey: .kind)
            try c.encode(reason, forKey: .reason)
            // Deterministic ordering so DSL diffs stay readable.
            try c.encode(
                allowedVerbs.sorted(by: { $0.rawValue < $1.rawValue }),
                forKey: .allowedVerbs
            )
        }
    }
}
