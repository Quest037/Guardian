import XCTest
@testable import GuardianHQ

/// Stage G: raw failure strings normalise to the same ``FleetCommandErrorKind`` through both
/// stack facades where both delegate to ``FleetCommandStackConverterShared`` — catches accidental
/// drift if one stack stops forwarding shared classification.
final class FleetCommandStackTaxonomyParityTests: XCTestCase {

    private func errorKinds(
        _ raw: String,
        command: FleetCommandName = .fleetVehicleDoArm
    ) -> (FleetCommandErrorKind?, FleetCommandErrorKind?) {
        let ap = FleetCommandStackConverterArduPilot()
        let px4 = FleetCommandStackConverterPX4()
        let rAP = ap.normaliseOutcome(.failed(raw), commandName: command, elapsed: 0.1)
        let rPX4 = px4.normaliseOutcome(.failed(raw), commandName: command, elapsed: 0.1)
        return (rAP.errorKind, rPX4.errorKind)
    }

    func test_noSession_keyword_sameKind_bothStacks() {
        let (a, p) = errorKinds("not connected")
        XCTAssertEqual(a, .noSession)
        XCTAssertEqual(a, p)
    }

    func test_authorityGated_keyword_sameKind_bothStacks() {
        let (a, p) = errorKinds("authority gate refused")
        XCTAssertEqual(a, .authorityGated)
        XCTAssertEqual(a, p)
    }

    func test_autopilotBusy_keyword_sameKind_bothStacks() {
        let (a, p) = errorKinds(
            "autopilot is busy",
            command: .fleetVehicleDoMode
        )
        XCTAssertEqual(a, .autopilotBusy)
        XCTAssertEqual(a, p)
    }
}
