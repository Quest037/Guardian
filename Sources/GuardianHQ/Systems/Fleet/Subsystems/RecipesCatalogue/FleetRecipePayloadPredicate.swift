import Foundation

// MARK: - Comparison op

/// Closed set of comparison operators used by numeric payload predicates.
enum FleetRecipeComparisonOp: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    case lessThan = "lt"
    case lessOrEqual = "le"
    case equal = "eq"
    case notEqual = "ne"
    case greaterOrEqual = "ge"
    case greaterThan = "gt"

    fileprivate func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool {
        switch self {
        case .lessThan: return lhs < rhs
        case .lessOrEqual: return lhs <= rhs
        case .equal: return lhs == rhs
        case .notEqual: return lhs != rhs
        case .greaterOrEqual: return lhs >= rhs
        case .greaterThan: return lhs > rhs
        }
    }
}

// MARK: - Payload predicate

/// Closed vocabulary of predicates a recipe step can match against a
/// ``FleetCommandResponsePayload``. Locked v1 scope (eight kinds, including a
/// regex-string match) — new kinds force every recipe author and every parser
/// site to reason about them, so additions are deliberate.
///
/// Predicates evaluate **only** against the payload of a `.succeeded` response —
/// failing outcomes are matched by ``FleetRecipeResponseMatcher/error(kind:)`` etc.
enum FleetRecipePayloadPredicate: Equatable, Hashable, Sendable {

    // MARK: keyValues payload

    /// Map contains `key` and the associated value equals `value` (exact string).
    case keyValueEquals(key: String, value: String)
    /// Map contains `key` regardless of its associated value.
    case keyValuePresent(key: String)

    // MARK: scalar payloads

    /// `.bool(let v)` payload equals the supplied boolean.
    case boolEquals(Bool)
    /// `.string(let v)` payload equals the supplied string.
    case stringEquals(String)
    /// `.string(let v)` payload matches the supplied regular expression
    /// (`NSRegularExpression`, anchored anywhere unless the pattern says otherwise).
    /// Parser-time validation rejects patterns that fail to compile.
    case stringMatches(regex: String)
    /// `.integer(let v)` payload satisfies the comparison against `value`.
    case integerCompare(op: FleetRecipeComparisonOp, value: Int64)
    /// `.double(let v)` payload satisfies the comparison against `value`.
    /// Comparison is performed in `Double` precision.
    case doubleCompare(op: FleetRecipeComparisonOp, value: Double)

    // MARK: list payload

    /// `.stringList(let xs)` payload contains the supplied string (exact match).
    case stringListContains(String)
}

// MARK: - Evaluation

extension FleetRecipePayloadPredicate {
    /// Whether this predicate matches the supplied payload.
    ///
    /// **Type discipline:** predicates only match their declared payload shape;
    /// e.g. `.boolEquals(true)` against a `.keyValues(...)` payload returns
    /// `false` rather than throwing. Recipe authors are expected to use
    /// `.data(...)` matchers against commands whose declared response shape
    /// matches the predicate kind.
    func evaluate(against payload: FleetCommandResponsePayload) -> Bool {
        switch self {

        case .keyValueEquals(let key, let value):
            if case .keyValues(let map) = payload {
                return map[key] == value
            }
            return false

        case .keyValuePresent(let key):
            if case .keyValues(let map) = payload {
                return map[key] != nil
            }
            return false

        case .boolEquals(let expected):
            if case .bool(let actual) = payload {
                return actual == expected
            }
            return false

        case .stringEquals(let expected):
            if case .string(let actual) = payload {
                return actual == expected
            }
            return false

        case .stringMatches(let pattern):
            guard case .string(let actual) = payload else { return false }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                // Parser-time validation should have caught uncompilable patterns;
                // at runtime an invalid pattern reads as "no match" rather than a
                // crash. The runner can additionally log this if it ever happens.
                return false
            }
            let range = NSRange(actual.startIndex..<actual.endIndex, in: actual)
            return regex.firstMatch(in: actual, options: [], range: range) != nil

        case .integerCompare(let op, let rhs):
            if case .integer(let lhs) = payload {
                return op.compare(lhs, rhs)
            }
            return false

        case .doubleCompare(let op, let rhs):
            if case .double(let lhs) = payload {
                return op.compare(lhs, rhs)
            }
            return false

        case .stringListContains(let needle):
            if case .stringList(let xs) = payload {
                return xs.contains(needle)
            }
            return false
        }
    }

    /// Whether the predicate is structurally well-formed (e.g. its regex compiles).
    /// Used by ``FleetRecipeBodyParser`` at parse time so authoring mistakes surface
    /// before the recipe ever runs.
    var isStructurallyValid: Bool {
        switch self {
        case .stringMatches(let pattern):
            return (try? NSRegularExpression(pattern: pattern, options: [])) != nil
        default:
            return true
        }
    }
}

// MARK: - Codable

extension FleetRecipePayloadPredicate: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind
        case key
        case value
        case op
        case integerValue
        case doubleValue
        case boolValue
        case stringValue
        case regex
    }

    private enum Kind: String, Codable {
        case keyValueEquals
        case keyValuePresent
        case boolEquals
        case stringEquals
        case stringMatches
        case integerCompare
        case doubleCompare
        case stringListContains
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .keyValueEquals:
            self = .keyValueEquals(
                key: try c.decode(String.self, forKey: .key),
                value: try c.decode(String.self, forKey: .value)
            )
        case .keyValuePresent:
            self = .keyValuePresent(key: try c.decode(String.self, forKey: .key))
        case .boolEquals:
            self = .boolEquals(try c.decode(Bool.self, forKey: .boolValue))
        case .stringEquals:
            self = .stringEquals(try c.decode(String.self, forKey: .stringValue))
        case .stringMatches:
            self = .stringMatches(regex: try c.decode(String.self, forKey: .regex))
        case .integerCompare:
            self = .integerCompare(
                op: try c.decode(FleetRecipeComparisonOp.self, forKey: .op),
                value: try c.decode(Int64.self, forKey: .integerValue)
            )
        case .doubleCompare:
            self = .doubleCompare(
                op: try c.decode(FleetRecipeComparisonOp.self, forKey: .op),
                value: try c.decode(Double.self, forKey: .doubleValue)
            )
        case .stringListContains:
            self = .stringListContains(try c.decode(String.self, forKey: .stringValue))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keyValueEquals(let key, let value):
            try c.encode(Kind.keyValueEquals, forKey: .kind)
            try c.encode(key, forKey: .key)
            try c.encode(value, forKey: .value)
        case .keyValuePresent(let key):
            try c.encode(Kind.keyValuePresent, forKey: .kind)
            try c.encode(key, forKey: .key)
        case .boolEquals(let v):
            try c.encode(Kind.boolEquals, forKey: .kind)
            try c.encode(v, forKey: .boolValue)
        case .stringEquals(let v):
            try c.encode(Kind.stringEquals, forKey: .kind)
            try c.encode(v, forKey: .stringValue)
        case .stringMatches(let pattern):
            try c.encode(Kind.stringMatches, forKey: .kind)
            try c.encode(pattern, forKey: .regex)
        case .integerCompare(let op, let value):
            try c.encode(Kind.integerCompare, forKey: .kind)
            try c.encode(op, forKey: .op)
            try c.encode(value, forKey: .integerValue)
        case .doubleCompare(let op, let value):
            try c.encode(Kind.doubleCompare, forKey: .kind)
            try c.encode(op, forKey: .op)
            try c.encode(value, forKey: .doubleValue)
        case .stringListContains(let v):
            try c.encode(Kind.stringListContains, forKey: .kind)
            try c.encode(v, forKey: .stringValue)
        }
    }
}
