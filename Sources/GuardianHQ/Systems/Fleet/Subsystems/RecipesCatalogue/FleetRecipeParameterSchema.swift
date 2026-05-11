import Foundation

// MARK: - Parameter type kinds

/// Closed dictionary of parameter types supported by the recipe catalogue.
///
/// Sibling of ``FleetCommandParameterType`` (locked-decision: "mirror Layer 0 shape
/// as a sibling type so future divergence is cheap"). Keep both in lockstep until a
/// real divergence is needed — the DSL parser and recipe authors should not have to
/// reason about two type vocabularies for the same shapes.
enum FleetRecipeParameterType: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    case bool
    case integer
    case double
    case string
    /// Ordered list of strings.
    case stringList
}

// MARK: - Parameter values (typed)

/// Single typed parameter value for a recipe step.
///
/// Codable so recipes can carry parameter literals through the JSON DSL. Equatable
/// so DSL matchers and tests can compare expected vs actual.
///
/// `reference(name:)` is intentionally part of the recipe-side value enum, not the
/// Layer 0 command parameter enum: references are resolved by ``FleetRecipeRunner``
/// against the caller-supplied recipe parameters immediately before dispatch.
enum FleetRecipeParameterValue: Equatable, Hashable, Sendable {
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case stringList([String])
    /// Reference to a caller-supplied recipe parameter. Valid only inside a step's
    /// `parameters` map; run-time parameter bundles must provide literal values.
    case reference(name: String)

    /// Type kind of this value. Used by ``FleetRecipeParameterValidator``.
    var typeKind: FleetRecipeParameterType? {
        switch self {
        case .bool: return .bool
        case .integer: return .integer
        case .double: return .double
        case .string: return .string
        case .stringList: return .stringList
        case .reference: return nil
        }
    }

    /// Stable string rendering for logs / audit trails. Floating-point uses up to 6
    /// fractional digits, trailing zeros trimmed.
    var loggable: String {
        switch self {
        case .bool(let b): return b ? "true" : "false"
        case .integer(let i): return String(i)
        case .double(let d):
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 6
            formatter.numberStyle = .decimal
            return formatter.string(from: d as NSNumber) ?? String(d)
        case .string(let s): return s
        case .stringList(let xs): return "[" + xs.joined(separator: ", ") + "]"
        case .reference(let name): return "$\(name)"
        }
    }

    /// Project a recipe-side typed value down to the Layer 0 ``FleetCommandParameterValue``
    /// it corresponds to. The two enums are case-for-case parallel today.
    var asCommandParameterValue: FleetCommandParameterValue {
        switch self {
        case .bool(let v): return .bool(v)
        case .integer(let v): return .integer(v)
        case .double(let v): return .double(v)
        case .string(let v): return .string(v)
        case .stringList(let v): return .stringList(v)
        case .reference(let name):
            preconditionFailure("Unresolved recipe parameter reference '\(name)' reached Layer 0 projection.")
        }
    }
}

extension FleetRecipeParameterValue: Codable {
    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable {
        case bool, integer, double, string, stringList, reference
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .bool: self = .bool(try container.decode(Bool.self, forKey: .value))
        case .integer: self = .integer(try container.decode(Int64.self, forKey: .value))
        case .double: self = .double(try container.decode(Double.self, forKey: .value))
        case .string: self = .string(try container.decode(String.self, forKey: .value))
        case .stringList: self = .stringList(try container.decode([String].self, forKey: .value))
        case .reference: self = .reference(name: try container.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let v):
            try container.encode(Kind.bool, forKey: .kind)
            try container.encode(v, forKey: .value)
        case .integer(let v):
            try container.encode(Kind.integer, forKey: .kind)
            try container.encode(v, forKey: .value)
        case .double(let v):
            try container.encode(Kind.double, forKey: .kind)
            try container.encode(v, forKey: .value)
        case .string(let v):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(v, forKey: .value)
        case .stringList(let v):
            try container.encode(Kind.stringList, forKey: .kind)
            try container.encode(v, forKey: .value)
        case .reference(let v):
            try container.encode(Kind.reference, forKey: .kind)
            try container.encode(v, forKey: .value)
        }
    }
}

// MARK: - Parameter declarations (per-descriptor schema)

/// Describes a single named parameter the recipe accepts. The recipe runner runs every
/// supplied ``FleetRecipeParameters`` set through ``FleetRecipeParameterValidator``
/// against the descriptor's declarations before starting execution — invalid
/// parameters short-circuit the run with a parse-time failure.
struct FleetRecipeParameterDeclaration: Equatable, Hashable, Sendable {
    /// Stable identifier (e.g. `"vehicleID"`, `"meters"`).
    let name: String
    /// Required kind. The validator rejects type mismatches.
    let type: FleetRecipeParameterType
    /// When `true`, the validator rejects bundles where this parameter is missing.
    let isRequired: Bool
    /// Optional closed allow-list for `string` parameters. When set and the value is
    /// not a member, the validator reports `notInAllowedValues`.
    let allowedStringValues: Set<String>?
    /// Operator-facing label, surfaced by wizard / inspector UI.
    let humanLabel: String?

    init(
        name: String,
        type: FleetRecipeParameterType,
        required: Bool = true,
        allowedStringValues: Set<String>? = nil,
        humanLabel: String? = nil
    ) {
        self.name = name
        self.type = type
        self.isRequired = required
        self.allowedStringValues = allowedStringValues
        self.humanLabel = humanLabel
    }
}

// MARK: - Parameter bundle (call-site values)

/// Bundle of parameter values supplied at recipe-run time. Lookup is by name; types
/// are checked by the validator, not the bundle itself.
struct FleetRecipeParameters: Equatable, Hashable, Sendable {
    let values: [String: FleetRecipeParameterValue]

    static let empty = FleetRecipeParameters(values: [:])

    init(values: [String: FleetRecipeParameterValue] = [:]) {
        self.values = values
    }

    // MARK: Convenience accessors

    func value(named name: String) -> FleetRecipeParameterValue? { values[name] }

    func bool(named name: String) -> Bool? {
        if case .bool(let v) = values[name] { return v }
        return nil
    }

    func integer(named name: String) -> Int64? {
        if case .integer(let v) = values[name] { return v }
        return nil
    }

    func double(named name: String) -> Double? {
        if case .double(let v) = values[name] { return v }
        if case .integer(let v) = values[name] { return Double(v) }
        return nil
    }

    func string(named name: String) -> String? {
        if case .string(let v) = values[name] { return v }
        return nil
    }

    func stringList(named name: String) -> [String]? {
        if case .stringList(let v) = values[name] { return v }
        return nil
    }
}

extension FleetRecipeParameters: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: FleetRecipeParameterValue].self)
        self.init(values: dict)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

// MARK: - Validation

/// Single failure produced by ``FleetRecipeParameterValidator``.
struct FleetRecipeParameterValidationFailure: Equatable, Hashable, Sendable {
    let parameterName: String
    let reason: Reason

    enum Reason: Equatable, Hashable, Sendable {
        /// Required parameter was not present in the supplied bundle.
        case missing
        /// Supplied value's type kind does not match the declared kind.
        case typeMismatch(expected: FleetRecipeParameterType, actual: FleetRecipeParameterType)
        /// String value is not a member of the declared `allowedStringValues` set.
        case notInAllowedValues(allowed: Set<String>, actual: String)
        /// A `reference(...)` value was supplied as a run-time parameter. References
        /// are DSL authoring constructs and must be resolved before validation.
        case referenceNotAllowed
    }

    /// Compact human-readable rendering for log lines and run-start failure details.
    var loggable: String {
        switch reason {
        case .missing:
            return "missing required parameter '\(parameterName)'"
        case .typeMismatch(let expected, let actual):
            return "parameter '\(parameterName)' type \(actual.rawValue) does not match declared \(expected.rawValue)"
        case .notInAllowedValues(let allowed, let actual):
            let list = allowed.sorted().joined(separator: "|")
            return "parameter '\(parameterName)' value '\(actual)' not in {\(list)}"
        case .referenceNotAllowed:
            return "parameter '\(parameterName)' is an unresolved reference; run-time parameter bundles must provide literal values"
        }
    }
}

/// Stateless validator — pure function over a parameter bundle and a declared schema.
/// Returns every failure (not just the first) so UIs can surface a complete picture.
///
/// Sibling of ``FleetCommandParameterValidator``. Field-for-field parity is
/// intentional (locked-decision: "mirror Layer 0 shape as a sibling type"); divergence
/// should be an explicit, reviewed change.
enum FleetRecipeParameterValidator: Sendable {

    static func validate(
        _ parameters: FleetRecipeParameters,
        against schema: [FleetRecipeParameterDeclaration]
    ) -> [FleetRecipeParameterValidationFailure] {

        var failures: [FleetRecipeParameterValidationFailure] = []

        for declaration in schema {
            let supplied = parameters.value(named: declaration.name)

            switch (supplied, declaration.isRequired) {
            case (nil, true):
                failures.append(.init(parameterName: declaration.name, reason: .missing))
                continue
            case (nil, false):
                continue
            case (.some, _):
                break
            }

            guard let value = supplied else { continue }
            guard let actualType = value.typeKind else {
                failures.append(.init(
                    parameterName: declaration.name,
                    reason: .referenceNotAllowed
                ))
                continue
            }

            // Same widening rule as Layer 0: integer-where-double-declared is accepted
            // so recipe authors do not have to disambiguate `35` vs `35.0` for a
            // `meters` field.
            let acceptable: Bool
            switch (declaration.type, actualType) {
            case (.double, .integer): acceptable = true
            default: acceptable = (declaration.type == actualType)
            }
            if !acceptable {
                failures.append(.init(
                    parameterName: declaration.name,
                    reason: .typeMismatch(expected: declaration.type, actual: actualType)
                ))
                continue
            }

            if case .string(let s) = value, let allowed = declaration.allowedStringValues, !allowed.contains(s) {
                failures.append(.init(
                    parameterName: declaration.name,
                    reason: .notInAllowedValues(allowed: allowed, actual: s)
                ))
            }
        }

        return failures
    }
}
