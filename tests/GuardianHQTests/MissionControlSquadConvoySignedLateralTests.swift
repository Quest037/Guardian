import XCTest
@testable import GuardianCore

final class MissionControlSquadConvoySignedLateralTests: XCTestCase {

    func test_signedLateral_starboardPositive() {
        let slot = RouteCoordinate(lat: 0, lon: 0)
        let latRad = 0.0
        let mPerLon = 111_320.0
        let eastM = 2.0
        let lonOffset = eastM / mPerLon
        let signed = MissionControlSquadConvoyFormationUtilities.convoySignedLateralErrorM(
            wingmanLatitudeDeg: 0,
            wingmanLongitudeDeg: lonOffset,
            slotCoordinate: slot,
            convoyHeadingDeg: 0
        )
        XCTAssertGreaterThan(signed, 0)
    }
}
