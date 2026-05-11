import XCTest
@testable import GuardianHQ

/// Stage B1 coverage for the escalation contract types: the closed top-level
/// reason shape, the string-backed extensible kind namespaces, and the closed
/// resumption verb set.
final class FleetRecipeEscalationTests: XCTestCase {

    // MARK: Kind extensibility

    func test_operatorActionKinds_curatedSeedSetIsPresent() {
        XCTAssertEqual(FleetRecipeOperatorActionKind.rotateDrone.rawValue, "rotateDrone")
        XCTAssertEqual(FleetRecipeOperatorActionKind.holdStill.rawValue, "holdStill")
        XCTAssertEqual(FleetRecipeOperatorActionKind.placeOnLevelSurface.rawValue, "placeOnLevelSurface")
        XCTAssertEqual(FleetRecipeOperatorActionKind.pointNorth.rawValue, "pointNorth")
    }

    func test_operatorActionKind_pluginAuthoredKindIsRoundTrippable() throws {
        let custom = FleetRecipeOperatorActionKind(rawValue: "paladin.flipBattery")
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(FleetRecipeOperatorActionKind.self, from: data)
        XCTAssertEqual(decoded, custom)
        XCTAssertEqual(decoded.rawValue, "paladin.flipBattery")
    }

    func test_unrecoverableFailureKind_isExtensibleStringBacked() throws {
        let custom = FleetRecipeUnrecoverableFailureKind(rawValue: "compassThreeAttemptsFailed")
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(FleetRecipeUnrecoverableFailureKind.self, from: data)
        XCTAssertEqual(decoded, custom)
    }

    func test_confirmationKind_isExtensibleStringBacked() throws {
        let custom = FleetRecipeConfirmationKind(rawValue: "confirmRebootAutopilot")
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(FleetRecipeConfirmationKind.self, from: data)
        XCTAssertEqual(decoded, custom)
    }

    // MARK: Resumption verbs

    func test_resumptionVerbs_closedSet() {
        XCTAssertEqual(
            Set(FleetRecipeResumptionVerb.allCases),
            [.acknowledge, .retry, .skip, .abort]
        )
    }

    func test_resumptionVerb_codableViaRawValue() throws {
        let data = try JSONEncoder().encode(FleetRecipeResumptionVerb.acknowledge)
        let asString = String(data: data, encoding: .utf8)
        XCTAssertEqual(asString, "\"acknowledge\"")
    }

    // MARK: Reason codable

    func test_escalationReason_codableRoundTripsForEveryCase() throws {
        let inputs: [FleetRecipeEscalationReason] = [
            .operatorActionRequired(kind: .rotateDrone),
            .unrecoverableFailure(kind: .calibrationDidNotConverge),
            .confirmation(kind: .confirmGroundOnlyAction),
            .operatorActionRequired(kind: FleetRecipeOperatorActionKind(rawValue: "custom.extension.kind")),
        ]
        for value in inputs {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(FleetRecipeEscalationReason.self, from: data)
            XCTAssertEqual(value, decoded, "Round-trip mismatch for reason \(value)")
        }
    }
}
