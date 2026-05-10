import Foundation

// MARK: - Parameter type kinds

/// Closed dictionary of parameter types supported by the command catalogue.
///
/// Kept deliberately small in v1 — new kinds force every parameter validator and every
/// recipe-DSL match site to reason about them. If a recipe needs a richer payload, it
/// can encode it as a string and parse on the consumer side until a real case is added.
enum FleetCommandParameterType: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    case bool
    case integer
    case double
    case string
    /// Ordered list of strings.
    case stringList
}

// MARK: - Parameter values (typed)

/// Single typed parameter value.
///
/// Codable so recipes can carry parameter literals through the JSON DSL. Equatable so
/// recipe-step matchers and tests can compare expected vs actual.
enum FleetCommandParameterValue: Equatable, Hashable, Sendable {
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case stringList([String])

    /// Type kind of this value. Used by ``FleetCommandParameterValidator``.
    var typeKind: FleetCommandParameterType {
        switch self {
        case .bool: return .bool
        case .integer: return .integer
        case .double: return .double
        case .string: return .string
        case .stringList: return .stringList
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
        }
    }
}

extension FleetCommandParameterValue: Codable {
    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable {
        case bool, integer, double, string, stringList
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
        }
    }
}

// MARK: - Parameter declarations (per-descriptor schema)

/// Describes a single named parameter the descriptor accepts. The catalogue's invoke
/// pipeline runs every supplied ``FleetCommandParameters`` set through
/// ``FleetCommandParameterValidator`` against the descriptor's declarations before
/// dispatching to the stack converter — invalid parameters short-circuit to
/// `.error(.dispatchFailed)`.
struct FleetCommandParameterDeclaration: Equatable, Hashable, Sendable {
    /// Stable identifier (e.g. `"mode"`, `"meters"`).
    let name: String
    /// Required kind. The validator rejects type mismatches.
    let type: FleetCommandParameterType
    /// When `true`, the validator rejects values where this parameter is missing.
    let isRequired: Bool
    /// Optional closed allow-list for `string` parameters (e.g. mode names). When set
    /// and the value is not a member, the validator reports `notInAllowedValues`.
    let allowedStringValues: Set<String>?
    /// Operator-facing label, used by future wizard UI to render a form.
    let humanLabel: String?

    init(
        name: String,
        type: FleetCommandParameterType,
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

/// Bundle of parameter values supplied at invocation time. Lookup is by name; types
/// are checked by the validator, not the bundle itself.
struct FleetCommandParameters: Equatable, Hashable, Sendable {
    let values: [String: FleetCommandParameterValue]

    static let empty = FleetCommandParameters(values: [:])

    init(values: [String: FleetCommandParameterValue] = [:]) {
        self.values = values
    }

    // MARK: Convenience accessors

    func value(named name: String) -> FleetCommandParameterValue? { values[name] }

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

extension FleetCommandParameters: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: FleetCommandParameterValue].self)
        self.init(values: dict)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

// MARK: - Validation

/// Single failure produced by ``FleetCommandParameterValidator``.
struct FleetCommandParameterValidationFailure: Equatable, Hashable, Sendable {
    let parameterName: String
    let reason: Reason

    enum Reason: Equatable, Hashable, Sendable {
        /// Required parameter was not present in the supplied bundle.
        case missing
        /// Supplied value's type kind does not match the declared kind.
        case typeMismatch(expected: FleetCommandParameterType, actual: FleetCommandParameterType)
        /// String value is not a member of the declared `allowedStringValues` set.
        case notInAllowedValues(allowed: Set<String>, actual: String)
    }

    /// Compact human-readable rendering for log lines and dispatch failure details.
    var loggable: String {
        switch reason {
        case .missing:
            return "missing required parameter '\(parameterName)'"
        case .typeMismatch(let expected, let actual):
            return "parameter '\(parameterName)' type \(actual.rawValue) does not match declared \(expected.rawValue)"
        case .notInAllowedValues(let allowed, let actual):
            let list = allowed.sorted().joined(separator: "|")
            return "parameter '\(parameterName)' value '\(actual)' not in {\(list)}"
        }
    }
}

/// Stateless validator — pure function over a parameter bundle and a declared schema.
/// Returns every failure (not just the first) so UIs can surface a complete picture.
enum FleetCommandParameterValidator: Sendable {

    static func validate(
        _ parameters: FleetCommandParameters,
        against schema: [FleetCommandParameterDeclaration]
    ) -> [FleetCommandParameterValidationFailure] {

        var failures: [FleetCommandParameterValidationFailure] = []

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

            // Type check. `integer` is implicitly accepted where `double` is declared
            // — recipe authors and call sites should not have to disambiguate `35` vs
            // `35.0` for a `meters` field.
            let acceptable: Bool
            switch (declaration.type, value.typeKind) {
            case (.double, .integer): acceptable = true
            default: acceptable = (declaration.type == value.typeKind)
            }
            if !acceptable {
                failures.append(.init(
                    parameterName: declaration.name,
                    reason: .typeMismatch(expected: declaration.type, actual: value.typeKind)
                ))
                continue
            }

            // Allow-list check (string parameters only).
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
