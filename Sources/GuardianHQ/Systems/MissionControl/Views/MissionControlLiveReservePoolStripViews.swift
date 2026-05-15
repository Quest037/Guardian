// MissionControlLiveReservePoolStripViews.swift — MC-R **floating reserve pool** roster strip (swap pick + browse): keyed by ``MissionRunReservePoolSlot/id`` and task id; fleet live fields via ``MCRLiveReservePoolBerthTileView`` + ``FleetVehicleLiveChannel`` (Phase 6).
import SwiftUI

/// Shared synthetic ``MissionRunAssignment`` for pool berths (fleet stream + SIM art resolution).
enum MissionControlReservePoolStrip {
    static func syntheticAssignment(from slot: MissionRunReservePoolSlot) -> MissionRunAssignment {
        MissionRunAssignment(
            id: slot.id,
            rosterDeviceId: slot.id,
            slotName: slot.label,
            attachedDevice: slot.attachedDevice,
            attachedFleetVehicleToken: slot.attachedFleetVehicleToken
        )
    }
}

// MARK: - Browse (task-scoped pool)

/// One pool berth tile while **browse reserves** is active for ``taskID``.
struct MissionControlLiveReservePoolBrowseTile: View {
    let slot: MissionRunReservePoolSlot
    let taskID: UUID
    let taskName: String
    let slotHeight: CGFloat
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let onTap: () -> Void

    var body: some View {
        let snapshot = MCRLiveReservePoolBerthSnapshotFactory.make(
            slot: slot,
            taskID: taskID,
            taskName: taskName,
            mode: .browse,
            fleetLink: fleetLink,
            sitl: sitl
        )
        MCRLiveReservePoolBerthTileView(
            snapshot: snapshot,
            fleetLink: fleetLink,
            slotHeight: slotHeight,
            onTap: onTap
        )
    }
}

/// Browse strip: lazy lane or column-major grid over ``poolSlots`` for ``taskID``.
struct MissionControlLiveReservePoolBrowseStrip: View {
    let poolSlots: [MissionRunReservePoolSlot]
    let taskID: UUID
    let taskName: String
    let cardHeight: CGFloat
    let cardWidth: CGFloat
    let horizontalSpacing: CGFloat
    let slotsPerColumn: Int
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let onBerthTap: (MissionRunReservePoolSlot) -> Void

    var body: some View {
        if MissionRunPrepLayout.liveRosterStripUsesLazyHorizontalLayout(itemCount: poolSlots.count) {
            MissionControlLiveLazyHorizontalRosterStrip(
                items: poolSlots,
                horizontalSpacing: horizontalSpacing,
                cardHeight: cardHeight,
                cardWidth: cardWidth
            ) { slot in
                MissionControlLiveReservePoolBrowseTile(
                    slot: slot,
                    taskID: taskID,
                    taskName: taskName,
                    slotHeight: cardHeight,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    onTap: { onBerthTap(slot) }
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            MissionControlLiveRosterColumnMajorPackedStrip(
                itemCount: poolSlots.count,
                slotsPerColumn: slotsPerColumn,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: horizontalSpacing
            ) { index in
                let slot = poolSlots[index]
                MissionControlLiveReservePoolBrowseTile(
                    slot: slot,
                    taskID: taskID,
                    taskName: taskName,
                    slotHeight: cardHeight,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    onTap: { onBerthTap(slot) }
                )
            }
        }
    }
}

// MARK: - Swap pick (vacancy + task)

/// One pool berth tile while **Swap in reserve** is picking a floating berth.
struct MissionControlLiveReservePoolSwapPickTile: View {
    let slot: MissionRunReservePoolSlot
    let taskName: String
    let slotHeight: CGFloat
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let onTap: () -> Void

    var body: some View {
        let snapshot = MCRLiveReservePoolBerthSnapshotFactory.make(
            slot: slot,
            taskID: UUID(),
            taskName: taskName,
            mode: .swapPick,
            fleetLink: fleetLink,
            sitl: sitl
        )
        MCRLiveReservePoolBerthTileView(
            snapshot: snapshot,
            fleetLink: fleetLink,
            slotHeight: slotHeight,
            onTap: onTap
        )
    }
}

/// Swap-pick strip: lazy lane or column-major grid over eligible ``poolSlots``.
struct MissionControlLiveReservePoolSwapPickStrip: View {
    let poolSlots: [MissionRunReservePoolSlot]
    let taskName: String
    let cardHeight: CGFloat
    let cardWidth: CGFloat
    let horizontalSpacing: CGFloat
    let slotsPerColumn: Int
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let onSwapSlotTap: (MissionRunReservePoolSlot) -> Void

    var body: some View {
        if MissionRunPrepLayout.liveRosterStripUsesLazyHorizontalLayout(itemCount: poolSlots.count) {
            MissionControlLiveLazyHorizontalRosterStrip(
                items: poolSlots,
                horizontalSpacing: horizontalSpacing,
                cardHeight: cardHeight,
                cardWidth: cardWidth
            ) { slot in
                MissionControlLiveReservePoolSwapPickTile(
                    slot: slot,
                    taskName: taskName,
                    slotHeight: cardHeight,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    onTap: { onSwapSlotTap(slot) }
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            MissionControlLiveRosterColumnMajorPackedStrip(
                itemCount: poolSlots.count,
                slotsPerColumn: slotsPerColumn,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: horizontalSpacing
            ) { index in
                let slot = poolSlots[index]
                MissionControlLiveReservePoolSwapPickTile(
                    slot: slot,
                    taskName: taskName,
                    slotHeight: cardHeight,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    onTap: { onSwapSlotTap(slot) }
                )
            }
        }
    }
}
