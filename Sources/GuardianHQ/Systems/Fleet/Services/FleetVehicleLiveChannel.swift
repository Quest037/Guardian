// FleetVehicleLiveChannel.swift — Phase 4–6: per-bridge-vehicle live slices for MC‑R roster tiles, task list hub, and vehicle overlay badges (strategy A).
import Foundation
import SwiftUI

/// Fleet-derived fields for one MC‑R roster health tile, keyed by bridge ``vehicleID`` (stream key).
struct MCRFleetRosterTileLiveFleetSlice: Equatable, Sendable {
    let bracketedVehicleShortID: String
    let vehicleClassForBundledDeviceArt: FleetVehicleType
    let vehicleModel: FleetVehicleOperationalModel
}

/// Builds the live fleet slice from ``FleetLinkService`` without an assignment row (stream-key fallbacks only).
@MainActor
enum MCRFleetRosterTileLiveFleetSliceFactory {
    static func make(vehicleID: String, fleetLink: FleetLinkService) -> MCRFleetRosterTileLiveFleetSlice? {
        let hasModel = fleetLink.vehicleModel(forVehicleID: vehicleID) != nil
        let hasHub = fleetLink.hubTelemetry(forVehicleID: vehicleID) != nil
        let hasLifecycle = fleetLink.vehicleStatus(forVehicleID: vehicleID) != nil
        guard hasModel || hasHub || hasLifecycle else { return nil }

        let op = fleetLink.vehicleOperationalModel(forVehicleID: vehicleID)
        let deviceArt: FleetVehicleType = {
            if let m = fleetLink.vehicleModel(forVehicleID: vehicleID) {
                return m.data.vehicleType
            }
            return .unknown
        }()
        let shortRaw = streamKeyDisplayShortID(vehicleID: vehicleID, fleetLink: fleetLink)
        let bracketed = shortRaw.isEmpty ? "—" : "[\(shortRaw)]"
        return MCRFleetRosterTileLiveFleetSlice(
            bracketedVehicleShortID: bracketed,
            vehicleClassForBundledDeviceArt: deviceArt,
            vehicleModel: op
        )
    }

    /// Short label aligned with ``MCRLiveRosterRowSnapshotFactory/assignmentFleetDisplayShortID`` when a ``FleetVehicleModel`` exists; otherwise ``sysid:`` / tail fallbacks without roster template class.
    private static func streamKeyDisplayShortID(vehicleID: String, fleetLink: FleetLinkService) -> String {
        if let m = fleetLink.vehicleModel(forVehicleID: vehicleID) {
            return m.displayShortID
        }
        let rosterDeviceClass = FleetVehicleType.unknown
        let prefix = "sysid:"
        if vehicleID.hasPrefix(prefix), let n = Int(vehicleID.dropFirst(prefix.count)) {
            return "\(rosterDeviceClass.classCode):\(n)"
        }
        let tail = vehicleID.split(separator: ":").last.map(String.init) ?? vehicleID
        return "\(rosterDeviceClass.classCode):\(tail)"
    }
}

/// Live triage badges for MC‑R vehicle / reserve-berth overlay (arm / motion / mode / battery / AGL + operator phase).
struct MCRLiveVehicleOverlayFleetSlice: Equatable, Sendable {
    let vehicleID: String
    let displayShortID: String
    let liveStatusBadgeRow: FleetVehicleLiveStatusBadgeRow
    let mcrOperatorPhase: FleetMcrOperatorVehiclePhase
}

@MainActor
enum MCRLiveVehicleOverlayFleetSliceFactory {
    static func make(vehicleID: String, fleetLink: FleetLinkService) -> MCRLiveVehicleOverlayFleetSlice? {
        let hasModel = fleetLink.vehicleModel(forVehicleID: vehicleID) != nil
        let hasHub = fleetLink.hubTelemetry(forVehicleID: vehicleID) != nil
        let hasLifecycle = fleetLink.vehicleStatus(forVehicleID: vehicleID) != nil
        guard hasModel || hasHub || hasLifecycle else { return nil }

        let statusRow = fleetLink.vehicleModel(forVehicleID: vehicleID)?.liveStatusBadgeRow
            ?? FleetVehicleLiveStatusBadgeRow(
                hub: fleetLink.hubTelemetry(forVehicleID: vehicleID),
                operational: fleetLink.vehicleOperationalModel(forVehicleID: vehicleID)
            )
        let shortRaw: String = {
            if let m = fleetLink.vehicleModel(forVehicleID: vehicleID) {
                return m.displayShortID
            }
            let prefix = "sysid:"
            if vehicleID.hasPrefix(prefix), let n = Int(vehicleID.dropFirst(prefix.count)) {
                return "\(FleetVehicleType.unknown.classCode):\(n)"
            }
            let tail = vehicleID.split(separator: ":").last.map(String.init) ?? vehicleID
            return "\(FleetVehicleType.unknown.classCode):\(tail)"
        }()
        return MCRLiveVehicleOverlayFleetSlice(
            vehicleID: vehicleID,
            displayShortID: shortRaw.isEmpty ? "—" : shortRaw,
            liveStatusBadgeRow: statusRow,
            mcrOperatorPhase: fleetLink.mcrOperatorVehiclePhase(vehicleID: vehicleID)
        )
    }
}

/// Narrow ``ObservableObject`` for one fleet stream key; MC‑R roster tiles observe **this** instead of ``FleetLinkService``.
@MainActor
final class FleetVehicleLiveChannel: ObservableObject {
    let vehicleID: String

    @Published private(set) var fleetSlice: MCRFleetRosterTileLiveFleetSlice?
    /// Primary-path MAVLink mission progress for MC‑R task rows (same stream key as ``fleetSlice``).
    @Published private(set) var primaryPathHubTelemetry: FleetHubVehicleTelemetry?
    /// Vehicle / reserve-berth overlay triage badges (same stream key).
    @Published private(set) var overlayFleetSlice: MCRLiveVehicleOverlayFleetSlice?

    init(vehicleID: String) {
        self.vehicleID = vehicleID
    }

    func refresh(from fleetLink: FleetLinkService) {
        let next = MCRFleetRosterTileLiveFleetSliceFactory.make(vehicleID: vehicleID, fleetLink: fleetLink)
        if next != fleetSlice {
            fleetSlice = next
        }
        let nextHub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
        if nextHub != primaryPathHubTelemetry {
            primaryPathHubTelemetry = nextHub
        }
        let nextOverlay = MCRLiveVehicleOverlayFleetSliceFactory.make(vehicleID: vehicleID, fleetLink: fleetLink)
        if nextOverlay != overlayFleetSlice {
            overlayFleetSlice = nextOverlay
        }
    }

    func clearFleetSlice() {
        if fleetSlice != nil { fleetSlice = nil }
        if primaryPathHubTelemetry != nil { primaryPathHubTelemetry = nil }
        if overlayFleetSlice != nil { overlayFleetSlice = nil }
    }
}
