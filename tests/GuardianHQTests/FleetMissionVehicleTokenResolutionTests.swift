import XCTest
@testable import GuardianHQ

/// ``resolvedFleetStreamVehicleID`` — live vs SITL disambiguation without requiring ``SitlService`` for live-only runs.
@MainActor
final class FleetMissionVehicleTokenResolutionTests: XCTestCase {

    func test_live_token_resolves_without_sitl_excluding_guardian_managed_streams() {
        let fleet = FleetLinkService()
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "bridge-live", vehicleType: .uavCopter, systemID: 9)
        fleet.seedMissionRunTestSitlCleanupStream(vehicleID: "sim-guardian", systemID: 1)
        let vid = resolvedFleetStreamVehicleID(token: .live, fleetLink: fleet, sitl: nil)
        XCTAssertEqual(vid, "bridge-live")
    }

    func test_sitl_token_returns_nil_when_sitl_service_absent() {
        let fleet = FleetLinkService()
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "bridge-live", vehicleType: .uavCopter)
        let uuid = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let vid = resolvedFleetStreamVehicleID(token: .sitl(uuid), fleetLink: fleet, sitl: nil)
        XCTAssertNil(vid)
    }
}
