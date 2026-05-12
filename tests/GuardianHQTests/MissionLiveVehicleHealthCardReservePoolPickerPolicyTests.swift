import XCTest

@testable import GuardianHQ

private func operationalModelForPolicyTest(
    lifecycleStatus: VehicleLifecycleStatus? = nil,
    telemetryAgeS: TimeInterval?,
    battery: FleetVehicleOperationalModel.BatterySummary
) -> FleetVehicleOperationalModel {
    FleetVehicleOperationalModel(
        lifecycleStatus: lifecycleStatus,
        telemetryAgeS: telemetryAgeS,
        battery: battery,
        gps: FleetVehicleOperationalModel.GpsSummary(satellites: nil, fixShort: "—"),
        movement: FleetVehicleOperationalModel.MovementSummary(horizontalSpeedMS: nil)
    )
}

final class MissionLiveVehicleHealthCardReservePoolPickerPolicyTests: XCTestCase {

    func test_console_hides_battery_without_telemetry_age_even_when_percent_known() {
        let m = operationalModelForPolicyTest(
            telemetryAgeS: nil,
            battery: FleetVehicleOperationalModel.BatterySummary(
                percent0to100: 42,
                voltageV: nil,
                currentA: nil,
                etaSeconds: nil
            )
        )
        XCTAssertFalse(
            MissionLiveVehicleHealthCardReservePoolPickerPolicy.showCompactBattery(
                vehicleModel: m,
                reservePoolPickerChrome: false
            )
        )
    }

    func test_pool_picker_shows_battery_when_percent_known_without_telemetry_age() {
        let m = operationalModelForPolicyTest(
            telemetryAgeS: nil,
            battery: FleetVehicleOperationalModel.BatterySummary(
                percent0to100: 42,
                voltageV: nil,
                currentA: nil,
                etaSeconds: nil
            )
        )
        XCTAssertTrue(
            MissionLiveVehicleHealthCardReservePoolPickerPolicy.showCompactBattery(
                vehicleModel: m,
                reservePoolPickerChrome: true
            )
        )
    }

    func test_pool_picker_shows_battery_when_only_telemetry_age_known() {
        let m = operationalModelForPolicyTest(
            telemetryAgeS: 1.0,
            battery: FleetVehicleOperationalModel.BatterySummary(
                percent0to100: nil,
                voltageV: nil,
                currentA: nil,
                etaSeconds: nil
            )
        )
        XCTAssertTrue(
            MissionLiveVehicleHealthCardReservePoolPickerPolicy.showCompactBattery(
                vehicleModel: m,
                reservePoolPickerChrome: true
            )
        )
    }

    func test_console_shows_battery_when_telemetry_age_known() {
        let m = operationalModelForPolicyTest(
            telemetryAgeS: 1.0,
            battery: FleetVehicleOperationalModel.BatterySummary(
                percent0to100: nil,
                voltageV: nil,
                currentA: nil,
                etaSeconds: nil
            )
        )
        XCTAssertTrue(
            MissionLiveVehicleHealthCardReservePoolPickerPolicy.showCompactBattery(
                vehicleModel: m,
                reservePoolPickerChrome: false
            )
        )
    }

    func test_no_battery_badge_when_no_percent_and_no_telemetry_age() {
        let m = operationalModelForPolicyTest(
            telemetryAgeS: nil,
            battery: FleetVehicleOperationalModel.BatterySummary(
                percent0to100: nil,
                voltageV: nil,
                currentA: nil,
                etaSeconds: nil
            )
        )
        XCTAssertFalse(
            MissionLiveVehicleHealthCardReservePoolPickerPolicy.showCompactBattery(
                vehicleModel: m,
                reservePoolPickerChrome: false
            )
        )
        XCTAssertFalse(
            MissionLiveVehicleHealthCardReservePoolPickerPolicy.showCompactBattery(
                vehicleModel: m,
                reservePoolPickerChrome: true
            )
        )
    }

    func test_reserve_pool_class_capsule_hidden_when_bracketed_id_embeds_class() {
        XCTAssertFalse(
            MissionLiveVehicleHealthCardReservePoolPickerPolicy.showReservePoolClassCapsule(
                bracketedVehicleShortID: "[UGV-W:2]",
                vehicleClassCode: "UGV-W"
            )
        )
    }

    func test_reserve_pool_class_capsule_shown_when_bracketed_id_has_no_class() {
        XCTAssertTrue(
            MissionLiveVehicleHealthCardReservePoolPickerPolicy.showReservePoolClassCapsule(
                bracketedVehicleShortID: "[sys:1]",
                vehicleClassCode: "UGV-W"
            )
        )
    }

    func test_reserve_pool_class_capsule_shown_when_bracketed_placeholder() {
        XCTAssertTrue(
            MissionLiveVehicleHealthCardReservePoolPickerPolicy.showReservePoolClassCapsule(
                bracketedVehicleShortID: "—",
                vehicleClassCode: "UGV-W"
            )
        )
    }
}
