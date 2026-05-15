import Foundation

/// Reuses one ``LiveLeafletMapMarkerBuildResult`` per hub sample + presentation key so digest `onChange`
/// and throttled marker-only pushes do not each call the shared builder.
@MainActor
final class LiveLeafletMapPerHubVehicleBuildCache: ObservableObject {
    private var cached = LiveLeafletMapMarkerBuildResult(markers: [], motionDigest: "", motionSamples: [])
    private var lastHubToken: UInt64 = .max
    private var lastPresentationKey: String = ""

    func build(
        hubSampleToken: UInt64,
        presentationKey: String,
        build: () -> LiveLeafletMapMarkerBuildResult
    ) -> LiveLeafletMapMarkerBuildResult {
        if hubSampleToken == lastHubToken, presentationKey == lastPresentationKey {
            LiveLeafletMapMarkerPipelineProfiler.recordVehicleBuildCacheHit()
            return cached
        }
        lastHubToken = hubSampleToken
        lastPresentationKey = presentationKey
        let result = build()
        cached = result
        LiveLeafletMapMarkerPipelineProfiler.recordVehicleBuild()
        return cached
    }

    /// Call when route topology / roster bindings change (``.task(id:)`` structural rebuild).
    func invalidate() {
        lastHubToken = .max
        lastPresentationKey = ""
        cached = LiveLeafletMapMarkerBuildResult(markers: [], motionDigest: "", motionSamples: [])
    }
}
