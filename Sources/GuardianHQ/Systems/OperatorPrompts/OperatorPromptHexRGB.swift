import Foundation

// MARK: - OperatorPromptHexRGB

/// Parses `#RRGGBB` / `RRGGBB` strings from **plugins or core constants** into normalized 6-digit lowercase hex.
enum OperatorPromptHexRGB {

    private static let hexScalars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")

    /// Returns normalized lowercased 6-digit hex **without** `#`, or `nil` if invalid.
    static func normalizedRGBHex6(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return nil }
        guard s.unicodeScalars.allSatisfy({ hexScalars.contains($0) }) else { return nil }
        return s.lowercased()
    }

    static func rgbUInt8Components(hex6 raw: String) -> (UInt8, UInt8, UInt8)? {
        guard let h = normalizedRGBHex6(raw), let v = UInt32(h, radix: 16) else { return nil }
        return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }
}
