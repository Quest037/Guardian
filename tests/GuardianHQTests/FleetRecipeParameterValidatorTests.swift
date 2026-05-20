import XCTest
@testable import GuardianCore

/// Stage B1 parameter-schema validation for recipes. Mirrors the Layer 0 tests
/// (`FleetCommandParameterValidatorTests`) so the two validators stay in lockstep.
final class FleetRecipeParameterValidatorTests: XCTestCase {

    // MARK: Missing / optional handling

    func test_missingRequired_producesMissingFailure() {
        let schema = [
            FleetRecipeParameterDeclaration(name: "vehicleID", type: .string, required: true),
        ]
        let result = FleetRecipeParameterValidator.validate(.empty, against: schema)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.parameterName, "vehicleID")
        XCTAssertEqual(result.first?.reason, .missing)
    }

    func test_missingOptional_doesNotProduceFailure() {
        let schema = [
            FleetRecipeParameterDeclaration(name: "altitudeMeters", type: .double, required: false),
        ]
        let result = FleetRecipeParameterValidator.validate(.empty, against: schema)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: Type handling

    func test_integerProvidedWhereDoubleDeclared_isAccepted() {
        let schema = [
            FleetRecipeParameterDeclaration(name: "altitudeMeters", type: .double, required: true),
        ]
        let params = FleetRecipeParameters(values: ["altitudeMeters": .integer(35)])
        let result = FleetRecipeParameterValidator.validate(params, against: schema)
        XCTAssertTrue(result.isEmpty)
    }

    func test_stringProvidedWhereIntegerDeclared_isRejected() {
        let schema = [
            FleetRecipeParameterDeclaration(name: "retries", type: .integer, required: true),
        ]
        let params = FleetRecipeParameters(values: ["retries": .string("3")])
        let result = FleetRecipeParameterValidator.validate(params, against: schema)
        XCTAssertEqual(result.count, 1)
        guard case .typeMismatch(let expected, let actual) = result.first?.reason else {
            return XCTFail("Expected typeMismatch")
        }
        XCTAssertEqual(expected, .integer)
        XCTAssertEqual(actual, .string)
    }

    func test_doubleProvidedWhereBoolDeclared_isRejected() {
        let schema = [
            FleetRecipeParameterDeclaration(name: "autoStart", type: .bool, required: true),
        ]
        let params = FleetRecipeParameters(values: ["autoStart": .double(1.0)])
        let result = FleetRecipeParameterValidator.validate(params, against: schema)
        XCTAssertEqual(result.count, 1)
        guard case .typeMismatch(let expected, let actual) = result.first?.reason else {
            return XCTFail("Expected typeMismatch")
        }
        XCTAssertEqual(expected, .bool)
        XCTAssertEqual(actual, .double)
    }

    // MARK: Allow-list handling

    func test_stringInAllowList_isAccepted() {
        let schema = [
            FleetRecipeParameterDeclaration(
                name: "mode",
                type: .string,
                required: true,
                allowedStringValues: ["hold", "loiter", "rtl"]
            ),
        ]
        let params = FleetRecipeParameters(values: ["mode": .string("hold")])
        let result = FleetRecipeParameterValidator.validate(params, against: schema)
        XCTAssertTrue(result.isEmpty)
    }

    func test_stringOutsideAllowList_producesNotInAllowedValues() {
        let schema = [
            FleetRecipeParameterDeclaration(
                name: "mode",
                type: .string,
                required: true,
                allowedStringValues: ["hold", "loiter"]
            ),
        ]
        let params = FleetRecipeParameters(values: ["mode": .string("manual")])
        let result = FleetRecipeParameterValidator.validate(params, against: schema)
        XCTAssertEqual(result.count, 1)
        guard case .notInAllowedValues(let allowed, let actual) = result.first?.reason else {
            return XCTFail("Expected notInAllowedValues")
        }
        XCTAssertEqual(allowed, ["hold", "loiter"])
        XCTAssertEqual(actual, "manual")
    }

    // MARK: Multi-failure surface

    func test_validatorReportsEveryFailure_notJustTheFirst() {
        let schema = [
            FleetRecipeParameterDeclaration(name: "missingRequired", type: .integer, required: true),
            FleetRecipeParameterDeclaration(name: "wrongType", type: .integer, required: true),
            FleetRecipeParameterDeclaration(
                name: "outsideAllow",
                type: .string,
                required: true,
                allowedStringValues: ["a", "b"]
            ),
        ]
        let params = FleetRecipeParameters(values: [
            "wrongType": .string("oops"),
            "outsideAllow": .string("c"),
        ])
        let result = FleetRecipeParameterValidator.validate(params, against: schema)
        XCTAssertEqual(result.count, 3)
        let names = Set(result.map(\.parameterName))
        XCTAssertEqual(names, ["missingRequired", "wrongType", "outsideAllow"])
    }

    func test_referenceValueInRuntimeParameters_isRejected() {
        let schema = [
            FleetRecipeParameterDeclaration(name: "degrees", type: .double, required: true),
        ]
        let params = FleetRecipeParameters(values: ["degrees": .reference(name: "degrees")])
        let result = FleetRecipeParameterValidator.validate(params, against: schema)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.reason, .referenceNotAllowed)
    }

    // MARK: Codable round-trip on parameter values

    func test_parameterValue_codableRoundTrip() throws {
        let inputs: [FleetRecipeParameterValue] = [
            .bool(true),
            .integer(42),
            .double(3.5),
            .string("hold"),
            .stringList(["a", "b", "c"]),
            .reference(name: "degrees"),
        ]
        for value in inputs {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(FleetRecipeParameterValue.self, from: data)
            XCTAssertEqual(value, decoded, "Round-trip mismatch for \(value.loggable)")
        }
    }
}
