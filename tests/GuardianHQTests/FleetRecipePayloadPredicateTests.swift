import XCTest
@testable import GuardianHQ

/// Stage B1 coverage for the closed payload-predicate vocabulary used by `.data(...)`
/// and `.success(payload:)` matchers. Pins:
/// - per-kind match semantics against each payload shape;
/// - type discipline (predicate against wrong payload kind returns `false`, never traps);
/// - regex compile guard via ``FleetRecipePayloadPredicate/isStructurallyValid``;
/// - comparison-op semantics for integer / double;
/// - Codable round-trips for every kind.
final class FleetRecipePayloadPredicateTests: XCTestCase {

    // MARK: keyValues

    func test_keyValueEquals_matchesOnExactKVPair() {
        let p = FleetRecipePayloadPredicate.keyValueEquals(key: "mode", value: "hold")
        XCTAssertTrue(p.evaluate(against: .keyValues(["mode": "hold", "armed": "true"])))
        XCTAssertFalse(p.evaluate(against: .keyValues(["mode": "loiter"])))
        XCTAssertFalse(p.evaluate(against: .keyValues([:])))
    }

    func test_keyValuePresent_ignoresValue() {
        let p = FleetRecipePayloadPredicate.keyValuePresent(key: "armed")
        XCTAssertTrue(p.evaluate(against: .keyValues(["armed": "false"])))
        XCTAssertTrue(p.evaluate(against: .keyValues(["armed": "anything"])))
        XCTAssertFalse(p.evaluate(against: .keyValues(["mode": "hold"])))
    }

    func test_keyValuePredicates_rejectWrongPayloadKind() {
        let p = FleetRecipePayloadPredicate.keyValueEquals(key: "k", value: "v")
        XCTAssertFalse(p.evaluate(against: .empty))
        XCTAssertFalse(p.evaluate(against: .string("v")))
        XCTAssertFalse(p.evaluate(against: .bool(true)))
    }

    // MARK: bool / string

    func test_boolEquals_matchesExactBool() {
        XCTAssertTrue(FleetRecipePayloadPredicate.boolEquals(true).evaluate(against: .bool(true)))
        XCTAssertFalse(FleetRecipePayloadPredicate.boolEquals(true).evaluate(against: .bool(false)))
        XCTAssertFalse(FleetRecipePayloadPredicate.boolEquals(true).evaluate(against: .integer(1)))
    }

    func test_stringEquals_matchesExactString() {
        XCTAssertTrue(FleetRecipePayloadPredicate.stringEquals("hold").evaluate(against: .string("hold")))
        XCTAssertFalse(FleetRecipePayloadPredicate.stringEquals("hold").evaluate(against: .string("loiter")))
        XCTAssertFalse(FleetRecipePayloadPredicate.stringEquals("hold").evaluate(against: .keyValues(["mode": "hold"])))
    }

    // MARK: regex

    func test_stringMatches_compilesAndMatchesPattern() {
        let p = FleetRecipePayloadPredicate.stringMatches(regex: "^(hold|loiter)$")
        XCTAssertTrue(p.evaluate(against: .string("hold")))
        XCTAssertTrue(p.evaluate(against: .string("loiter")))
        XCTAssertFalse(p.evaluate(against: .string("manual")))
    }

    func test_stringMatches_returnsFalseForUncompilablePatternRatherThanCrashing() {
        let p = FleetRecipePayloadPredicate.stringMatches(regex: "[unterminated")
        XCTAssertFalse(p.evaluate(against: .string("anything")))
    }

    func test_isStructurallyValid_rejectsUncompilableRegex() {
        let bad = FleetRecipePayloadPredicate.stringMatches(regex: "[unterminated")
        XCTAssertFalse(bad.isStructurallyValid)
        let good = FleetRecipePayloadPredicate.stringMatches(regex: "^ok$")
        XCTAssertTrue(good.isStructurallyValid)
    }

    func test_isStructurallyValid_isTrueForNonRegexCases() {
        XCTAssertTrue(FleetRecipePayloadPredicate.keyValueEquals(key: "k", value: "v").isStructurallyValid)
        XCTAssertTrue(FleetRecipePayloadPredicate.boolEquals(true).isStructurallyValid)
    }

    // MARK: integer / double comparison

    func test_integerCompare_appliesEveryOperator() {
        let payload: FleetCommandResponsePayload = .integer(10)
        XCTAssertTrue(FleetRecipePayloadPredicate.integerCompare(op: .equal, value: 10).evaluate(against: payload))
        XCTAssertFalse(FleetRecipePayloadPredicate.integerCompare(op: .notEqual, value: 10).evaluate(against: payload))
        XCTAssertTrue(FleetRecipePayloadPredicate.integerCompare(op: .lessOrEqual, value: 10).evaluate(against: payload))
        XCTAssertTrue(FleetRecipePayloadPredicate.integerCompare(op: .greaterOrEqual, value: 10).evaluate(against: payload))
        XCTAssertFalse(FleetRecipePayloadPredicate.integerCompare(op: .lessThan, value: 10).evaluate(against: payload))
        XCTAssertFalse(FleetRecipePayloadPredicate.integerCompare(op: .greaterThan, value: 10).evaluate(against: payload))
        XCTAssertTrue(FleetRecipePayloadPredicate.integerCompare(op: .lessThan, value: 11).evaluate(against: payload))
        XCTAssertTrue(FleetRecipePayloadPredicate.integerCompare(op: .greaterThan, value: 9).evaluate(against: payload))
    }

    func test_doubleCompare_appliesEveryOperator() {
        let payload: FleetCommandResponsePayload = .double(3.5)
        XCTAssertTrue(FleetRecipePayloadPredicate.doubleCompare(op: .equal, value: 3.5).evaluate(against: payload))
        XCTAssertTrue(FleetRecipePayloadPredicate.doubleCompare(op: .lessThan, value: 3.6).evaluate(against: payload))
        XCTAssertTrue(FleetRecipePayloadPredicate.doubleCompare(op: .greaterThan, value: 3.4).evaluate(against: payload))
        XCTAssertFalse(FleetRecipePayloadPredicate.doubleCompare(op: .greaterThan, value: 3.5).evaluate(against: payload))
    }

    // MARK: stringList

    func test_stringListContains_matchesExactMember() {
        let payload: FleetCommandResponsePayload = .stringList(["compass", "gyro", "baro"])
        XCTAssertTrue(FleetRecipePayloadPredicate.stringListContains("gyro").evaluate(against: payload))
        XCTAssertFalse(FleetRecipePayloadPredicate.stringListContains("accelerometer").evaluate(against: payload))
        XCTAssertFalse(FleetRecipePayloadPredicate.stringListContains("gyro").evaluate(against: .empty))
    }

    // MARK: Codable

    func test_everyPredicateKind_codableRoundTrip() throws {
        let inputs: [FleetRecipePayloadPredicate] = [
            .keyValueEquals(key: "mode", value: "hold"),
            .keyValuePresent(key: "armed"),
            .boolEquals(true),
            .stringEquals("hold"),
            .stringMatches(regex: "^(hold|loiter)$"),
            .integerCompare(op: .greaterOrEqual, value: 10),
            .doubleCompare(op: .lessThan, value: 3.5),
            .stringListContains("gyro"),
        ]
        for value in inputs {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(FleetRecipePayloadPredicate.self, from: data)
            XCTAssertEqual(value, decoded, "Round-trip mismatch for predicate \(value)")
        }
    }
}
