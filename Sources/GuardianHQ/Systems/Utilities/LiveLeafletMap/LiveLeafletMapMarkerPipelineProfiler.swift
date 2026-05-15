import Foundation

/// Rolling counters for live map marker builder + hub apply throttle (Debug builds only).
struct LiveLeafletMapMarkerPipelineProfileAccumulator: Equatable, Sendable {
    var vehicleBuilds: Int = 0
    var vehicleBuildCacheHits: Int = 0
    var throttleCoalescedRequests: Int = 0
    var throttleImmediateFlushes: Int = 0
    var markerOnlyApplies: Int = 0
    var imageCacheHits: Int = 0
    var imageCacheMisses: Int = 0
    var imageCacheEncodes: Int = 0

    func summaryLine() -> String {
        """
        vehicleBuild=\(vehicleBuilds) buildCacheHit=\(vehicleBuildCacheHits) \
        throttleCoalesce=\(throttleCoalescedRequests) throttleFlush=\(throttleImmediateFlushes) \
        markerApply=\(markerOnlyApplies) imgHit=\(imageCacheHits) imgMiss=\(imageCacheMisses) \
        imgEncode=\(imageCacheEncodes)
        """
    }
}

#if DEBUG
@MainActor
enum LiveLeafletMapMarkerPipelineProfiler {
    static let loggingEnabledEnvKey = "GUARDIAN_MAP_MARKER_PROFILE"
    private static let summaryInterval: TimeInterval = 5.0

    private static var accumulator = LiveLeafletMapMarkerPipelineProfileAccumulator()
    private static var lastSummaryTime = CFAbsoluteTimeGetCurrent()

    static var isLoggingEnabled: Bool {
        ProcessInfo.processInfo.environment[loggingEnabledEnvKey] == "1"
    }

    static func snapshotForTesting() -> LiveLeafletMapMarkerPipelineProfileAccumulator {
        accumulator
    }

    static func resetForTesting() {
        accumulator = LiveLeafletMapMarkerPipelineProfileAccumulator()
        lastSummaryTime = CFAbsoluteTimeGetCurrent()
    }

    static func recordVehicleBuild() {
        accumulator.vehicleBuilds += 1
        syncImageCacheCounters()
        maybeEmitSummary()
    }

    static func recordVehicleBuildCacheHit() {
        accumulator.vehicleBuildCacheHits += 1
        syncImageCacheCounters()
        maybeEmitSummary()
    }

    static func recordThrottleCoalescedRequest() {
        accumulator.throttleCoalescedRequests += 1
        maybeEmitSummary()
    }

    static func recordThrottleImmediateFlush() {
        accumulator.throttleImmediateFlushes += 1
        maybeEmitSummary()
    }

    static func recordMarkerOnlyApply() {
        accumulator.markerOnlyApplies += 1
        maybeEmitSummary()
    }

    private static func syncImageCacheCounters() {
        let stats = Utilities.liveLeafletMap.markerImageCache.statistics
        accumulator.imageCacheHits = stats.hits
        accumulator.imageCacheMisses = stats.misses
        accumulator.imageCacheEncodes = stats.encodes
    }

    private static func maybeEmitSummary() {
        guard isLoggingEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSummaryTime >= summaryInterval else { return }
        lastSummaryTime = now
        print("[GuardianHQ][MapMarker][Profile] \(accumulator.summaryLine())")
    }
}
#else
@MainActor
enum LiveLeafletMapMarkerPipelineProfiler {
    static let loggingEnabledEnvKey = "GUARDIAN_MAP_MARKER_PROFILE"

    static var isLoggingEnabled: Bool { false }

    static func recordVehicleBuild() {}
    static func recordVehicleBuildCacheHit() {}
    static func recordThrottleCoalescedRequest() {}
    static func recordThrottleImmediateFlush() {}
    static func recordMarkerOnlyApply() {}
}
#endif
