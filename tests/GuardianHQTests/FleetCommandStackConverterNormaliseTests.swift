import XCTest
@testable import GuardianCore

/// Stage B0 normalisation-heuristics coverage. Pins the failure-string classification
/// rules in ``FleetCommandStackConverterShared`` and the ArduPilot PreArm shortcut so
/// future tweaks to the keyword tables don't quietly change recipe-branch semantics.
final class FleetCommandStackConverterNormaliseTests: XCTestCase {

    // MARK: - Helpers

    private func classify(
        _ rawMessage: String,
        for command: FleetCommandName,
        converter: any FleetCommandStackConverter
    ) -> FleetCommandResponse {
        converter.normaliseOutcome(
            .failed(rawMessage),
            commandName: command,
            elapsed: 0.42
        )
    }

    // MARK: - Success path

    func test_succeeded_yieldsSuccessResponse() {
        let converter = FleetCommandStackConverterPX4()
        let response = converter.normaliseOutcome(
            .succeeded,
            commandName: .fleetVehicleDoArm,
            elapsed: 0.1
        )
        XCTAssertTrue(response.isSuccess)
        XCTAssertNil(response.errorKind)
    }

    func test_succeededWithPayload_surfacesPayload() {
        let converter = FleetCommandStackConverterPX4()
        let response = converter.normaliseOutcome(
            .succeededWithPayload(.bool(true)),
            commandName: .fleetVehicleGetMissionFinished,
            elapsed: 0.2
        )
        XCTAssertTrue(response.isSuccess)
        XCTAssertEqual(response.payload, .bool(true))
    }

    // MARK: - Arm / disarm contextual mapping

    func test_alreadyArmed_isContextSensitive() {
        let converter = FleetCommandStackConverterPX4()
        XCTAssertEqual(
            classify("already armed", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .alreadyArmed
        )
        // The same raw message for disarm should NOT map to alreadyArmed.
        XCTAssertNotEqual(
            classify("already armed", for: .fleetVehicleDoDisarm, converter: converter).errorKind,
            .alreadyArmed
        )
    }

    func test_alreadyDisarmed_isContextSensitive() {
        let converter = FleetCommandStackConverterPX4()
        XCTAssertEqual(
            classify("already disarmed", for: .fleetVehicleDoDisarm, converter: converter).errorKind,
            .alreadyDisarmed
        )
        XCTAssertNotEqual(
            classify("already disarmed", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .alreadyDisarmed
        )
    }

    func test_armRejection_mapsToArmRejectedByAutopilot() {
        let converter = FleetCommandStackConverterPX4()
        XCTAssertEqual(
            classify("permission denied", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .armRejectedByAutopilot
        )
        XCTAssertEqual(
            classify("rejected by autopilot", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .armRejectedByAutopilot
        )
    }

    // MARK: - Calibration outcomes

    func test_calibrationDidNotConverge_keyword() {
        let converter = FleetCommandStackConverterPX4()
        XCTAssertEqual(
            classify(
                "Calibration did not converge after rotation",
                for: .fleetVehicleDoCalibrateCompass,
                converter: converter
            ).errorKind,
            .calibrationDidNotConverge
        )
    }

    func test_calibrationDeclinedFallback() {
        let converter = FleetCommandStackConverterPX4()
        XCTAssertEqual(
            classify(
                "Calibration already running",
                for: .fleetVehicleDoCalibrateGyro,
                converter: converter
            ).errorKind,
            .calibrationDeclined
        )
    }

    func test_calibrationCancellation_mapsToCancelledOutcome() {
        let converter = FleetCommandStackConverterPX4()
        let response = classify(
            "Calibration cancelled by operator",
            for: .fleetVehicleDoCalibrateCompass,
            converter: converter
        )
        XCTAssertEqual(response.outcome, .cancelled)
        XCTAssertEqual(response.detail, "Calibration cancelled by operator")
    }

    func test_calibrationCancellationHeuristic_isGatedToCalibrationCommands() {
        let converter = FleetCommandStackConverterPX4()
        // Non-calibration command with the same raw message must NOT be cancelled.
        let response = classify(
            "cancelled",
            for: .fleetVehicleDoArm,
            converter: converter
        )
        XCTAssertNotEqual(response.outcome, .cancelled)
    }

    // MARK: - Parameter read-back

    func test_parameterReadBackMismatch_keyword() {
        let converter = FleetCommandStackConverterPX4()
        let response = classify(
            "PARAM_SET read-back mismatch: requested=1.234 actual=0.000",
            for: .fleetVehicleDoCalibrateCompassDeclination,
            converter: converter
        )
        XCTAssertEqual(response.errorKind, .parameterReadBackMismatch)
    }

    // MARK: - Mode / busy

    func test_modeNotSupported_keyword() {
        let converter = FleetCommandStackConverterPX4()
        XCTAssertEqual(
            classify("mode not supported", for: .fleetVehicleDoMode, converter: converter).errorKind,
            .modeNotSupported
        )
    }

    func test_busy_keyword() {
        let converter = FleetCommandStackConverterPX4()
        XCTAssertEqual(
            classify("autopilot is busy", for: .fleetVehicleDoMode, converter: converter).errorKind,
            .autopilotBusy
        )
    }

    // MARK: - Routing failures

    func test_noSession_keyword() {
        let converter = FleetCommandStackConverterPX4()
        XCTAssertEqual(
            classify("not connected", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .noSession
        )
    }

    func test_authorityGated_keyword() {
        let converter = FleetCommandStackConverterPX4()
        XCTAssertEqual(
            classify("authority gate refused", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .authorityGated
        )
    }

    func test_unknownFallback() {
        let converter = FleetCommandStackConverterPX4()
        // A message with no keywords falls through to .unknown so recipes can escalate.
        XCTAssertEqual(
            classify("the airframe ate the homework", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .unknown
        )
    }

    // MARK: - ArduPilot PreArm shortcut

    func test_arduPilotPreArmCompass_mapsToCalibrationDeclined() {
        let converter = FleetCommandStackConverterArduPilot()
        XCTAssertEqual(
            classify("PreArm: Compass not calibrated", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .calibrationDeclined
        )
    }

    func test_arduPilotPreArmAccelOrGyro_mapsToCalibrationDeclined() {
        let converter = FleetCommandStackConverterArduPilot()
        XCTAssertEqual(
            classify("PreArm: Accel inconsistent", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .calibrationDeclined
        )
        XCTAssertEqual(
            classify("PreArm: Gyros inconsistent", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .calibrationDeclined
        )
        XCTAssertEqual(
            classify("PreArm: INS not calibrated", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .calibrationDeclined
        )
    }

    func test_arduPilotPreArmBaro_mapsToCalibrationDeclined() {
        let converter = FleetCommandStackConverterArduPilot()
        XCTAssertEqual(
            classify("PreArm: Baro reading inconsistent", for: .fleetVehicleDoArm, converter: converter).errorKind,
            .calibrationDeclined
        )
    }
}
