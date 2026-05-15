import XCTest
@testable import GuardianHQ

@MainActor
final class MCRLiveVehicleOverlayFleetSliceTests: XCTestCase {

    func test_overlayFleetSliceFactory_nil_when_no_stream_data() {
        let fleet = FleetLinkService()
        XCTAssertNil(MCRLiveVehicleOverlayFleetSliceFactory.make(vehicleID: "sysid:99", fleetLink: fleet))
    }
}
