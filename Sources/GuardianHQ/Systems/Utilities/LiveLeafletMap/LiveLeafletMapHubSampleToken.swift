import Foundation

/// Stable hub-sample fingerprint for coalescing live map vehicle marker builds within one telemetry publish.
enum LiveLeafletMapHubSampleToken {
    /// Folds each row's ``FleetHubVehicleTelemetry/lastUpdate`` (sorted keys) into one token.
    static func fromHubTelemetryByVehicleID(_ map: [String: FleetHubVehicleTelemetry]) -> UInt64 {
        var token: UInt64 = 5381
        for key in map.keys.sorted() {
            guard let hub = map[key] else { continue }
            let tick = UInt64(bitPattern: Int64(hub.lastUpdate.timeIntervalSinceReferenceDate.bitPattern))
            token = token &* 33 &+ tick
        }
        return token
    }
}
