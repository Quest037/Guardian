// MCRRosterTileView.swift — MC-R roster strip: one tile keyed by ``MissionRunAssignment/id`` (Phase 3 roster observation).
import SwiftUI

/// Stable identity for roster ``ForEach`` — display order follows the parent’s assignment array, not snapshot array order.
struct MCRRosterStripOrderedSlot: Identifiable, Equatable, Hashable {
    let id: UUID
}

/// One roster health tile: reads ``MCRLiveRosterRowPresentation`` from the shared ``MCRLiveRosterSnapshotStore`` by ``assignmentID`` (no ``@ObservedObject var run`` here). When ``resolvedFleetVehicleID`` is set, fleet-driven fields merge from ``FleetVehicleLiveChannel`` (narrow observation — Phase 4 strategy A).
struct MCRRosterTileView<Presented: View, Fallback: View>: View {
    let assignmentID: UUID
    /// Resolved bridge stream key for this row; when non-nil, tile observes ``FleetLinkService/mcrRosterLiveChannel(forVehicleID:)`` only.
    let resolvedFleetVehicleID: String?
    let fallbackAssignment: MissionRunAssignment?
    let fleetLink: FleetLinkService
    @EnvironmentObject private var rosterSnapshotStore: MCRLiveRosterSnapshotStore
    @ViewBuilder var presented: (MCRLiveRosterRowPresentation) -> Presented
    @ViewBuilder var fallback: (MissionRunAssignment) -> Fallback

    var body: some View {
        if let vid = resolvedFleetVehicleID, !vid.isEmpty {
            MCRRosterTileFleetKeyedView(
                assignmentID: assignmentID,
                fallbackAssignment: fallbackAssignment,
                fleetLink: fleetLink,
                vehicleID: vid,
                presented: presented,
                fallback: fallback
            )
        } else {
            MCRRosterTileStoreOnlyView(
                assignmentID: assignmentID,
                fallbackAssignment: fallbackAssignment,
                presented: presented,
                fallback: fallback
            )
        }
    }
}

// MARK: - Store-only path (no bound stream)

private struct MCRRosterTileStoreOnlyView<Presented: View, Fallback: View>: View {
    let assignmentID: UUID
    let fallbackAssignment: MissionRunAssignment?
    @EnvironmentObject private var rosterSnapshotStore: MCRLiveRosterSnapshotStore
    @ViewBuilder var presented: (MCRLiveRosterRowPresentation) -> Presented
    @ViewBuilder var fallback: (MissionRunAssignment) -> Fallback

    var body: some View {
        if let row = rosterSnapshotStore.presentations.first(where: { $0.assignmentID == assignmentID }) {
            presented(row)
        } else if let assignment = fallbackAssignment {
            fallback(assignment)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Fleet channel merge path

private struct MCRRosterTileFleetKeyedView<Presented: View, Fallback: View>: View {
    let assignmentID: UUID
    let fallbackAssignment: MissionRunAssignment?
    @EnvironmentObject private var rosterSnapshotStore: MCRLiveRosterSnapshotStore
    let fleetLink: FleetLinkService
    let vehicleID: String
    @ViewBuilder var presented: (MCRLiveRosterRowPresentation) -> Presented
    @ViewBuilder var fallback: (MissionRunAssignment) -> Fallback

    @ObservedObject private var vehicleLiveChannel: FleetVehicleLiveChannel

    init(
        assignmentID: UUID,
        fallbackAssignment: MissionRunAssignment?,
        fleetLink: FleetLinkService,
        vehicleID: String,
        @ViewBuilder presented: @escaping (MCRLiveRosterRowPresentation) -> Presented,
        @ViewBuilder fallback: @escaping (MissionRunAssignment) -> Fallback
    ) {
        self.assignmentID = assignmentID
        self.fallbackAssignment = fallbackAssignment
        self.fleetLink = fleetLink
        self.vehicleID = vehicleID
        self.presented = presented
        self.fallback = fallback
        _vehicleLiveChannel = ObservedObject(wrappedValue: fleetLink.mcrRosterLiveChannel(forVehicleID: vehicleID))
    }

    var body: some View {
        Group {
            if let row = rosterSnapshotStore.presentations.first(where: { $0.assignmentID == assignmentID }) {
                presented(row.mergedWithLiveFleetSlice(vehicleLiveChannel.fleetSlice))
            } else if let assignment = fallbackAssignment {
                fallback(assignment)
            } else {
                EmptyView()
            }
        }
        .onAppear {
            fleetLink.mcrRosterRetainLiveChannel(forVehicleID: vehicleID)
            vehicleLiveChannel.refresh(from: fleetLink)
        }
        .onDisappear {
            fleetLink.mcrRosterReleaseLiveChannel(forVehicleID: vehicleID)
        }
    }
}
