import XCTest
@testable import GuardianHQ

final class MissionSquadFormationHeadingPolicyTests: XCTestCase {

    func test_wingmanHeadingDeg_prefersHubHeading() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.headingDeg = 88
        hub.yawDeg = 12
        XCTAssertEqual(MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: hub), 88)
    }

    func test_wingmanHeadingDeg_fallsBackToYaw() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.yawDeg = 12
        XCTAssertEqual(MissionSquadFormationHeadingPolicy.wingmanHeadingDeg(hub: hub), 12)
    }
}
