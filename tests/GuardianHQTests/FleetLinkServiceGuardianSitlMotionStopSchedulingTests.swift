import XCTest

@testable import GuardianHQ

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
}
