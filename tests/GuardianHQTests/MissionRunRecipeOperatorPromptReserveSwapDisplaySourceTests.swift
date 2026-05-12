import XCTest

@testable import GuardianHQ

@MainActor
final class MissionRunRecipeOperatorPromptReserveSwapDisplaySourceTests: XCTestCase {

    func test_awaitFixedReserveSwapEngagementConsent_usesProvidedAssistantDisplaySource() async {
        let bridge = MissionRunRecipeOperatorPromptBridge.shared
        let center = OperatorPromptCenter.shared
        let runID = UUID()
        let rdPrimary = UUID()
        let rdReserve = UUID()
        let primary = MissionRunAssignment(
            id: UUID(),
            taskId: nil,
            rosterDeviceId: rdPrimary,
            slotName: "Primary",
            attachedFleetVehicleToken: "a"
        )
        let reserve = MissionRunAssignment(
            id: UUID(),
            taskId: nil,
            rosterDeviceId: rdReserve,
            slotName: "Reserve",
            attachedFleetVehicleToken: "b"
        )
        let taskID = UUID()
        let displaySource = OperatorPromptDisplaySource.assistant(
            pluginID: "test.plugin",
            displayName: "Test Assistant",
            operatorPromptBackgroundHex: "aabbcc"
        )

        center.setMCRPromptPanelHostActive(true, missionRunID: runID)
        defer { center.setMCRPromptPanelHostActive(false, missionRunID: runID) }

        async let waiter: FleetRecipeResumptionVerb = bridge.awaitFixedReserveSwapEngagementConsent(
            missionRunID: runID,
            primary: primary,
            reserve: reserve,
            missionTaskID: taskID,
            taskName: "Alpha",
            displaySource: displaySource
        )
        await Task.yield()
        await Task.yield()

        let prompt = center.activeMCRPrompts(forMissionRunID: runID).first
        XCTAssertNotNil(prompt)
        XCTAssertEqual(prompt?.displaySource, displaySource)

        let pid = prompt!.id
        XCTAssertTrue(
            center.submitAnswer(
                OperatorPromptAnswer(
                    promptID: pid,
                    selectedOptionID: OperatorPromptOption.standardID(for: .abort),
                    verb: .abort,
                    remember: false,
                    resolution: .operatorChose
                )
            )
        )
        let verb = await waiter
        XCTAssertEqual(verb, .abort)
        XCTAssertTrue(center.activeMCRPrompts(forMissionRunID: runID).isEmpty)
    }

    func test_awaitFixedReserveSwapEngagementConsent_usesMreDisplaySource() async {
        let bridge = MissionRunRecipeOperatorPromptBridge.shared
        let center = OperatorPromptCenter.shared
        let runID = UUID()
        let primary = MissionRunAssignment(
            id: UUID(),
            taskId: nil,
            rosterDeviceId: UUID(),
            slotName: "Primary",
            attachedFleetVehicleToken: "a"
        )
        let reserve = MissionRunAssignment(
            id: UUID(),
            taskId: nil,
            rosterDeviceId: UUID(),
            slotName: "Reserve",
            attachedFleetVehicleToken: "b"
        )
        let taskID = UUID()

        center.setMCRPromptPanelHostActive(true, missionRunID: runID)
        defer { center.setMCRPromptPanelHostActive(false, missionRunID: runID) }

        async let waiter: FleetRecipeResumptionVerb = bridge.awaitFixedReserveSwapEngagementConsent(
            missionRunID: runID,
            primary: primary,
            reserve: reserve,
            missionTaskID: taskID,
            taskName: "Alpha",
            displaySource: .mre
        )
        await Task.yield()
        await Task.yield()

        let prompt = center.activeMCRPrompts(forMissionRunID: runID).first
        XCTAssertEqual(prompt?.displaySource, .mre)

        let pid = prompt!.id
        XCTAssertTrue(
            center.submitAnswer(
                OperatorPromptAnswer(
                    promptID: pid,
                    selectedOptionID: OperatorPromptOption.standardID(for: .abort),
                    verb: .abort,
                    remember: false,
                    resolution: .operatorChose
                )
            )
        )
        _ = await waiter
    }
}
