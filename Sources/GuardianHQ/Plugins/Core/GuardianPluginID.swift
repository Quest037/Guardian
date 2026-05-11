import Foundation

/// Stable, validated identifier for a built-in Guardian integration (reverse-DNS style).
///
/// Only strings matching ``GuardianPluginID/isValidBuiltInRawValue(_:)`` are accepted. This keeps
/// log-template ownership and sidebar contributions namespaced so random modules cannot spoof a
/// known plugin id.
struct GuardianPluginID: Hashable, Sendable, Codable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    /// Namespace tail after the ``guardian.`` prefix — used when mapping a plugin id to
    /// owned `command.*` / `recipe.*` prefixes (e.g. `guardian.plugin.paladin` → `plugin.paladin`).
    var fleetNamespaceTail: String {
        guard rawValue.hasPrefix("guardian.") else { return "" }
        return String(rawValue.dropFirst("guardian.".count))
    }

    /// Mission Control assistant and related surfaces.
    static let paladin: GuardianPluginID = GuardianPluginID(uncheckedRawValue: "guardian.plugin.paladin")

    /// UI theme catalog and shared chrome defaults.
    static let theme: GuardianPluginID = GuardianPluginID(uncheckedRawValue: "guardian.plugin.theme")

    /// Validates and constructs; throws ``GuardianPluginIDError/invalidFormat`` when malformed.
    init(validating rawValue: String) throws {
        guard Self.isValidBuiltInRawValue(rawValue) else {
            throw GuardianPluginIDError.invalidFormat(rawValue)
        }
        self.rawValue = rawValue
    }

    /// Internal: known-safe literals only (e.g. ``paladin``).
    fileprivate init(uncheckedRawValue: String) {
        self.rawValue = uncheckedRawValue
    }

    /// `guardian.plugin.<segment>[.<segment>…]` — lowercase labels, digits, dots only; bounded length.
    static func isValidBuiltInRawValue(_ raw: String) -> Bool {
        guard raw.hasPrefix("guardian.plugin.") else { return false }
        let tail = String(raw.dropFirst("guardian.plugin.".count))
        guard !tail.isEmpty, tail.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.")
        guard tail.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard !tail.hasPrefix("."), !tail.hasSuffix("."), !tail.contains("..") else { return false }
        return true
    }
}

enum GuardianPluginIDError: Error {
    case invalidFormat(String)
}
