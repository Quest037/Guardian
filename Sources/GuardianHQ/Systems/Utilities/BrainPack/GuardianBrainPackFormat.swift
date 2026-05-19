import Foundation

/// Schema and file conventions for **Guardian Brain Pack** (`.guardianbrain`).
enum GuardianBrainPackFormat {
    /// Increment when the on-disk JSON shape changes incompatibly.
    static let currentFormatVersion = 1

    static let supportedFormatVersionRange = 1...1

    static let fileExtension = "guardianbrain"

    static let packFileName = "brain.guardianbrain"

    /// Mission builds at or above this format version can import packs produced by this build.
    static var compatibilityMatrixSummary: String {
        "Guardian Mission / Training builds shipping format version \(currentFormatVersion) import packs with `format_version` \(supportedFormatVersionRange.lowerBound)–\(supportedFormatVersionRange.upperBound) only."
    }
}
