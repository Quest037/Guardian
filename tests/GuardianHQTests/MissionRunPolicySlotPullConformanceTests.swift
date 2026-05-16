import XCTest
@testable import GuardianHQ

final class MissionRunPolicySlotPullConformanceTests: XCTestCase {

    func test_settled_when_disarmed_slow_and_fresh() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = Date()
        hub.isArmed = false
        hub.inAir = false
        hub.velocityNorthMS = 0.1
        hub.velocityEastMS = 0.1
        XCTAssertTrue(MissionRunPolicySlotPullConformance.hubSuggestsPolicyWindDownSettled(hub))
    }

    func test_not_settled_when_armed() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = Date()
        hub.isArmed = true
        hub.inAir = false
        XCTAssertFalse(MissionRunPolicySlotPullConformance.hubSuggestsPolicyWindDownSettled(hub))
    }

    func test_settled_when_armed_slow_and_operator_park_latch() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = Date()
        hub.isArmed = true
        hub.inAir = false
        hub.velocityNorthMS = 0.05
        hub.velocityEastMS = 0.05
        XCTAssertTrue(
            MissionRunPolicySlotPullConformance.hubSuggestsPolicyWindDownSettled(
                hub,
                operatorParkAwaitingContinue: true
            )
        )
    }

    func test_not_settled_when_armed_fast_even_with_operator_park_latch() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = Date()
        hub.isArmed = true
        hub.inAir = false
        hub.velocityNorthMS = 3
        hub.velocityEastMS = 0
        XCTAssertFalse(
            MissionRunPolicySlotPullConformance.hubSuggestsPolicyWindDownSettled(
                hub,
                operatorParkAwaitingContinue: true
            )
        )
    }

    func test_not_settled_when_in_air() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = Date()
        hub.isArmed = false
        hub.inAir = true
        XCTAssertFalse(MissionRunPolicySlotPullConformance.hubSuggestsPolicyWindDownSettled(hub))
    }

    func test_not_settled_when_stale_hub() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = Date().addingTimeInterval(-100)
        hub.isArmed = false
        XCTAssertFalse(MissionRunPolicySlotPullConformance.hubSuggestsPolicyWindDownSettled(hub))
    }

    func test_not_settled_when_fast_horizontal() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.lastUpdate = Date()
        hub.isArmed = false
        hub.inAir = false
        hub.velocityNorthMS = 3
        hub.velocityEastMS = 0
        XCTAssertFalse(MissionRunPolicySlotPullConformance.hubSuggestsPolicyWindDownSettled(hub))
    }
}
