import Foundation

/// Human-facing metadata for a registered integration.
struct GuardianPluginManifest: Identifiable, Equatable, Sendable {
    let pluginID: GuardianPluginID
    let displayName: String
    let shortDescription: String

    var id: String { pluginID.rawValue }
}
