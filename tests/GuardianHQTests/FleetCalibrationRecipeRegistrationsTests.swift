import XCTest
@testable import GuardianCore

/// Stage C coverage for the calibration subsystem registration entry point.
///
/// As recipes land, this suite gains per-recipe assertions covering: the recipe
/// is registered, its risk tier and `cancelRecipe` pointer are correct, and the
/// loaded body has the expected step + matcher shape. The idempotency contract
/// is checked once at the bottom and applies to the whole subsystem.
///
/// Body validation against the live registries (matchers, branch targets,
/// command references, regex, budget caps, composition depth) happens inside
/// `FleetRecipesCatalogue.register(...)`, so the matching commands must be
/// registered first — `setUp` calls `FleetCommandsCatalogueBootstrap.ensureRegistered()`
/// for that reason.
@MainActor
final class FleetCalibrationRecipeRegistrationsTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        FleetRecipesCatalogue.shared._testOnlyReset()
        FleetRecipesCatalogueBootstrap._testOnlyResetIdempotencyFlag()
        // Core commands must be registered so body validation passes when
        // `register(...)` runs the parser against the live registries. Bootstrap
        // is idempotent so the across-suite cost is one register pass total.
        FleetCommandsCatalogueBootstrap.ensureRegistered()
    }

    // MARK: - recipe.fleet.calibrate.cancel

    func test_registerAll_registersCalibrateCancel() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let descriptor = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.cancel")

        XCTAssertNotNil(descriptor, "Cancel cleanup recipe must register first so compass can reference it.")
        XCTAssertEqual(descriptor?.riskTier, .safeInLiveMission)
        XCTAssertNil(descriptor?.cancelRecipe, "Cleanup recipes are atomic — no own cancelRecipe.")
        XCTAssertTrue(descriptor?.containsRecipes.isEmpty == true, "Cleanup recipes are atomic — no composition.")
    }

    func test_cancelRecipe_bodyHasSingleAnyToSucceedMatcher() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.cancel")?
            .body

        XCTAssertEqual(body?.steps.count, 1)
        XCTAssertEqual(body?.steps.first?.matchers.count, 1)
        let matcher = body?.steps.first?.matchers.first
        if case .any = matcher?.when, case .succeed = matcher?.then {
            // expected
        } else {
            XCTFail("Cancel recipe must match `.any → .succeed` for best-effort cleanup; got \(String(describing: matcher)).")
        }
    }

    // MARK: - recipe.fleet.calibrate.compass

    func test_registerAll_registersCalibrateCompass() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let descriptor = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.compass")

        XCTAssertNotNil(descriptor, "Compass calibration must be registered after registerAll().")
        XCTAssertEqual(descriptor?.riskTier, .groundOnly)
        XCTAssertEqual(
            descriptor?.cancelRecipe?.rawValue,
            "recipe.fleet.calibrate.cancel",
            "Compass cal must declare the shared cancel recipe so mid-flight cancel leaves a clean autopilot state."
        )
        XCTAssertEqual(descriptor?.appliesToSystems, ["compass"])
    }

    func test_compassRecipe_bodyHasFiveMatchers() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.compass")?
            .body

        XCTAssertEqual(body?.steps.count, 1, "Compass cal is a single-step recipe (success-or-escalate model).")
        XCTAssertEqual(
            body?.steps.first?.matchers.count,
            5,
            "Matchers: success → succeed | calibrationDeclined → escalate(removeMagneticInterference) | calibrationDidNotConverge → escalate(rotateDrone) | cancelled → fail | any → fail."
        )
    }

    func test_compassRecipe_escalatesOnCalibrationDeclined() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.calibrate.compass")?
                .body
        )
        let matchers = try XCTUnwrap(body.steps.first?.matchers)
        let declined = matchers.first { matcher in
            if case .error(let kind) = matcher.when, kind == .calibrationDeclined { return true }
            return false
        }
        let matcher = try XCTUnwrap(declined)

        guard case .escalate(let reason, let verbs) = matcher.then else {
            XCTFail("calibrationDeclined matcher must escalate; got \(matcher.then).")
            return
        }
        if case .operatorActionRequired(let kind) = reason {
            XCTAssertEqual(kind, .removeMagneticInterference)
        } else {
            XCTFail("Expected operatorActionRequired escalation; got \(reason).")
        }
        XCTAssertEqual(Set(verbs), [.retry, .abort])
    }

    func test_compassRecipe_escalatesOnCalibrationDidNotConverge() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.calibrate.compass")?
                .body
        )
        let matchers = try XCTUnwrap(body.steps.first?.matchers)
        let didNotConverge = matchers.first { matcher in
            if case .error(let kind) = matcher.when, kind == .calibrationDidNotConverge { return true }
            return false
        }
        let matcher = try XCTUnwrap(didNotConverge)

        guard case .escalate(let reason, let verbs) = matcher.then else {
            XCTFail("calibrationDidNotConverge matcher must escalate; got \(matcher.then).")
            return
        }
        if case .operatorActionRequired(let kind) = reason {
            XCTAssertEqual(kind, .rotateDrone)
        } else {
            XCTFail("Expected operatorActionRequired escalation; got \(reason).")
        }
        XCTAssertEqual(Set(verbs), [.retry, .abort])
    }

    func test_compassRecipe_overallBudgetIs300Seconds() {
        FleetCalibrationRecipeRegistrations.registerAll()
        let body = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.compass")?
            .body
        XCTAssertEqual(body?.overallBudgetSeconds, 300)
    }

    // MARK: - recipe.fleet.calibrate.accelerometer

    func test_registerAll_registersCalibrateAccelerometer() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let descriptor = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.accelerometer")

        XCTAssertNotNil(descriptor, "Accelerometer calibration must be registered after registerAll().")
        XCTAssertEqual(descriptor?.riskTier, .groundOnly)
        XCTAssertEqual(
            descriptor?.cancelRecipe?.rawValue,
            "recipe.fleet.calibrate.cancel",
            "Accelerometer cal must declare the shared cancel recipe so mid-flight cancel leaves a clean autopilot state."
        )
        XCTAssertEqual(descriptor?.appliesToSystems, ["accelerometer"])
    }

    func test_accelerometerRecipe_bodyHasFiveMatchers() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.accelerometer")?
            .body

        XCTAssertEqual(body?.steps.count, 1, "Accel cal is a single-step recipe (success-or-escalate model).")
        XCTAssertEqual(
            body?.steps.first?.matchers.count,
            5,
            "Matchers: success → succeed | calibrationDeclined → escalate(placeOnLevelSurface) | calibrationDidNotConverge → escalate(rotateDrone) | cancelled → fail | any → fail."
        )
    }

    func test_accelerometerRecipe_escalatesOnCalibrationDeclined() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.calibrate.accelerometer")?
                .body
        )
        let matchers = try XCTUnwrap(body.steps.first?.matchers)
        let declined = matchers.first { matcher in
            if case .error(let kind) = matcher.when, kind == .calibrationDeclined { return true }
            return false
        }
        let matcher = try XCTUnwrap(declined)

        guard case .escalate(let reason, let verbs) = matcher.then else {
            XCTFail("calibrationDeclined matcher must escalate; got \(matcher.then).")
            return
        }
        if case .operatorActionRequired(let kind) = reason {
            XCTAssertEqual(
                kind,
                .placeOnLevelSurface,
                "Accel declined typically means no stable level reference — operator must place vehicle on a level surface."
            )
        } else {
            XCTFail("Expected operatorActionRequired escalation; got \(reason).")
        }
        XCTAssertEqual(Set(verbs), [.retry, .abort])
    }

    // MARK: - recipe.fleet.calibrate.gyro

    func test_registerAll_registersCalibrateGyro() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let descriptor = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.gyro")

        XCTAssertNotNil(descriptor, "Gyro calibration must be registered after registerAll().")
        XCTAssertEqual(descriptor?.riskTier, .groundOnly)
        XCTAssertEqual(
            descriptor?.cancelRecipe?.rawValue,
            "recipe.fleet.calibrate.cancel",
            "Gyro cal must declare the shared cancel recipe so mid-flight cancel leaves a clean autopilot state."
        )
        XCTAssertEqual(descriptor?.appliesToSystems, ["gyro"])
    }

    func test_gyroRecipe_bodyHasFiveMatchersAnd60sBudget() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.gyro")?
            .body

        XCTAssertEqual(body?.steps.count, 1, "Gyro cal is a single-step recipe (success-or-escalate model).")
        XCTAssertEqual(
            body?.steps.first?.matchers.count,
            5,
            "Matchers: success → succeed | calibrationDeclined → escalate(holdStill) | calibrationDidNotConverge → escalate(holdStill) | cancelled → fail | any → fail."
        )
        XCTAssertEqual(
            body?.overallBudgetSeconds,
            60,
            "Gyro cal is fast (10-30s); 60s budget covers procedure plus operator setup."
        )
    }

    func test_gyroRecipe_bothFailureKindsEscalateToHoldStill() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.calibrate.gyro")?
                .body
        )
        // Gyro is one of several calibration recipes whose two recoverable error
        // kinds resolve to the *same* operator action (motion during sampling is
        // the only operator-recoverable cause). Helper pins the same intent for
        // gyro / baro / level so a copy-paste between them can't accidentally
        // swap one matcher to a different operator kind.
        try assertBothFailureKindsEscalateToSameOperatorKind(
            in: body,
            expected: .holdStill,
            recipeLabel: "gyro"
        )
    }

    func test_accelerometerRecipe_escalatesOnCalibrationDidNotConverge() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.calibrate.accelerometer")?
                .body
        )
        let matchers = try XCTUnwrap(body.steps.first?.matchers)
        let didNotConverge = matchers.first { matcher in
            if case .error(let kind) = matcher.when, kind == .calibrationDidNotConverge { return true }
            return false
        }
        let matcher = try XCTUnwrap(didNotConverge)

        guard case .escalate(let reason, let verbs) = matcher.then else {
            XCTFail("calibrationDidNotConverge matcher must escalate; got \(matcher.then).")
            return
        }
        if case .operatorActionRequired(let kind) = reason {
            XCTAssertEqual(
                kind,
                .rotateDrone,
                "Accel didNotConverge means the six-position pass missed samples — operator must repeat orientations."
            )
        } else {
            XCTFail("Expected operatorActionRequired escalation; got \(reason).")
        }
        XCTAssertEqual(Set(verbs), [.retry, .abort])
    }

    // MARK: - recipe.fleet.calibrate.baro

    func test_registerAll_registersCalibrateBaro() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let descriptor = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.baro")

        XCTAssertNotNil(descriptor, "Baro calibration must be registered after registerAll().")
        XCTAssertEqual(descriptor?.riskTier, .groundOnly)
        XCTAssertEqual(
            descriptor?.cancelRecipe?.rawValue,
            "recipe.fleet.calibrate.cancel"
        )
        XCTAssertEqual(descriptor?.appliesToSystems, ["barometer"])
    }

    func test_baroRecipe_bodyHasFiveMatchersAnd30sBudget() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.baro")?
            .body

        XCTAssertEqual(body?.steps.count, 1)
        XCTAssertEqual(body?.steps.first?.matchers.count, 5)
        XCTAssertEqual(
            body?.overallBudgetSeconds,
            30,
            "Baro cal is very fast (<5s); 30s budget covers procedure plus one operator retry."
        )
    }

    func test_baroRecipe_bothFailureKindsEscalateToHoldStill() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.calibrate.baro")?
                .body
        )
        try assertBothFailureKindsEscalateToSameOperatorKind(
            in: body,
            expected: .holdStill,
            recipeLabel: "baro"
        )
    }

    // MARK: - recipe.fleet.calibrate.level

    func test_registerAll_registersCalibrateLevel() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let descriptor = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.level")

        XCTAssertNotNil(descriptor, "Level calibration must be registered after registerAll().")
        XCTAssertEqual(descriptor?.riskTier, .groundOnly)
        XCTAssertEqual(
            descriptor?.cancelRecipe?.rawValue,
            "recipe.fleet.calibrate.cancel"
        )
        XCTAssertEqual(descriptor?.appliesToSystems, ["level"])
    }

    func test_levelRecipe_bodyHasFiveMatchersAnd60sBudget() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.calibrate.level")?
            .body

        XCTAssertEqual(body?.steps.count, 1)
        XCTAssertEqual(body?.steps.first?.matchers.count, 5)
        XCTAssertEqual(
            body?.overallBudgetSeconds,
            60,
            "Level cal is fast (10-30s); 60s budget covers procedure plus operator setup time."
        )
    }

    func test_levelRecipe_bothFailureKindsEscalateToPlaceOnLevelSurface() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.calibrate.level")?
                .body
        )
        try assertBothFailureKindsEscalateToSameOperatorKind(
            in: body,
            expected: .placeOnLevelSurface,
            recipeLabel: "level"
        )
    }

    // MARK: - Shared assertion helper

    /// Pins the design decision for any calibration recipe whose two recoverable
    /// error kinds resolve to the same operator action (gyro, baro, level today).
    /// Both `calibrationDeclined` and `calibrationDidNotConverge` must escalate to
    /// the supplied `operatorKind` with `[.retry, .abort]` verbs.
    private func assertBothFailureKindsEscalateToSameOperatorKind(
        in body: FleetRecipeBody,
        expected operatorKind: FleetRecipeOperatorActionKind,
        recipeLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let matchers = try XCTUnwrap(body.steps.first?.matchers, file: file, line: line)
        for expectedErrorKind in [FleetCommandErrorKind.calibrationDeclined, .calibrationDidNotConverge] {
            let match = matchers.first { matcher in
                if case .error(let kind) = matcher.when, kind == expectedErrorKind { return true }
                return false
            }
            let matcher = try XCTUnwrap(
                match,
                "Expected \(recipeLabel) matcher for \(expectedErrorKind).",
                file: file,
                line: line
            )

            guard case .escalate(let reason, let verbs) = matcher.then else {
                XCTFail(
                    "\(recipeLabel): \(expectedErrorKind) matcher must escalate; got \(matcher.then).",
                    file: file,
                    line: line
                )
                continue
            }
            if case .operatorActionRequired(let kind) = reason {
                XCTAssertEqual(
                    kind,
                    operatorKind,
                    "\(recipeLabel): both failure kinds must escalate to \(operatorKind.rawValue).",
                    file: file,
                    line: line
                )
            } else {
                XCTFail(
                    "\(recipeLabel): expected operatorActionRequired escalation; got \(reason).",
                    file: file,
                    line: line
                )
            }
            XCTAssertEqual(Set(verbs), [.retry, .abort], file: file, line: line)
        }
    }

    // MARK: - Comprehensive coverage of remaining cals (compass.motor, baro.temperature,
    //         airspeed, esc, rc, rc.trim, gimbal, rangefinder, flow, vision)

    /// Table-driven smoke check that every newly-authored calibration recipe is
    /// registered with the expected metadata. Per-recipe assertions specific to
    /// matcher shape live in the bespoke tests below.
    func test_registerAll_registersAllCalibrationRecipes() {
        struct Expected {
            let rawName: String
            let appliesToSystems: [String]
        }

        let expected: [Expected] = [
            Expected(rawName: "recipe.fleet.calibrate.compass.motor",       appliesToSystems: ["compass"]),
            Expected(rawName: "recipe.fleet.calibrate.baro.temperature",    appliesToSystems: ["barometer"]),
            Expected(rawName: "recipe.fleet.calibrate.airspeed",            appliesToSystems: ["airspeed"]),
            Expected(rawName: "recipe.fleet.calibrate.esc",                 appliesToSystems: ["esc"]),
            Expected(rawName: "recipe.fleet.calibrate.rc",                  appliesToSystems: ["rc"]),
            Expected(rawName: "recipe.fleet.calibrate.rc.trim",             appliesToSystems: ["rc"]),
            Expected(rawName: "recipe.fleet.calibrate.gimbal",              appliesToSystems: ["gimbal"]),
            Expected(rawName: "recipe.fleet.calibrate.rangefinder",         appliesToSystems: ["rangefinder"]),
            Expected(rawName: "recipe.fleet.calibrate.flow",                appliesToSystems: ["flow"]),
            Expected(rawName: "recipe.fleet.calibrate.vision",              appliesToSystems: ["vision"]),
            Expected(rawName: "recipe.fleet.calibrate.compass.declination", appliesToSystems: ["compass"]),
            Expected(rawName: "recipe.fleet.calibrate.battery.voltage",     appliesToSystems: ["battery"]),
            Expected(rawName: "recipe.fleet.calibrate.battery.current",     appliesToSystems: ["battery"]),
            Expected(rawName: "recipe.fleet.calibrate.battery.capacity",    appliesToSystems: ["battery"]),
            Expected(rawName: "recipe.fleet.calibrate.servo",               appliesToSystems: ["servo"]),
            Expected(rawName: "recipe.fleet.calibrate.gimbal.neutral",      appliesToSystems: ["gimbal"]),
        ]

        FleetCalibrationRecipeRegistrations.registerAll()

        for entry in expected {
            let descriptor = FleetRecipesCatalogue.shared.descriptor(forRawValue: entry.rawName)
            XCTAssertNotNil(descriptor, "\(entry.rawName) must be registered after registerAll().")
            XCTAssertEqual(descriptor?.riskTier, .groundOnly, "\(entry.rawName) must be groundOnly — all cals overwrite calibration state.")
            XCTAssertEqual(
                descriptor?.cancelRecipe?.rawValue,
                "recipe.fleet.calibrate.cancel",
                "\(entry.rawName) must declare the shared cancel recipe."
            )
            XCTAssertEqual(descriptor?.appliesToSystems, entry.appliesToSystems, "\(entry.rawName) appliesToSystems mismatch.")
        }
    }

    func test_paramDrivenRecipes_declareSchemasAndReferenceParameters() throws {
        struct Expected {
            let rawName: String
            let parameterNames: Set<String>
        }
        let expected: [Expected] = [
            Expected(rawName: "recipe.fleet.calibrate.compass.declination", parameterNames: ["degrees"]),
            Expected(rawName: "recipe.fleet.calibrate.battery.voltage", parameterNames: ["scale"]),
            Expected(rawName: "recipe.fleet.calibrate.battery.current", parameterNames: ["scale"]),
            Expected(rawName: "recipe.fleet.calibrate.battery.capacity", parameterNames: ["mAh"]),
            Expected(rawName: "recipe.fleet.calibrate.servo", parameterNames: ["channel", "minPwm", "maxPwm", "trimPwm"]),
            Expected(rawName: "recipe.fleet.calibrate.gimbal.neutral", parameterNames: ["rollDeg", "pitchDeg", "yawDeg"]),
        ]

        FleetCalibrationRecipeRegistrations.registerAll()

        for entry in expected {
            let descriptor = try XCTUnwrap(
                FleetRecipesCatalogue.shared.descriptor(forRawValue: entry.rawName),
                "\(entry.rawName) must be registered."
            )
            XCTAssertEqual(Set(descriptor.parameters.map(\.name)), entry.parameterNames)

            let step = try XCTUnwrap(descriptor.body?.steps.first)
            let stepParameterValues: [String: FleetRecipeParameterValue]
            if case .invokeCommand(_, _, let parameters, _, _) = step {
                stepParameterValues = parameters.values
            } else {
                return XCTFail("\(entry.rawName) expected an invokeCommand body.")
            }
            XCTAssertEqual(Set(stepParameterValues.keys), entry.parameterNames)
            for parameterName in entry.parameterNames {
                XCTAssertEqual(
                    stepParameterValues[parameterName],
                    .reference(name: parameterName),
                    "\(entry.rawName) must forward \(parameterName) from recipe params into the command step."
                )
            }
        }
    }

    // Pattern B: stack-asymmetric interactive recipes carry an explicit
    // `error(notImplemented) → fail` matcher so unsupported-stack failures get a
    // precise message instead of falling through to the generic `any` catch-all.

    func test_compassMotorRecipe_hasNotImplementedMatcher() throws {
        FleetCalibrationRecipeRegistrations.registerAll()
        try assertHasNotImplementedFailMatcher(
            recipeRawName: "recipe.fleet.calibrate.compass.motor",
            expectedDetailSubstring: "ArduPilot-only"
        )
    }

    func test_baroTemperatureRecipe_hasNotImplementedMatcher() throws {
        FleetCalibrationRecipeRegistrations.registerAll()
        try assertHasNotImplementedFailMatcher(
            recipeRawName: "recipe.fleet.calibrate.baro.temperature",
            expectedDetailSubstring: "ArduPilot-only"
        )
    }

    func test_gimbalRecipe_hasNotImplementedMatcher() throws {
        FleetCalibrationRecipeRegistrations.registerAll()
        try assertHasNotImplementedFailMatcher(
            recipeRawName: "recipe.fleet.calibrate.gimbal",
            expectedDetailSubstring: "PX4-only"
        )
    }

    // Pattern A: interactive cals where both failure kinds map to the same kind
    // (already covered for gyro / baro / level — extend the helper to esc / rc /
    // rc.trim).

    func test_escRecipe_bothFailureKindsEscalateToRestartVehicle() throws {
        FleetCalibrationRecipeRegistrations.registerAll()
        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared.descriptor(forRawValue: "recipe.fleet.calibrate.esc")?.body
        )
        try assertBothFailureKindsEscalateToSameOperatorKind(
            in: body, expected: .restartVehicle, recipeLabel: "esc"
        )
    }

    func test_airspeedRecipe_bothFailureKindsEscalateToHoldStill() throws {
        FleetCalibrationRecipeRegistrations.registerAll()
        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared.descriptor(forRawValue: "recipe.fleet.calibrate.airspeed")?.body
        )
        try assertBothFailureKindsEscalateToSameOperatorKind(
            in: body, expected: .holdStill, recipeLabel: "airspeed"
        )
    }

    func test_rcRecipes_bothFailureKindsEscalateToConnectExternalSensor() throws {
        FleetCalibrationRecipeRegistrations.registerAll()
        for raw in ["recipe.fleet.calibrate.rc", "recipe.fleet.calibrate.rc.trim"] {
            let body = try XCTUnwrap(
                FleetRecipesCatalogue.shared.descriptor(forRawValue: raw)?.body,
                "Recipe \(raw) must be registered."
            )
            try assertBothFailureKindsEscalateToSameOperatorKind(
                in: body, expected: .connectExternalSensor, recipeLabel: raw
            )
        }
    }

    // Pattern C: discoverability shells for cals whose per-stack support is not
    // implemented in v1. They ship with 4 matchers: success / notImplemented-fail
    // / cancelled / any. No recoverable-error escalations because the failure mode
    // is structural (unsupported stack), not operator-recoverable.

    func test_patternC_recipes_haveFourMatchersAndNotImplementedHandling() throws {
        FleetCalibrationRecipeRegistrations.registerAll()
        for raw in [
            "recipe.fleet.calibrate.rangefinder",
            "recipe.fleet.calibrate.flow",
            "recipe.fleet.calibrate.vision",
        ] {
            let descriptor = try XCTUnwrap(
                FleetRecipesCatalogue.shared.descriptor(forRawValue: raw),
                "Pattern-C recipe \(raw) must be registered."
            )
            let matchers = try XCTUnwrap(descriptor.body?.steps.first?.matchers)
            XCTAssertEqual(
                matchers.count,
                4,
                "Pattern-C recipe \(raw) ships with 4 matchers (success / notImplemented-fail / cancelled / any)."
            )
            try assertHasNotImplementedFailMatcher(
                recipeRawName: raw,
                expectedDetailSubstring: "not implemented in this app version"
            )
        }
    }

    // MARK: - Shared matcher helper for notImplemented assertions

    private func assertHasNotImplementedFailMatcher(
        recipeRawName: String,
        expectedDetailSubstring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let descriptor = try XCTUnwrap(
            FleetRecipesCatalogue.shared.descriptor(forRawValue: recipeRawName),
            "Recipe \(recipeRawName) must be registered.",
            file: file, line: line
        )
        let matchers = try XCTUnwrap(descriptor.body?.steps.first?.matchers, file: file, line: line)
        let notImpl = matchers.first { matcher in
            if case .error(let kind) = matcher.when, kind == .notImplemented { return true }
            return false
        }
        let matcher = try XCTUnwrap(
            notImpl,
            "\(recipeRawName) must carry an `error(notImplemented) → fail` matcher.",
            file: file, line: line
        )
        guard case .fail(let detail) = matcher.then else {
            XCTFail("\(recipeRawName): notImplemented matcher must fail; got \(matcher.then).", file: file, line: line)
            return
        }
        let detailString = try XCTUnwrap(detail, "\(recipeRawName) notImplemented fail must carry a detail.", file: file, line: line)
        XCTAssertTrue(
            detailString.contains(expectedDetailSubstring),
            "\(recipeRawName) notImplemented detail must mention '\(expectedDetailSubstring)'; got: \(detailString)",
            file: file, line: line
        )
    }

    // MARK: - recipe.fleet.diagnose.cancel + armprobe (+ armprobe.hold)

    func test_registerAll_registersDiagnoseArmProbeCancel() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let descriptor = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.diagnose.cancel")

        XCTAssertNotNil(descriptor, "Diagnose cancel recipe must register so armprobe can reference it as cancelRecipe.")
        XCTAssertEqual(descriptor?.riskTier, .safeInLiveMission)
        XCTAssertNil(descriptor?.cancelRecipe, "Cleanup recipes are atomic — no own cancelRecipe.")
        XCTAssertTrue(descriptor?.containsRecipes.isEmpty == true)
    }

    func test_diagnoseCancel_bodyIsBestEffortDisarm() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.diagnose.cancel")?
                .body
        )
        XCTAssertEqual(body.steps.count, 1)

        guard case .invokeCommand(_, let command, _, _, _) = body.steps[0] else {
            return XCTFail("Diagnose cancel body must be an invokeCommand step.")
        }
        XCTAssertEqual(
            command.rawValue,
            "command.fleet.vehicle.do.disarm",
            "Diagnose cancel must disarm so cancel mid-probe never leaves a vehicle armed on the pad."
        )

        let matchers = body.steps[0].matchers
        XCTAssertEqual(matchers.count, 1)
        guard case .any = matchers[0].when, case .succeed = matchers[0].then else {
            return XCTFail("Diagnose cancel must use `any → succeed` for best-effort cleanup; got \(matchers[0]).")
        }
    }

    func test_registerAll_registersDiagnoseArmProbe() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let descriptor = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.diagnose.armprobe")

        XCTAssertNotNil(descriptor, "Arm probe must be registered after registerAll().")
        XCTAssertEqual(descriptor?.riskTier, .groundOnly)
        XCTAssertEqual(
            descriptor?.cancelRecipe?.rawValue,
            "recipe.fleet.diagnose.cancel",
            "Arm probe must declare the diagnose cancel recipe so mid-probe cancel still disarms."
        )
        XCTAssertEqual(descriptor?.appliesToSystems, ["arm", "preflight"])
        XCTAssertTrue(
            descriptor?.parameters.isEmpty == true,
            "Arm probe takes no parameters — single-vehicle probe with no caller knobs."
        )
    }

    func test_armProbe_bodyIsArmThenDisarm() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.diagnose.armprobe")?
                .body
        )
        XCTAssertEqual(body.steps.count, 2, "Arm probe is arm → disarm so the probe leaves the vehicle in its starting state.")
        XCTAssertEqual(body.overallBudgetSeconds, 20)

        guard case .invokeCommand(_, let armCommand, _, _, _) = body.steps[0] else {
            return XCTFail("First step must be an invokeCommand.")
        }
        XCTAssertEqual(armCommand.rawValue, "command.fleet.vehicle.do.arm")

        guard case .invokeCommand(_, let disarmCommand, _, _, _) = body.steps[1] else {
            return XCTFail("Second step must be an invokeCommand.")
        }
        XCTAssertEqual(disarmCommand.rawValue, "command.fleet.vehicle.do.disarm")
    }

    /// The arm probe's value over a raw `do.arm` is the classification of the
    /// common refusal kinds the catalogue exposes today. Lock the matcher table
    /// in one place so accidental drops don't quietly degrade the probe.
    func test_armProbe_armStepClassifiesAllCommonFailureKinds() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.diagnose.armprobe")?
                .body
        )
        let armMatchers = body.steps[0].matchers

        // `success` and `alreadyArmed` must continue the recipe to disarm.
        let continueKinds: [(String, FleetRecipeResponseMatcher)] = [
            ("success",      .success(payload: nil)),
            ("alreadyArmed", .error(kind: .alreadyArmed)),
        ]
        for (label, matcherKind) in continueKinds {
            let matcher = try XCTUnwrap(
                armMatchers.first(where: { $0.when == matcherKind }),
                "Arm step must carry a matcher for \(label)."
            )
            guard case .continueToNextStep = matcher.then else {
                XCTFail("\(label) matcher must continueToNextStep so the probe runs the disarm step; got \(matcher.then).")
                return
            }
        }

        // Every other classified failure kind must `fail` with a populated detail.
        let failKinds: [FleetCommandErrorKind] = [
            .armRejectedByAutopilot, .calibrationDeclined, .modeNotSupported,
            .autopilotBusy, .notConnected, .noSession, .authorityGated,
        ]
        for kind in failKinds {
            let matcher = try XCTUnwrap(
                armMatchers.first(where: {
                    if case .error(let k) = $0.when, k == kind { return true }
                    return false
                }),
                "Arm step must classify \(kind) with a dedicated matcher."
            )
            guard case .fail(let detail) = matcher.then else {
                XCTFail("\(kind) matcher must fail with a detail; got \(matcher.then).")
                continue
            }
            let unwrapped = try XCTUnwrap(detail, "\(kind) matcher must carry a non-nil detail.")
            XCTAssertFalse(unwrapped.isEmpty, "\(kind) detail must be non-empty so the wizard has something to surface.")
        }

        // Operator cancellation must fail the recipe (not succeed) so the wizard
        // never reads cancel as a passing probe.
        let cancelMatcher = try XCTUnwrap(
            armMatchers.first(where: { if case .cancelled = $0.when { return true } else { return false } }),
            "Arm step must classify cancelled."
        )
        guard case .fail = cancelMatcher.then else {
            return XCTFail("cancelled matcher must fail; got \(cancelMatcher.then).")
        }

        // `any` must be the last matcher (parser rule) and fail with a detail.
        XCTAssertEqual(armMatchers.last?.when, .any, "any matcher must be last so it acts as the catch-all.")
        if case .fail = armMatchers.last?.then {
            // expected
        } else {
            XCTFail("any matcher must fail; got \(String(describing: armMatchers.last?.then)).")
        }
    }

    func test_registerAll_registersDiagnoseArmProbeHold() {
        FleetCalibrationRecipeRegistrations.registerAll()

        let descriptor = FleetRecipesCatalogue.shared
            .descriptor(forRawValue: "recipe.fleet.diagnose.armprobe.hold")

        XCTAssertNotNil(descriptor, "Arm probe (hold) must register after registerAll().")
        XCTAssertEqual(descriptor?.riskTier, .groundOnly)
        XCTAssertEqual(
            descriptor?.cancelRecipe?.rawValue,
            "recipe.fleet.diagnose.cancel",
            "Hold variant must still declare diagnose cancel so mid-probe cancel attempts disarm."
        )
        XCTAssertEqual(descriptor?.appliesToSystems, ["arm", "preflight"])
    }

    func test_armProbeHold_bodyIsSingleArmStepWithSucceedTerminals() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.diagnose.armprobe.hold")?
                .body
        )
        XCTAssertEqual(body.steps.count, 1, "Hold probe stops after arm — no trailing disarm step.")
        XCTAssertEqual(body.overallBudgetSeconds, 15)

        let armMatchers = body.steps[0].matchers
        let succeedKinds: [(String, FleetRecipeResponseMatcher)] = [
            ("success",      .success(payload: nil)),
            ("alreadyArmed", .error(kind: .alreadyArmed)),
        ]
        for (label, matcherKind) in succeedKinds {
            let matcher = try XCTUnwrap(
                armMatchers.first(where: { $0.when == matcherKind }),
                "Hold arm step must carry a matcher for \(label)."
            )
            guard case .succeed = matcher.then else {
                XCTFail("\(label) matcher must succeed (no disarm follow-up); got \(matcher.then).")
                return
            }
        }
    }

    /// The disarm step is the safety floor — anything other than "vehicle no
    /// longer armed" is a hard failure because a vehicle that armed but won't
    /// disarm is the worst-case probe outcome.
    func test_armProbe_disarmStepFailsOnAnythingOtherThanDisarmed() throws {
        FleetCalibrationRecipeRegistrations.registerAll()

        let body = try XCTUnwrap(
            FleetRecipesCatalogue.shared
                .descriptor(forRawValue: "recipe.fleet.diagnose.armprobe")?
                .body
        )
        let disarmMatchers = body.steps[1].matchers
        XCTAssertEqual(disarmMatchers.count, 3, "Disarm step matchers: success | alreadyDisarmed | any.")

        // success → succeed
        let success = try XCTUnwrap(disarmMatchers.first(where: {
            if case .success = $0.when { return true } else { return false }
        }))
        if case .succeed = success.then {
            // expected
        } else { XCTFail("disarm success matcher must succeed; got \(success.then).") }

        // alreadyDisarmed → succeed (race condition is still a healthy outcome)
        let already = try XCTUnwrap(disarmMatchers.first(where: {
            if case .error(let k) = $0.when, k == .alreadyDisarmed { return true } else { return false }
        }))
        if case .succeed = already.then {
            // expected
        } else { XCTFail("disarm alreadyDisarmed matcher must succeed; got \(already.then).") }

        // any → fail (the safety floor)
        let any = try XCTUnwrap(disarmMatchers.last)
        XCTAssertEqual(any.when, .any)
        guard case .fail(let detail) = any.then else {
            return XCTFail("disarm any matcher must fail; got \(any.then).")
        }
        let unwrapped = try XCTUnwrap(detail)
        XCTAssertTrue(
            unwrapped.contains("UNSAFE"),
            "disarm any-fail detail must flag the unsafe state explicitly so the wizard renders it loudly; got: \(unwrapped)"
        )
    }

    // MARK: - Subsystem-wide idempotency

    func test_registerAll_isIdempotent() {
        FleetCalibrationRecipeRegistrations.registerAll()
        let countAfterFirst = FleetRecipesCatalogue.shared.descriptors.count

        FleetCalibrationRecipeRegistrations.registerAll()
        let countAfterSecond = FleetRecipesCatalogue.shared.descriptors.count

        XCTAssertEqual(
            countAfterFirst,
            countAfterSecond,
            "Calling registerAll() twice must not double-register descriptors. " +
            "The catalogue's per-name overwrite rule keeps this stable."
        )
        XCTAssertEqual(
            countAfterFirst,
            25,
            "Calibration subsystem currently ships exactly 25 recipes: cancel + 5 core sensor cals " +
            "(compass, accelerometer, gyro, baro, level) + 7 additional sensor cals " +
            "(compass.motor, baro.temperature, airspeed, esc, rc, rc.trim, gimbal) + " +
            "3 v1 discoverability shells (rangefinder, flow, vision) + 6 param-driven cals " +
            "(compass.declination, battery.voltage/current/capacity, servo, gimbal.neutral) + " +
            "3 diagnose recipes (cancel, armprobe, armprobe.hold). " +
            "When new calibration or diagnose recipes land, update this assertion."
        )
    }
}
