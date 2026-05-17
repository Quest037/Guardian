import XCTest
@testable import GuardianHQ

final class FormationsPlaygroundFollowDiagnosticsTests: XCTestCase {

    func test_evaluate_inPosition_requiresHeadingAligned() {
        let slot = RouteCoordinate(lat: -35, lon: 149)
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = -35.00001
        hub.longitudeDeg = 149.00001
        hub.headingDeg = 90
        let eval = FormationsPlaygroundFollowDiagnostics.evaluate(
            vehicleLabel: "W1",
            hub: hub,
            slot: slot,
            targetHeadingDeg: 90,
            arrivalM: 1.5,
            stuckDistanceM: 6,
            ticksWithoutProgress: 0
        )
        XCTAssertEqual(eval.state, .inPosition)
        XCTAssertTrue(eval.headingAligned)
        XCTAssertTrue(eval.message.contains("Heading aligned"))
    }

    func test_evaluate_inSlot_butTurningWhenHeadingOff() {
        let slot = RouteCoordinate(lat: -35, lon: 149)
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = -35.00001
        hub.longitudeDeg = 149.00001
        hub.headingDeg = 0
        let eval = FormationsPlaygroundFollowDiagnostics.evaluate(
            vehicleLabel: "W1",
            hub: hub,
            slot: slot,
            targetHeadingDeg: 90,
            arrivalM: 1.5,
            stuckDistanceM: 6,
            ticksWithoutProgress: 0
        )
        XCTAssertEqual(eval.state, .movingToPosition)
        XCTAssertFalse(eval.headingAligned)
        XCTAssertTrue(eval.message.contains("turning to match primary heading"))
    }

    func test_evaluate_stuck_whenFarAndNoProgress() {
        let slot = RouteCoordinate(lat: -35, lon: 149)
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = -35.01
        hub.longitudeDeg = 149
        hub.headingDeg = 45
        let eval = FormationsPlaygroundFollowDiagnostics.evaluate(
            vehicleLabel: "W1",
            hub: hub,
            slot: slot,
            targetHeadingDeg: 90,
            arrivalM: 1.5,
            stuckDistanceM: 6,
            ticksWithoutProgress: FormationsPlaygroundFollowDiagnostics.stuckTickThreshold
        )
        XCTAssertEqual(eval.state, .stuck)
        XCTAssertTrue(eval.message.contains("stuck"))
        XCTAssertTrue(eval.message.contains("Heading"))
    }

    func test_shouldSnapToSlot_whenBeyondThreshold() {
        XCTAssertTrue(FormationsPlaygroundFollowDiagnostics.shouldSnapToSlot(distanceM: 12, arrivalM: 1.5))
        XCTAssertFalse(FormationsPlaygroundFollowDiagnostics.shouldSnapToSlot(distanceM: 3, arrivalM: 1.5))
    }
}
