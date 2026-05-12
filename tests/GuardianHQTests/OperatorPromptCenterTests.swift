import XCTest
@testable import GuardianHQ

@MainActor
final class OperatorPromptCenterTests: XCTestCase {

    private func sampleEscalation(
        allowedVerbs: [FleetRecipeResumptionVerb] = [.retry, .abort]
    ) -> FleetRecipeEscalationEvent {
        FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: .literal("recipe.fleet.test.escalation.prompt"),
            vehicleID: "ALPHA-1",
            stepID: .literal("calibrate"),
            reason: .operatorActionRequired(kind: .rotateDrone),
            allowedVerbs: allowedVerbs,
            lastResponse: .success()
        )
    }

    func test_awaitAnswer_registersInbox_thenSubmit_clearsInbox() async {
        let resumption = OperatorPromptResumptionChannel()
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouter.defaultAvailabilityProbe)
        let center = OperatorPromptCenter(router: router, resumption: resumption)
        center.prepareOperatorPromptRoutingSession()

        let escalation = sampleEscalation()
        let event = OperatorPromptEvent(fromRecipeEscalation: escalation)

        let task = Task { await center.awaitAnswer(for: event) }
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(center.inboxPrompts.count, 1)
        XCTAssertEqual(center.inboxPrompts.first?.id, event.id)

        let submitted = center.submitAnswer(
            OperatorPromptAnswer(
                promptID: event.id,
                selectedOptionID: OperatorPromptOption.standardID(for: .retry),
                verb: .retry,
                remember: false,
                resolution: .operatorChose
            )
        )
        XCTAssertTrue(submitted)

        let answer = await task.value
        XCTAssertEqual(answer.verb, .retry)
        XCTAssertEqual(center.inboxPrompts.count, 0)
    }

    func test_prepareOperatorPromptRoutingSession_installsInboxOnlyProbeOnRouter() {
        let router = OperatorPromptRouter(availabilityProbe: { _ in true })
        let center = OperatorPromptCenter(router: router, resumption: OperatorPromptResumptionChannel())
        center.prepareOperatorPromptRoutingSession()

        let probe = router.availabilityProbe
        XCTAssertTrue(probe(.inAppInbox))
        XCTAssertFalse(probe(.persistentToast))
    }
}
