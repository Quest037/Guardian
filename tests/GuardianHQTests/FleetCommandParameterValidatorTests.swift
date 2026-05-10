import XCTest
@testable import GuardianHQ

/// Stage B0 parameter-validation coverage. Pins the contract of
/// ``FleetCommandParameterValidator`` so changes to the schema rules are intentional.
final class FleetCommandParameterValidatorTests: XCTestCase {

    // MARK: missing / optional handling

    func test_missingRequired_producesMissingFailure() {
        let schema = [
            FleetCommandParameterDeclaration(name: "meters", type: .double, required: true)
        ]
        let failures = FleetCommandParameterValidator.validate(.empty, against: schema)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.parameterName, "meters")
        if case .missing = failures.first?.reason {
            // ok
        } else {
            XCTFail("Expected .missing, got \(String(describing: failures.first?.reason))")
        }
    }

    func test_missingOptional_doesNotProduceFailure() {
        let schema = [
            FleetCommandParameterDeclaration(name: "yawDeg", type: .double, required: false)
        ]
        let failures = FleetCommandParameterValidator.validate(.empty, against: schema)
        XCTAssertTrue(failures.isEmpty)
    }

    // MARK: type kind handling

    func test_integerProvidedWhereDoubleDeclared_isAccepted() {
        let schema = [
            FleetCommandParameterDeclaration(name: "meters", type: .double, required: true)
        ]
        let params = FleetCommandParameters(values: ["meters": .integer(35)])
        let failures = FleetCommandParameterValidator.validate(params, against: schema)
        XCTAssertTrue(
            failures.isEmpty,
            "Integer values must be accepted for `double` declarations so callers don't have to disambiguate `35` vs `35.0`."
        )
    }

    func test_stringProvidedWhereIntegerDeclared_isRejected() {
        let schema = [
            FleetCommandParameterDeclaration(name: "channel", type: .integer, required: true)
        ]
        let params = FleetCommandParameters(values: ["channel": .string("1")])
        let failures = FleetCommandParameterValidator.validate(params, against: schema)
        XCTAssertEqual(failures.count, 1)
        if case .typeMismatch(let expected, let actual) = failures.first?.reason {
            XCTAssertEqual(expected, .integer)
            XCTAssertEqual(actual, .string)
        } else {
            XCTFail("Expected .typeMismatch, got \(String(describing: failures.first?.reason))")
        }
    }

    func test_doubleProvidedWhereBoolDeclared_isRejected() {
        let schema = [
            FleetCommandParameterDeclaration(name: "flag", type: .bool, required: true)
        ]
        let params = FleetCommandParameters(values: ["flag": .double(1.0)])
        let failures = FleetCommandParameterValidator.validate(params, against: schema)
        XCTAssertEqual(failures.count, 1)
        if case .typeMismatch(let expected, let actual) = failures.first?.reason {
            XCTAssertEqual(expected, .bool)
            XCTAssertEqual(actual, .double)
        } else {
            XCTFail("Expected .typeMismatch, got \(String(describing: failures.first?.reason))")
        }
    }

    // MARK: allow-list handling

    func test_stringInAllowList_isAccepted() {
        let allowed: Set<String> = ["hold", "manual", "rtl"]
        let schema = [
            FleetCommandParameterDeclaration(
                name: "mode",
                type: .string,
                required: true,
                allowedStringValues: allowed
            )
        ]
        let params = FleetCommandParameters(values: ["mode": .string("hold")])
        let failures = FleetCommandParameterValidator.validate(params, against: schema)
        XCTAssertTrue(failures.isEmpty)
    }

    func test_stringOutsideAllowList_producesNotInAllowedValues() {
        let allowed: Set<String> = ["hold", "manual"]
        let schema = [
            FleetCommandParameterDeclaration(
                name: "mode",
                type: .string,
                required: true,
                allowedStringValues: allowed
            )
        ]
        let params = FleetCommandParameters(values: ["mode": .string("goLikeHell")])
        let failures = FleetCommandParameterValidator.validate(params, against: schema)
        XCTAssertEqual(failures.count, 1)
        if case .notInAllowedValues(let returnedAllowed, let actual) = failures.first?.reason {
            XCTAssertEqual(returnedAllowed, allowed)
            XCTAssertEqual(actual, "goLikeHell")
        } else {
            XCTFail("Expected .notInAllowedValues, got \(String(describing: failures.first?.reason))")
        }
    }

    // MARK: multi-failure surface

    func test_validatorReportsEveryFailure_notJustTheFirst() {
        let schema = [
            FleetCommandParameterDeclaration(name: "meters", type: .double, required: true),
            FleetCommandParameterDeclaration(name: "datum", type: .string, required: true,
                                             allowedStringValues: ["asl", "msl", "agl"])
        ]
        // Missing `meters`, invalid `datum` value.
        let params = FleetCommandParameters(values: ["datum": .string("bogus")])
        let failures = FleetCommandParameterValidator.validate(params, against: schema)
        XCTAssertEqual(failures.count, 2)
        let names = Set(failures.map(\.parameterName))
        XCTAssertEqual(names, ["meters", "datum"])
    }
}
