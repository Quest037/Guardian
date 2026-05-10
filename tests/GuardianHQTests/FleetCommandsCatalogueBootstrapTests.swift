import XCTest
@testable import GuardianHQ

/// Stage B0 descriptor-registration coverage. Pins that
/// ``FleetCommandsCatalogueBootstrap`` enrolls every Stage A literal and that the call
/// is idempotent. Also confirms the stack converters for every defined autopilot stack
/// are registered.
@MainActor
final class FleetCommandsCatalogueBootstrapTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        FleetCommandsCatalogueBootstrap.ensureRegistered()
    }

    // MARK: Idempotency

    func test_ensureRegistered_isIdempotent() {
        let countAfterFirst = FleetCommandsCatalogue.shared.descriptors.count
        FleetCommandsCatalogueBootstrap.ensureRegistered()
        FleetCommandsCatalogueBootstrap.ensureRegistered()
        let countAfterRepeat = FleetCommandsCatalogue.shared.descriptors.count
        XCTAssertEqual(
            countAfterFirst, countAfterRepeat,
            "ensureRegistered() must be a no-op after the first call."
        )
    }

    // MARK: Sampled coverage of expected literals

    func test_expectedLiteralsAreRegistered() {
        let expected: [String] = [
            "command.fleet.vehicle.do.arm",
            "command.fleet.vehicle.do.disarm",
            "command.fleet.vehicle.do.land",
            "command.fleet.vehicle.do.loiter",
            "command.fleet.vehicle.do.return.home",
            "command.fleet.vehicle.do.mode",
            "command.fleet.vehicle.do.surface",
            "command.fleet.vehicle.do.move.point",
            "command.fleet.vehicle.do.move.altitude",
            "command.fleet.vehicle.do.move.heading",
            "command.fleet.vehicle.do.mission.upload",
            "command.fleet.vehicle.do.reboot.autopilot",
            "command.fleet.vehicle.do.calibrate.gyro",
            "command.fleet.vehicle.do.calibrate.accelerometer",
            "command.fleet.vehicle.do.calibrate.compass",
            "command.fleet.vehicle.do.calibrate.compass.declination",
            "command.fleet.vehicle.do.calibrate.compass.motor",
            "command.fleet.vehicle.do.calibrate.baro",
            "command.fleet.vehicle.do.calibrate.level",
            "command.fleet.vehicle.do.calibrate.servo",
            "command.fleet.vehicle.do.calibrate.rangefinder",
            "command.fleet.vehicle.do.calibrate.flow",
            "command.fleet.vehicle.do.calibrate.vision",
            "command.fleet.vehicle.get.telemetry.battery",
            "command.fleet.vehicle.get.telemetry.compass",
            "command.fleet.vehicle.get.telemetry.gps",
            "command.fleet.vehicle.get.telemetry.flight",
            "command.fleet.vehicle.cancel.calibration",
        ]
        for raw in expected {
            XCTAssertNotNil(
                FleetCommandsCatalogue.shared.descriptor(forRawValue: raw),
                "Expected descriptor '\(raw)' to be registered after bootstrap."
            )
        }
    }

    func test_paramDrivenCalibrationDescriptorsDeclareReadBackKind() throws {
        let paramDrivenSamples = [
            "command.fleet.vehicle.do.calibrate.compass.declination",
            "command.fleet.vehicle.do.calibrate.battery.voltage",
            "command.fleet.vehicle.do.calibrate.battery.current",
            "command.fleet.vehicle.do.calibrate.battery.capacity",
            "command.fleet.vehicle.do.calibrate.gimbal.neutral",
            "command.fleet.vehicle.do.calibrate.servo",
        ]
        for raw in paramDrivenSamples {
            let descriptor = try XCTUnwrap(
                FleetCommandsCatalogue.shared.descriptor(forRawValue: raw),
                "Missing descriptor for \(raw)."
            )
            XCTAssertTrue(
                descriptor.declaredResponseKinds.errorKinds.contains(.parameterReadBackMismatch),
                "Descriptor \(raw) must declare parameterReadBackMismatch — the catalogue's read-back verifier emits it."
            )
        }
    }

    // MARK: Stack converters

    func test_allDefinedAutopilotStacksHaveAConverterRegistered() {
        for stack in FleetAutopilotStack.allCases {
            XCTAssertNotNil(
                FleetCommandsCatalogue.shared.stackConverter(for: stack),
                "Stack converter missing for \(stack.rawValue)."
            )
        }
    }
}
