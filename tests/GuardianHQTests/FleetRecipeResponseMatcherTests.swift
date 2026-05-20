import XCTest
@testable import GuardianCore

/// Stage B1 coverage for ``FleetRecipeResponseMatcher``: per-case match semantics
/// against every `FleetCommandResponse` outcome shape, plus Codable round-trip for
/// the JSON DSL.
final class FleetRecipeResponseMatcherTests: XCTestCase {

    // MARK: success / data

    func test_successMatcher_withoutPredicate_matchesAnySuccess() {
        let m = FleetRecipeResponseMatcher.success()
        XCTAssertTrue(m.matches(.success(detail: nil, payload: .empty, elapsed: nil)))
        XCTAssertTrue(m.matches(.success(detail: nil, payload: .bool(true), elapsed: nil)))
        XCTAssertFalse(m.matches(.error(.unknown, detail: nil, elapsed: nil)))
    }

    func test_successMatcher_withPredicate_alsoChecksPayload() {
        let m = FleetRecipeResponseMatcher.success(payload: .keyValueEquals(key: "armed", value: "true"))
        XCTAssertTrue(m.matches(.success(detail: nil, payload: .keyValues(["armed": "true"]), elapsed: nil)))
        XCTAssertFalse(m.matches(.success(detail: nil, payload: .keyValues(["armed": "false"]), elapsed: nil)))
        XCTAssertFalse(m.matches(.error(.unknown, detail: nil, elapsed: nil)))
    }

    func test_dataMatcher_requiresSuccessAndPayloadMatch() {
        let m = FleetRecipeResponseMatcher.data(predicate: .stringEquals("hold"))
        XCTAssertTrue(m.matches(.success(detail: nil, payload: .string("hold"), elapsed: nil)))
        XCTAssertFalse(m.matches(.success(detail: nil, payload: .string("loiter"), elapsed: nil)))
        XCTAssertFalse(m.matches(.error(.unknown, detail: nil, elapsed: nil)))
    }

    // MARK: error / timeout / cancelled

    func test_errorMatcher_matchesExactKind() {
        let m = FleetRecipeResponseMatcher.error(kind: .calibrationDeclined)
        XCTAssertTrue(m.matches(.error(.calibrationDeclined, detail: nil, elapsed: nil)))
        XCTAssertFalse(m.matches(.error(.calibrationDidNotConverge, detail: nil, elapsed: nil)))
        XCTAssertFalse(m.matches(.success(detail: nil, payload: .empty, elapsed: nil)))
    }

    func test_timeoutMatcher_matchesOnlyTimeoutOutcome() {
        let m = FleetRecipeResponseMatcher.timeout
        XCTAssertTrue(m.matches(.timeout(detail: nil, elapsed: nil)))
        XCTAssertFalse(m.matches(.error(.unknown, detail: nil, elapsed: nil)))
        XCTAssertFalse(m.matches(.success(detail: nil, payload: .empty, elapsed: nil)))
    }

    func test_cancelledMatcher_matchesOnlyCancelledOutcome() {
        let m = FleetRecipeResponseMatcher.cancelled
        XCTAssertTrue(m.matches(.cancelled(detail: nil, elapsed: nil)))
        XCTAssertFalse(m.matches(.error(.unknown, detail: nil, elapsed: nil)))
    }

    // MARK: any

    func test_anyMatcher_matchesEveryOutcome() {
        let m = FleetRecipeResponseMatcher.any
        XCTAssertTrue(m.matches(.success(detail: nil, payload: .empty, elapsed: nil)))
        XCTAssertTrue(m.matches(.error(.unknown, detail: nil, elapsed: nil)))
        XCTAssertTrue(m.matches(.timeout(detail: nil, elapsed: nil)))
        XCTAssertTrue(m.matches(.cancelled(detail: nil, elapsed: nil)))
    }

    // MARK: Codable

    func test_matchers_codableRoundTrip() throws {
        let inputs: [FleetRecipeResponseMatcher] = [
            .success(),
            .success(payload: .keyValueEquals(key: "armed", value: "true")),
            .error(kind: .calibrationDeclined),
            .data(predicate: .stringEquals("hold")),
            .timeout,
            .cancelled,
            .any,
        ]
        for value in inputs {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(FleetRecipeResponseMatcher.self, from: data)
            XCTAssertEqual(value, decoded, "Round-trip mismatch for matcher \(value)")
        }
    }
}
