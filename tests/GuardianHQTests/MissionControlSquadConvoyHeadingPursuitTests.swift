import XCTest
@testable import GuardianHQ

final class MissionControlSquadConvoyHeadingPursuitTests: XCTestCase {

    func test_pursuitYawRate_nonZeroWhenHeadingOffDespiteLowLateral() {
        let rate = MissionControlSquadConvoyFormationUtilities.pursuitYawRateDegS(
            wingmanHeadingDeg: 0,
            convoyHeadingDeg: 30,
            lateralErrorM: 0
        )
        XCTAssertGreaterThan(abs(rate), 1.0)
    }

    func test_pursuitYawRate_nearZeroWhenHeadingAligned() {
        let rate = MissionControlSquadConvoyFormationUtilities.pursuitYawRateDegS(
            wingmanHeadingDeg: 90,
            convoyHeadingDeg: 92,
            lateralErrorM: 0
        )
        XCTAssertLessThan(abs(rate), 0.5)
    }

    func test_pursuitForwardSpeed_zeroInSlotWhenHeadingOff() {
        let speed = MissionControlSquadConvoyFormationUtilities.pursuitForwardSpeedMS(
            alongErrorM: 0.2,
            distToSlotM: MissionSquadConvoyFollowControlPolicy.convoyAssemblyArrivalM,
            primarySpeedMS: 1,
            headingErrorDeg: 40
        )
        XCTAssertEqual(speed, 0)
    }

    func test_pursuitYawRate_skipsLateralKickWhenHeadingErrorLarge() {
        let withLateral = MissionControlSquadConvoyFormationUtilities.pursuitYawRateDegS(
            wingmanHeadingDeg: 0,
            convoyHeadingDeg: 90,
            lateralErrorM: 5
        )
        let headingOnly = MissionControlSquadConvoyFormationUtilities.headingAlignYawRateDegS(headingErrorDeg: 90)
        XCTAssertEqual(withLateral, headingOnly, accuracy: 0.01)
    }
}
