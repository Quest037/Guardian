import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunRecipeOperatorPromptBridgeTests: XCTestCase {

    func test_awaitMissionRecipeEscalationAnswer_registersThenClearsActivePrompt() async {
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
        defer { center.setMCRPromptPanelHostActive(false, missionRunID: runID) }

        async let waiter: FleetRecipeResumptionVerb = bridge.awaitMissionRecipeEscalationAnswer(
            missionRunID: runID,
            assignmentID: assignID,
            missionTaskID: nil,
            slotLabel: "Alpha",
            run: nil,
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
        if case .recipeEscalation(let wrapped) = prompt?.origin {
            XCTAssertEqual(wrapped.runID, escalation.runID)
        } else {
            XCTFail("expected recipeEscalation origin")
        }

        let pid = prompt!.id
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
}
