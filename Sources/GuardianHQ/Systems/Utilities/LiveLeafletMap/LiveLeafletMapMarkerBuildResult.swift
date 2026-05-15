import Foundation

/// Hub motion sample for ``LiveLeafletMapMarkerMotionDigest`` (no icon / selection fields).
struct LiveLeafletMapMarkerMotionSample: Equatable, Sendable {
    var id: String
    var lat: Double
    var lon: Double
    var headingDeg: Double?
}

/// Output of ``LiveLeafletMapMarkerBuilder/build(inputs:imageCache:rosterAccessibilityTitle:)``.
struct LiveLeafletMapMarkerBuildResult: Equatable, Sendable {
    var markers: [MapVehicleMarker]
    /// Quantized lat/lon/heading signature for SwiftUI `onChange` gating — **never** includes `imageDataURL`.
    var motionDigest: String
    var motionSamples: [LiveLeafletMapMarkerMotionSample]
}

/// Encodes ``LiveLeafletMapMarkerMotionSample`` lists for cheap hub-tick comparison.
enum LiveLeafletMapMarkerMotionDigest {
    /// Matches MC-R ``liveOverviewMapMarkerCoordinateDigest`` vehicle segment precision.
    static let coordinateDecimalPlaces = 5
    static let headingDecimalPlaces = 2

    static func make(from samples: [LiveLeafletMapMarkerMotionSample]) -> String {
        samples
            .sorted { $0.id < $1.id }
            .map { sample in
                let heading = sample.headingDeg ?? 0
                return String(
                    format: "%@:%.\(coordinateDecimalPlaces)f:%.\(coordinateDecimalPlaces)f:%.\(headingDecimalPlaces)f",
                    sample.id,
                    sample.lat,
                    sample.lon,
                    heading
                )
            }
            .joined(separator: "|")
    }

    static func make(from markers: [MapVehicleMarker]) -> String {
        let samples = markers.map {
            LiveLeafletMapMarkerMotionSample(
                id: $0.id,
                lat: $0.lat,
                lon: $0.lon,
                headingDeg: $0.headingDeg
            )
        }
        return make(from: samples)
    }
}
