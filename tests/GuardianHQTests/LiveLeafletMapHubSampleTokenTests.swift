import XCTest

@testable import GuardianHQ

@MainActor
final class LiveLeafletMapHubSampleTokenTests: XCTestCase {

    func test_token_changes_when_last_update_changes() {
        let d1 = Date(timeIntervalSinceReferenceDate: 100)
        let d2 = Date(timeIntervalSinceReferenceDate: 200)
        var hub1 = FleetHubVehicleTelemetry.empty
        hub1.lastUpdate = d1
        var hub2 = FleetHubVehicleTelemetry.empty
        hub2.lastUpdate = d2
        let t1 = LiveLeafletMapHubSampleToken.fromHubTelemetryByVehicleID(["v1": hub1])
        let t2 = LiveLeafletMapHubSampleToken.fromHubTelemetryByVehicleID(["v1": hub2])
        XCTAssertNotEqual(t1, t2)
    }

    func test_token_is_order_independent() {
        let d = Date(timeIntervalSinceReferenceDate: 100)
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = d
        let a = LiveLeafletMapHubSampleToken.fromHubTelemetryByVehicleID([
            "b": hub,
            "a": hub,
        ])
        let b = LiveLeafletMapHubSampleToken.fromHubTelemetryByVehicleID([
            "a": hub,
            "b": hub,
        ])
        XCTAssertEqual(a, b)
    }
}
