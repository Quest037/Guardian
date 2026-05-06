import Foundation

/// Live snapshot for the first system the Python bridge sees (multi-vehicle later).
struct FleetTelemetrySnapshot: Equatable {
    var isArmed: Bool
    var flightMode: String
    var latitudeDeg: Double?
    var longitudeDeg: Double?
    var relativeAltM: Double?
    var lastUpdate: Date
    /// Best-effort from MAVSDK `info.get_identification()` (`vehicle_stack` bridge events).
    var autopilotStack: FleetAutopilotStack

    static let empty = FleetTelemetrySnapshot(
        isArmed: false,
        flightMode: "—",
        latitudeDeg: nil,
        longitudeDeg: nil,
        relativeAltM: nil,
        lastUpdate: Date(),
        autopilotStack: .unknown
    )
}
