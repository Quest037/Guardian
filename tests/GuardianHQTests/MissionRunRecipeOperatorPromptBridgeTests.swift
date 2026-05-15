import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunRecipeOperatorPromptBridgeTests: XCTestCase {

    func test_awaitMissionRecipeEscalationAnswer_registersThenClearsActivePrompt() async {
        OperatorPromptCenter.shared.prepareOperatorPromptRoutingSession()
        let bridge = MissionRunRecipeOperatorPromptBridge.shared
        let center = OperatorPromptCenter.shared
        let runID = UUID()
        let assignID = UUID()
        let escalation = FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName,
            vehicleID: "V-1",
            stepID: .literal("upload"),
            reason: .confirmation(kind: .confirmInLiveMission),
            allowedVerbs: [.acknowledge, .abort],
            lastResponse: .success()
        )

        center.setMCRPromptPanelHostActive(true, missionRunID: runID)
        center.noteMCRRunDetailViewPresented(missionRunID: runID)
        defer {
            center.setMCRPromptPanelHostActive(false, missionRunID: runID)
            center.noteMCRRunDetailViewDismissed(missionRunID: runID)
        }

        async let waiter: FleetRecipeResumptionVerb = bridge.awaitMissionRecipeEscalationAnswer(
            missionRunID: runID,
            assignmentID: assignID,
            missionTaskID: nil,
            slotLabel: "Alpha",
            run: nil,
            recipeIssuerKey: MissionRunCommandIssuerKey.localOperator,
            escalation: escalation
        )
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(center.activeMCRPrompts(forMissionRunID: runID).count, 1)
        XCTAssertTrue(
            center.persistentOperatorToastPrompts.isEmpty,
            "MC-R strip already shows this prompt; sticky toast should stay off to avoid duplicate chrome."
        )
        let prompt = center.activeMCRPrompts(forMissionRunID: runID).first
        XCTAssertNotNil(prompt)
        XCTAssertEqual(prompt?.displaySource, .mre, "mission-run MC-R recipe prompts align with MRE engagement attribution")
        guard let prompt else {
            XCTFail("expected MC-R mounted prompt")
            return
        }
        if case .recipeEscalation(let wrapped) = prompt.origin {
            XCTAssertEqual(wrapped.runID, escalation.runID)
        } else {
            XCTFail("expected recipeEscalation origin")
        }

        let pid = prompt.id
        XCTAssertTrue(
            center.submitAnswer(
                OperatorPromptAnswer(
                    promptID: pid,
                    selectedOptionID: OperatorPromptOption.standardID(for: .acknowledge),
                    verb: .acknowledge,
                    remember: false,
                    resolution: .operatorChose
                )
            )
        )
        let verb = await waiter
        XCTAssertEqual(verb, .acknowledge)
        XCTAssertTrue(center.activeMCRPrompts(forMissionRunID: runID).isEmpty)
    }

    func test_complete_policy_wind_down_auto_acks_confirmInLiveMission_without_prompt() async {
        OperatorPromptCenter.shared.prepareOperatorPromptRoutingSession()
        let bridge = MissionRunRecipeOperatorPromptBridge.shared
        let center = OperatorPromptCenter.shared
        let runID = UUID()
        let assignID = UUID()
        let escalation = FleetRecipeEscalationEvent(
            runID: FleetRecipeRunID(),
            recipe: FleetMovePointParkRecipeRegistrations.movePointParkRecipeName,
            vehicleID: "V-1",
            stepID: .literal("move"),
            reason: .confirmation(kind: .confirmInLiveMission),
            allowedVerbs: [.acknowledge, .retry, .abort],
            lastResponse: .success()
        )

        center.setMCRPromptPanelHostActive(true, missionRunID: runID)
        defer { center.setMCRPromptPanelHostActive(false, missionRunID: runID) }

        let verb = await bridge.awaitMissionRecipeEscalationAnswer(
            missionRunID: runID,
            assignmentID: assignID,
            missionTaskID: nil,
            slotLabel: "Alpha",
            run: nil,
            recipeIssuerKey: MissionRunCommandIssuerKey.completePolicyWindDown,
            escalation: escalation
        )
        XCTAssertEqual(verb, .acknowledge)
        XCTAssertTrue(
            center.activeMCRPrompts(forMissionRunID: runID).isEmpty,
            "complete-policy wind-down should not enqueue a per-vehicle confirmation toast"
        )
    }
}
