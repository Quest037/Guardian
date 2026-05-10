import XCTest
@testable import GuardianHQ

/// Stage B0 namespace-validation coverage. Stage A established the lexical / structural
/// rules in ``FleetCommandName.isValidRawValue(_:)``; this test pins them.
final class FleetCommandNameTests: XCTestCase {

    // MARK: Positive cases

    func test_validNames_acceptedByConstructor() throws {
        let valid = [
            "command.fleet.vehicle.do.arm",
            "command.fleet.vehicle.do.disarm",
            "command.fleet.vehicle.do.calibrate.compass",
            "command.fleet.vehicle.do.calibrate.compass.motor",
            "command.fleet.vehicle.do.calibrate.compass.declination",
            "command.fleet.vehicle.get.telemetry.battery",
            "command.fleet.vehicle.cancel.calibration",
            "command.fleet.vehicle.do.reboot.autopilot",
            "command.fleet.vehicle.do.mission.upload",
        ]
        for raw in valid {
            XCTAssertNoThrow(
                try FleetCommandName(validating: raw),
                "Expected '\(raw)' to validate."
            )
            XCTAssertTrue(
                FleetCommandName.isValidRawValue(raw),
                "Expected '\(raw)' to be a valid raw value."
            )
        }
    }

    func test_decomposition_returnsVerbAddressingAndSpecifier() throws {
        let name = try FleetCommandName(validating: "command.fleet.vehicle.do.calibrate.compass.motor")
        XCTAssertEqual(name.verb, .do)
        XCTAssertEqual(name.addressingPath, ["fleet", "vehicle"])
        XCTAssertEqual(name.specifier, ["calibrate", "compass", "motor"])
    }

    func test_isUnderAddressingPrefix_matchesExpectedNamespaceClaims() throws {
        let name = try FleetCommandName(validating: "command.fleet.vehicle.do.arm")
        XCTAssertTrue(name.isUnderAddressingPrefix(["fleet"]))
        XCTAssertTrue(name.isUnderAddressingPrefix(["fleet", "vehicle"]))
        XCTAssertFalse(name.isUnderAddressingPrefix(["mc"]))
        XCTAssertFalse(name.isUnderAddressingPrefix(["fleet", "vehicle", "extra"]))
    }

    // MARK: Negative cases

    func test_invalidNames_rejectedByValidator() {
        let invalid: [String] = [
            "",
            "command",
            "command.",
            ".command.fleet.vehicle.do.arm",
            "command.fleet.vehicle.do.arm.",
            "command..fleet.vehicle.do.arm",
            "fleet.vehicle.do.arm",                       // missing "command." prefix
            "Command.Fleet.Vehicle.Do.Arm",               // uppercase
            "command.fleet.vehicle.arm",                  // no verb segment
            "command.do.arm",                             // missing addressing segments
            "command.fleet.vehicle.do",                   // missing specifier
            "command.fleet.vehicle.do.arm/disarm",        // illegal character
            "command.fleet.vehicle.do get telemetry",     // whitespace illegal
            "command.fleet.vehicle.subscribe.foo",        // `subscribe` verb deferred
            "command.fleet.vehicle.do.get.foo",           // two verb segments
        ]
        for raw in invalid {
            XCTAssertFalse(
                FleetCommandName.isValidRawValue(raw),
                "Expected '\(raw)' to be rejected but it passed validation."
            )
            XCTAssertThrowsError(
                try FleetCommandName(validating: raw),
                "Expected '\(raw)' to throw."
            ) { error in
                guard case FleetCommandNameError.invalidFormat(let echoed) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(echoed, raw)
            }
        }
    }

    func test_maximumLength_rejected() {
        // 130 characters all 'a' is well past the 128-char cap and lacks structure
        // anyway; we still expect the lexical guard to fail before length is hit.
        let oversize = "command." + String(repeating: "a", count: FleetCommandName.maximumLength)
        XCTAssertFalse(FleetCommandName.isValidRawValue(oversize))
    }
}
