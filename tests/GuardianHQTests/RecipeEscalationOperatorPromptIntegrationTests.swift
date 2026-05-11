import XCTest
@testable import GuardianHQ

/// Stage G — integration between ``FleetRecipeEscalationEvent`` / recipe escalation and the
/// Stage D operator prompt channel: lift to ``OperatorPromptEvent``, ``OperatorPromptRouter/route``,
/// and ``OperatorPromptResumptionChannel`` resumption with a typed ``FleetRecipeResumptionVerb``.
@MainActor
final class RecipeEscalationOperatorPromptIntegrationTests: XCTestCase {

    private func sampleEscalation(
        vehicleID: String = "ALPHA-1",
        allowedVerbs: [FleetRecipeResumptionVerb] = [.retry, .abort]
    ) -> FleetRecipeEscalationEvent {
        FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: .literal("recipe.fleet.test.escalation.prompt"),
            vehicleID: vehicleID,
            stepID: .literal("calibrate"),
            reason: .operatorActionRequired(kind: .rotateDrone),
            allowedVerbs: allowedVerbs,
            lastResponse: .success()
        )
    }

    func test_fromRecipeEscalation_promptEvent_routesViaOperatorPromptRouter_toWizardPrimary() {
        let escalation = sampleEscalation()
        let prompt = OperatorPromptEvent(fromRecipeEscalation: escalation)

        guard case .recipeEscalation(let wrapped) = prompt.origin else {
            return XCTFail("Expected recipeEscalation origin, got \(prompt.origin)")
        }
        XCTAssertEqual(wrapped.runID, escalation.runID)
        XCTAssertEqual(prompt.target.affectedVehicleID, escalation.vehicleID)
        XCTAssertEqual(prompt.target.recipeRunID, escalation.runID)
        XCTAssertEqual(prompt.allowedVerbs, escalation.allowedVerbs)

        let router = OperatorPromptRouter(availabilityProbe: { _ in true })
        let decision = router.route(prompt)

        XCTAssertFalse(decision.isUnroutable)
        XCTAssertEqual(
            decision.primary,
            .vehicleInspectorWizardPanel(vehicleID: escalation.vehicleID, recipeRunID: escalation.runID)
        )
        XCTAssertTrue(decision.mirrors.contains(.inAppInbox))
    }

    func test_resumptionChannel_resolvesPromptLiftedFromRecipeEscalation() async {
        let channel = OperatorPromptResumptionChannel()
        let escalation = sampleEscalation(allowedVerbs: [.retry, .abort])
        let prompt = OperatorPromptEvent(fromRecipeEscalation: escalation)

        let router = OperatorPromptRouter(availabilityProbe: { _ in true })
        let decision = router.route(prompt)
        XCTAssertFalse(decision.isUnroutable, "Routing should yield at least one delivery target.")

        async let answer = channel.awaitAnswer(for: prompt)
        try await Task.sleep(nanoseconds: 30_000_000)

        let submitted = channel.submit(
            OperatorPromptAnswer(
                promptID: prompt.id,
                selectedOptionID: "verb.retry",
                verb: .retry,
                remember: false,
                resolution: .operatorChose
            )
        )
        XCTAssertTrue(submitted, "submit should match the awaiting prompt id.")

        let resolved = await answer
        XCTAssertEqual(resolved.verb, .retry)
        XCTAssertEqual(resolved.promptID, prompt.id)
    }
}
