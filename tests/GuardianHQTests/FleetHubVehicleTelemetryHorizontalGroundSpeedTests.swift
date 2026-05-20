import XCTest
@testable import GuardianCore

final class FleetHubVehicleTelemetryHorizontalGroundSpeedTests: XCTestCase {

    func test_horizontalGroundSpeedMS_prefersVelocityNorthEast() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.velocityNorthMS = 3
        hub.velocityEastMS = 4
        guard let s = hub.horizontalGroundSpeedMS else { return XCTFail("expected speed") }
        XCTAssertEqual(s, 5, accuracy: 0.0001)
    }

    func test_horizontalGroundSpeedMS_fallsBackToPositionVelocity() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.velocityNorthMS = nil
        hub.velocityEastMS = nil
        hub.positionVelNorthM = 0.6
        hub.positionVelEastM = 0.8
        guard let s = hub.horizontalGroundSpeedMS else { return XCTFail("expected speed") }
        XCTAssertEqual(s, 1, accuracy: 0.0001)
    }

    func test_horizontalGroundSpeedMS_nilWhenInsufficientComponents() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.velocityNorthMS = 1
        hub.velocityEastMS = nil
        XCTAssertNil(hub.horizontalGroundSpeedMS)
    }
}
