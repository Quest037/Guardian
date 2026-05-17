import Foundation

/// How wingmen align yaw while joining / holding a formation slot (playground + MRE squad follow).
enum MissionSquadFormationHeadingPolicy {
    /// v1 default: match the primary's current heading (fallback when hub heading is missing).
    enum Source: String, Sendable, Equatable {
        case matchPrimary
    }

    /// Resolved target yaw (degrees) for OFFBOARD / Guided streams and assembly checks.
    static func resolvedTargetHeadingDeg(
        source: Source = .matchPrimary,
        primaryHeadingDeg: Double,
        fallbackHeadingDeg: Double? = nil
    ) -> Double {
        switch source {
        case .matchPrimary:
            if primaryHeadingDeg.isFinite {
                return primaryHeadingDeg
            }
            return fallbackHeadingDeg ?? 0
        }
    }

    /// Hub heading for formation alignment — prefer ``FleetHubVehicleTelemetry/headingDeg`` (updates live on SITL); fall back to ``yawDeg``.
    static func wingmanHeadingDeg(hub: FleetHubVehicleTelemetry?) -> Double? {
        guard let hub else { return nil }
        if let heading = hub.headingDeg, heading.isFinite { return heading }
        if let yaw = hub.yawDeg, yaw.isFinite { return yaw }
        return nil
    }

    static func headingErrorDeg(
        wingmanHeadingDeg: Double?,
        targetHeadingDeg: Double
    ) -> Double? {
        guard let wingmanHeadingDeg, wingmanHeadingDeg.isFinite, targetHeadingDeg.isFinite else { return nil }
        return MissionTelemetryGeo.angleDifferenceDeg(targetHeadingDeg, wingmanHeadingDeg)
    }

    static func headingErrorDeg(
        hub: FleetHubVehicleTelemetry?,
        targetHeadingDeg: Double
    ) -> Double? {
        headingErrorDeg(
            wingmanHeadingDeg: wingmanHeadingDeg(hub: hub),
            targetHeadingDeg: targetHeadingDeg
        )
    }

    static func isHeadingAligned(
        wingmanHeadingDeg: Double?,
        targetHeadingDeg: Double,
        toleranceDeg: Double = MissionSquadConvoyFollowControlPolicy.convoyAssemblyHeadingToleranceDeg
    ) -> Bool {
        guard let error = headingErrorDeg(wingmanHeadingDeg: wingmanHeadingDeg, targetHeadingDeg: targetHeadingDeg)
        else { return false }
        return abs(error) <= toleranceDeg
    }

    static func isHeadingAligned(
        hub: FleetHubVehicleTelemetry?,
        targetHeadingDeg: Double,
        toleranceDeg: Double = MissionSquadConvoyFollowControlPolicy.convoyAssemblyHeadingToleranceDeg
    ) -> Bool {
        isHeadingAligned(
            wingmanHeadingDeg: wingmanHeadingDeg(hub: hub),
            targetHeadingDeg: targetHeadingDeg,
            toleranceDeg: toleranceDeg
        )
    }
}
