import Foundation

// MARK: - Errors

enum FleetRecipeStepIDError: Error, Equatable, Sendable {
    /// The supplied raw value did not satisfy ``FleetRecipeStepID/isValidRawValue(_:)``.
    case invalidFormat(String)
}

// MARK: - Identifier

/// Stable in-body identifier for a single step in a ``FleetRecipeBody``.
///
/// Step IDs are author-chosen labels (e.g. `"calibrate"`, `"verifyTelemetry"`) used
/// by matchers to express control flow (`branch(stepID:)`). They live entirely inside
/// a single body — they are **not** globally unique and have nothing to do with
/// ``FleetRecipeName``.
///
/// **Lexical rules:** ASCII letters, digits, and underscores only. Must start with
/// a letter. Bounded length. No whitespace, no punctuation, no case restriction so
/// authors can use camelCase or snake_case.
///
/// Examples:
/// - `calibrate`
/// - `verify_telemetry`
/// - `branchOnDecline`
struct FleetRecipeStepID: Hashable, Sendable, Codable, Identifiable, CustomStringConvertible {

    /// Maximum length of a step identifier. Long enough for descriptive author intent,
    /// short enough that the JSON DSL stays scannable.
    static let maximumLength: Int = 48

    let rawValue: String

    var id: String { rawValue }
    var description: String { rawValue }

    // MARK: Construction

    init(validating raw: String) throws {
        guard Self.isValidRawValue(raw) else {
            throw FleetRecipeStepIDError.invalidFormat(raw)
        }
        self.rawValue = raw
    }

    /// Internal known-safe literal escape hatch for tests and inline body authoring.
    fileprivate init(uncheckedRawValue: String) {
        self.rawValue = uncheckedRawValue
    }

    // MARK: Codable

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        try self.init(validating: raw)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: Validation

    static func isValidRawValue(_ raw: String) -> Bool {
        guard !raw.isEmpty, raw.count <= maximumLength else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
        )
        guard raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let firstLetters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        guard let first = raw.unicodeScalars.first, firstLetters.contains(first) else { return false }
        return true
    }
}

// MARK: - Internal known-safe literal factory

extension FleetRecipeStepID {
    /// Internal-only factory for literal step IDs declared at body-construction time.
    static func literal(_ raw: String, file: StaticString = #file, line: UInt = #line) -> FleetRecipeStepID {
        assert(Self.isValidRawValue(raw), "Invalid FleetRecipeStepID literal: \(raw)", file: file, line: line)
        return FleetRecipeStepID(uncheckedRawValue: raw)
    }
}
