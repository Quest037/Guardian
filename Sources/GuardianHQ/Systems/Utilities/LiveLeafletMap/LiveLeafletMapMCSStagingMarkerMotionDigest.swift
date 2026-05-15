import Foundation

/// MCS roster staging map motion signature (lat/lon + ``MapVehicleMarker/pendingSimSync`` — no heading segment).
enum LiveLeafletMapMCSStagingMarkerMotionDigest {
    static let coordinateDecimalPlaces = LiveLeafletMapMarkerMotionDigest.coordinateDecimalPlaces

    static func make(from markers: [MapVehicleMarker]) -> String {
        markers
            .sorted { $0.id < $1.id }
            .map { marker in
                String(
                    format: "%@:%.\(coordinateDecimalPlaces)f:%.\(coordinateDecimalPlaces)f:%@",
                    marker.id,
                    marker.lat,
                    marker.lon,
                    marker.pendingSimSync ? "1" : "0"
                )
            }
            .joined(separator: "|")
    }
}
