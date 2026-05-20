import XCTest
@testable import GuardianCore

/// Stage B0 `.notImplemented` failure-path coverage. The catalogue surfaces
/// `.notImplemented` translations to recipes as `.error(.notImplemented)` with the
/// converter's `detail` carried through, so the wording matters for operator-facing
/// logs. These tests pin both the case classification and a non-empty detail string.
@MainActor
final class FleetCommandStackConverterNotImplementedTests: XCTestCase {

    // MARK: - Helpers

    private func emptyContext(vehicleType: FleetVehicleType) -> FleetCommandStackConverterContext {
        FleetCommandStackConverterContext(
            vehicleID: "TEST",
            vehicleType: vehicleType,
            hubTelemetry: FleetHubVehicleTelemetry.empty
        )
    }

    private func assertNotImplemented(
        _ translation: FleetCommandStackTranslation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .notImplemented(let detail) = translation {
            XCTAssertFalse(
                detail.isEmpty,
                "notImplemented detail must be populated — recipes / logs surface this string.",
                file: file, line: line
            )
        } else {
            XCTFail("Expected .notImplemented, got \(translation)", file: file, line: line)
        }
    }

    // MARK: - PX4 deliberate gaps

    func test_pX4Surface_isNotImplemented() {
        let converter = FleetCommandStackConverterPX4()
        let translation = converter.translate(
            commandName: .fleetVehicleDoSurface,
            parameters: .empty,
            context: emptyContext(vehicleType: .uuv) // even with UUV class, PX4 has no UUV stack
        )
        assertNotImplemented(translation)
    }

    func test_pX4CalibrateRangefinder_isNotImplemented() {
        let converter = FleetCommandStackConverterPX4()
        let translation = converter.translate(
            commandName: .fleetVehicleDoCalibrateRangefinder,
            parameters: FleetCommandParameters(values: [
                "minM": .double(0.2),
                "maxM": .double(40.0),
                "groundClearanceM": .double(0.1),
                "orientation": .string("down")
            ]),
            context: emptyContext(vehicleType: .uavCopter)
        )
        assertNotImplemented(translation)
    }

    func test_pX4CalibrateFlow_isNotImplemented() {
        let converter = FleetCommandStackConverterPX4()
        let translation = converter.translate(
            commandName: .fleetVehicleDoCalibrateFlow,
            parameters: .empty,
            context: emptyContext(vehicleType: .uavCopter)
        )
        assertNotImplemented(translation)
    }

    func test_pX4CalibrateVision_isNotImplemented() {
        let converter = FleetCommandStackConverterPX4()
        let translation = converter.translate(
            commandName: .fleetVehicleDoCalibrateVision,
            parameters: .empty,
            context: emptyContext(vehicleType: .uavCopter)
        )
        assertNotImplemented(translation)
    }

    // MARK: - ArduPilot deliberate gaps

    func test_arduPilotCalibrateFlow_isNotImplemented() {
        let converter = FleetCommandStackConverterArduPilot()
        let translation = converter.translate(
            commandName: .fleetVehicleDoCalibrateFlow,
            parameters: .empty,
            context: emptyContext(vehicleType: .uavCopter)
        )
        assertNotImplemented(translation)
    }

    func test_arduPilotCalibrateVision_isNotImplemented() {
        let converter = FleetCommandStackConverterArduPilot()
        let translation = converter.translate(
            commandName: .fleetVehicleDoCalibrateVision,
            parameters: .empty,
            context: emptyContext(vehicleType: .uavCopter)
        )
        assertNotImplemented(translation)
    }

    // MARK: - ArduPilot surface command gating

    func test_arduPilotSurface_dispatchesForUUV() {
        let converter = FleetCommandStackConverterArduPilot()
        let translation = converter.translate(
            commandName: .fleetVehicleDoSurface,
            parameters: .empty,
            context: emptyContext(vehicleType: .uuv)
        )
        switch translation {
        case .vehicleCommands(let commands):
            XCTAssertEqual(commands.count, 1)
            if case .setMode(let mode) = commands.first {
                XCTAssertEqual(mode, .surface)
            } else {
                XCTFail("Expected setMode(.surface), got \(String(describing: commands.first))")
            }
        case .immediate, .notImplemented:
            XCTFail("Expected vehicleCommands for UUV class, got \(translation)")
        }
    }

    func test_arduPilotSurface_refusesForNonUUVAirframes() {
        let converter = FleetCommandStackConverterArduPilot()
        let nonUUVTypes: [FleetVehicleType] = [.uavCopter, .uavFixedWing, .ugvWheeled, .usv, .unknown]
        for type in nonUUVTypes {
            let translation = converter.translate(
                commandName: .fleetVehicleDoSurface,
                parameters: .empty,
                context: emptyContext(vehicleType: type)
            )
            assertNotImplemented(translation)
        }
    }

    // MARK: - Unknown stack baseline

    func test_unknownStack_neverEmitsVehicleCommands_forKnownCommandSample() {
        let converter = FleetCommandStackConverterUnknown()
        let sample: [FleetCommandName] = [
            .fleetVehicleDoArm,
            .fleetVehicleDoDisarm,
            .fleetVehicleDoCalibrateCompass,
            .fleetVehicleDoMode,
            .fleetVehicleDoMovePoint,
            .fleetVehicleDoRebootAutopilot,
        ]
        for name in sample {
            let translation = converter.translate(
                commandName: name,
                parameters: .empty,
                context: emptyContext(vehicleType: .unknown)
            )
            if case .vehicleCommands = translation {
                XCTFail("Unknown stack converter must never produce vehicleCommands; \(name.rawValue) leaked one.")
            }
        }
    }
}
