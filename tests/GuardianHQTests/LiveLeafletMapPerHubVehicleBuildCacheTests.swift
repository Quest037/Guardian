import XCTest

@testable import GuardianHQ

@MainActor
final class LiveLeafletMapPerHubVehicleBuildCacheTests: XCTestCase {

    func test_same_hub_token_and_presentation_key_reuses_build() {
        let cache = LiveLeafletMapPerHubVehicleBuildCache()
        LiveLeafletMapMarkerPipelineProfiler.resetForTesting()
        var buildCount = 0
        let sample = LiveLeafletMapMarkerBuildResult(
            markers: [
                MapVehicleMarker(
                    id: "a",
                    lat: 1,
                    lon: 2,
                    label: "A",
                    colorHex: "#ffffff",
                    selected: false,
                    draggable: false
                ),
            ],
            motionDigest: "a",
            motionSamples: []
        )
        let first = cache.build(hubSampleToken: 1, presentationKey: "p") {
            buildCount += 1
            return sample
        }
        let second = cache.build(hubSampleToken: 1, presentationKey: "p") {
            buildCount += 1
            return LiveLeafletMapMarkerBuildResult(markers: [], motionDigest: "", motionSamples: [])
        }
        XCTAssertEqual(first, sample)
        XCTAssertEqual(second, sample)
        XCTAssertEqual(buildCount, 1)
        XCTAssertEqual(LiveLeafletMapMarkerPipelineProfiler.snapshotForTesting().vehicleBuilds, 1)
        XCTAssertEqual(LiveLeafletMapMarkerPipelineProfiler.snapshotForTesting().vehicleBuildCacheHits, 1)
    }

    func test_hub_token_change_rebuilds() {
        let cache = LiveLeafletMapPerHubVehicleBuildCache()
        var buildCount = 0
        _ = cache.build(hubSampleToken: 1, presentationKey: "p") {
            buildCount += 1
            return LiveLeafletMapMarkerBuildResult(markers: [], motionDigest: "a", motionSamples: [])
        }
        _ = cache.build(hubSampleToken: 2, presentationKey: "p") {
            buildCount += 1
            return LiveLeafletMapMarkerBuildResult(markers: [], motionDigest: "b", motionSamples: [])
        }
        XCTAssertEqual(buildCount, 2)
    }

    func test_invalidate_forces_next_build() {
        let cache = LiveLeafletMapPerHubVehicleBuildCache()
        var buildCount = 0
        _ = cache.build(hubSampleToken: 1, presentationKey: "p") {
            buildCount += 1
            return LiveLeafletMapMarkerBuildResult(markers: [], motionDigest: "a", motionSamples: [])
        }
        cache.invalidate()
        _ = cache.build(hubSampleToken: 1, presentationKey: "p") {
            buildCount += 1
            return LiveLeafletMapMarkerBuildResult(markers: [], motionDigest: "a", motionSamples: [])
        }
        XCTAssertEqual(buildCount, 2)
    }
}
