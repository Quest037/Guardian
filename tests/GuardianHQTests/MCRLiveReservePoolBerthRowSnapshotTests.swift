import XCTest
@testable import GuardianHQ

final class MCRLiveReservePoolBerthRowSnapshotTests: XCTestCase {

    func test_mergedWithFleetSlice_nil_is_identity() {
        let snap = MCRLiveReservePoolBerthRowSnapshot(
            poolSlotID: UUID(),
            slotTitle: "B1",
            rosterSubtitle: "Floating reserve",
            bracketedVehicleShortID: "[OLD]",
            vehicleID: "sysid:1",
            simulationImageBasenames: nil,
            vehicleClassForBundledDeviceArt: .unknown,
            vehicleModel: FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil),
            tapHelp: "Tap",
            accessibilitySummary: nil,
            accessibilityHint: nil
        )
        XCTAssertEqual(snap.mergedWithFleetSlice(nil), snap)
    }
}
