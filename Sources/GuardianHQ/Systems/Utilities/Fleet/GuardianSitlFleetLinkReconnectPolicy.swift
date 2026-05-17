import Foundation

/// When **Reconnect link** may be offered for a built-in SITL.
@MainActor
enum GuardianSitlFleetLinkReconnectPolicy {
    /// Vehicle Inspector: sim process is running and MAVLink position telemetry is not up yet.
    static func mayOfferReconnectLink(
        fleetLink: FleetLinkService,
        sitl: SitlService,
        vehicleID: String,
        lifecycleStage: VehicleLifecycleStage?
    ) -> Bool {
        guard fleetLink.isSimulateEnabled,
              lifecycleStage != .live,
              sitl.sitlSessionID(forGuardianVehicleID: vehicleID) != nil,
              !mavlinkPositionTelemetryIsUp(fleetLink: fleetLink, vehicleID: vehicleID)
        else { return false }
        return true
    }

    /// Devices grid card: same **no MAVLink position** rule (ignores spawn-default battery seeds on the hub).
    static func mayOfferReconnectLinkOnDevicesGrid(
        fleetLink: FleetLinkService,
        sitl: SitlService,
        vehicleID: String,
        lifecycleStage: VehicleLifecycleStage
    ) -> Bool {
        mayOfferReconnectLink(
            fleetLink: fleetLink,
            sitl: sitl,
            vehicleID: vehicleID,
            lifecycleStage: lifecycleStage
        )
    }

    /// Formations playground **link ready** uses hub lat/lon; spawn-default battery alone does not count.
    static func mavlinkPositionTelemetryIsUp(fleetLink: FleetLinkService, vehicleID: String) -> Bool {
        guard let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID) else { return false }
        return hub.latitudeDeg != nil && hub.longitudeDeg != nil
    }
}
