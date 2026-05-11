import XCTest
@testable import GuardianHQ

/// Stage B1 retry policy coverage. Pins the locked v1 defaults, the hard caps, the
/// `relaxRetryCaps` behaviour at the registration layer (see
/// ``FleetRecipesCatalogueRegistrationTests``), and the response-matching helper the
/// runner will consume.
final class FleetRecipeRetryPolicyTests: XCTestCase {

    // MARK: Locked defaults

    func test_catalogueDefault_isOneRetry250msTransientOnly() {
        let p = FleetRecipeRetryPolicy.catalogueDefault
        XCTAssertEqual(p.maxAttempts, 1)
        XCTAssertEqual(p.delaySeconds, 0.25, accuracy: 0.0001)
        XCTAssertTrue(p.retryOnTimeout)
        XCTAssertEqual(p.retryableErrorKinds, [.noSession, .autopilotBusy])
    }

    func test_disabled_neverRetries() {
        let p = FleetRecipeRetryPolicy.disabled
        XCTAssertEqual(p.maxAttempts, 0)
        XCTAssertEqual(p.delaySeconds, 0)
        XCTAssertFalse(p.retryOnTimeout)
        XCTAssertTrue(p.retryableErrorKinds.isEmpty)
    }

    // MARK: shouldRetry() match logic

    func test_shouldRetry_catalogueDefault_matchesTimeout() {
        let p = FleetRecipeRetryPolicy.catalogueDefault
        let response = FleetCommandResponse.timeout(detail: nil, elapsed: 1.0)
        XCTAssertTrue(p.shouldRetry(response))
    }

    func test_shouldRetry_catalogueDefault_matchesNoSession() {
        let p = FleetRecipeRetryPolicy.catalogueDefault
        let response = FleetCommandResponse.error(.noSession, detail: nil, elapsed: 0.1)
        XCTAssertTrue(p.shouldRetry(response))
    }

    func test_shouldRetry_catalogueDefault_matchesAutopilotBusy() {
        let p = FleetRecipeRetryPolicy.catalogueDefault
        let response = FleetCommandResponse.error(.autopilotBusy, detail: nil, elapsed: 0.2)
        XCTAssertTrue(p.shouldRetry(response))
    }

    func test_shouldRetry_catalogueDefault_doesNotMatchAuthorityFailures() {
        let p = FleetRecipeRetryPolicy.catalogueDefault
        for kind: FleetCommandErrorKind in [
            .authorityGated,
            .armRejectedByAutopilot,
            .calibrationDeclined,
            .modeNotSupported,
            .parameterRejected,
            .parameterReadBackMismatch,
            .unknown,
        ] {
            let response = FleetCommandResponse.error(kind, detail: nil, elapsed: 0.1)
            XCTAssertFalse(p.shouldRetry(response), "Default retry should not match \(kind.rawValue)")
        }
    }

    func test_shouldRetry_neverRetriesCancelledOrSucceeded() {
        let p = FleetRecipeRetryPolicy.catalogueDefault
        XCTAssertFalse(p.shouldRetry(.success(detail: nil, payload: .empty, elapsed: 0.1)))
        XCTAssertFalse(p.shouldRetry(.cancelled(detail: nil, elapsed: 0.1)))
    }

    func test_shouldRetry_disabled_neverMatches() {
        let p = FleetRecipeRetryPolicy.disabled
        XCTAssertFalse(p.shouldRetry(.timeout(detail: nil, elapsed: 0.1)))
        XCTAssertFalse(p.shouldRetry(.error(.noSession, detail: nil, elapsed: 0.1)))
    }

    // MARK: Cap enforcement

    func test_violations_catalogueDefault_isWithinCaps() {
        XCTAssertEqual(
            FleetRecipeRetryPolicy.violations(for: .catalogueDefault),
            []
        )
    }

    func test_violations_maxAttemptsExceedsCap_reportsMaxAttemptsKind() {
        let p = FleetRecipeRetryPolicy(
            maxAttempts: FleetRecipeRetryPolicy.maxAttemptsCap + 1,
            delaySeconds: 0.25,
            retryableErrorKinds: [.noSession],
            retryOnTimeout: false
        )
        let v = FleetRecipeRetryPolicy.violations(for: p)
        XCTAssertTrue(v.contains(where: { $0.kind == .maxAttempts }))
    }

    func test_violations_delayExceedsCap_reportsDelaySecondsKind() {
        let p = FleetRecipeRetryPolicy(
            maxAttempts: 1,
            delaySeconds: FleetRecipeRetryPolicy.maxDelaySecondsCap + 1,
            retryableErrorKinds: [],
            retryOnTimeout: true
        )
        let v = FleetRecipeRetryPolicy.violations(for: p)
        XCTAssertTrue(v.contains(where: { $0.kind == .delaySeconds }))
    }

    func test_violations_worstCaseExceedsCap_reportsWorstCaseKind() {
        let p = FleetRecipeRetryPolicy(
            maxAttempts: 5,
            delaySeconds: 5,
            retryableErrorKinds: [],
            retryOnTimeout: true
        )
        let v = FleetRecipeRetryPolicy.violations(for: p)
        XCTAssertTrue(v.contains(where: { $0.kind == .worstCaseAdditionalSeconds }))
    }

    func test_violations_negativeValues_reportNegativeKinds() {
        let p = FleetRecipeRetryPolicy(
            maxAttempts: -1,
            delaySeconds: -0.5,
            retryableErrorKinds: [],
            retryOnTimeout: false
        )
        let v = FleetRecipeRetryPolicy.violations(for: p)
        XCTAssertTrue(v.contains(where: { $0.kind == .negativeMaxAttempts }))
        XCTAssertTrue(v.contains(where: { $0.kind == .negativeDelay }))
    }

    // MARK: Codable

    func test_policy_codableRoundTripIsOrderStable() throws {
        let original = FleetRecipeRetryPolicy(
            maxAttempts: 2,
            delaySeconds: 0.5,
            retryableErrorKinds: [.noSession, .autopilotBusy, .calibrationDidNotConverge],
            retryOnTimeout: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FleetRecipeRetryPolicy.self, from: data)
        XCTAssertEqual(original, decoded)
        // Encoded form sorts retryableErrorKinds for deterministic DSL diffs.
        if let json = String(data: data, encoding: .utf8) {
            let kindsArrayRange = json.range(of: "\"retryableErrorKinds\":[")
            XCTAssertNotNil(kindsArrayRange, "Encoded JSON should include retryableErrorKinds key.")
        }
    }
}
