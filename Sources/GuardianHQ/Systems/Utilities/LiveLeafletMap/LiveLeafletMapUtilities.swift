import Foundation

/// Global Utilities entry for shared live Leaflet map marker construction (Phase B).
@MainActor
enum LiveLeafletMapUtilities {
    typealias Focus = LiveLeafletMapMarkerFocus
    typealias BuildInputs = LiveLeafletMapMarkerBuildInputs
    typealias BuildResult = LiveLeafletMapMarkerBuildResult
    typealias ImageCache = LiveLeafletMapMarkerCache
    typealias ImageCacheKey = LiveLeafletMapMarkerImageCacheKey
    typealias HubMarkerApplyThrottle = LiveLeafletMapHubMarkerApplyThrottle
    typealias PerHubVehicleBuildCache = LiveLeafletMapPerHubVehicleBuildCache
    typealias HubSampleToken = LiveLeafletMapHubSampleToken

    @MainActor
    static func buildMapVehicleMarkersLive(
        inputs: LiveLeafletMapMarkerBuildInputs,
        imageCache: LiveLeafletMapMarkerCache = Utilities.liveLeafletMap.markerImageCache,
        rosterAccessibilityTitle: ((MissionRunAssignment, Mission) -> String?)? = nil
    ) -> LiveLeafletMapMarkerBuildResult {
        LiveLeafletMapMarkerBuilder.build(
            inputs: inputs,
            imageCache: imageCache,
            rosterAccessibilityTitle: rosterAccessibilityTitle
        )
    }

    @MainActor
    static func buildMCSStagingMapVehicleMarkers(
        inputs: LiveLeafletMapMCSStagingMarkerBuildInputs,
        imageCache: LiveLeafletMapMarkerCache = Utilities.liveLeafletMap.markerImageCache
    ) -> LiveLeafletMapMarkerBuildResult {
        LiveLeafletMapMCSStagingMarkerBuilder.build(inputs: inputs, imageCache: imageCache)
    }
}
