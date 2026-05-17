import Foundation

/// Inputs for choosing a movement while closing a formation slot (pad or path-anchored).
struct GuardianMovementSlotApproachContext: Equatable, Sendable {
    let vehicleType: FleetVehicleType
    let wingmanLatitudeDeg: Double
    let wingmanLongitudeDeg: Double
    let wingmanHeadingDeg: Double?
    let slot: RouteCoordinate
    /// Formation / convoy axis heading (primary-matched by default).
    let convoyHeadingDeg: Double
    let targetHeadingDeg: Double
    /// Signed along convoy axis (m): positive = wingman ahead of slot toward primary.
    let alongErrorM: Double
    /// Signed lateral (m): positive = starboard of convoy axis.
    let signedLateralErrorM: Double
    let distToSlotM: Double
    let primarySpeedMS: Double?
}
