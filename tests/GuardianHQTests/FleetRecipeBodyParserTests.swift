import XCTest
@testable import GuardianCore

/// Stage B1 coverage for `FleetRecipeBodyParser`: every structural rule the parser
/// enforces, including the parse-time **1-level recipe composition depth** check
/// (Stage B1 item 8). Each rule is asserted in both directions: a body that
/// satisfies it parses cleanly; a body that breaks it surfaces the expected error
/// kind. Multi-error surface is also pinned so authoring UIs can show a complete
/// problem list, not one-at-a-time.
@MainActor
final class FleetRecipeBodyParserTests: XCTestCase {

    // MARK: Setup

    override func setUp() async throws {
        try await super.setUp()
        FleetRecipesCatalogue.shared._testOnlyReset()
        // Make sure the Layer 0 catalogue has at least the descriptors we reference.
        // The bootstrap is idempotent, so calling it here is harmless.
        FleetCommandsCatalogueBootstrap.ensureRegistered()
    }

    // MARK: Helpers

    private func emptyDescriptor(name rawName: String, body: FleetRecipeBody? = nil) -> FleetRecipeDescriptor {
        FleetRecipeDescriptor(
            name: FleetRecipeName.literal(rawName),
            humanLabel: rawName,
            humanDescription: "Test descriptor for \(rawName)",
            riskTier: .groundOnly,
            body: body
        )
    }

    private func minimalValidBody(
        entry: String = "calibrate",
        steps: [FleetRecipeStep]? = nil,
        budget: TimeInterval = 60
    ) -> FleetRecipeBody {
        let defaultSteps: [FleetRecipeStep] = [
            FleetRecipeStep.invokeCommand(
                id: FleetRecipeStepID.literal(entry),
                command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                matchers: [
                    FleetRecipeStepMatcher(when: .success(), then: .succeed),
                    FleetRecipeStepMatcher(when: .any, then: .fail(detail: nil)),
                ]
            ),
        ]
        return FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal(entry),
            steps: steps ?? defaultSteps,
            overallBudgetSeconds: budget
        )
    }

    // MARK: Happy path

    func test_validate_acceptsMinimalValidBody() {
        let descriptor = emptyDescriptor(name: "recipe.fleet.calibrate.compass")
        let errors = FleetRecipeBodyParser.validate(
            minimalValidBody(),
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertEqual(errors, [])
    }

    // MARK: Step-set checks

    func test_noSteps_isRejected() {
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("calibrate"),
            steps: [],
            overallBudgetSeconds: 60
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(errors.contains(.noSteps))
    }

    func test_duplicateStepID_isRejected() {
        let dupStep = FleetRecipeStep.invokeCommand(
            id: FleetRecipeStepID.literal("dup"),
            command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
            matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
        )
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("dup"),
            steps: [dupStep, dupStep]
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(errors.contains(.duplicateStepID(FleetRecipeStepID.literal("dup"))))
    }

    func test_entryStepNotFound_isRejected() {
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("missing"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("present"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
                ),
            ]
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(errors.contains(.entryStepNotFound(FleetRecipeStepID.literal("missing"))))
    }

    // MARK: Matcher list rules

    func test_stepHasNoMatchers_isRejected() {
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("solo"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("solo"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                    matchers: []
                ),
            ]
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(errors.contains(.stepHasNoMatchers(FleetRecipeStepID.literal("solo"))))
    }

    func test_anyMatcher_inNonFinalPosition_isRejected() {
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("solo"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("solo"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                    matchers: [
                        FleetRecipeStepMatcher(when: .any, then: .succeed),
                        FleetRecipeStepMatcher(when: .success(), then: .succeed),
                    ]
                ),
            ]
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(errors.contains(.anyMatcherMustBeLast(FleetRecipeStepID.literal("solo"))))
    }

    func test_multipleAnyMatchers_inSameStep_areRejected() {
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("solo"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("solo"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                    matchers: [
                        FleetRecipeStepMatcher(when: .any, then: .fail(detail: nil)),
                        FleetRecipeStepMatcher(when: .any, then: .succeed),
                    ]
                ),
            ]
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(errors.contains(.anyMatcherMustBeLast(FleetRecipeStepID.literal("solo"))))
    }

    func test_branchTargetNotFound_isRejected() {
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("calibrate"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("calibrate"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                    matchers: [
                        FleetRecipeStepMatcher(
                            when: .error(kind: .calibrationDeclined),
                            then: .branch(stepID: FleetRecipeStepID.literal("nonexistent"))
                        ),
                        FleetRecipeStepMatcher(when: .any, then: .succeed),
                    ]
                ),
            ]
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(
            errors.contains(.branchTargetNotFound(
                stepID: FleetRecipeStepID.literal("nonexistent"),
                fromStep: FleetRecipeStepID.literal("calibrate")
            ))
        )
    }

    // MARK: Command / recipe registration checks

    func test_invokedCommandNotRegistered_isRejected() {
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("ghost"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("ghost"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.totallymade.up"),
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
                ),
            ]
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(errors.contains(where: {
            if case .invokedCommandNotRegistered = $0 { return true } else { return false }
        }))
    }

    func test_stepParameterReferenceToDeclaredRecipeParameter_isAccepted() {
        let descriptor = FleetRecipeDescriptor(
            name: FleetRecipeName.literal("recipe.fleet.calibrate.compass.declination"),
            humanLabel: "Compass declination",
            humanDescription: "Test descriptor.",
            parameters: [
                FleetRecipeParameterDeclaration(name: "degrees", type: .double, required: true),
            ],
            riskTier: .groundOnly
        )
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("write"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("write"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass.declination"),
                    parameters: FleetRecipeParameters(values: [
                        "degrees": .reference(name: "degrees"),
                    ]),
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
                ),
            ]
        )

        let errors = FleetRecipeBodyParser.validate(
            body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )

        XCTAssertEqual(errors, [])
    }

    func test_stepParameterReferenceToUndeclaredRecipeParameter_isRejected() {
        let descriptor = emptyDescriptor(name: "recipe.fleet.calibrate.compass.declination")
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("write"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("write"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass.declination"),
                    parameters: FleetRecipeParameters(values: [
                        "degrees": .reference(name: "degrees"),
                    ]),
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
                ),
            ]
        )

        let errors = FleetRecipeBodyParser.validate(
            body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )

        XCTAssertTrue(errors.contains(.stepParameterReferenceNotDeclared(
            stepID: FleetRecipeStepID.literal("write"),
            parameterName: "degrees"
        )))
    }

    func test_stepParameterReferenceTypeMismatch_isRejected() {
        let descriptor = FleetRecipeDescriptor(
            name: FleetRecipeName.literal("recipe.fleet.calibrate.compass.declination"),
            humanLabel: "Compass declination",
            humanDescription: "Test descriptor.",
            parameters: [
                FleetRecipeParameterDeclaration(name: "degrees", type: .string, required: true),
            ],
            riskTier: .groundOnly
        )
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("write"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("write"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass.declination"),
                    parameters: FleetRecipeParameters(values: [
                        "degrees": .reference(name: "degrees"),
                    ]),
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
                ),
            ]
        )

        let errors = FleetRecipeBodyParser.validate(
            body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )

        XCTAssertTrue(errors.contains(.stepParameterReferenceTypeMismatch(
            stepID: FleetRecipeStepID.literal("write"),
            parameterName: "degrees",
            expected: .double,
            actual: .string
        )))
    }

    func test_invokedRecipeNotRegistered_isRejected() {
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("call"),
            steps: [
                FleetRecipeStep.invokeRecipe(
                    id: FleetRecipeStepID.literal("call"),
                    recipe: FleetRecipeName.literal("recipe.fleet.calibrate.missing"),
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
                ),
            ]
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.suite"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(errors.contains(where: {
            if case .invokedRecipeNotRegistered = $0 { return true } else { return false }
        }))
    }

    // MARK: 1-level depth check (Stage B1 item 8)

    func test_invokedRecipeBodyExceedsDepth_isRejectedAtParseTime() {
        // Register a leaf recipe (no invokeRecipe steps).
        let leafBody = minimalValidBody(entry: "calibrate")
        let leaf = emptyDescriptor(name: "recipe.fleet.calibrate.compass", body: leafBody)
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(leaf))

        // Register a middle recipe that itself invokes the leaf.
        let middleBody = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("call_leaf"),
            steps: [
                FleetRecipeStep.invokeRecipe(
                    id: FleetRecipeStepID.literal("call_leaf"),
                    recipe: FleetRecipeName.literal("recipe.fleet.calibrate.compass"),
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
                ),
            ]
        )
        let middle = emptyDescriptor(name: "recipe.fleet.calibrate.middle", body: middleBody)
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(middle))

        // Now try to register an outer recipe that calls the middle recipe.
        // Middle's body itself contains invokeRecipe, so this is a depth-2 call
        // and must be rejected at parse time.
        let outerBody = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("call_middle"),
            steps: [
                FleetRecipeStep.invokeRecipe(
                    id: FleetRecipeStepID.literal("call_middle"),
                    recipe: FleetRecipeName.literal("recipe.fleet.calibrate.middle"),
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
                ),
            ]
        )
        let outer = emptyDescriptor(name: "recipe.fleet.calibrate.outer", body: outerBody)

        let errors = FleetRecipeBodyParser.validate(
            outerBody,
            against: outer,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(errors.contains(where: {
            if case .invokedRecipeBodyExceedsDepthLimit = $0 { return true } else { return false }
        }), "Expected parse-time depth violation but got: \(errors)")

        // Confirm the catalogue refuses to register the outer descriptor.
        XCTAssertFalse(FleetRecipesCatalogue.shared.register(outer))
    }

    // MARK: Regex / budget / retry caps

    func test_predicateRegexInvalid_isRejected() {
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("solo"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("solo"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                    matchers: [
                        FleetRecipeStepMatcher(
                            when: .data(predicate: .stringMatches(regex: "[unterminated")),
                            then: .succeed
                        ),
                        FleetRecipeStepMatcher(when: .any, then: .fail(detail: nil)),
                    ]
                ),
            ]
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(errors.contains(where: {
            if case .predicateRegexInvalid = $0 { return true } else { return false }
        }))
    }

    func test_budget_exceedsCapAndNonPositive_areBothReported() {
        let oversizeBody = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("calibrate"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("calibrate"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
                ),
            ],
            overallBudgetSeconds: FleetRecipeBody.maximumOverallBudgetSeconds + 1
        )
        let oversizeErrors = FleetRecipeBodyParser.validate(
            oversizeBody,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(oversizeErrors.contains(where: {
            if case .overallBudgetExceedsCap = $0 { return true } else { return false }
        }))

        let zeroBody = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("calibrate"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("calibrate"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
                ),
            ],
            overallBudgetSeconds: 0
        )
        let zeroErrors = FleetRecipeBodyParser.validate(
            zeroBody,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(zeroErrors.contains(where: {
            if case .overallBudgetNotPositive = $0 { return true } else { return false }
        }))
    }

    func test_stepRetryPolicy_exceedingCapsWithoutRelax_isRejected() {
        let overcap = FleetRecipeRetryPolicy(
            maxAttempts: FleetRecipeRetryPolicy.maxAttemptsCap + 1,
            delaySeconds: 0.25,
            retryableErrorKinds: [.noSession],
            retryOnTimeout: false
        )
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("calibrate"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("calibrate"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                    retry: overcap,
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .succeed)]
                ),
            ]
        )
        let strict = emptyDescriptor(name: "recipe.fleet.calibrate.compass")
        let strictErrors = FleetRecipeBodyParser.validate(
            body,
            against: strict,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(strictErrors.contains(where: {
            if case .stepRetryPolicyExceedsCaps = $0 { return true } else { return false }
        }))

        let relaxed = FleetRecipeDescriptor(
            name: FleetRecipeName.literal("recipe.fleet.calibrate.compass"),
            humanLabel: "Compass",
            humanDescription: "Relaxed.",
            riskTier: .groundOnly,
            relaxRetryCaps: true,
            body: body
        )
        let relaxedErrors = FleetRecipeBodyParser.validate(
            body,
            against: relaxed,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertFalse(relaxedErrors.contains(where: {
            if case .stepRetryPolicyExceedsCaps = $0 { return true } else { return false }
        }), "relaxRetryCaps=true must skip step-level cap checks too.")
    }

    // MARK: Multi-error surface

    func test_multipleErrors_areAllReportedInOnePass() {
        let body = FleetRecipeBody(
            entryStepID: FleetRecipeStepID.literal("missingEntry"),
            steps: [
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("dup"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.totallymade.up"),
                    matchers: []
                ),
                FleetRecipeStep.invokeCommand(
                    id: FleetRecipeStepID.literal("dup"),
                    command: FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass"),
                    matchers: [FleetRecipeStepMatcher(when: .any, then: .branch(stepID: FleetRecipeStepID.literal("ghost")))]
                ),
            ],
            overallBudgetSeconds: 0
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: emptyDescriptor(name: "recipe.fleet.calibrate.compass"),
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        // Expect a fistful: entry-not-found, duplicate-id, no-matchers, command-not-registered,
        // branch-target-not-found, budget-not-positive. We assert ≥4 distinct kinds.
        let kindCount = Set(errors.map { String(describing: type(of: $0)) + "." + "\($0)".prefix(30) }).count
        XCTAssertGreaterThanOrEqual(errors.count, 4, "Parser must surface every problem in one pass, got: \(errors)")
        XCTAssertGreaterThanOrEqual(kindCount, 4)
    }

    // MARK: End-to-end JSON parse

    func test_parse_jsonHappyPath_returnsBody() {
        let descriptor = emptyDescriptor(name: "recipe.fleet.calibrate.compass")
        let json = #"""
        {
            "entryStepID": "calibrate",
            "overallBudgetSeconds": 60,
            "steps": [
                {
                    "kind": "invokeCommand",
                    "id": "calibrate",
                    "command": "command.fleet.vehicle.do.calibrate.compass",
                    "matchers": [
                        { "when": { "kind": "success" }, "then": { "kind": "succeed" } },
                        { "when": { "kind": "any" }, "then": { "kind": "fail" } }
                    ]
                }
            ]
        }
        """#
        switch FleetRecipeBodyParser.parse(
            jsonData: Data(json.utf8),
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        ) {
        case .success(let body):
            XCTAssertEqual(body.entryStepID.rawValue, "calibrate")
            XCTAssertEqual(body.steps.count, 1)
        case .failure(let bundle):
            XCTFail("Expected happy-path parse to succeed; got: \(bundle)")
        }
    }

    func test_parse_jsonDecodeFailure_isReportedAsDecodeFailed() {
        let descriptor = emptyDescriptor(name: "recipe.fleet.calibrate.compass")
        let json = #"""
        { "entryStepID": "calibrate", "steps": "not an array" }
        """#
        switch FleetRecipeBodyParser.parse(
            jsonData: Data(json.utf8),
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        ) {
        case .success:
            XCTFail("Expected decode failure")
        case .failure(let bundle):
            XCTAssertEqual(bundle.errors.count, 1)
            XCTAssertTrue(bundle.errors.contains(where: {
                if case .decodeFailed = $0 { return true } else { return false }
            }))
        }
    }

    // MARK: - Stage F plugin invoked-namespace claims

    func test_validate_pluginOwnedBody_rejectsFleetCommandWithoutInvokeClaim() {
        GuardianPluginBootstrap.ensureRegistered()
        let body = minimalValidBody()
        let descriptor = FleetRecipeDescriptor(
            name: FleetRecipeName.literal("recipe.plugin.theme.bodyclaims"),
            humanLabel: "t",
            humanDescription: "t",
            riskTier: .groundOnly,
            pluginID: .theme,
            body: body
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(
            errors.contains(where: {
                if case .invokedCommandOutsidePluginManifestClaims = $0 { return true }
                return false
            }),
            "Expected invoked-namespace violation; got: \(errors)"
        )
    }

    func test_validate_pluginOwnedBody_acceptsFleetCommandWhenInvokeClaimCovers() {
        GuardianPluginBootstrap.ensureRegistered()
        let restored = GuardianPluginBootstrap.builtInPaladinManifest()
        GuardianPluginRegistry.shared.ingestBuiltInRegistration(
            manifest: GuardianPluginManifest(
                pluginID: .paladin,
                displayName: "Paladin",
                shortDescription: "Mission Control assistant: execution handoff, prompts, and Paladin-authored log lines.",
                invokedCommandNamespaces: ["command.fleet.vehicle"]
            ),
            sidebarItems: []
        )
        defer {
            GuardianPluginRegistry.shared.ingestBuiltInRegistration(manifest: restored, sidebarItems: [])
        }

        let body = minimalValidBody()
        let descriptor = FleetRecipeDescriptor(
            name: FleetRecipeName.literal("recipe.plugin.paladin.bodyclaimsok"),
            humanLabel: "t",
            humanDescription: "t",
            riskTier: .groundOnly,
            pluginID: .paladin,
            body: body
        )
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertEqual(errors, [], "Got: \(errors)")
    }
}
