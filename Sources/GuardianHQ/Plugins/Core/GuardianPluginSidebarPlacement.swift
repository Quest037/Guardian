import Foundation

/// Where a plugin contributes an extra sidebar control.
enum GuardianPluginSidebarPlacement: String, Sendable, Codable, Hashable, CaseIterable, Identifiable {
    /// Upper scrollable region with primary app destinations (and optional plugin shortcuts).
    case primary
    /// Lower pinned rail: optional plugin rows, then built-in Settings and Plugins, then version.
    case secondary

    var id: String { rawValue }
}
