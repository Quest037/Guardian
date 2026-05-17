import XCTest
@testable import GuardianHQ

@MainActor
final class FormationsPlaygroundStreamTargetsTests: XCTestCase {
    func test_wingmanPursuit_usesSlotWhenFarFromHub() {
        let fleetLink = FleetLinkService()
        let slot = RouteCoordinate(lat: -35.001, lon: 149.001)
        let target = FormationsPlaygroundStreamTargets.wingmanPursuit(
            wingmanVehicleID: "sysid:2",
            slot: slot,
            primaryHeadingDeg: 0,
            vehicleType: .ugvWheeled,
            wingmanAbsoluteAltitudeM: 0,
            primarySpeedMS: 1.0,
            fleetLink: fleetLink
        )
        XCTAssertEqual(target.coord.lat, slot.lat, accuracy: 0.0001)
        XCTAssertEqual(target.coord.lon, slot.lon, accuracy: 0.0001)
        XCTAssertEqual(target.yawDeg, 0, accuracy: 0.001)
    }
}
