import XCTest

@testable import GuardianHQ

@MainActor
final class MCRLiveRosterSnapshotStoreTests: XCTestCase {

    func test_store_skips_publish_when_rows_unchanged() {
        let store = MCRLiveRosterSnapshotStore()
        let id = UUID()
        let snap = MCRLiveRosterRowSnapshot(
            slotTitle: "Alpha",
            rosterSubtitle: "primary · 1",
            bracketedVehicleShortID: "[UAV-C:1]",
            vehicleID: "sysid:1",
            simulationImageBasenames: nil,
            vehicleClassForBundledDeviceArt: .uavCopter,
            vehicleModel: FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil),
            slotAttention: nil,
            accessibilitySummary: nil,
            brainBindingCaption: nil
        )
        let rosterDeviceId = UUID()
        let proj = MissionRunAssignmentLiveProjection(
            assignmentID: id,
            rosterDeviceId: rosterDeviceId,
            taskId: nil,
            mergedSlotState: .idle,
            attachedFleetVehicleToken: nil,
            resolvedStreamVehicleID: "sysid:1",
            reserveSwapStripRole: .inactive,
            sitlBoundInstanceID: nil
        )
        let row = MCRLiveRosterRowPresentation(assignmentID: id, assignmentProjection: proj, snapshot: snap)
        store.setPresentationsIfChanged([row])
        XCTAssertEqual(store.presentations.count, 1)
        store.setPresentationsIfChanged([row])
        XCTAssertEqual(store.presentations.count, 1)
    }

    func test_snapshot_equality_ignores_identical_operational_model() {
        let m = FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil)
        let a = MCRLiveRosterRowSnapshot(
            slotTitle: "A",
            rosterSubtitle: "—",
            bracketedVehicleShortID: "—",
            vehicleID: nil,
            simulationImageBasenames: nil,
            vehicleClassForBundledDeviceArt: .unknown,
            vehicleModel: m,
            slotAttention: nil,
            accessibilitySummary: nil,
            brainBindingCaption: nil
        )
        let b = MCRLiveRosterRowSnapshot(
            slotTitle: "A",
            rosterSubtitle: "—",
            bracketedVehicleShortID: "—",
            vehicleID: nil,
            simulationImageBasenames: nil,
            vehicleClassForBundledDeviceArt: .unknown,
            vehicleModel: m,
            slotAttention: nil,
            accessibilitySummary: nil,
            brainBindingCaption: nil
        )
        XCTAssertEqual(a, b)
    }
}
