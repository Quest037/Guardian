import XCTest

@testable import GuardianHQ

final class MissionControlReserveSwapInPreflightGatesTests: XCTestCase {

    private let refDate = Date(timeIntervalSince1970: 1_700_000_000)

    func test_nil_hub_fails() {
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: nil, now: refDate, isSimulation: false)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.passed, false)
        XCTAssertEqual(r?.remediationAdvice?.patternId, "reserveSwapIn.telemetry_missing")
    }

    func test_stale_telemetry_live_fails() {
        var h = FleetHubVehicleTelemetry.empty
        h.lastUpdate = refDate.addingTimeInterval(-100)
        h.gpsFixType = "GPS_FIX_TYPE_3D_FIX"
        h.batteryRemainingPercent = 0.95
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: h, now: refDate, isSimulation: false)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.remediationAdvice?.patternId, "reserveSwapIn.telemetry_stale")
    }

    func test_stale_telemetry_simulation_allows_longer_gap() {
        var h = FleetHubVehicleTelemetry.empty
        h.lastUpdate = refDate.addingTimeInterval(-25)
        h.gpsFixType = "GPS_FIX_TYPE_3D_FIX"
        h.batteryRemainingPercent = 0.95
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: h, now: refDate, isSimulation: true)
        XCTAssertNil(r)
    }

    func test_simulation_still_fails_when_far_too_stale() {
        var h = FleetHubVehicleTelemetry.empty
        h.lastUpdate = refDate.addingTimeInterval(-120)
        h.gpsFixType = "GPS_FIX_TYPE_3D_FIX"
        h.batteryRemainingPercent = 0.95
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: h, now: refDate, isSimulation: true)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.remediationAdvice?.patternId, "reserveSwapIn.telemetry_stale")
    }

    func test_in_air_while_disarmed_fails() {
        var h = FleetHubVehicleTelemetry.empty
        h.lastUpdate = refDate
        h.isArmed = false
        h.inAir = true
        h.gpsFixType = "GPS_FIX_TYPE_3D_FIX"
        h.batteryRemainingPercent = 0.95
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: h, now: refDate, isSimulation: false)
        XCTAssertEqual(r?.remediationAdvice?.patternId, "reserveSwapIn.in_air_inconsistent")
    }

    func test_in_air_when_armed_does_not_fail_in_air_gate() {
        var h = FleetHubVehicleTelemetry.empty
        h.lastUpdate = refDate
        h.isArmed = true
        h.inAir = true
        h.gpsFixType = "GPS_FIX_TYPE_3D_FIX"
        h.batteryRemainingPercent = 0.95
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: h, now: refDate, isSimulation: false)
        XCTAssertNil(r)
    }

    func test_health_armable_false_fails() {
        var h = FleetHubVehicleTelemetry.empty
        h.lastUpdate = refDate
        h.healthArmable = false
        h.gpsFixType = "GPS_FIX_TYPE_3D_FIX"
        h.batteryRemainingPercent = 0.95
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: h, now: refDate, isSimulation: false)
        XCTAssertEqual(r?.remediationAdvice?.patternId, "reserveSwapIn.health_not_armable")
    }

    func test_health_global_position_false_fails() {
        var h = FleetHubVehicleTelemetry.empty
        h.lastUpdate = refDate
        h.healthGlobalPositionOk = false
        h.gpsFixType = "GPS_FIX_TYPE_3D_FIX"
        h.batteryRemainingPercent = 0.95
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: h, now: refDate, isSimulation: false)
        XCTAssertEqual(r?.remediationAdvice?.patternId, "reserveSwapIn.health_global_position")
    }

    func test_no_gps_fix_fails() {
        var h = FleetHubVehicleTelemetry.empty
        h.lastUpdate = refDate
        h.gpsFixType = "GPS_FIX_TYPE_NO_FIX"
        h.batteryRemainingPercent = 0.95
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: h, now: refDate, isSimulation: false)
        XCTAssertEqual(r?.remediationAdvice?.patternId, "reserveSwapIn.gps_no_fix")
    }

    func test_battery_critical_fails() {
        var h = FleetHubVehicleTelemetry.empty
        h.lastUpdate = refDate
        h.gpsFixType = "GPS_FIX_TYPE_3D_FIX"
        h.batteryRemainingPercent = 0.05
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: h, now: refDate, isSimulation: false)
        XCTAssertEqual(r?.remediationAdvice?.patternId, "reserveSwapIn.battery_critical")
    }

    func test_flight_mode_failsafe_substring_fails() {
        var h = FleetHubVehicleTelemetry.empty
        h.lastUpdate = refDate
        h.flightMode = "TERMINATION"
        h.gpsFixType = "GPS_FIX_TYPE_3D_FIX"
        h.batteryRemainingPercent = 0.95
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: h, now: refDate, isSimulation: false)
        XCTAssertEqual(r?.remediationAdvice?.patternId, "reserveSwapIn.flight_mode_blocked")
    }

    func test_healthy_snapshot_passes() {
        var h = FleetHubVehicleTelemetry.empty
        h.lastUpdate = refDate
        h.flightMode = "STABILIZE"
        h.gpsFixType = "GPS_FIX_TYPE_3D_FIX"
        h.batteryRemainingPercent = 0.95
        let r = MissionControlReserveSwapInPreflightGates.evaluate(hub: h, now: refDate, isSimulation: false)
        XCTAssertNil(r)
    }
}
