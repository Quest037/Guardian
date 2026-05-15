import Foundation

/// Hub-driven marker-only apply rate for live maps (SwiftUI layer, before ``GuardianLeafletMissionBridgeCoalescer``).
enum LiveLeafletMapHubMarkerApplyThrottlePolicy {
    /// Default cap when ``GUARDIAN_MAP_HUB_MARKER_MAX_HZ`` is unset.
    static let defaultMaxHz: Double = 10

    /// `0` disables throttling (every digest-driven apply runs immediately). Otherwise max applies per second.
    static var resolvedMaxHz: Double {
        guard let raw = ProcessInfo.processInfo.environment["GUARDIAN_MAP_HUB_MARKER_MAX_HZ"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            let parsed = Double(raw),
            parsed >= 0
        else { return defaultMaxHz }
        return parsed
    }
}
