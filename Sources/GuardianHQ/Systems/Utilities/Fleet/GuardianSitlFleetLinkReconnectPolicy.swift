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
              lifecycleStage != .starting,
              lifecycleStage != .connecting,
              lifecycleStage != .awaitingTelemetry,
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

    /// Built-in SITL row is linked for spawn panels / preflight (position telemetry, not lifecycle stage alone).
    static func simulatorFleetLinkReady(fleetLink: FleetLinkService, vehicleID: String) -> Bool {
        guard fleetLink.vehicleModel(forVehicleID: vehicleID) != nil else { return false }
        return mavlinkPositionTelemetryIsUp(fleetLink: fleetLink, vehicleID: vehicleID)
    }

    /// Position telemetry is up **and** a Guardian MAVSDK session is active (ignores orphan hub rows with no session).
    static func simulatorFleetLinkReadyWithMavsdkSession(fleetLink: FleetLinkService, vehicleID: String) -> Bool {
        guard fleetLink.isGuardianManagedSitlStream(vehicleID: vehicleID) else { return false }
        return simulatorFleetLinkReady(fleetLink: fleetLink, vehicleID: vehicleID)
    }
}
