// MCRLiveReservePoolBerthProjection.swift — MC-R floating reserve pool strip tiles: slot/task-keyed snapshot + ``FleetVehicleLiveChannel`` merge (Phase 6).
import SwiftUI

enum MCRLiveReservePoolStripTileMode: Equatable, Sendable {
    case browse
    case swapPick
}

/// Slot-scoped inputs for one floating reserve berth tile (no whole-run observation).
struct MCRLiveReservePoolBerthLiveProjection: Equatable, Sendable {
    let poolSlotID: UUID
    let taskID: UUID
    let resolvedStreamVehicleID: String?

    @MainActor
    static func make(
        slot: MissionRunReservePoolSlot,
        taskID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> MCRLiveReservePoolBerthLiveProjection {
        let syn = MissionControlReservePoolStrip.syntheticAssignment(from: slot)
        return MCRLiveReservePoolBerthLiveProjection(
            poolSlotID: slot.id,
            taskID: taskID,
            resolvedStreamVehicleID: resolvedFleetStreamVehicleID(assignment: syn, fleetLink: fleetLink, sitl: sitl)
        )
    }
}

/// Equatable MC-R pool berth health tile payload (fleet-facing fields merge from ``FleetVehicleLiveChannel``).
struct MCRLiveReservePoolBerthRowSnapshot: Equatable {
    let poolSlotID: UUID
    let slotTitle: String
    let rosterSubtitle: String
    let bracketedVehicleShortID: String
    let vehicleID: String?
    let simulationImageBasenames: [String]?
    let vehicleClassForBundledDeviceArt: FleetVehicleType
    let vehicleModel: FleetVehicleOperationalModel
    let tapHelp: String
    let accessibilitySummary: String?
    let accessibilityHint: String?
}

extension MCRLiveReservePoolBerthRowSnapshot {
    func mergedWithFleetSlice(_ slice: MCRFleetRosterTileLiveFleetSlice?) -> MCRLiveReservePoolBerthRowSnapshot {
        guard let slice else { return self }
        return MCRLiveReservePoolBerthRowSnapshot(
            poolSlotID: poolSlotID,
            slotTitle: slotTitle,
            rosterSubtitle: rosterSubtitle,
            bracketedVehicleShortID: slice.bracketedVehicleShortID,
            vehicleID: vehicleID,
            simulationImageBasenames: simulationImageBasenames,
            vehicleClassForBundledDeviceArt: slice.vehicleClassForBundledDeviceArt,
            vehicleModel: slice.vehicleModel,
            tapHelp: tapHelp,
            accessibilitySummary: accessibilitySummary,
            accessibilityHint: accessibilityHint
        )
    }
}

@MainActor
enum MCRLiveReservePoolBerthSnapshotFactory {
    static func make(
        slot: MissionRunReservePoolSlot,
        taskID: UUID,
        taskName: String,
        mode: MCRLiveReservePoolStripTileMode,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> MCRLiveReservePoolBerthRowSnapshot {
        let syn = MissionControlReservePoolStrip.syntheticAssignment(from: slot)
        let vehicleID = resolvedFleetStreamVehicleID(assignment: syn, fleetLink: fleetLink, sitl: sitl)
        let deviceArt: FleetVehicleType = {
            if let vid = vehicleID, let model = fleetLink.vehicleModel(forVehicleID: vid) {
                return model.data.vehicleType
            }
            return .unknown
        }()
        let shortRaw = MCRLiveRosterRowSnapshotFactory.assignmentFleetDisplayShortID(
            assignment: syn,
            rosterDevice: nil,
            fleetLink: fleetLink,
            sitl: sitl
        )
        let bracketed = shortRaw.isEmpty ? "—" : "[\(shortRaw)]"
        let op = vehicleID.map { fleetLink.vehicleOperationalModel(forVehicleID: $0) }
            ?? FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil)
        let (tapHelp, accessibilitySummary, accessibilityHint): (String, String?, String?) = {
            switch mode {
            case .browse:
                return (
                    "Open floating reserve berth",
                    MissionRunReserveSwapAccessibilityCopy.floatingPoolStripBrowseCandidate(
                        taskName: taskName,
                        berthLabel: slot.label,
                        aircraftShortID: bracketed
                    ),
                    nil
                )
            case .swapPick:
                return (
                    "Select this reserve",
                    MissionRunReserveSwapAccessibilityCopy.floatingPoolStripSwapPickCandidate(
                        taskName: taskName,
                        berthLabel: slot.label,
                        aircraftShortID: bracketed
                    ),
                    "Opens a confirmation; arm checks run before the roster changes."
                )
            }
        }()
        return MCRLiveReservePoolBerthRowSnapshot(
            poolSlotID: slot.id,
            slotTitle: slot.label,
            rosterSubtitle: "Floating reserve",
            bracketedVehicleShortID: bracketed,
            vehicleID: vehicleID,
            simulationImageBasenames: simulationImageBasenamesForAssignment(syn, sitl: sitl),
            vehicleClassForBundledDeviceArt: deviceArt,
            vehicleModel: op,
            tapHelp: tapHelp,
            accessibilitySummary: accessibilitySummary,
            accessibilityHint: accessibilityHint
        )
    }
}

/// One floating reserve berth health tile; observes ``FleetVehicleLiveChannel`` when a stream id resolves.
struct MCRLiveReservePoolBerthTileView: View {
    let snapshot: MCRLiveReservePoolBerthRowSnapshot
    let fleetLink: FleetLinkService
    let slotHeight: CGFloat
    let onTap: () -> Void

    var body: some View {
        if let vid = snapshot.vehicleID, !vid.isEmpty {
            MCRLiveReservePoolBerthTileFleetHost(
                snapshot: snapshot,
                fleetLink: fleetLink,
                vehicleID: vid,
                slotHeight: slotHeight,
                onTap: onTap
            )
        } else {
            Self.poolHealthCard(snapshot: snapshot, slotHeight: slotHeight, onTap: onTap)
        }
    }

    @ViewBuilder
    fileprivate static func poolHealthCard(snapshot: MCRLiveReservePoolBerthRowSnapshot, slotHeight: CGFloat, onTap: @escaping () -> Void) -> some View {
        MissionLiveVehicleHealthCard(
            slotTitle: snapshot.slotTitle,
            rosterSubtitle: snapshot.rosterSubtitle,
            bracketedVehicleShortID: snapshot.bracketedVehicleShortID,
            vehicleID: snapshot.vehicleID,
            simulationImageBasenames: snapshot.simulationImageBasenames,
            vehicleClassForBundledDeviceArt: snapshot.vehicleClassForBundledDeviceArt,
            vehicleModel: snapshot.vehicleModel,
            slotHeight: slotHeight,
            onTap: onTap,
            slotAttention: nil,
            reservePoolPickerChrome: true,
            tapHelp: snapshot.tapHelp,
            accessibilitySummary: snapshot.accessibilitySummary,
            accessibilityHint: snapshot.accessibilityHint
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MCRLiveReservePoolBerthTileFleetHost: View {
    let snapshot: MCRLiveReservePoolBerthRowSnapshot
    let fleetLink: FleetLinkService
    let vehicleID: String
    let slotHeight: CGFloat
    let onTap: () -> Void

    @ObservedObject private var vehicleLiveChannel: FleetVehicleLiveChannel

    init(
        snapshot: MCRLiveReservePoolBerthRowSnapshot,
        fleetLink: FleetLinkService,
        vehicleID: String,
        slotHeight: CGFloat,
        onTap: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.fleetLink = fleetLink
        self.vehicleID = vehicleID
        self.slotHeight = slotHeight
        self.onTap = onTap
        _vehicleLiveChannel = ObservedObject(wrappedValue: fleetLink.mcrRosterLiveChannel(forVehicleID: vehicleID))
    }

    var body: some View {
        MCRLiveReservePoolBerthTileView.poolHealthCard(
            snapshot: snapshot.mergedWithFleetSlice(vehicleLiveChannel.fleetSlice),
            slotHeight: slotHeight,
            onTap: onTap
        )
        .onAppear {
            fleetLink.mcrRosterRetainLiveChannel(forVehicleID: vehicleID)
            vehicleLiveChannel.refresh(from: fleetLink)
        }
        .onDisappear {
            fleetLink.mcrRosterReleaseLiveChannel(forVehicleID: vehicleID)
        }
    }
}
