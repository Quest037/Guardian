import Foundation

// MARK: - Step matcher (when → then)

/// A single ordered matcher attached to a recipe step.
///
/// The runner evaluates a step's matchers top-to-bottom and applies the first one
/// whose `when` fires against the step's response. Parser rules guarantee the list
/// is non-empty and that any explicit `.any` matcher is the final entry.
struct FleetRecipeStepMatcher: Equatable, Hashable, Sendable, Codable {
    let when: FleetRecipeResponseMatcher
    let then: FleetRecipeControlOutcome

    init(when: FleetRecipeResponseMatcher, then: FleetRecipeControlOutcome) {
        self.when = when
        self.then = then
    }
}

// MARK: - Step

/// A single step inside a ``FleetRecipeBody``.
///
/// Closed two-case enum — the locked composition model says a recipe is a list of
/// commands and/or recipes with response-driven branching. New step kinds force the
/// runner and authoring docs to reason about new shapes, so additions are
/// deliberate.
///
/// **Step IDs are local to the body**, not global. The runner uses them to route
/// `branch(stepID:)` outcomes; matchers reference IDs declared in the same body.
enum FleetRecipeStep: Equatable, Hashable, Sendable {

    /// Invoke a Layer 0 command. `retry` overrides the recipe-level default retry
    /// policy when set. Matchers branch on the resulting ``FleetCommandResponse``.
    case invokeCommand(
        id: FleetRecipeStepID,
        command: FleetCommandName,
        parameters: FleetRecipeParameters = .empty,
        retry: FleetRecipeRetryPolicy? = nil,
        matchers: [FleetRecipeStepMatcher]
    )

    /// Invoke another registered recipe. The child recipe must itself contain only
    /// `.invokeCommand` steps (1-level composition limit enforced by the parser).
    /// Matchers branch on the child's overall outcome surfaced as a synthetic
    /// ``FleetCommandResponse`` (`.succeeded` or `.error(.unknown)` with the
    /// failing path in `detail`).
    case invokeRecipe(
        id: FleetRecipeStepID,
        recipe: FleetRecipeName,
        parameters: FleetRecipeParameters = .empty,
        matchers: [FleetRecipeStepMatcher]
    )

    // MARK: Accessors

    /// Step identifier (always present regardless of kind).
    var id: FleetRecipeStepID {
        switch self {
        case .invokeCommand(let id, _, _, _, _): return id
        case .invokeRecipe(let id, _, _, _): return id
        }
    }

    /// Ordered matcher list for this step. Always non-empty after parsing.
    var matchers: [FleetRecipeStepMatcher] {
        switch self {
        case .invokeCommand(_, _, _, _, let matchers): return matchers
        case .invokeRecipe(_, _, _, let matchers): return matchers
        }
    }
}

// MARK: - Codable

extension FleetRecipeStep: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
        case command
        case recipe
        case parameters
        case retry
        case matchers
    }

    private enum Kind: String, Codable {
        case invokeCommand
        case invokeRecipe
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        let id = try c.decode(FleetRecipeStepID.self, forKey: .id)
        let matchers = try c.decode([FleetRecipeStepMatcher].self, forKey: .matchers)
        let parameters = try c.decodeIfPresent(FleetRecipeParameters.self, forKey: .parameters) ?? .empty
        switch kind {
        case .invokeCommand:
            let command = try c.decode(FleetCommandName.self, forKey: .command)
            let retry = try c.decodeIfPresent(FleetRecipeRetryPolicy.self, forKey: .retry)
            self = .invokeCommand(
                id: id,
                command: command,
                parameters: parameters,
                retry: retry,
                matchers: matchers
            )
        case .invokeRecipe:
            let recipe = try c.decode(FleetRecipeName.self, forKey: .recipe)
            self = .invokeRecipe(
                id: id,
                recipe: recipe,
                parameters: parameters,
                matchers: matchers
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        switch self {
        case .invokeCommand(_, let command, let parameters, let retry, let matchers):
            try c.encode(Kind.invokeCommand, forKey: .kind)
            try c.encode(command, forKey: .command)
            if !parameters.values.isEmpty {
                try c.encode(parameters, forKey: .parameters)
            }
            if let retry {
                try c.encode(retry, forKey: .retry)
            }
            try c.encode(matchers, forKey: .matchers)
        case .invokeRecipe(_, let recipe, let parameters, let matchers):
            try c.encode(Kind.invokeRecipe, forKey: .kind)
            try c.encode(recipe, forKey: .recipe)
            if !parameters.values.isEmpty {
                try c.encode(parameters, forKey: .parameters)
            }
            try c.encode(matchers, forKey: .matchers)
        }
    }
}
