import XCTest
@testable import GuardianHQ

@MainActor
final class MissionControlOperatorTriggerNextSquadPolicyTests: XCTestCase {
    private func twoPrimaryMission() -> (Mission, MissionTask, MissionRunAssignment, MissionRunAssignment) {
        let d1 = UUID()
        let d2 = UUID()
        let task = MissionTask(
            name: "Layer",
            regularity: .operatorTriggered,
            staggerTrigger: .operatorFirstWaveGate,
            rosterDeviceIds: [d1, d2]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: d1, name: "P1", slot: .primary),
                RosterDevice(id: d2, name: "P2", slot: .primary)
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: d1,
            slotName: "P1",
            attachedFleetVehicleToken: "v1"
        )
        let a2 = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: d2,
            slotName: "P2",
            attachedFleetVehicleToken: "v2"
        )
        return (mission, task, a1, a2)
    }

    func test_coldStart_offersColdStartTask() {
        let (mission, task, a1, a2) = twoPrimaryMission()
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        run.status = .running
        run.setSessionPhase(.executing)

        XCTAssertEqual(
            MissionControlOperatorTriggerNextSquadPolicy.nextLaunchAction(
                run: run,
                task: task,
                mission: mission
            ),
            .coldStartTask
        )
    }

    func test_deferredHead_afterLeadCycle_whileQueueNonEmpty() {
        let (mission, task, a1, a2) = twoPrimaryMission()
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        run.status = .running
        run.setSessionPhase(.executing)
        _ = run.recordSquadCycleCompletions(assignmentIDs: [a1.id], mission: mission)
        run.registerDeferredFirstWaveSquads(taskID: task.id, assignmentIDs: [a2.id])

        XCTAssertEqual(
            MissionControlOperatorTriggerNextSquadPolicy.nextLaunchAction(
                run: run,
                task: task,
                mission: mission
            ),
            .releaseDeferredFirstWaveHead(a2.id)
        )
    }

    func test_leadNextLap_afterDeferredQueueDrained() {
        let (mission, task, a1, a2) = twoPrimaryMission()
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        run.status = .running
        run.setSessionPhase(.executing)
        _ = run.recordSquadCycleCompletions(assignmentIDs: [a1.id, a2.id], mission: mission)

        XCTAssertEqual(
            MissionControlOperatorTriggerNextSquadPolicy.nextLaunchAction(
                run: run,
                task: task,
                mission: mission
            ),
            .launchPrimary(a1.id)
        )
    }

    func test_deferredHead_whenLeadActive() {
        let (mission, task, a1, a2) = twoPrimaryMission()
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markSquadActiveInCurrentCycle(a1.id)
        run.registerDeferredFirstWaveSquads(taskID: task.id, assignmentIDs: [a2.id])

        XCTAssertEqual(
            MissionControlOperatorTriggerNextSquadPolicy.nextLaunchAction(
                run: run,
                task: task,
                mission: mission
            ),
            .releaseDeferredFirstWaveHead(a2.id)
        )
    }

    func test_showsTrigger_whenLeadIdleAfterCycleWhileOtherFlying() {
        let (mission, task, a1, a2) = twoPrimaryMission()
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        run.status = .running
        run.setSessionPhase(.executing)
        run.markSquadActiveInCurrentCycle(a2.id)
        _ = run.recordSquadCycleCompletions(assignmentIDs: [a1.id], mission: mission)

        XCTAssertTrue(
            MissionControlOperatorTriggerNextSquadPolicy.showsTriggerButton(
                run: run,
                task: task,
                mission: mission
            )
        )
    }
}
