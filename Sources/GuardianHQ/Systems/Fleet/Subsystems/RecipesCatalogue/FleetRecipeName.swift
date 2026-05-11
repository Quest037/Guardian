import Foundation

// MARK: - Errors

enum FleetRecipeNameError: Error, Equatable, Sendable {
    /// The supplied raw value did not satisfy ``FleetRecipeName/isValidRawValue(_:)``.
    case invalidFormat(String)
}

// MARK: - Identifier

/// Strongly-typed, validated identifier for an entry in ``FleetRecipesCatalogue``.
///
/// **Shape:** `recipe.<subsystem>.<specifier-segments>`
///
/// - `recipe.` prefix is mandatory and identifies the universal recipe namespace.
/// - The **subsystem** segment immediately after `recipe` claims a recipe domain
///   (e.g. `fleet`, `mc`, `plugin.<id>`). Subsystem ownership composes the same way
///   plugin namespaces do — Stage F manifest claims enforce this.
/// - The **specifier** (everything after the subsystem) names the recipe operation.
///   At least one specifier segment is required.
///
/// **Lexical rules:** lowercase ASCII letters, digits, and dots only. No leading or
/// trailing dot. No `..`. Bounded length. These rules mirror
/// ``FleetCommandName/isValidRawValue(_:)`` and ``GuardianPluginID/isValidBuiltInRawValue(_:)``
/// so namespaces from all three systems compose without conflict.
///
/// Recipes deliberately do **not** carry a reserved verb segment (the Layer 0 `do |
/// get | cancel` distinction is a command-level concept). Recipes orchestrate
/// commands; the verb belongs to the commands they invoke.
///
/// Examples:
/// - `recipe.fleet.calibrate.compass`
/// - `recipe.fleet.calibrate.accelerometer`
/// - `recipe.fleet.diagnose.armprobe`
/// - `recipe.fleet.errors.fix.compass.interference`
struct FleetRecipeName: Hashable, Sendable, Codable, Identifiable, CustomStringConvertible {

    /// Maximum total length of the dotted identifier. Same cap as ``FleetCommandName``
    /// so logs and audit lines stay bounded.
    static let maximumLength: Int = 128

    /// Minimum total segments: `recipe` + subsystem + at least one specifier = 3.
    static let minimumSegmentCount: Int = 3

    let rawValue: String

    var id: String { rawValue }
    var description: String { rawValue }

    // MARK: Construction

    /// Validating constructor. Throws ``FleetRecipeNameError/invalidFormat(_:)`` if
    /// `raw` does not satisfy ``isValidRawValue(_:)``.
    init(validating raw: String) throws {
        guard Self.isValidRawValue(raw) else {
            throw FleetRecipeNameError.invalidFormat(raw)
        }
        self.rawValue = raw
    }

    /// Internal escape hatch for known-safe literals declared at registration time.
    /// Mirrors ``FleetCommandName/init(uncheckedRawValue:)`` / ``GuardianPluginID/init(uncheckedRawValue:)``.
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

    /// Closed lexical + structural validation:
    /// - starts with `recipe.`
    /// - length within ``maximumLength``
    /// - lowercase ASCII letters, digits, and dots only
    /// - no leading / trailing dot, no `..`
    /// - at least ``minimumSegmentCount`` dotted segments total (`recipe`, subsystem,
    ///   ≥1 specifier).
    static func isValidRawValue(_ raw: String) -> Bool {
        guard raw.hasPrefix("recipe."), raw.count <= maximumLength else { return false }
        guard !raw.hasPrefix("."), !raw.hasSuffix("."), !raw.contains("..") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.")
        guard raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }

        let segments = raw.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard segments.count >= minimumSegmentCount else { return false }
        guard segments[0] == "recipe" else { return false }
        guard !segments[1].isEmpty else { return false }
        // Specifier must contribute at least one non-empty segment.
        guard segments.dropFirst(2).allSatisfy({ !$0.isEmpty }) else { return false }
        guard !segments.dropFirst(2).isEmpty else { return false }
        return true
    }

    // MARK: Decomposition

    private var segments: [String] {
        rawValue.split(separator: ".").map(String.init)
    }

    /// First segment after `recipe.` — e.g. `"fleet"`.
    var subsystem: String {
        let parts = segments
        return parts.count >= 2 ? parts[1] : ""
    }

    /// Specifier segments after the subsystem — e.g. `["calibrate", "compass"]`.
    var specifier: [String] {
        let parts = segments
        guard parts.count > 2 else { return [] }
        return Array(parts[2...])
    }

    /// Whether this name is owned (or could be owned) by the given namespace prefix.
    ///
    /// Used by Stage F manifest enforcement: `recipe.plugin.paladin.calibrate.foo`
    /// is owned by namespace prefix `["plugin", "paladin"]`.
    ///
    /// The prefix is matched against the segments **after** `recipe.`, so a
    /// `recipe.fleet.calibrate.compass` is under prefix `["fleet"]` and under
    /// prefix `["fleet", "calibrate"]`, but not under `["fleet", "diagnose"]`.
    func isUnderNamespacePrefix(_ prefix: [String]) -> Bool {
        let tail = segments.dropFirst()
        guard prefix.count <= tail.count else { return false }
        return Array(tail.prefix(prefix.count)) == prefix
    }
}

// MARK: - Internal known-safe literal factory

extension FleetRecipeName {
    /// Internal-only factory for literal recipe names declared at registration time.
    /// Bootstrap and subsystem registration code uses this to keep call sites terse
    /// while still catching typos in debug builds.
    ///
    /// Public callers should prefer ``init(validating:)`` so the failure path is explicit.
    static func literal(_ raw: String, file: StaticString = #file, line: UInt = #line) -> FleetRecipeName {
        assert(Self.isValidRawValue(raw), "Invalid FleetRecipeName literal: \(raw)", file: file, line: line)
        return FleetRecipeName(uncheckedRawValue: raw)
    }
}
