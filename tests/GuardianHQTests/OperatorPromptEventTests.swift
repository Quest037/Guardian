import XCTest
@testable import GuardianHQ

/// Stage D item 2 coverage for the operator-prompt event type definitions:
/// shape (init defaults), the closed verb / custom-options layering, the
/// remember-choice gating, the timeout window, and the recipe-escalation
/// construction helper. The router / center / cache work that consumes this
/// type lands in subsequent Stage D items and is covered separately.
final class OperatorPromptEventTests: XCTestCase {

    // MARK: - Construction defaults

    func test_init_expiresAtIs5MinutesAfterCreatedAtByDefault() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let event = OperatorPromptEvent(
            origin: .freeform(source: "test.basic"),
            severity: .info,
            title: "Hello",
            body: "World",
            allowedVerbs: [.acknowledge],
            createdAt: now
        )
        XCTAssertEqual(event.expiresAt.timeIntervalSince(now), 5 * 60, accuracy: 0.001)
    }

    func test_init_customTimeoutIsHonoured() {
        let now = Date()
        let event = OperatorPromptEvent(
            origin: .freeform(source: "test.timeout"),
            severity: .info,
            title: "T",
            body: "B",
            allowedVerbs: [.acknowledge],
            createdAt: now,
            timeout: 30
        )
        XCTAssertEqual(event.expiresAt.timeIntervalSince(now), 30, accuracy: 0.001)
    }

    func test_init_negativeTimeoutClampsToZero() {
        let now = Date()
        let event = OperatorPromptEvent(
            origin: .freeform(source: "test.clamp"),
            severity: .info,
            title: "T",
            body: "B",
            allowedVerbs: [.acknowledge],
            createdAt: now,
            timeout: -10
        )
        XCTAssertEqual(event.expiresAt, now)
        XCTAssertTrue(event.isExpired(at: now))
    }

    func test_isExpired_isFalseBeforeExpiry_trueAtAndAfter() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let event = OperatorPromptEvent(
            origin: .freeform(source: "test.expiry"),
            severity: .info,
            title: "T",
            body: "B",
            allowedVerbs: [.acknowledge],
            createdAt: now,
            timeout: 60
        )
        XCTAssertFalse(event.isExpired(at: now))
        XCTAssertFalse(event.isExpired(at: now.addingTimeInterval(59)))
        XCTAssertTrue(event.isExpired(at: now.addingTimeInterval(60)))
        XCTAssertTrue(event.isExpired(at: now.addingTimeInterval(120)))
    }

    func test_allowsRememberChoice_isFalseWithoutPolicyKey_trueWithIt() {
        let base = OperatorPromptEvent(
            origin: .freeform(source: "test.remember"),
            severity: .info,
            title: "T",
            body: "B",
            allowedVerbs: [.acknowledge]
        )
        XCTAssertFalse(base.allowsRememberChoice)

        let keyed = OperatorPromptEvent(
            origin: .freeform(source: "test.remember"),
            severity: .info,
            title: "T",
            body: "B",
            allowedVerbs: [.acknowledge],
            policyKey: "mre.run.42.engagement.rtl"
        )
        XCTAssertTrue(keyed.allowsRememberChoice)
    }

    // MARK: - Standard option synthesis

    func test_standardOptions_orderingIsAcknowledgeRetrySkipAbort() {
        let options = OperatorPromptOption.standardOptions(
            forAllowedVerbs: [.abort, .skip, .retry, .acknowledge]
        )
        XCTAssertEqual(options.map(\.verb), [.acknowledge, .retry, .skip, .abort])
    }

    func test_standardOptions_dedupesRepeatedVerbs() {
        let options = OperatorPromptOption.standardOptions(
            forAllowedVerbs: [.acknowledge, .acknowledge, .abort, .abort]
        )
        XCTAssertEqual(options.map(\.verb), [.acknowledge, .abort])
    }

    func test_standardOptions_rolesMatchSemanticColors() {
        let options = OperatorPromptOption.standardOptions(
            forAllowedVerbs: FleetRecipeResumptionVerb.allCases
        )
        let rolesByVerb = Dictionary(uniqueKeysWithValues: options.map { ($0.verb, $0.role) })
        XCTAssertEqual(rolesByVerb[.acknowledge], .confirm)
        XCTAssertEqual(rolesByVerb[.retry], .neutral)
        XCTAssertEqual(rolesByVerb[.skip], .neutral)
        XCTAssertEqual(rolesByVerb[.abort], .cancel)
    }

    func test_standardOptions_idsUseStableSentinelPattern() {
        let options = OperatorPromptOption.standardOptions(
            forAllowedVerbs: FleetRecipeResumptionVerb.allCases
        )
        let idsByVerb = Dictionary(uniqueKeysWithValues: options.map { ($0.verb, $0.id) })
        XCTAssertEqual(idsByVerb[.acknowledge], "verb.acknowledge")
        XCTAssertEqual(idsByVerb[.retry], "verb.retry")
        XCTAssertEqual(idsByVerb[.skip], "verb.skip")
        XCTAssertEqual(idsByVerb[.abort], "verb.abort")
    }

    func test_standardOptions_humanLabelsAreDefaulted() {
        let options = OperatorPromptOption.standardOptions(
            forAllowedVerbs: FleetRecipeResumptionVerb.allCases
        )
        let labelsByVerb = Dictionary(uniqueKeysWithValues: options.map { ($0.verb, $0.humanLabel) })
        XCTAssertEqual(labelsByVerb[.acknowledge], "Acknowledge")
        XCTAssertEqual(labelsByVerb[.retry], "Retry")
        XCTAssertEqual(labelsByVerb[.skip], "Skip")
        XCTAssertEqual(labelsByVerb[.abort], "Abort")
    }

    func test_effectiveOptions_synthesisesFromAllowedVerbsWhenNil() {
        let event = OperatorPromptEvent(
            origin: .freeform(source: "test.effective"),
            severity: .info,
            title: "T",
            body: "B",
            options: nil,
            allowedVerbs: [.acknowledge, .abort]
        )
        XCTAssertEqual(event.effectiveOptions.map(\.verb), [.acknowledge, .abort])
        XCTAssertEqual(event.effectiveOptions.map(\.id), ["verb.acknowledge", "verb.abort"])
    }

    func test_effectiveOptions_returnsPublisherOptionsWhenSupplied() {
        let custom = [
            OperatorPromptOption(id: "swapNow", humanLabel: "Swap now", role: .confirm, verb: .acknowledge),
            OperatorPromptOption(id: "waitThenSwap", humanLabel: "Wait then swap", role: .neutral, verb: .acknowledge),
            OperatorPromptOption(id: "abortSwap", humanLabel: "Abort", role: .cancel, verb: .abort),
        ]
        let event = OperatorPromptEvent(
            origin: .freeform(source: "test.custom"),
            severity: .warning,
            title: "Swap?",
            body: "Reserve drone is ready.",
            options: custom,
            allowedVerbs: [.acknowledge, .abort]
        )
        XCTAssertEqual(event.effectiveOptions.map(\.id), ["swapNow", "waitThenSwap", "abortSwap"])
    }

    func test_effectiveOptions_emptyPublisherListFallsBackToSynthesis() {
        let event = OperatorPromptEvent(
            origin: .freeform(source: "test.emptyCustom"),
            severity: .info,
            title: "T",
            body: "B",
            options: [],
            allowedVerbs: [.acknowledge]
        )
        XCTAssertEqual(event.effectiveOptions.map(\.id), ["verb.acknowledge"])
    }

    // MARK: - Recipe-escalation construction helper

    func test_recipeEscalationInit_preservesAllowedVerbsAndWrapsOrigin() {
        let escalation = sampleEscalation(reason: .operatorActionRequired(kind: .rotateDrone))
        let event = OperatorPromptEvent(fromRecipeEscalation: escalation)

        XCTAssertEqual(event.allowedVerbs, escalation.allowedVerbs)
        guard case .recipeEscalation(let wrapped) = event.origin else {
            return XCTFail("Expected recipeEscalation origin, got \(event.origin)")
        }
        XCTAssertEqual(wrapped, escalation)
    }

    func test_recipeEscalationInit_defaultsDisplaySourceToMissionControl() {
        let escalation = sampleEscalation(reason: .operatorActionRequired(kind: .rotateDrone))
        let event = OperatorPromptEvent(fromRecipeEscalation: escalation)
        XCTAssertEqual(event.displaySource, .missionControl)
    }

    func test_recipeEscalationInit_customDisplaySourceIsPreserved() {
        let escalation = sampleEscalation(reason: .operatorActionRequired(kind: .rotateDrone))
        let event = OperatorPromptEvent(
            fromRecipeEscalation: escalation,
            displaySource: .assistant(
                pluginID: GuardianPluginID.paladin.rawValue,
                displayName: "Paladin",
                operatorPromptBackgroundHex: "aabbcc"
            )
        )
        guard case .assistant(let pid, let name, let hex) = event.displaySource else {
            return XCTFail("expected assistant display source")
        }
        XCTAssertEqual(pid, GuardianPluginID.paladin.rawValue)
        XCTAssertEqual(name, "Paladin")
        XCTAssertEqual(hex, "aabbcc")
    }

    func test_recipeEscalationInit_operatorActionRequired_defaultsToWarning() {
        let escalation = sampleEscalation(reason: .operatorActionRequired(kind: .rotateDrone))
        let event = OperatorPromptEvent(fromRecipeEscalation: escalation)
        XCTAssertEqual(event.severity, .warning)
        XCTAssertEqual(event.title, "Operator action required")
        XCTAssertTrue(event.body.contains("rotateDrone"))
    }

    func test_recipeEscalationInit_unrecoverableFailure_defaultsToError() {
        let escalation = sampleEscalation(
            reason: .unrecoverableFailure(kind: .calibrationDidNotConverge),
            allowedVerbs: [.abort]
        )
        let event = OperatorPromptEvent(fromRecipeEscalation: escalation)
        XCTAssertEqual(event.severity, .error)
        XCTAssertEqual(event.title, "Recipe failed")
        XCTAssertTrue(event.body.contains("calibrationDidNotConverge"))
    }

    func test_recipeEscalationInit_confirmation_defaultsToInfo() {
        let escalation = sampleEscalation(
            reason: .confirmation(kind: .confirmInLiveMission),
            allowedVerbs: [.acknowledge, .abort]
        )
        let event = OperatorPromptEvent(fromRecipeEscalation: escalation)
        XCTAssertEqual(event.severity, .info)
        XCTAssertEqual(event.title, "Confirmation needed")
        XCTAssertTrue(event.body.contains("confirmInLiveMission"))
    }

    func test_recipeEscalationInit_overridesReplaceDerivedDefaults() {
        let escalation = sampleEscalation(reason: .operatorActionRequired(kind: .rotateDrone))
        let event = OperatorPromptEvent(
            fromRecipeEscalation: escalation,
            title: "Custom title",
            body: "Custom body",
            severity: .error,
            options: [
                OperatorPromptOption(id: "ok", humanLabel: "OK", role: .confirm, verb: .acknowledge),
            ],
            policyKey: "test.recipe.policy"
        )
        XCTAssertEqual(event.title, "Custom title")
        XCTAssertEqual(event.body, "Custom body")
        XCTAssertEqual(event.severity, .error)
        XCTAssertEqual(event.effectiveOptions.map(\.id), ["ok"])
        XCTAssertEqual(event.policyKey, "test.recipe.policy")
        XCTAssertTrue(event.allowsRememberChoice)
    }

    // MARK: - Answer round-trip

    func test_answer_carriesEveryFieldVerbatim() {
        let now = Date()
        let answer = OperatorPromptAnswer(
            promptID: UUID(),
            selectedOptionID: "swapNow",
            verb: .acknowledge,
            remember: true,
            resolution: .operatorChose,
            answeredAt: now
        )
        XCTAssertEqual(answer.selectedOptionID, "swapNow")
        XCTAssertEqual(answer.verb, .acknowledge)
        XCTAssertTrue(answer.remember)
        XCTAssertEqual(answer.resolution, .operatorChose)
        XCTAssertEqual(answer.answeredAt, now)
    }

    func test_resolutionSource_cases_areAllPresent() {
        XCTAssertEqual(
            Set(OperatorPromptResolutionSource.allCases),
            [.operatorChose, .rememberedFromCache, .timeoutAborted]
        )
    }

    // MARK: - Target

    func test_target_defaultsToUnspecified() {
        let event = OperatorPromptEvent(
            origin: .freeform(source: "test.target.default"),
            severity: .info,
            title: "T",
            body: "B",
            allowedVerbs: [.acknowledge]
        )
        XCTAssertEqual(event.target, .unspecified)
        XCTAssertTrue(event.target.isUnspecified)
    }

    func test_target_unspecified_everyFieldIsNil() {
        let target = OperatorPromptTarget.unspecified
        XCTAssertNil(target.missionRunID)
        XCTAssertNil(target.missionTaskID)
        XCTAssertNil(target.squad)
        XCTAssertNil(target.affectedRosterSlotID)
        XCTAssertNil(target.affectedAssignmentID)
        XCTAssertNil(target.affectedVehicleID)
        XCTAssertNil(target.recipeRunID)
        XCTAssertNil(target.pluginID)
        XCTAssertTrue(target.isUnspecified)
    }

    func test_target_anyFieldSetIsNoLongerUnspecified() {
        let withRun = OperatorPromptTarget(missionRunID: UUID())
        XCTAssertFalse(withRun.isUnspecified)

        let withVehicle = OperatorPromptTarget(affectedVehicleID: "V-12")
        XCTAssertFalse(withVehicle.isUnspecified)

        let withPlugin = OperatorPromptTarget(pluginID: "plugin.paladin")
        XCTAssertFalse(withPlugin.isUnspecified)
    }

    func test_target_matches_unspecifiedFilterAcceptsEverything() {
        let prompt = OperatorPromptTarget(
            missionRunID: UUID(),
            affectedVehicleID: "V-9"
        )
        XCTAssertTrue(OperatorPromptTarget.unspecified.matches(prompt))
    }

    func test_target_matches_filterFieldsMustEqualPromptFields() {
        let runID = UUID()
        let vehicleID = "V-9"
        let panelContext = OperatorPromptTarget(missionRunID: runID)
        let matchingPrompt = OperatorPromptTarget(missionRunID: runID, affectedVehicleID: vehicleID)
        let otherPrompt = OperatorPromptTarget(missionRunID: UUID(), affectedVehicleID: vehicleID)
        XCTAssertTrue(panelContext.matches(matchingPrompt))
        XCTAssertFalse(panelContext.matches(otherPrompt))
    }

    func test_target_matches_squadFilterUsesPrimaryRosterDeviceID() {
        let primary = UUID()
        let other = UUID()
        let filter = OperatorPromptTarget(
            squad: OperatorPromptSquadContext(primaryRosterDeviceID: primary)
        )
        let matching = OperatorPromptTarget(
            squad: OperatorPromptSquadContext(primaryRosterDeviceID: primary,
                                              wingmanRosterDeviceIDs: [UUID(), UUID()])
        )
        let mismatched = OperatorPromptTarget(
            squad: OperatorPromptSquadContext(primaryRosterDeviceID: other)
        )
        XCTAssertTrue(filter.matches(matching))
        XCTAssertFalse(filter.matches(mismatched))
    }

    func test_target_supportsFullSwapInReserveAddressing() {
        let runID = UUID()
        let taskID = UUID()
        let primary = UUID()
        let reservePrimaryAssignment = UUID()
        let target = OperatorPromptTarget(
            missionRunID: runID,
            missionTaskID: taskID,
            squad: OperatorPromptSquadContext(
                primaryRosterDeviceID: primary,
                primaryAssignmentID: reservePrimaryAssignment,
                primaryVehicleID: "V-9",
                wingmanRosterDeviceIDs: [UUID(), UUID()],
                reserveRosterDeviceIDs: [UUID()]
            ),
            affectedRosterSlotID: primary,
            affectedAssignmentID: reservePrimaryAssignment,
            affectedVehicleID: "V-9"
        )
        XCTAssertEqual(target.missionRunID, runID)
        XCTAssertEqual(target.squad?.primaryRosterDeviceID, primary)
        XCTAssertEqual(target.squad?.wingmanRosterDeviceIDs.count, 2)
        XCTAssertEqual(target.squad?.reserveRosterDeviceIDs.count, 1)
        XCTAssertFalse(target.isUnspecified)
    }

    // MARK: - Context facts

    func test_contextFacts_defaultsToEmpty() {
        let event = OperatorPromptEvent(
            origin: .freeform(source: "test.facts.empty"),
            severity: .info,
            title: "T",
            body: "B",
            allowedVerbs: [.acknowledge]
        )
        XCTAssertTrue(event.contextFacts.isEmpty)
    }

    func test_contextFacts_preserveAuthoredOrder() {
        let facts: [OperatorPromptContextFact] = [
            .init(label: "Mission run", value: "Hawkeye-3", group: "Where"),
            .init(label: "Task", value: "Sweep South", group: "Where"),
            .init(label: "Primary battery", value: "8%", emphasis: .error, group: "State"),
            .init(label: "Reserve readiness", value: "Ready", emphasis: .success, group: "State"),
        ]
        let event = OperatorPromptEvent(
            origin: .freeform(source: "test.facts.ordered"),
            severity: .warning,
            title: "Swap?",
            body: "",
            contextFacts: facts,
            allowedVerbs: [.acknowledge, .abort]
        )
        XCTAssertEqual(event.contextFacts.map(\.label),
                       ["Mission run", "Task", "Primary battery", "Reserve readiness"])
        XCTAssertEqual(event.contextFacts.map(\.emphasis),
                       [.normal, .normal, .error, .success])
    }

    func test_contextFact_codableRoundTrip() throws {
        let original = OperatorPromptContextFact(
            label: "Primary battery",
            value: "8% (critical)",
            emphasis: .error,
            icon: "battery.0",
            group: "State"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OperatorPromptContextFact.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_contextFactEmphasis_casesAreAllPresent() {
        XCTAssertEqual(
            Set(OperatorPromptContextFactEmphasis.allCases),
            [.normal, .caption, .success, .warning, .error]
        )
    }

    // MARK: - Option summary

    func test_option_summaryDefaultsToNil() {
        let option = OperatorPromptOption(
            id: "x", humanLabel: "X", role: .confirm, verb: .acknowledge
        )
        XCTAssertNil(option.summary)
    }

    func test_option_summaryRoundTrips() {
        let option = OperatorPromptOption(
            id: "swapNow",
            humanLabel: "Swap now",
            summary: "Land Alpha-1 at home, deploy R-2 immediately",
            role: .confirm,
            verb: .acknowledge
        )
        XCTAssertEqual(option.summary, "Land Alpha-1 at home, deploy R-2 immediately")
    }

    func test_standardOption_factoriesAcceptSummary() {
        let ack = OperatorPromptOption.standardAcknowledge(summary: "Continue mission")
        let abort = OperatorPromptOption.standardAbort(summary: "RTL everything")
        XCTAssertEqual(ack.summary, "Continue mission")
        XCTAssertEqual(abort.summary, "RTL everything")
    }

    // MARK: - Recipe-escalation lift target/facts auto-population

    func test_recipeEscalationInit_autoPopulatesTargetVehicleAndRecipeRun() {
        let escalation = sampleEscalation(reason: .operatorActionRequired(kind: .rotateDrone))
        let event = OperatorPromptEvent(fromRecipeEscalation: escalation)
        XCTAssertEqual(event.target.affectedVehicleID, escalation.vehicleID)
        XCTAssertEqual(event.target.recipeRunID, escalation.runID)
        XCTAssertNil(event.target.missionRunID, "Recipe runner has no mission context to fill")
    }

    func test_recipeEscalationInit_autoAttachesRecipeAndStepFacts() {
        let escalation = sampleEscalation(reason: .operatorActionRequired(kind: .rotateDrone))
        let event = OperatorPromptEvent(fromRecipeEscalation: escalation)
        XCTAssertGreaterThanOrEqual(event.contextFacts.count, 2)
        XCTAssertEqual(event.contextFacts[0].label, "Recipe")
        XCTAssertEqual(event.contextFacts[0].value, escalation.recipe.rawValue)
        XCTAssertEqual(event.contextFacts[0].group, "Recipe")
        XCTAssertEqual(event.contextFacts[1].label, "Step")
        XCTAssertEqual(event.contextFacts[1].value, escalation.stepID.rawValue)
        XCTAssertEqual(event.contextFacts[1].group, "Recipe")
    }

    func test_recipeEscalationInit_extraFactsAppendAfterAutoFacts() {
        let escalation = sampleEscalation(reason: .operatorActionRequired(kind: .rotateDrone))
        let extra: [OperatorPromptContextFact] = [
            .init(label: "Mission run", value: "Hawkeye-3", group: "Where"),
        ]
        let event = OperatorPromptEvent(
            fromRecipeEscalation: escalation,
            contextFacts: extra
        )
        XCTAssertEqual(event.contextFacts.count, 3)
        XCTAssertEqual(event.contextFacts[0].label, "Recipe")
        XCTAssertEqual(event.contextFacts[1].label, "Step")
        XCTAssertEqual(event.contextFacts[2].label, "Mission run")
    }

    func test_recipeEscalationInit_targetOverrideReplacesAutoTarget() {
        let escalation = sampleEscalation(reason: .operatorActionRequired(kind: .rotateDrone))
        let runID = UUID()
        let taskID = UUID()
        let overrideTarget = OperatorPromptTarget(
            missionRunID: runID,
            missionTaskID: taskID,
            affectedVehicleID: escalation.vehicleID,
            recipeRunID: escalation.runID
        )
        let event = OperatorPromptEvent(
            fromRecipeEscalation: escalation,
            target: overrideTarget
        )
        XCTAssertEqual(event.target.missionRunID, runID)
        XCTAssertEqual(event.target.missionTaskID, taskID)
        XCTAssertEqual(event.target.affectedVehicleID, escalation.vehicleID)
        XCTAssertEqual(event.target.recipeRunID, escalation.runID)
    }

    // MARK: - Helpers

    private func sampleEscalation(
        reason: FleetRecipeEscalationReason,
        allowedVerbs: [FleetRecipeResumptionVerb] = [.acknowledge, .abort]
    ) -> FleetRecipeEscalationEvent {
        FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: FleetRecipeName.literal("recipe.fleet.calibrate.compass"),
            vehicleID: "test-vehicle",
            stepID: try! FleetRecipeStepID(validating: "step_one"),
            reason: reason,
            allowedVerbs: allowedVerbs,
            lastResponse: .success()
        )
    }
}
