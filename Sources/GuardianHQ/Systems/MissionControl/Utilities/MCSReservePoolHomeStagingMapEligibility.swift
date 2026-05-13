import Foundation

/// Eligibility for **Set reserve pool home** on the MCS staging map — which pool berths can follow the same
/// ``FleetLinkService/applySimState`` path as ``MissionControlSetupView/applySetupMarkerDrag``.
@MainActor
enum MCSReservePoolHomeStagingMapEligibility {
    /// Count of pool berths bound to **SITL** with a running instance and a **non-unknown** autopilot stack (hub or model).
    static func eligibleSitlReservePoolSlotCount(
        entries: [MissionRunReservePoolSlot],
        sitl: SitlService,
        fleetLink: FleetLinkService
    ) -> Int {
        entries.reduce(0) { partial, slot in
            partial + (isEligibleSitlReservePoolSlot(slot: slot, sitl: sitl, fleetLink: fleetLink) ? 1 : 0)
        }
    }

    static func isEligibleSitlReservePoolSlot(
        slot: MissionRunReservePoolSlot,
        sitl: SitlService,
        fleetLink: FleetLinkService
    ) -> Bool {
        guard slot.hasFleetOrLegacyBinding else { return false }
        guard let key = slot.attachedFleetVehicleToken,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let token = FleetMissionVehicleToken(storageKey: key),
              case .sitl(let sitlInstanceID) = token
        else { return false }
        guard let inst = sitl.instances.first(where: { $0.id == sitlInstanceID }) else { return false }
        let systemID = inst.stackInstanceIndex + 1
        let vehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
        let stack = fleetLink.hubTelemetry(forVehicleID: vehicleID)?.autopilotStack
            ?? fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.telemetry?.autopilotStack
            ?? .unknown
        return stack != .unknown
    }
}
