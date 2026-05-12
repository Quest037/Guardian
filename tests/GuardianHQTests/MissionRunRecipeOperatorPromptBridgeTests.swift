import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunRecipeOperatorPromptBridgeTests: XCTestCase {

    func test_awaitMissionRecipeEscalationAnswer_registersThenClearsActivePrompt() async {
        let bridge = MissionRunRecipeOperatorPromptBridge.shared
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

        async let waiter: FleetRecipeResumptionVerb = bridge.awaitMissionRecipeEscalationAnswer(
            missionRunID: runID,
            assignmentID: assignID,
            missionTaskID: nil,
            slotLabel: "Alpha",
            run: nil,
            escalation: escalation
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(bridge.activePrompts(forMissionRunID: runID).count, 1)
        let prompt = bridge.activePrompts(forMissionRunID: runID).first
        XCTAssertNotNil(prompt)
        if case .recipeEscalation(let wrapped) = prompt?.origin {
            XCTAssertEqual(wrapped.runID, escalation.runID)
        } else {
            XCTFail("expected recipeEscalation origin")
        }

        let pid = prompt!.id
        XCTAssertTrue(
            OperatorPromptResumptionChannel.shared.submit(
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
        XCTAssertTrue(bridge.activePrompts(forMissionRunID: runID).isEmpty)
    }
}
