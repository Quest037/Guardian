import XCTest
@testable import GuardianCore

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
        XCTAssertEqual(center.persistentOperatorToastPrompts.count, 1)
        XCTAssertEqual(center.persistentOperatorToastPrompts.first?.id, event.id)

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
        XCTAssertTrue(center.persistentOperatorToastPrompts.isEmpty)
    }

    func test_prepareOperatorPromptRoutingSession_installsProbe_mcrAndLiveDriveFalseUntilHostsRegister() {
        let router = OperatorPromptRouter(availabilityProbe: { _ in true })
        let center = OperatorPromptCenter(router: router, resumption: OperatorPromptResumptionChannel())
        center.prepareOperatorPromptRoutingSession()

        let probe = router.availabilityProbe
        XCTAssertTrue(probe(.inAppInbox))
        XCTAssertTrue(probe(.persistentToast))
        let rid = UUID()
        XCTAssertFalse(probe(.mcrPromptPanel(missionRunID: rid)))
        center.setMCRPromptPanelHostActive(true, missionRunID: rid)
        XCTAssertTrue(probe(.mcrPromptPanel(missionRunID: rid)))
        center.setMCRPromptPanelHostActive(false, missionRunID: rid)
    }

    func test_mcrPromptPanel_available_whenRunDetailPresented_matchesMissionRunID_withoutBannerHost() {
        let router = OperatorPromptRouter(availabilityProbe: { _ in true })
        let center = OperatorPromptCenter(router: router, resumption: OperatorPromptResumptionChannel())
        center.prepareOperatorPromptRoutingSession()

        let probe = router.availabilityProbe
        let rid = UUID()
        XCTAssertFalse(probe(.mcrPromptPanel(missionRunID: rid)))
        center.noteMCRRunDetailViewPresented(missionRunID: rid)
        XCTAssertTrue(probe(.mcrPromptPanel(missionRunID: rid)))
        center.noteMCRRunDetailViewDismissed(missionRunID: rid)
        XCTAssertFalse(probe(.mcrPromptPanel(missionRunID: rid)))
    }

    func test_awaitAnswer_mountsMCRStripWhenRunDetailPresentedWithoutBannerHost() async {
        let resumption = OperatorPromptResumptionChannel()
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouter.defaultAvailabilityProbe)
        let center = OperatorPromptCenter(router: router, resumption: resumption)
        center.prepareOperatorPromptRoutingSession()
        let runID = UUID()
        center.noteMCRRunDetailViewPresented(missionRunID: runID)
        defer { center.noteMCRRunDetailViewDismissed(missionRunID: runID) }

        let escalation = FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: .literal("recipe.fleet.test.escalation.prompt"),
            vehicleID: "ALPHA-1",
            stepID: .literal("step"),
            reason: .operatorActionRequired(kind: .rotateDrone),
            allowedVerbs: [.retry, .abort],
            lastResponse: .success()
        )
        let event = OperatorPromptEvent(
            fromRecipeEscalation: escalation,
            target: OperatorPromptTarget(
                missionRunID: runID,
                affectedVehicleID: "ALPHA-1",
                recipeRunID: escalation.runID
            )
        )

        let task = Task { await center.awaitAnswer(for: event) }
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(center.activeMCRPrompts(forMissionRunID: runID).count, 1)
        XCTAssertTrue(center.persistentOperatorToastPrompts.isEmpty)

        XCTAssertTrue(
            center.submitAnswer(
                OperatorPromptAnswer(
                    promptID: event.id,
                    selectedOptionID: OperatorPromptOption.standardID(for: .retry),
                    verb: .retry,
                    remember: false,
                    resolution: .operatorChose
                )
            )
        )
        _ = await task.value
    }

    func test_awaitAnswer_mountsPersistentToastWhenNoStripContextualDispatched() async {
        let resumption = OperatorPromptResumptionChannel()
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouter.defaultAvailabilityProbe)
        let center = OperatorPromptCenter(router: router, resumption: resumption)
        center.prepareOperatorPromptRoutingSession()

        let escalation = FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: .literal("recipe.fleet.test.escalation.prompt"),
            vehicleID: "ALPHA-1",
            stepID: .literal("step"),
            reason: .operatorActionRequired(kind: .rotateDrone),
            allowedVerbs: [.retry, .abort],
            lastResponse: .success()
        )
        let event = OperatorPromptEvent(fromRecipeEscalation: escalation)

        let task = Task { await center.awaitAnswer(for: event) }
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(center.inboxPrompts.count, 1)
        XCTAssertEqual(center.persistentOperatorToastPrompts.count, 1)
        XCTAssertEqual(center.persistentOperatorToastPrompts.first?.id, event.id)

        XCTAssertTrue(
            center.submitAnswer(
                OperatorPromptAnswer(
                    promptID: event.id,
                    selectedOptionID: OperatorPromptOption.standardID(for: .retry),
                    verb: .retry,
                    remember: false,
                    resolution: .operatorChose
                )
            )
        )
        let answer = await task.value
        XCTAssertEqual(answer.verb, .retry)
        XCTAssertTrue(center.persistentOperatorToastPrompts.isEmpty)
    }

    func test_awaitAnswer_skipsPersistentToastWhenMCRStripDispatched() async {
        let resumption = OperatorPromptResumptionChannel()
        let router = OperatorPromptRouter(availabilityProbe: OperatorPromptRouter.defaultAvailabilityProbe)
        let center = OperatorPromptCenter(router: router, resumption: resumption)
        center.prepareOperatorPromptRoutingSession()
        let runID = UUID()
        center.setMCRPromptPanelHostActive(true, missionRunID: runID)
        defer { center.setMCRPromptPanelHostActive(false, missionRunID: runID) }

        let escalation = FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: .literal("recipe.fleet.test.escalation.prompt"),
            vehicleID: "ALPHA-1",
            stepID: .literal("step"),
            reason: .operatorActionRequired(kind: .rotateDrone),
            allowedVerbs: [.retry, .abort],
            lastResponse: .success()
        )
        let event = OperatorPromptEvent(
            fromRecipeEscalation: escalation,
            target: OperatorPromptTarget(
                missionRunID: runID,
                affectedVehicleID: "ALPHA-1",
                recipeRunID: escalation.runID
            )
        )

        let task = Task { await center.awaitAnswer(for: event) }
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(center.activeMCRPrompts(forMissionRunID: runID).count, 1)
        XCTAssertTrue(center.persistentOperatorToastPrompts.isEmpty)

        XCTAssertTrue(
            center.submitAnswer(
                OperatorPromptAnswer(
                    promptID: event.id,
                    selectedOptionID: OperatorPromptOption.standardID(for: .retry),
                    verb: .retry,
                    remember: false,
                    resolution: .operatorChose
                )
            )
        )
        _ = await task.value
    }
}
