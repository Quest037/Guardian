// MCSRosterSlotFleetKeyedWrap.swift — Phase 9: MCS setup roster / reserve pool cards observe per-stream hub via ``FleetVehicleLiveChannel`` (strategy A) instead of only the shell’s ``fleetLink`` publish.
import SwiftUI

/// Hub-driven fields merged from ``MCRFleetRosterTileLiveFleetSlice`` with one-shot fallbacks (assignment snapshot / shell read).
@MainActor
enum MCSRosterSlotFleetKeyedMerge {
    struct Fields: Equatable {
        let rosterBatterySummary: FleetVehicleOperationalModel.BatterySummary?
        let lifecycleStatus: VehicleLifecycleStatus?
        let vehicleClassForBundledDeviceArt: FleetVehicleType
        let fleetDisplayShortID: String?
    }

    /// Prefer live slice when present; otherwise fall back to values captured when the assignment row last rebuilt from the shell.
    static func fields(
        slice: MCRFleetRosterTileLiveFleetSlice?,
        fallbackBattery: FleetVehicleOperationalModel.BatterySummary?,
        fallbackLifecycle: VehicleLifecycleStatus?,
        fallbackDeviceArtVehicleClass: FleetVehicleType,
        fallbackFleetDisplayShortID: String?
    ) -> Fields {
        guard let slice else {
            return Fields(
                rosterBatterySummary: fallbackBattery,
                lifecycleStatus: fallbackLifecycle,
                vehicleClassForBundledDeviceArt: fallbackDeviceArtVehicleClass,
                fleetDisplayShortID: fallbackFleetDisplayShortID
            )
        }
        let bracketed = slice.bracketedVehicleShortID.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortFromSlice: String? = {
            guard bracketed.count >= 3, bracketed.first == "[", bracketed.last == "]" else { return nil }
            let inner = String(bracketed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.isEmpty || inner == "—" { return nil }
            return inner
        }()
        return Fields(
            rosterBatterySummary: slice.vehicleModel.battery,
            lifecycleStatus: slice.vehicleModel.lifecycleStatus,
            vehicleClassForBundledDeviceArt: slice.vehicleClassForBundledDeviceArt,
            fleetDisplayShortID: shortFromSlice ?? fallbackFleetDisplayShortID
        )
    }
}

/// Wraps MCS roster / pool chrome so **hub churn** updates ``FleetVehicleLiveChannel`` subscribers without requiring the whole ``MissionRunDetailView`` body to depend on every ``FleetLinkService`` publish.
@MainActor
struct MCSRosterSlotFleetKeyedWrapper<Content: View>: View {
    let vehicleID: String
    let fleetLink: FleetLinkService
    let fallbackBattery: FleetVehicleOperationalModel.BatterySummary?
    let fallbackLifecycle: VehicleLifecycleStatus?
    let fallbackDeviceArtVehicleClass: FleetVehicleType
    let fallbackFleetDisplayShortID: String?
    @ViewBuilder var build: (MCSRosterSlotFleetKeyedMerge.Fields) -> Content

    @ObservedObject private var vehicleLiveChannel: FleetVehicleLiveChannel

    init(
        vehicleID: String,
        fleetLink: FleetLinkService,
        fallbackBattery: FleetVehicleOperationalModel.BatterySummary?,
        fallbackLifecycle: VehicleLifecycleStatus?,
        fallbackDeviceArtVehicleClass: FleetVehicleType,
        fallbackFleetDisplayShortID: String?,
        @ViewBuilder build: @escaping (MCSRosterSlotFleetKeyedMerge.Fields) -> Content
    ) {
        self.vehicleID = vehicleID
        self.fleetLink = fleetLink
        self.fallbackBattery = fallbackBattery
        self.fallbackLifecycle = fallbackLifecycle
        self.fallbackDeviceArtVehicleClass = fallbackDeviceArtVehicleClass
        self.fallbackFleetDisplayShortID = fallbackFleetDisplayShortID
        self.build = build
        _vehicleLiveChannel = ObservedObject(wrappedValue: fleetLink.mcrRosterLiveChannel(forVehicleID: vehicleID))
    }

    var body: some View {
        let merged = MCSRosterSlotFleetKeyedMerge.fields(
            slice: vehicleLiveChannel.fleetSlice,
            fallbackBattery: fallbackBattery,
            fallbackLifecycle: fallbackLifecycle,
            fallbackDeviceArtVehicleClass: fallbackDeviceArtVehicleClass,
            fallbackFleetDisplayShortID: fallbackFleetDisplayShortID
        )
        build(merged)
            .onAppear {
                fleetLink.mcrRosterRetainLiveChannel(forVehicleID: vehicleID)
                vehicleLiveChannel.refresh(from: fleetLink)
            }
            .onDisappear {
                fleetLink.mcrRosterReleaseLiveChannel(forVehicleID: vehicleID)
            }
    }
}
