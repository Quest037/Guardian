import XCTest

@testable import GuardianHQ

final class FleetVehicleLiveStatusBadgeRowTests: XCTestCase {

    func test_arm_unknown_when_no_hub() {
        let op = FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil)
        let row = FleetVehicleLiveStatusBadgeRow(hub: nil, operational: op)
        XCTAssertEqual(row.arm.title, "Armed")
        XCTAssertFalse(row.arm.isActive)
        XCTAssertEqual(row.battery.percentLabel, "—")
        XCTAssertEqual(row.battery.trafficBand, .unknown)
        XCTAssertEqual(row.battery.systemImageName, "battery.100")
        XCTAssertEqual(row.altitude.title, "AGL —")
    }

    func test_agl_title_from_relative_altitude() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.relativeAltM = 47.6
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil)
        let row = FleetVehicleLiveStatusBadgeRow(hub: hub, operational: op)
        XCTAssertEqual(row.altitude.title, "AGL 48m")
        XCTAssertTrue(row.altitude.helpSummary.contains("48"))
    }

    func test_arm_disarmed_neutral() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.isArmed = false
        hub.flightMode = "FlightMode.offboard"
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil)
        let row = FleetVehicleLiveStatusBadgeRow(hub: hub, operational: op)
        XCTAssertEqual(row.arm.title, "Armed")
        XCTAssertFalse(row.arm.isActive)
    }

    func test_arm_armed_active() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.isArmed = true
        hub.flightMode = "FlightMode.offboard"
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil)
        let row = FleetVehicleLiveStatusBadgeRow(hub: hub, operational: op)
        XCTAssertEqual(row.arm.title, "Armed")
        XCTAssertTrue(row.arm.isActive)
    }

    func test_motion_prefers_max_when_position_velocity_stale_but_velocity_ned_reports_motion() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.positionVelVnMS = 0
        hub.positionVelVeMS = 0
        hub.velocityNorthMS = 2.0
        hub.velocityEastMS = 0
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil)
        let row = FleetVehicleLiveStatusBadgeRow(hub: hub, operational: op)
        XCTAssertEqual(row.motion.title, "Moving")
        XCTAssertTrue(row.motion.isActive)
        XCTAssertTrue(op.movement.titleText.contains("2.0"))
    }

    func test_motion_label_respects_operator_moving_threshold() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.positionVelVnMS = 0.11
        hub.positionVelVeMS = 0
        let opSlow = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil)
        let rowSlow = FleetVehicleLiveStatusBadgeRow(hub: hub, operational: opSlow)
        XCTAssertEqual(rowSlow.motion.title, "Moving")
        XCTAssertFalse(rowSlow.motion.isActive)
        XCTAssertEqual(opSlow.movement.titleText, "Stationary")

        hub.positionVelVnMS = FleetVehicleOperationalModel.MovementSummary.operatorMovingSpeedThresholdMS
        let opAtThreshold = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil)
        let rowAt = FleetVehicleLiveStatusBadgeRow(hub: hub, operational: opAtThreshold)
        XCTAssertTrue(rowAt.motion.isActive)
        XCTAssertTrue(opAtThreshold.movement.titleText.hasPrefix("Moving"))
    }

    func test_motion_velocity_north_only_slow_ugv_crawl() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.velocityNorthMS = 0.18
        hub.velocityEastMS = nil
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil)
        let row = FleetVehicleLiveStatusBadgeRow(hub: hub, operational: op)
        XCTAssertTrue(row.motion.isActive)
        XCTAssertTrue(op.movement.titleText.contains("0.18"))
    }

    func test_motion_odometry_forward_vx_only() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.odometryVelXMS = -0.25
        hub.odometryVelYMS = nil
        hub.odometryVelZMS = nil
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil)
        let row = FleetVehicleLiveStatusBadgeRow(hub: hub, operational: op)
        XCTAssertTrue(row.motion.isActive)
        guard let horizontal = op.movement.horizontalSpeedMS else {
            return XCTFail("expected horizontal speed from odometry vx")
        }
        XCTAssertEqual(horizontal, 0.25, accuracy: 1e-6)
    }

    func test_mode_hold_inactive_other_active() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.flightMode = "FlightMode.hold"
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil)
        let row = FleetVehicleLiveStatusBadgeRow(hub: hub, operational: op)
        XCTAssertEqual(row.mode.title, "Hold")
        XCTAssertFalse(row.mode.isActive)
    }

    func test_mode_offboard_active() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.flightMode = "FlightMode.offboard"
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil)
        let row = FleetVehicleLiveStatusBadgeRow(hub: hub, operational: op)
        XCTAssertEqual(row.mode.title, "Offboard")
        XCTAssertTrue(row.mode.isActive)
    }

    func test_mode_placeholder_not_hold_is_green() {
        let op = FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil)
        let row = FleetVehicleLiveStatusBadgeRow(hub: nil, operational: op)
        XCTAssertEqual(row.mode.title, "Mode —")
        XCTAssertTrue(row.mode.isActive)
    }

    func test_battery_chip_charging_symbol_and_band() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.batteryRemainingPercent = 0.95
        hub.batteryCurrentA = -0.5
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil)
        let row = FleetVehicleLiveStatusBadgeRow(hub: hub, operational: op)
        XCTAssertEqual(row.battery.percentLabel, "95%")
        XCTAssertEqual(row.battery.trafficBand, .ok)
        XCTAssertEqual(row.battery.systemImageName, "battery.100.bolt")
    }

    func test_battery_traffic_band_thresholds() {
        func band(_ pct: Double) -> FleetVehicleBatteryTrafficBand {
            let s = FleetVehicleOperationalModel.BatterySummary(
                percent0to100: pct,
                voltageV: nil,
                currentA: nil,
                etaSeconds: nil
            )
            return s.trafficBand
        }
        XCTAssertEqual(band(5), .critical)
        XCTAssertEqual(band(50), .warn)
        XCTAssertEqual(band(90), .ok)
        XCTAssertEqual(
            FleetVehicleOperationalModel.BatterySummary(
                percent0to100: nil,
                voltageV: nil,
                currentA: nil,
                etaSeconds: nil
            ).trafficBand,
            .unknown
        )
    }

    func test_humanizedFlightMode_unknown() {
        XCTAssertEqual(FleetVehicleLiveStatusBadgeRow.humanizedFlightMode(from: nil), "Mode —")
        var hub = FleetHubVehicleTelemetry.empty
        hub.flightMode = "   "
        XCTAssertEqual(FleetVehicleLiveStatusBadgeRow.humanizedFlightMode(from: hub), "Mode —")
    }

    func test_isHoldLikeFlightMode_heuristics() {
        XCTAssertTrue(FleetVehicleLiveStatusBadgeRow.isHoldLikeFlightMode(humanized: "Hold", rawFlightMode: "x"))
        XCTAssertTrue(FleetVehicleLiveStatusBadgeRow.isHoldLikeFlightMode(humanized: "Hold", rawFlightMode: "FlightMode.hold"))
        XCTAssertFalse(FleetVehicleLiveStatusBadgeRow.isHoldLikeFlightMode(humanized: "Loiter", rawFlightMode: "LOITER"))
        XCTAssertFalse(FleetVehicleLiveStatusBadgeRow.isHoldLikeFlightMode(humanized: "Offboard", rawFlightMode: "FlightMode.offboard"))
    }

    func test_fleet_vehicle_model_liveStatusBadgeRow_matches_init() {
        var model = FleetVehicleModel(vehicleID: "sysid:7")
        model.applyTelemetryMutation { hub in
            hub.isArmed = true
            hub.flightMode = "FlightMode.auto"
            hub.positionVelVnMS = 2
            hub.positionVelVeMS = 0
        }
        let fromModel = model.liveStatusBadgeRow
        let fromInit = FleetVehicleLiveStatusBadgeRow(hub: model.data.telemetry, operational: model.collections.operational)
        XCTAssertEqual(fromModel, fromInit)
        XCTAssertTrue(fromModel.arm.isActive)
        XCTAssertTrue(fromModel.motion.isActive)
        XCTAssertEqual(fromModel.mode.title, "Auto")
        XCTAssertTrue(fromModel.mode.isActive)
    }
}
