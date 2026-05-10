import Foundation

// MARK: - Reserved verbs

/// Closed dictionary of reserved verbs in v1 (`do | get | cancel`).
///
/// Adding a new verb is a deliberate Layer 0 change: every stack converter and every
/// caller has to reason about its semantics. `subscribe` is intentionally **not** here —
/// streaming responses are deferred to a later milestone and existing telemetry pipes
/// cover live data needs today.
enum FleetCommandReservedVerb: String, CaseIterable, Sendable, Hashable {
    case `do`
    case get
    case cancel

    static var allRawValues: Set<String> {
        Set(allCases.map(\.rawValue))
    }
}

// MARK: - Errors

enum FleetCommandNameError: Error, Equatable, Sendable {
    /// The supplied raw value did not satisfy ``FleetCommandName/isValidRawValue(_:)``.
    case invalidFormat(String)
}

// MARK: - Identifier

/// Strongly-typed, validated identifier for an entry in ``FleetCommandsCatalogue``.
///
/// **Shape:** `command.<addressing-segments>.<verb>.<specifier-segments>`
///
/// - `command.` prefix is mandatory and identifies the universal-bus namespace.
/// - The **addressing path** (everything between `command` and the verb) routes the
///   command to the owning system / subsystem / plugin (e.g. `fleet.vehicle`,
///   later `mc.mre`, `plugin.paladin`).
/// - The **verb** is exactly one segment from ``FleetCommandReservedVerb``.
/// - The **specifier** (everything after the verb) names the operation. At least one
///   segment is required.
///
/// **Lexical rules:** lowercase ASCII letters, digits, and dots only. No leading or
/// trailing dot. No `..`. Bounded length. These rules mirror the
/// ``GuardianPluginID/isValidBuiltInRawValue(_:)`` convention so namespaces from both
/// systems compose without conflict.
///
/// Examples:
/// - `command.fleet.vehicle.do.arm`
/// - `command.fleet.vehicle.do.calibrate.compass`
/// - `command.fleet.vehicle.get.telemetry.battery`
/// - `command.fleet.vehicle.cancel.calibration`
struct FleetCommandName: Hashable, Sendable, Codable, Identifiable, CustomStringConvertible {

    /// Maximum total length of the dotted identifier. Keeps log lines bounded and
    /// discourages encoding parameters into the namespace.
    static let maximumLength: Int = 128

    let rawValue: String

    var id: String { rawValue }
    var description: String { rawValue }

    // MARK: Construction

    /// Validating constructor. Throws ``FleetCommandNameError/invalidFormat(_:)`` if
    /// `raw` does not satisfy ``isValidRawValue(_:)``.
    init(validating raw: String) throws {
        guard Self.isValidRawValue(raw) else {
            throw FleetCommandNameError.invalidFormat(raw)
        }
        self.rawValue = raw
    }

    /// Internal escape hatch for known-safe literals declared at registration time.
    /// Keeps the call-site terse while preserving the validating path for any external
    /// or runtime-derived identifiers. Mirrors ``GuardianPluginID/init(uncheckedRawValue:)``.
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
    /// - starts with `command.`
    /// - length within ``maximumLength``
    /// - lowercase ASCII letters, digits, and dots only
    /// - no leading / trailing dot, no `..`
    /// - segment layout `command . addressing+ . verb . specifier+`
    /// - exactly one verb segment from ``FleetCommandReservedVerb``
    /// - at least one addressing segment and at least one specifier segment
    static func isValidRawValue(_ raw: String) -> Bool {
        guard raw.hasPrefix("command."), raw.count <= maximumLength else { return false }
        guard !raw.hasPrefix("."), !raw.hasSuffix("."), !raw.contains("..") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.")
        guard raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }

        let segments = raw.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard segments.count >= 4 else { return false }
        guard segments[0] == "command" else { return false }

        let verbs = FleetCommandReservedVerb.allRawValues
        guard let verbIndex = segments.firstIndex(where: { verbs.contains($0) }) else {
            return false
        }
        // Need at least one addressing segment and at least one specifier segment.
        guard verbIndex >= 2 else { return false }
        guard verbIndex < segments.count - 1 else { return false }
        // Defensive: only one verb segment in the identifier (verbs are reserved words and
        // should not also appear as addressing or specifier labels).
        let verbCount = segments.filter { verbs.contains($0) }.count
        guard verbCount == 1 else { return false }
        return true
    }

    // MARK: Decomposition

    private var segments: [String] {
        rawValue.split(separator: ".").map(String.init)
    }

    private var verbIndex: Int? {
        let verbs = FleetCommandReservedVerb.allRawValues
        return segments.firstIndex(where: { verbs.contains($0) })
    }

    /// Reserved verb extracted from the identifier, or `nil` if malformed.
    var verb: FleetCommandReservedVerb? {
        guard let idx = verbIndex else { return nil }
        return FleetCommandReservedVerb(rawValue: segments[idx])
    }

    /// Addressing path between `command` and the verb (e.g. `["fleet", "vehicle"]`).
    var addressingPath: [String] {
        guard let idx = verbIndex, idx > 1 else { return [] }
        return Array(segments[1..<idx])
    }

    /// Operation specifier following the verb (e.g. `["calibrate", "compass"]`).
    var specifier: [String] {
        guard let idx = verbIndex, idx + 1 < segments.count else { return [] }
        return Array(segments[(idx + 1)...])
    }

    /// Whether this name is owned (or could be owned) by the given namespace prefix.
    ///
    /// Used by Stage F manifest enforcement: `command.plugin.paladin.do.foo` is owned
    /// by namespace prefix `plugin.paladin`.
    func isUnderAddressingPrefix(_ prefix: [String]) -> Bool {
        let path = addressingPath
        guard prefix.count <= path.count else { return false }
        return Array(path.prefix(prefix.count)) == prefix
    }
}

// MARK: - Internal known-safe literal factory

extension FleetCommandName {
    /// Internal-only factory for literal command names declared at registration time.
    /// Bootstrap code uses this (and `assertValidLiteral` below) to keep call sites terse
    /// while still catching typos in debug builds.
    ///
    /// Public callers should prefer ``init(validating:)`` so the failure path is explicit.
    static func literal(_ raw: String, file: StaticString = #file, line: UInt = #line) -> FleetCommandName {
        // In DEBUG, a malformed literal is a programmer error and trips an assertion.
        // In RELEASE, we still construct the instance so the registry can carry the
        // (invalid) name through to a later validation pass — the catalogue refuses
        // to register descriptors whose names fail ``isValidRawValue``.
        assert(Self.isValidRawValue(raw), "Invalid FleetCommandName literal: \(raw)", file: file, line: line)
        return FleetCommandName(uncheckedRawValue: raw)
    }
}
