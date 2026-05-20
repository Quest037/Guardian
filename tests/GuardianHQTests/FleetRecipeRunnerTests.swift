import XCTest
@testable import GuardianCore

/// Stage B1 coverage for ``FleetRecipeRunner``: state-machine behaviour, retry
/// policy interaction, escalation handler vocabulary, cancellation (with declared
/// cleanup), recipe budget enforcement, per-vehicle conflict refusal, and audit
/// trace fidelity. All scenarios are exercised against a deterministic in-process
/// invoker stub — there is no MAVSDK / SITL dependency at this layer.
@MainActor
final class FleetRecipeRunnerTests: XCTestCase {

    // MARK: Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        FleetRecipesCatalogue.shared._testOnlyReset()
        FleetRecipesCatalogueBootstrap._testOnlyResetIdempotencyFlag()
        FleetRecipeRunner.shared._testOnlyResetActiveRuns()
    }

    override func tearDown() async throws {
        FleetRecipeRunner.shared._testOnlyResetActiveRuns()
        FleetRecipesCatalogue.shared._testOnlyReset()
        try await super.tearDown()
    }

    // MARK: - Invoker stub

    /// In-test stand-in for ``FleetCommandsCatalogue/invoke(...)``. Supports a
    /// per-command response queue (deterministic sequencing across attempts)
    /// and records every call so tests can assert dispatch shape.
    final class StubInvoker {
        struct Call: Equatable {
            let command: FleetCommandName
            let parameters: FleetCommandParameters
            let vehicleID: String
            let source: String
        }

        var queueByCommand: [FleetCommandName: [FleetCommandResponse]] = [:]
        var defaultResponse: FleetCommandResponse = .success()
        var calls: [Call] = []

        @MainActor
        func makeInvoker() -> FleetRecipeCommandInvoker {
            return { [weak self] command, parameters, vehicleID, source, _, _ in
                guard let self else {
                    return .error(.dispatchFailed, detail: "Stub released.", elapsed: 0)
                }
                self.calls.append(.init(command: command, parameters: parameters, vehicleID: vehicleID, source: source))
                if var queue = self.queueByCommand[command], !queue.isEmpty {
                    let head = queue.removeFirst()
                    self.queueByCommand[command] = queue
                    return head
                }
                return self.defaultResponse
            }
        }
    }

    // MARK: - Helpers

    private func registerCommand(
        _ rawName: String,
        parameters: [FleetCommandParameterDeclaration] = []
    ) -> FleetCommandName {
        let name = FleetCommandName.literal(rawName)
        let descriptor = FleetCommandDescriptor(
            name: name,
            humanLabel: rawName,
            humanDescription: "Stub command for \(rawName)",
            parameters: parameters,
            declaredResponseKinds: .standardDo,
            riskTier: .groundOnly
        )
        let didRegister = FleetCommandsCatalogue.shared.register(descriptor)
        XCTAssertTrue(didRegister, "Test setup expected command \(rawName) to register.")
        return name
    }

    private func registerRecipe(
        _ rawName: String,
        body: FleetRecipeBody,
        retry: FleetRecipeRetryPolicy = .disabled,
        cancelRecipe: FleetRecipeName? = nil,
        parameters: [FleetRecipeParameterDeclaration] = [],
        riskTier: FleetRecipeRiskTier = .groundOnly
    ) -> FleetRecipeName {
        let name = FleetRecipeName.literal(rawName)
        let descriptor = FleetRecipeDescriptor(
            name: name,
            humanLabel: rawName,
            humanDescription: "Stub recipe for \(rawName)",
            parameters: parameters,
            riskTier: riskTier,
            defaultRetryPolicy: retry,
            body: body,
            cancelRecipe: cancelRecipe
        )
        XCTAssertTrue(
            FleetRecipesCatalogue.shared.register(descriptor),
            "Test setup expected recipe \(rawName) to register."
        )
        return name
    }

    /// Convenience for an `.invokeCommand` step that maps a single matcher.
    private func commandStep(
        _ stepRaw: String,
        invokes command: FleetCommandName,
        parameters: FleetRecipeParameters = .empty,
        retry: FleetRecipeRetryPolicy? = nil,
        matchers: [FleetRecipeStepMatcher]
    ) -> FleetRecipeStep {
        .invokeCommand(
            id: .literal(stepRaw),
            command: command,
            parameters: parameters,
            retry: retry,
            matchers: matchers
        )
    }

    private func dummyFleetLink() -> FleetLinkService {
        FleetLinkService(userDefaults: UserDefaults(suiteName: "FleetRecipeRunnerTests-\(UUID().uuidString)")!)
    }

    private func runWithStub(
        recipe name: FleetRecipeName,
        parameters: FleetRecipeParameters = .empty,
        vehicleID: String = "TEST-VEHICLE",
        stub: StubInvoker,
        escalationHandler: FleetRecipeEscalationHandler? = nil
    ) async -> FleetRecipeOutcome {
        FleetRecipeRunner.shared.commandInvokerOverride = stub.makeInvoker()
        defer { FleetRecipeRunner.shared.commandInvokerOverride = nil }
        return await FleetRecipeRunner.shared.run(
            recipe: name,
            parameters: parameters,
            vehicleID: vehicleID,
            source: "runnerTests",
            fleetLink: dummyFleetLink(),
            escalationHandler: escalationHandler
        )
    }

    // MARK: - Happy path

    func test_happyPath_singleSuccessStep_completes() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("arm"),
            steps: [
                commandStep("arm", invokes: cmd, matchers: [
                    .init(when: .success(), then: .continueToNextStep)
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.arm", body: body)
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(outcome.trace.entries.count, 1)
        XCTAssertEqual(outcome.trace.entries.first?.stepID.rawValue, "arm")
        XCTAssertEqual(outcome.trace.entries.first?.attempt, 1)
        XCTAssertEqual(stub.calls.count, 1)
        XCTAssertEqual(stub.calls.first?.command, cmd)
    }

    func test_wizard_progress_map_cleared_when_run_completes() async {
        let vid = "WIZ-PROG-MAP-CLEAR"
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("one"),
            steps: [
                commandStep("one", invokes: cmd, matchers: [
                    .init(when: .success(), then: .succeed)
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.wizprog.clear", body: body)
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: recipe, vehicleID: vid, stub: stub)

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertNil(FleetRecipeRunner.shared.wizardProgressByVehicleID[vid])
    }

    func test_wizard_escalation_inline_publishes_snapshot_submit_advances() async {
        let vid = "WIZ-ESC-INLINE"
        let cal = registerCommand("command.fleet.vehicle.do.calibrate.compass")
        let confirm = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("calibrate"),
            steps: [
                commandStep("calibrate", invokes: cal, matchers: [
                    .init(when: .any, then: .escalate(
                        reason: .operatorActionRequired(kind: .rotateDrone),
                        allowedVerbs: [.acknowledge, .abort]
                    ))
                ]),
                commandStep("confirm", invokes: confirm, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.wizesc.inline", body: body)
        let stub = StubInvoker()
        let handler = FleetRecipeRunner.shared.vehicleInspectorWizardEscalationHandler(for: vid)

        let runTask = Task {
            await self.runWithStub(recipe: recipe, vehicleID: vid, stub: stub, escalationHandler: handler)
        }

        for _ in 0 ..< 500 {
            if FleetRecipeRunner.shared.wizardEscalationByVehicleID[vid] != nil { break }
            await Task.yield()
        }

        guard let snap = FleetRecipeRunner.shared.wizardEscalationByVehicleID[vid] else {
            XCTFail("Expected wizard escalation snapshot to publish")
            return
        }
        XCTAssertTrue(snap.headline.contains("Rotate"), "Headline: \(snap.headline)")
        XCTAssertEqual(Set(snap.allowedVerbs), Set([.acknowledge, .abort]))

        XCTAssertTrue(FleetRecipeRunner.shared.submitWizardEscalationVerb(vehicleID: vid, verb: .acknowledge))

        let outcome = await runTask.value
        XCTAssertTrue(outcome.isSuccess)
        XCTAssertNil(FleetRecipeRunner.shared.wizardEscalationByVehicleID[vid])
        XCTAssertEqual(stub.calls.map(\.command), [cal, confirm])
    }

    func test_wizard_escalation_cancel_unblocks_with_abort_when_allowed() async {
        let vid = "WIZ-ESC-CANCEL"
        let cmd = registerCommand("command.fleet.vehicle.do.calibrate.compass")
        let body = FleetRecipeBody(
            entryStepID: .literal("calibrate"),
            steps: [
                commandStep("calibrate", invokes: cmd, matchers: [
                    .init(when: .any, then: .escalate(
                        reason: .operatorActionRequired(kind: .rotateDrone),
                        allowedVerbs: [.acknowledge, .abort]
                    ))
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.wizesc.cancel", body: body)
        let stub = StubInvoker()
        let handler = FleetRecipeRunner.shared.vehicleInspectorWizardEscalationHandler(for: vid)

        let runTask = Task {
            await self.runWithStub(recipe: recipe, vehicleID: vid, stub: stub, escalationHandler: handler)
        }

        for _ in 0 ..< 500 {
            if FleetRecipeRunner.shared.wizardEscalationByVehicleID[vid] != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(FleetRecipeRunner.shared.wizardEscalationByVehicleID[vid])

        XCTAssertTrue(FleetRecipeRunner.shared.cancel(vehicleID: vid))

        let outcome = await runTask.value
        XCTAssertFalse(outcome.isSuccess)
        XCTAssertNil(FleetRecipeRunner.shared.wizardEscalationByVehicleID[vid])
        if case .failed(_, _, let detail, _) = outcome {
            XCTAssertTrue(detail?.contains("Operator aborted") == true, "Got: \(detail ?? "")")
        } else {
            XCTFail("Expected failed outcome; got \(outcome)")
        }
    }

    func test_cancel_runID_unknown_returns_false() {
        XCTAssertFalse(FleetRecipeRunner.shared.cancel(runID: FleetRecipeRunID(rawValue: UUID())))
    }

    func test_cancel_runID_matches_escalation_snapshot() async {
        let vid = "CANCEL-RUNID-ESC"
        let cmd = registerCommand("command.fleet.vehicle.do.calibrate.compass")
        let body = FleetRecipeBody(
            entryStepID: .literal("calibrate"),
            steps: [
                commandStep("calibrate", invokes: cmd, matchers: [
                    .init(when: .any, then: .escalate(
                        reason: .operatorActionRequired(kind: .rotateDrone),
                        allowedVerbs: [.acknowledge, .abort]
                    ))
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.wizesc.cancel.runid", body: body)
        let stub = StubInvoker()
        let handler = FleetRecipeRunner.shared.vehicleInspectorWizardEscalationHandler(for: vid)

        let runTask = Task {
            await self.runWithStub(recipe: recipe, vehicleID: vid, stub: stub, escalationHandler: handler)
        }

        var cancelled = false
        for _ in 0 ..< 500 {
            if let esc = FleetRecipeRunner.shared.wizardEscalationByVehicleID[vid] {
                XCTAssertTrue(FleetRecipeRunner.shared.cancel(runID: esc.runID))
                cancelled = true
                break
            }
            await Task.yield()
        }
        XCTAssertTrue(cancelled, "Expected escalation so cancel(runID:) can target the snapshot")

        let outcome = await runTask.value
        XCTAssertFalse(outcome.isSuccess)
        XCTAssertNil(FleetRecipeRunner.shared.wizardEscalationByVehicleID[vid])
    }

    func test_wizard_progress_runID_stable_during_nested_invokeRecipe() async {
        let vid = "WIZ-RUNID-NESTED"
        let arm = registerCommand("command.fleet.vehicle.do.arm")
        let takeoff = registerCommand("command.fleet.vehicle.do.takeoff")
        let childBody = FleetRecipeBody(
            entryStepID: .literal("innerA"),
            steps: [
                commandStep("innerA", invokes: arm, matchers: [
                    .init(when: .success(), then: .continueToNextStep)
                ]),
                commandStep("innerB", invokes: takeoff, matchers: [
                    .init(when: .success(), then: .succeed)
                ]),
            ]
        )
        let child = registerRecipe("recipe.fleet.test.child.runidsnap", body: childBody)

        let parentBody = FleetRecipeBody(
            entryStepID: .literal("invokeChild"),
            steps: [
                .invokeRecipe(
                    id: .literal("invokeChild"),
                    recipe: child,
                    parameters: .empty,
                    matchers: [
                        .init(when: .success(), then: .succeed),
                        .init(when: .any, then: .fail(detail: "child should have succeeded"))
                    ]
                )
            ]
        )
        let parent = registerRecipe("recipe.fleet.test.parent.runidsnap", body: parentBody)
        let stub = StubInvoker()

        let runTask = Task {
            await self.runWithStub(recipe: parent, vehicleID: vid, stub: stub)
        }

        var surfaceRunID: FleetRecipeRunID?
        var sawNestedActivity = false
        for _ in 0 ..< 800 {
            if let snap = FleetRecipeRunner.shared.wizardProgressByVehicleID[vid] {
                if surfaceRunID == nil {
                    surfaceRunID = snap.runID
                } else {
                    XCTAssertEqual(
                        snap.runID,
                        surfaceRunID,
                        "Wizard progress must keep the top-level run id during nested invokeRecipe"
                    )
                }
                if snap.activityLine.contains("Nested procedure") {
                    sawNestedActivity = true
                }
            }
            await Task.yield()
        }

        let outcome = await runTask.value
        XCTAssertTrue(outcome.isSuccess, outcome.loggable)
        XCTAssertNotNil(surfaceRunID)
        XCTAssertTrue(sawNestedActivity, "Expected nested invokeRecipe to publish a nested activity line")
    }

    func test_happyPath_multipleStepsChainViaContinue() async {
        let arm = registerCommand("command.fleet.vehicle.do.arm")
        let takeoff = registerCommand("command.fleet.vehicle.do.takeoff")
        let body = FleetRecipeBody(
            entryStepID: .literal("arm"),
            steps: [
                commandStep("arm", invokes: arm, matchers: [
                    .init(when: .success(), then: .continueToNextStep)
                ]),
                commandStep("takeoff", invokes: takeoff, matchers: [
                    .init(when: .success(), then: .continueToNextStep)
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.armthentakeoff", body: body)
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(stub.calls.map(\.command), [arm, takeoff])
        XCTAssertEqual(outcome.trace.entries.count, 2)
    }

    func test_commandStep_resolvesCallerSuppliedParameterReferences() async {
        let command = registerCommand(
            "command.fleet.vehicle.do.calibrate.compass.declination",
            parameters: [
                FleetCommandParameterDeclaration(name: "degrees", type: .double, required: true),
            ]
        )
        let body = FleetRecipeBody(
            entryStepID: .literal("write"),
            steps: [
                commandStep(
                    "write",
                    invokes: command,
                    parameters: FleetRecipeParameters(values: [
                        "degrees": .reference(name: "degrees"),
                    ]),
                    matchers: [
                        .init(when: .success(), then: .succeed),
                        .init(when: .any, then: .fail(detail: nil)),
                    ]
                )
            ]
        )
        let recipe = registerRecipe(
            "recipe.fleet.test.paramreference",
            body: body,
            parameters: [
                FleetRecipeParameterDeclaration(name: "degrees", type: .double, required: true),
            ]
        )
        let stub = StubInvoker()

        let outcome = await runWithStub(
            recipe: recipe,
            parameters: FleetRecipeParameters(values: ["degrees": .double(13.25)]),
            stub: stub
        )

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(stub.calls.count, 1)
        XCTAssertEqual(stub.calls.first?.parameters.double(named: "degrees"), 13.25)
    }

    func test_childRecipeStep_resolvesCallerSuppliedParameterReferences() async {
        let command = registerCommand(
            "command.fleet.vehicle.do.calibrate.battery.capacity",
            parameters: [
                FleetCommandParameterDeclaration(name: "mAh", type: .integer, required: true),
            ]
        )
        let childBody = FleetRecipeBody(
            entryStepID: .literal("write"),
            steps: [
                commandStep(
                    "write",
                    invokes: command,
                    parameters: FleetRecipeParameters(values: [
                        "mAh": .reference(name: "mAh"),
                    ]),
                    matchers: [.init(when: .success(), then: .succeed)]
                )
            ]
        )
        let child = registerRecipe(
            "recipe.fleet.test.childcapacity",
            body: childBody,
            parameters: [
                FleetRecipeParameterDeclaration(name: "mAh", type: .integer, required: true),
            ]
        )
        let parentBody = FleetRecipeBody(
            entryStepID: .literal("child"),
            steps: [
                .invokeRecipe(
                    id: .literal("child"),
                    recipe: child,
                    parameters: FleetRecipeParameters(values: [
                        "mAh": .reference(name: "capacity"),
                    ]),
                    matchers: [.init(when: .success(), then: .succeed)]
                )
            ]
        )
        let parent = registerRecipe(
            "recipe.fleet.test.parentcapacity",
            body: parentBody,
            parameters: [
                FleetRecipeParameterDeclaration(name: "capacity", type: .integer, required: true),
            ]
        )
        let stub = StubInvoker()

        let outcome = await runWithStub(
            recipe: parent,
            parameters: FleetRecipeParameters(values: ["capacity": .integer(5000)]),
            stub: stub
        )

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(stub.calls.count, 1)
        XCTAssertEqual(stub.calls.first?.parameters.integer(named: "mAh"), 5000)
    }

    // MARK: - Branch / succeed / fail

    func test_branch_jumpsToTargetStep() async {
        let probe = registerCommand("command.fleet.vehicle.get.telemetry.battery")
        let recover = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("probe"),
            steps: [
                commandStep("probe", invokes: probe, matchers: [
                    .init(when: .error(kind: .noSession), then: .branch(stepID: .literal("recover"))),
                    .init(when: .any, then: .continueToNextStep)
                ]),
                commandStep("intermediate", invokes: probe, matchers: [
                    .init(when: .any, then: .fail(detail: "should have branched past me"))
                ]),
                commandStep("recover", invokes: recover, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.branch", body: body)
        let stub = StubInvoker()
        stub.queueByCommand[probe] = [.error(.noSession, detail: "Link down.")]

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        XCTAssertTrue(outcome.isSuccess, "Branch should skip intermediate and reach recover. got: \(outcome.loggable)")
        XCTAssertEqual(stub.calls.map(\.command), [probe, recover])
    }

    func test_succeed_endsRecipeImmediately() async {
        let arm = registerCommand("command.fleet.vehicle.do.arm")
        let after = registerCommand("command.fleet.vehicle.do.takeoff")
        let body = FleetRecipeBody(
            entryStepID: .literal("arm"),
            steps: [
                commandStep("arm", invokes: arm, matchers: [
                    .init(when: .success(), then: .succeed)
                ]),
                commandStep("never", invokes: after, matchers: [
                    .init(when: .any, then: .fail(detail: "should not run"))
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.succeedearly", body: body)
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(stub.calls.map(\.command), [arm])
    }

    func test_fail_attributesFailingStep() async {
        let arm = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("arm"),
            steps: [
                commandStep("arm", invokes: arm, matchers: [
                    .init(when: .any, then: .fail(detail: "explicit failure"))
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.failexplicit", body: body)
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        if case .failed(let path, _, let detail, _) = outcome {
            XCTAssertEqual(path.map(\.rawValue), ["arm"])
            XCTAssertEqual(detail, "explicit failure")
        } else {
            XCTFail("Expected failed outcome; got \(outcome)")
        }
    }

    func test_fail_auditTrace_stepMatchesFailingCommandPath() async {
        let arm = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("arm"),
            steps: [
                commandStep("arm", invokes: arm, matchers: [
                    .init(when: .any, then: .fail(detail: "explicit failure"))
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.failauditpath", body: body)
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        guard case .failed(let path, let lastResponse, _, let trace) = outcome else {
            XCTFail("Expected failed outcome; got \(outcome)")
            return
        }
        XCTAssertEqual(path.map(\.rawValue), ["arm"])
        XCTAssertEqual(trace.entries.count, 1)
        XCTAssertEqual(trace.entries.first?.stepID.rawValue, path.first?.rawValue)
        XCTAssertNotNil(lastResponse)
        XCTAssertNotNil(trace.entries.first?.controlOutcome)
    }

    func test_noMatcherFires_isImplicitFail() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("arm"),
            steps: [
                commandStep("arm", invokes: cmd, matchers: [
                    .init(when: .error(kind: .noSession), then: .continueToNextStep)
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.nomatch", body: body)
        let stub = StubInvoker()
        stub.queueByCommand[cmd] = [.success()]

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        if case .failed(let path, _, let detail, _) = outcome {
            XCTAssertEqual(path.map(\.rawValue), ["arm"])
            XCTAssertTrue(detail?.contains("No matcher fired") == true, "Expected 'No matcher fired' detail; got \(detail ?? "")")
        } else {
            XCTFail("Expected failed outcome; got \(outcome)")
        }
    }

    // MARK: - Retry

    func test_retryPolicy_retriesOnRetryableErrorAndSucceeds() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("arm"),
            steps: [
                commandStep("arm", invokes: cmd, retry: .catalogueDefault, matchers: [
                    .init(when: .success(), then: .succeed),
                    .init(when: .any, then: .fail(detail: "transport failed after retries"))
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.retrysucceeds", body: body)
        let stub = StubInvoker()
        stub.queueByCommand[cmd] = [
            .error(.noSession, detail: "down"),
            .success()
        ]

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(stub.calls.count, 2)
        XCTAssertEqual(outcome.trace.entries.first?.attempt, 2, "Retry consumes attempts inside one dispatch.")
    }

    func test_retryPolicy_exhaustsThenFallsThroughToNextMatcher() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let stingy = FleetRecipeRetryPolicy(
            maxAttempts: 1,
            delaySeconds: 0,
            retryableErrorKinds: [.noSession],
            retryOnTimeout: false
        )
        let body = FleetRecipeBody(
            entryStepID: .literal("arm"),
            steps: [
                commandStep("arm", invokes: cmd, retry: stingy, matchers: [
                    .init(when: .success(), then: .succeed),
                    .init(when: .error(kind: .noSession), then: .fail(detail: "transport persistently down"))
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.retryexhausted", body: body)
        let stub = StubInvoker()
        stub.queueByCommand[cmd] = [
            .error(.noSession, detail: "down 1"),
            .error(.noSession, detail: "down 2")
        ]

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        if case .failed(_, _, let detail, _) = outcome {
            XCTAssertEqual(detail, "transport persistently down")
        } else {
            XCTFail("Expected failed outcome; got \(outcome)")
        }
        XCTAssertEqual(stub.calls.count, 2, "Initial attempt + one retry.")
    }

    // MARK: - Escalation

    func test_escalate_acknowledgeAdvancesToNextStep() async {
        let cal = registerCommand("command.fleet.vehicle.do.calibrate.compass")
        let confirm = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("calibrate"),
            steps: [
                commandStep("calibrate", invokes: cal, matchers: [
                    .init(when: .any, then: .escalate(
                        reason: .operatorActionRequired(kind: .rotateDrone),
                        allowedVerbs: [.acknowledge, .abort]
                    ))
                ]),
                commandStep("confirm", invokes: confirm, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.escalateack", body: body)
        let stub = StubInvoker()
        let observed = ObservedEscalationEvents()

        let outcome = await runWithStub(recipe: recipe, stub: stub) { event in
            observed.events.append(event)
            return .acknowledge
        }

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(stub.calls.map(\.command), [cal, confirm])
        XCTAssertEqual(observed.events.count, 1)
        XCTAssertEqual(observed.events.first?.stepID.rawValue, "calibrate")
    }

    func test_escalate_retryReinvokes() async {
        let cal = registerCommand("command.fleet.vehicle.do.calibrate.compass")
        let body = FleetRecipeBody(
            entryStepID: .literal("calibrate"),
            steps: [
                commandStep("calibrate", invokes: cal, matchers: [
                    .init(when: .success(), then: .succeed),
                    .init(when: .any, then: .escalate(
                        reason: .operatorActionRequired(kind: .rotateDrone),
                        allowedVerbs: [.retry, .abort]
                    ))
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.escalateretry", body: body)
        let stub = StubInvoker()
        stub.queueByCommand[cal] = [
            .error(.calibrationDidNotConverge, detail: "first try"),
            .success()
        ]

        let outcome = await runWithStub(recipe: recipe, stub: stub) { _ in .retry }

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(stub.calls.count, 2)
    }

    func test_escalate_abortFails() async {
        let cmd = registerCommand("command.fleet.vehicle.do.calibrate.compass")
        let body = FleetRecipeBody(
            entryStepID: .literal("calibrate"),
            steps: [
                commandStep("calibrate", invokes: cmd, matchers: [
                    .init(when: .any, then: .escalate(
                        reason: .unrecoverableFailure(kind: .calibrationDidNotConverge),
                        allowedVerbs: [.abort]
                    ))
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.escalateabort", body: body)
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: recipe, stub: stub) { _ in .abort }

        if case .failed(let path, _, let detail, _) = outcome {
            XCTAssertEqual(path.map(\.rawValue), ["calibrate"])
            XCTAssertTrue(detail?.contains("Operator aborted") == true, "Got: \(detail ?? "")")
        } else {
            XCTFail("Expected failed outcome; got \(outcome)")
        }
    }

    func test_escalate_disallowedVerbFails() async {
        let cmd = registerCommand("command.fleet.vehicle.do.calibrate.compass")
        let body = FleetRecipeBody(
            entryStepID: .literal("calibrate"),
            steps: [
                commandStep("calibrate", invokes: cmd, matchers: [
                    .init(when: .any, then: .escalate(
                        reason: .operatorActionRequired(kind: .rotateDrone),
                        allowedVerbs: [.acknowledge]
                    ))
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.escalatedisallowed", body: body)
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: recipe, stub: stub) { _ in .retry }

        if case .failed(_, _, let detail, _) = outcome {
            XCTAssertTrue(detail?.contains("disallowed verb") == true, "Got: \(detail ?? "")")
        } else {
            XCTFail("Expected failed outcome; got \(outcome)")
        }
    }

    func test_escalate_defaultHandlerAborts() async {
        let cmd = registerCommand("command.fleet.vehicle.do.calibrate.compass")
        let body = FleetRecipeBody(
            entryStepID: .literal("calibrate"),
            steps: [
                commandStep("calibrate", invokes: cmd, matchers: [
                    .init(when: .any, then: .escalate(
                        reason: .operatorActionRequired(kind: .rotateDrone),
                        allowedVerbs: [.acknowledge, .abort]
                    ))
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.escalatedefault", body: body)
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        XCTAssertFalse(outcome.isSuccess, "Default handler aborts; recipe should fail.")
    }

    // MARK: - Budget

    func test_overallBudget_exceededFails() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("loop"),
            steps: [
                commandStep("loop", invokes: cmd, matchers: [
                    .init(when: .any, then: .retry)
                ])
            ],
            overallBudgetSeconds: 0.2
        )
        let recipe = registerRecipe("recipe.fleet.test.budgetexceeded", body: body)

        // Inject a slow stub so wall-clock time accumulates. Without a per-dispatch
        // delay, the runner would tight-loop on `.retry` faster than the budget
        // can elapse on a fast CI machine.
        FleetRecipeRunner.shared.commandInvokerOverride = { _, _, _, _, _, _ in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
            return .success()
        }
        defer { FleetRecipeRunner.shared.commandInvokerOverride = nil }

        let outcome = await FleetRecipeRunner.shared.run(
            recipe: recipe,
            vehicleID: "TEST-VEHICLE",
            source: "runnerTests",
            fleetLink: dummyFleetLink()
        )

        if case .failed(_, _, let detail, _) = outcome {
            XCTAssertTrue(detail?.contains("budget exceeded") == true, "Got: \(detail ?? "")")
        } else {
            XCTFail("Expected failed outcome; got \(outcome)")
        }
    }

    // MARK: - Cancellation

    func test_cancel_betweenSteps_failsWithCancelledDetail() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("first"),
            steps: [
                commandStep("first", invokes: cmd, matchers: [
                    .init(when: .any, then: .continueToNextStep)
                ]),
                commandStep("second", invokes: cmd, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.cancelbetween", body: body)
        let stub = StubInvoker()
        let vehicleID = "TEST-VEHICLE"

        FleetRecipeRunner.shared.commandInvokerOverride = { command, parameters, vid, source, _, _ in
            stub.calls.append(.init(command: command, parameters: parameters, vehicleID: vid, source: source))
            FleetRecipeRunner.shared.cancel(vehicleID: vid)
            return .success()
        }
        defer { FleetRecipeRunner.shared.commandInvokerOverride = nil }

        let outcome = await FleetRecipeRunner.shared.run(
            recipe: recipe,
            vehicleID: vehicleID,
            source: "runnerTests",
            fleetLink: dummyFleetLink()
        )

        if case .failed(_, _, let detail, _) = outcome {
            XCTAssertEqual(detail, "cancelled")
        } else {
            XCTFail("Expected failed/cancelled outcome; got \(outcome)")
        }
        XCTAssertEqual(stub.calls.count, 1, "Second step should not have dispatched.")
    }

    func test_cancel_runsDeclaredCleanupRecipe() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let cleanupCmd = registerCommand("command.fleet.vehicle.do.disarm")

        let cleanupBody = FleetRecipeBody(
            entryStepID: .literal("cleanup"),
            steps: [
                commandStep("cleanup", invokes: cleanupCmd, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
        let cleanupName = registerRecipe("recipe.fleet.test.cancelcleanup", body: cleanupBody)

        let body = FleetRecipeBody(
            entryStepID: .literal("first"),
            steps: [
                commandStep("first", invokes: cmd, matchers: [
                    .init(when: .any, then: .continueToNextStep)
                ]),
                commandStep("second", invokes: cmd, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
        let recipe = registerRecipe(
            "recipe.fleet.test.cancelwithcleanup",
            body: body,
            cancelRecipe: cleanupName
        )

        let stub = StubInvoker()
        let vehicleID = "TEST-VEHICLE"

        FleetRecipeRunner.shared.commandInvokerOverride = { command, parameters, vid, source, _, _ in
            stub.calls.append(.init(command: command, parameters: parameters, vehicleID: vid, source: source))
            if command == cmd {
                FleetRecipeRunner.shared.cancel(vehicleID: vid)
            }
            return .success()
        }
        defer { FleetRecipeRunner.shared.commandInvokerOverride = nil }

        let outcome = await FleetRecipeRunner.shared.run(
            recipe: recipe,
            vehicleID: vehicleID,
            source: "runnerTests",
            fleetLink: dummyFleetLink()
        )

        if case .failed(_, _, let detail, _) = outcome {
            XCTAssertEqual(detail, "cancelled")
        } else {
            XCTFail("Expected failed outcome; got \(outcome)")
        }
        XCTAssertEqual(stub.calls.map(\.command), [cmd, cleanupCmd])
    }

    // MARK: - Concurrency / per-vehicle gate

    func test_secondRunOnSameVehicle_refused() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("first"),
            steps: [
                commandStep("first", invokes: cmd, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
        let recipe = registerRecipe("recipe.fleet.test.concurrencya", body: body)

        let started = expectation(description: "first run reached invoker")
        let release = expectation(description: "first run allowed to complete")
        FleetRecipeRunner.shared.commandInvokerOverride = { _, _, _, _, _, _ in
            started.fulfill()
            await self.fulfillment(of: [release], timeout: 5)
            return .success()
        }
        defer { FleetRecipeRunner.shared.commandInvokerOverride = nil }

        // Hoist link so `async let` does not capture MainActor `self` via `dummyFleetLink()`.
        let fleetLink = dummyFleetLink()
        async let firstOutcome = FleetRecipeRunner.shared.run(
            recipe: recipe,
            vehicleID: "TEST-VEHICLE",
            source: "first",
            fleetLink: fleetLink
        )

        await fulfillment(of: [started], timeout: 2)

        let secondOutcome = await FleetRecipeRunner.shared.run(
            recipe: recipe,
            vehicleID: "TEST-VEHICLE",
            source: "second",
            fleetLink: fleetLink
        )

        if case .failed(_, _, let detail, _) = secondOutcome {
            XCTAssertTrue(
                detail?.contains("already executing") == true,
                "Expected per-vehicle conflict refusal; got \(detail ?? "")"
            )
        } else {
            XCTFail("Expected failed outcome on conflict; got \(secondOutcome)")
        }

        release.fulfill()
        let resolvedFirst = await firstOutcome
        XCTAssertTrue(resolvedFirst.isSuccess)
    }

    // MARK: - invokeRecipe composition

    func test_invokeRecipe_childSuccessBubblesUpAsSuccess() async {
        let childCmd = registerCommand("command.fleet.vehicle.do.arm")
        let childBody = FleetRecipeBody(
            entryStepID: .literal("inner"),
            steps: [
                commandStep("inner", invokes: childCmd, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
        let child = registerRecipe("recipe.fleet.test.child", body: childBody)

        let parentBody = FleetRecipeBody(
            entryStepID: .literal("invokeChild"),
            steps: [
                .invokeRecipe(
                    id: .literal("invokeChild"),
                    recipe: child,
                    parameters: .empty,
                    matchers: [
                        .init(when: .success(), then: .succeed),
                        .init(when: .any, then: .fail(detail: "child should have succeeded"))
                    ]
                )
            ]
        )
        let parent = registerRecipe("recipe.fleet.test.parent", body: parentBody)
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: parent, stub: stub)

        XCTAssertTrue(outcome.isSuccess, "Got: \(outcome.loggable)")
        XCTAssertEqual(stub.calls.map(\.command), [childCmd])
    }

    func test_invokeRecipe_childFailureSurfacesSyntheticError() async {
        let childCmd = registerCommand("command.fleet.vehicle.do.arm")
        let childBody = FleetRecipeBody(
            entryStepID: .literal("inner"),
            steps: [
                commandStep("inner", invokes: childCmd, matchers: [
                    .init(when: .any, then: .fail(detail: "child explicit fail"))
                ])
            ]
        )
        let child = registerRecipe("recipe.fleet.test.childfails", body: childBody)

        let parentBody = FleetRecipeBody(
            entryStepID: .literal("invokeChild"),
            steps: [
                .invokeRecipe(
                    id: .literal("invokeChild"),
                    recipe: child,
                    parameters: .empty,
                    matchers: [
                        .init(when: .error(kind: .unknown), then: .succeed),
                        .init(when: .any, then: .fail(detail: "parent did not see error.unknown"))
                    ]
                )
            ]
        )
        let parent = registerRecipe("recipe.fleet.test.parentrecovers", body: parentBody)
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: parent, stub: stub)

        XCTAssertTrue(outcome.isSuccess, "Parent should branch on synthetic error.unknown from child fail.")
    }

    // MARK: - Entry refusals

    func test_unknownRecipe_fails() async {
        let stub = StubInvoker()
        let outcome = await runWithStub(
            recipe: FleetRecipeName.literal("recipe.fleet.test.unregistered"),
            stub: stub
        )
        if case .failed(_, _, let detail, _) = outcome {
            XCTAssertTrue(detail?.contains("No descriptor registered") == true)
        } else {
            XCTFail("Expected failed; got \(outcome)")
        }
    }

    func test_bodylessRecipe_fails() async {
        let name = FleetRecipeName.literal("recipe.fleet.test.nobody")
        let descriptor = FleetRecipeDescriptor(
            name: name,
            humanLabel: "no body",
            humanDescription: "intentionally missing",
            riskTier: .groundOnly
        )
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(descriptor))
        let stub = StubInvoker()

        let outcome = await runWithStub(recipe: name, stub: stub)

        if case .failed(_, _, let detail, _) = outcome {
            XCTAssertTrue(detail?.contains("no body") == true, "Got: \(detail ?? "")")
        } else {
            XCTFail("Expected failed; got \(outcome)")
        }
    }

    func test_parameterValidation_failsBeforeDispatch() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let body = FleetRecipeBody(
            entryStepID: .literal("first"),
            steps: [
                commandStep("first", invokes: cmd, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
        let name = FleetRecipeName.literal("recipe.fleet.test.requiresmeters")
        let descriptor = FleetRecipeDescriptor(
            name: name,
            humanLabel: "requires meters",
            humanDescription: "requires meters parameter",
            parameters: [
                .init(name: "meters", type: .double, required: true)
            ],
            riskTier: .groundOnly,
            body: body
        )
        XCTAssertTrue(FleetRecipesCatalogue.shared.register(descriptor))

        let stub = StubInvoker()
        let outcome = await runWithStub(recipe: name, parameters: .empty, stub: stub)

        if case .failed(_, _, let detail, _) = outcome {
            XCTAssertTrue(detail?.contains("missing required parameter 'meters'") == true, "Got: \(detail ?? "")")
        } else {
            XCTFail("Expected failed; got \(outcome)")
        }
        XCTAssertEqual(stub.calls.count, 0, "No dispatch should occur when validation fails.")
    }

    // MARK: - Live-mission gate

    /// Shared body for the gate tests: a single arm step that always succeeds.
    private func gateTestBody(invokes cmd: FleetCommandName) -> FleetRecipeBody {
        FleetRecipeBody(
            entryStepID: .literal("first"),
            steps: [
                commandStep("first", invokes: cmd, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
    }

    func test_liveMissionGate_nilGate_doesNotBlock() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let recipe = registerRecipe(
            "recipe.fleet.test.gatenil",
            body: gateTestBody(invokes: cmd),
            riskTier: .groundOnly
        )
        let stub = StubInvoker()
        FleetRecipeRunner.shared.liveMissionGate = nil

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        XCTAssertTrue(outcome.isSuccess, "nil gate disables enforcement; got: \(outcome.loggable)")
    }

    func test_liveMissionGate_gateClear_runsNormally() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let recipe = registerRecipe(
            "recipe.fleet.test.gateclear",
            body: gateTestBody(invokes: cmd),
            riskTier: .groundOnly
        )
        let stub = StubInvoker()
        FleetRecipeRunner.shared.liveMissionGate = { _ in false }

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        XCTAssertTrue(outcome.isSuccess)
    }

    func test_liveMissionGate_groundOnly_refusesDuringLiveMission() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let recipe = registerRecipe(
            "recipe.fleet.test.gategroundonly",
            body: gateTestBody(invokes: cmd),
            riskTier: .groundOnly
        )
        let stub = StubInvoker()
        FleetRecipeRunner.shared.liveMissionGate = { _ in true }

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        if case .failed(_, _, let detail, _) = outcome {
            XCTAssertTrue(detail?.contains("groundOnly") == true, "Got: \(detail ?? "")")
            XCTAssertTrue(detail?.contains("live mission") == true, "Got: \(detail ?? "")")
        } else {
            XCTFail("Expected failed outcome; got \(outcome)")
        }
        XCTAssertEqual(stub.calls.count, 0, "Gate refusal must short-circuit before dispatch.")
    }

    func test_liveMissionGate_confirmInLiveMission_refusesWithoutFlag() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let recipe = registerRecipe(
            "recipe.fleet.test.gateconfirm",
            body: gateTestBody(invokes: cmd),
            riskTier: .confirmInLiveMission
        )
        let stub = StubInvoker()
        FleetRecipeRunner.shared.liveMissionGate = { _ in true }

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        if case .failed(_, _, let detail, _) = outcome {
            XCTAssertTrue(detail?.contains("operator confirmation") == true, "Got: \(detail ?? "")")
        } else {
            XCTFail("Expected failed outcome; got \(outcome)")
        }
        XCTAssertEqual(stub.calls.count, 0)
    }

    func test_liveMissionGate_safeInLiveMission_runsRegardless() async {
        let cmd = registerCommand("command.fleet.vehicle.get.telemetry.battery")
        let recipe = registerRecipe(
            "recipe.fleet.test.gatesafe",
            body: gateTestBody(invokes: cmd),
            riskTier: .safeInLiveMission
        )
        let stub = StubInvoker()
        FleetRecipeRunner.shared.liveMissionGate = { _ in true }

        let outcome = await runWithStub(recipe: recipe, stub: stub)

        XCTAssertTrue(outcome.isSuccess, "safeInLiveMission ignores the gate; got: \(outcome.loggable)")
    }

    func test_liveMissionGate_allowDuringLiveMissionOverrides() async {
        let cmd = registerCommand("command.fleet.vehicle.do.arm")
        let recipe = registerRecipe(
            "recipe.fleet.test.gateoverride",
            body: gateTestBody(invokes: cmd),
            riskTier: .groundOnly
        )
        let stub = StubInvoker()
        FleetRecipeRunner.shared.liveMissionGate = { _ in true }
        FleetRecipeRunner.shared.commandInvokerOverride = stub.makeInvoker()
        defer { FleetRecipeRunner.shared.commandInvokerOverride = nil }

        let outcome = await FleetRecipeRunner.shared.run(
            recipe: recipe,
            vehicleID: "TEST-VEHICLE",
            source: "runnerTests",
            fleetLink: dummyFleetLink(),
            allowDuringLiveMission: true
        )

        XCTAssertTrue(outcome.isSuccess, "allowDuringLiveMission=true must bypass the gate; got: \(outcome.loggable)")
        XCTAssertEqual(stub.calls.count, 1)
    }

    func test_liveMissionGate_appliesOnlyToTopLevel_notChildRecipes() async {
        // Inner recipe is `groundOnly`; parent is `safeInLiveMission`. Gate
        // returns true. The locked decision says the parent's tier is
        // authoritative — the child's tier should NOT cause a re-refusal mid-run.
        let childCmd = registerCommand("command.fleet.vehicle.do.arm")
        let childBody = FleetRecipeBody(
            entryStepID: .literal("inner"),
            steps: [
                commandStep("inner", invokes: childCmd, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
        let child = registerRecipe(
            "recipe.fleet.test.gatechild",
            body: childBody,
            riskTier: .groundOnly
        )

        let parentBody = FleetRecipeBody(
            entryStepID: .literal("call"),
            steps: [
                .invokeRecipe(
                    id: .literal("call"),
                    recipe: child,
                    parameters: .empty,
                    matchers: [
                        .init(when: .success(), then: .succeed),
                        .init(when: .any, then: .fail(detail: "child should have succeeded"))
                    ]
                )
            ]
        )
        let parent = registerRecipe(
            "recipe.fleet.test.gateparent",
            body: parentBody,
            riskTier: .safeInLiveMission
        )
        let stub = StubInvoker()
        FleetRecipeRunner.shared.liveMissionGate = { _ in true }

        let outcome = await runWithStub(recipe: parent, stub: stub)

        XCTAssertTrue(outcome.isSuccess, "Gate must not re-check at child boundary; got: \(outcome.loggable)")
        XCTAssertEqual(stub.calls.map { $0.command }, [childCmd])
    }

    // MARK: - Vehicle Inspector chrome helpers

    func test_activeTopLevelRecipeName_nilWhenIdle() {
        XCTAssertNil(FleetRecipeRunner.shared.activeTopLevelRecipeName(forVehicleID: "no-active-run"))
    }

    func test_activeTopLevelRecipeName_reportsOuterRecipeDuringNestedChildDispatch() async {
        let vehicleID = "TEST-VEHICLE"
        let childCmd = registerCommand("command.fleet.vehicle.do.arm")
        let childBody = FleetRecipeBody(
            entryStepID: .literal("inner"),
            steps: [
                commandStep("inner", invokes: childCmd, matchers: [
                    .init(when: .any, then: .succeed)
                ])
            ]
        )
        let child = registerRecipe("recipe.fleet.test.activenamechild", body: childBody)

        let parentBody = FleetRecipeBody(
            entryStepID: .literal("invokeChild"),
            steps: [
                .invokeRecipe(
                    id: .literal("invokeChild"),
                    recipe: child,
                    parameters: .empty,
                    matchers: [
                        .init(when: .success(), then: .succeed),
                        .init(when: .any, then: .fail(detail: "child should have succeeded"))
                    ]
                )
            ]
        )
        let parent = registerRecipe("recipe.fleet.test.activenameparent", body: parentBody)
        let stub = StubInvoker()
        let baseInvoker = stub.makeInvoker()
        var observedDuringChild: [FleetRecipeName?] = []
        FleetRecipeRunner.shared.commandInvokerOverride = { command, parameters, vehicleID, source, timeout, invokingPluginID in
            if command == childCmd {
                observedDuringChild.append(
                    FleetRecipeRunner.shared.activeTopLevelRecipeName(forVehicleID: vehicleID)
                )
            }
            return await baseInvoker(command, parameters, vehicleID, source, timeout, invokingPluginID)
        }
        defer { FleetRecipeRunner.shared.commandInvokerOverride = nil }

        let outcome = await FleetRecipeRunner.shared.run(
            recipe: parent,
            parameters: .empty,
            vehicleID: vehicleID,
            source: "runnerTests",
            fleetLink: dummyFleetLink(),
            escalationHandler: nil
        )

        XCTAssertTrue(outcome.isSuccess, "Got: \(outcome.loggable)")
        XCTAssertEqual(observedDuringChild, [parent])
        XCTAssertEqual(stub.calls.map(\.command), [childCmd])
    }
}

// MARK: - Test-local helpers

/// Reference-typed observation box so the escalation closure (`@MainActor`) can
/// record events without fighting Swift's value-type capture rules.
@MainActor
private final class ObservedEscalationEvents {
    var events: [FleetRecipeEscalationEvent] = []
}
