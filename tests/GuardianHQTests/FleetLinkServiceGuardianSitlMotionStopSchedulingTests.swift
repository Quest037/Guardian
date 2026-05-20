import XCTest

@testable import GuardianCore

@MainActor
final class FleetLinkServiceGuardianSitlMotionStopSchedulingTests: XCTestCase {

    func test_guardianManagedSitlSessionVehicleIDsSorted_emptyWithoutRegisteredSim() {
        let fleet = FleetLinkService()
        XCTAssertTrue(fleet.guardianManagedSitlSessionVehicleIDsSorted().isEmpty)
    }

    func test_awaitGuardianSitlMotionStopAfterMissionRunCompleted_emptyVehicleList_returnsZero() async {
        let fleet = FleetLinkService()
        let n = await fleet.awaitGuardianSitlMotionStopAfterMissionRunCompleted(vehicleIDs: [])
        XCTAssertEqual(n, 0)
    }

    func test_performRunCleanupSimKill_skipsWithoutSession() async {
        let fleet = FleetLinkService()
        let outcome = await fleet.performRunCleanupSimKill(vehicleID: "nonexistent-stream")
        XCTAssertEqual(outcome, .skippedNoSession)
    }
}
