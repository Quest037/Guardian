import Foundation

// MARK: - Response matcher

/// Closed vocabulary of the conditions a recipe step matches against a
/// ``FleetCommandResponse``.
///
/// Matchers are ordered inside a step (see ``FleetRecipeStepMatcher``); the runner
/// evaluates them top-to-bottom and applies the first one that matches. ``any`` is
/// the explicit "fallback" catch-all and must — by parser rule — be the **last**
/// matcher in the list if it appears.
enum FleetRecipeResponseMatcher: Equatable, Hashable, Sendable {

    /// Matches `.succeeded`. Optionally narrows the match by also testing the
    /// response payload via a ``FleetRecipePayloadPredicate``. When the predicate is
    /// `nil`, any success matches. When set, the predicate must return `true` for
    /// the payload as well.
    case success(payload: FleetRecipePayloadPredicate? = nil)

    /// Matches `.error(kind: kind)`.
    case error(kind: FleetCommandErrorKind)

    /// Matches `.succeeded` whose payload passes the supplied predicate. Authored
    /// separately from ``success(payload:)`` so recipes can express the common
    /// "I don't care about overall success/failure, I want to branch on data"
    /// pattern. Equivalent to `success(payload: predicate)` in terms of when it
    /// fires — kept as a sibling case for ergonomic recipe authoring.
    case data(predicate: FleetRecipePayloadPredicate)

    /// Matches `.timeout`.
    case timeout

    /// Matches `.cancelled`.
    case cancelled

    /// Fallback matcher — fires on any outcome not matched by an earlier matcher.
    /// Parser requires this to be the **last** matcher in a step if used.
    case any
}

// MARK: - Match

extension FleetRecipeResponseMatcher {
    /// Whether this matcher fires for the supplied response.
    func matches(_ response: FleetCommandResponse) -> Bool {
        switch self {
        case .success(let predicate):
            guard response.isSuccess else { return false }
            guard let predicate else { return true }
            return predicate.evaluate(against: response.payload)

        case .error(let expectedKind):
            return response.errorKind == expectedKind

        case .data(let predicate):
            guard response.isSuccess else { return false }
            return predicate.evaluate(against: response.payload)

        case .timeout:
            if case .timeout = response.outcome { return true }
            return false

        case .cancelled:
            if case .cancelled = response.outcome { return true }
            return false

        case .any:
            return true
        }
    }
}

// MARK: - Codable

extension FleetRecipeResponseMatcher: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind
        case errorKind
        case payload
        case predicate
    }

    private enum Kind: String, Codable {
        case success
        case error
        case data
        case timeout
        case cancelled
        case any
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .success:
            let predicate = try c.decodeIfPresent(FleetRecipePayloadPredicate.self, forKey: .payload)
            self = .success(payload: predicate)
        case .error:
            self = .error(kind: try c.decode(FleetCommandErrorKind.self, forKey: .errorKind))
        case .data:
            self = .data(predicate: try c.decode(FleetRecipePayloadPredicate.self, forKey: .predicate))
        case .timeout:
            self = .timeout
        case .cancelled:
            self = .cancelled
        case .any:
            self = .any
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success(let predicate):
            try c.encode(Kind.success, forKey: .kind)
            if let predicate {
                try c.encode(predicate, forKey: .payload)
            }
        case .error(let kind):
            try c.encode(Kind.error, forKey: .kind)
            try c.encode(kind, forKey: .errorKind)
        case .data(let predicate):
            try c.encode(Kind.data, forKey: .kind)
            try c.encode(predicate, forKey: .predicate)
        case .timeout:
            try c.encode(Kind.timeout, forKey: .kind)
        case .cancelled:
            try c.encode(Kind.cancelled, forKey: .kind)
        case .any:
            try c.encode(Kind.any, forKey: .kind)
        }
    }
}
