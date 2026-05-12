import Foundation

/// MCS staging map: when a SITL vehicle is dragged, we keep an optimistic overlay until hub telemetry **stably**
/// agrees (MAVSDK can briefly publish stale lat/lon right after a sim teleport) or the wait expires.
enum MissionControlSetupSimDragOverlayPolicy {
    /// Degrees — same order of magnitude as a few metres at mid-latitudes.
    static let hubMatchEpsilonDegrees: Double = 2.5e-5
    static let pendingSyncTimeoutSeconds: TimeInterval = 10
    /// Hub must stay within epsilon of the dragged pose for this long before we drop the optimistic overlay.
    static let hubAgreesSustainSeconds: TimeInterval = 0.75

    static func shouldClearOverlayByTimeout(overlayStartedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(overlayStartedAt) >= pendingSyncTimeoutSeconds
    }

    /// Hub pose agrees with the optimistic drag within ``hubMatchEpsilonDegrees``.
    static func hubMatches(pendingCoordinate: RouteCoordinate, hubCoordinate: RouteCoordinate) -> Bool {
        abs(hubCoordinate.lat - pendingCoordinate.lat) < hubMatchEpsilonDegrees
            && abs(hubCoordinate.lon - pendingCoordinate.lon) < hubMatchEpsilonDegrees
    }

    /// While hub keeps matching, anchor the streak start at the first match; any divergent hub sample clears it.
    static func updatedHubAgreesSince(hubMatchesPending: Bool, previous: Date?, now: Date) -> Date? {
        hubMatchesPending ? (previous ?? now) : nil
    }

    static func isSustainedHubAgreement(hubAgreesSince: Date?, now: Date) -> Bool {
        guard let since = hubAgreesSince else { return false }
        return now.timeIntervalSince(since) >= hubAgreesSustainSeconds
    }
}
