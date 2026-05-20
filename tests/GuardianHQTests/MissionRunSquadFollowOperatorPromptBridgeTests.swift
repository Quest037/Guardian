import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunSquadFollowOperatorPromptBridgeTests: XCTestCase {
    func test_formationFollowFailureContextFacts_includes_brain_when_bound() {
        let brainId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let binding = MissionRunBrainBinding(
            taskKindRaw: TrainingTaskKind.formation.rawValue,
            vehicleClassRaw: TrainingVehicleClass.ugvWheeled.rawValue,
            brainId: brainId,
            brainVersion: GuardianBrainVersion.fromLegacyInteger(3),
            displayName: "Convoy lab"
        )
        let facts = MissionRunSquadFollowOperatorPromptBridge.formationFollowFailureContextFacts(
            taskName: "Patrol A",
            primarySlotName: "Alpha",
            failedWingmen: [(UUID(), "Bravo")],
            brainBinding: binding
        )
        XCTAssertEqual(facts.filter { $0.group == "Policy" }.count, 2)
        XCTAssertTrue(facts.contains { $0.label == "Brain" && $0.value.contains("Convoy lab") && $0.value.contains("0.0.3") })
        XCTAssertTrue(facts.contains { $0.label == "Brain ID" && $0.value == brainId.uuidString })
        XCTAssertTrue(facts.contains { $0.label == "Task" && $0.value == "Patrol A" })
    }

    func test_formationFollowFailureContextFacts_omits_policy_without_binding() {
        let facts = MissionRunSquadFollowOperatorPromptBridge.formationFollowFailureContextFacts(
            taskName: "Patrol A",
            primarySlotName: "Alpha",
            failedWingmen: [],
            brainBinding: nil
        )
        XCTAssertTrue(facts.allSatisfy { $0.group != "Policy" })
        XCTAssertEqual(facts.count, 3)
    }
}
