import XCTest
@testable import GuardianHQ

final class MCRRosterFleetChannelMergeTests: XCTestCase {
    func test_mergedWithFleetSlice_overridesFleetFacingSnapshotFields() {
        let baseSnap = MCRLiveRosterRowSnapshot(
            slotTitle: "Alpha",
            rosterSubtitle: "active · role",
            bracketedVehicleShortID: "[OLD]",
            vehicleID: "sysid:1",
            simulationImageBasenames: nil,
            vehicleClassForBundledDeviceArt: .unknown,
            vehicleModel: FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil),
            slotAttention: nil,
            accessibilitySummary: nil,
            brainBindingCaption: nil
        )
        let slice = MCRFleetRosterTileLiveFleetSlice(
            bracketedVehicleShortID: "[NEW]",
            vehicleClassForBundledDeviceArt: .uavCopter,
            vehicleModel: FleetVehicleOperationalModel(
                hub: nil,
                lifecycleStatus: VehicleLifecycleStatus(stage: .live)
            )
        )
        let merged = baseSnap.mergedWithFleetSlice(slice)
        XCTAssertEqual(merged.bracketedVehicleShortID, "[NEW]")
        XCTAssertEqual(merged.vehicleClassForBundledDeviceArt, .uavCopter)
        XCTAssertEqual(merged.vehicleModel.lifecycleStatus?.stage, .live)
        XCTAssertEqual(merged.slotTitle, "Alpha")
        XCTAssertEqual(merged.vehicleID, "sysid:1")
    }

    func test_presentation_mergedWithLiveFleetSlice_nil_is_identity() {
        let snap = MCRLiveRosterRowSnapshot(
            slotTitle: "A",
            rosterSubtitle: "b",
            bracketedVehicleShortID: "—",
            vehicleID: nil,
            simulationImageBasenames: nil,
            vehicleClassForBundledDeviceArt: .unknown,
            vehicleModel: FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil),
            slotAttention: nil,
            accessibilitySummary: nil,
            brainBindingCaption: nil
        )
        let projection = MissionRunAssignmentLiveProjection(
            assignmentID: UUID(),
            rosterDeviceId: UUID(),
            taskId: nil,
            mergedSlotState: .idle,
            attachedFleetVehicleToken: nil,
            resolvedStreamVehicleID: nil,
            reserveSwapStripRole: .inactive,
            sitlBoundInstanceID: nil
        )
        let row = MCRLiveRosterRowPresentation(assignmentID: projection.assignmentID, assignmentProjection: projection, snapshot: snap)
        let out = row.mergedWithLiveFleetSlice(nil)
        XCTAssertEqual(out, row)
    }
}
