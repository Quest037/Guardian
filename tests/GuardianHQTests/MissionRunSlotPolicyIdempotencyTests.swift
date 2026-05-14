import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunSlotPolicyIdempotencyTests: XCTestCase {

    func test_setSlotPolicyLanesBoth_returns_false_when_already_at_terminal() {
        let task = MissionTask(name: "T", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let aid = UUID()
        let row = MissionRunAssignment(
            id: aid,
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "S1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .idle, observed: .idle)
        )
        let env = MissionRunEnvironment(mission: mission, assignments: [row])
        XCTAssertTrue(env.setSlotPolicyLanesBoth(assignmentID: aid, terminal: .policySucceeded))
        XCTAssertFalse(env.setSlotPolicyLanesBoth(assignmentID: aid, terminal: .policySucceeded))
    }

    func test_applySlotPolicyPushEvidence_duplicate_success_does_not_append_second_auto_ack_event() {
        let task = MissionTask(name: "Juliet", enabled: true)
        let mission = Mission(name: "M", description: "", type: .mobile, routeMacro: RouteMacro(tasks: [task]))
        let aid = UUID()
        let row = MissionRunAssignment(
            id: aid,
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "S1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policyAborting, observed: .policyAborting)
        )
        let env = MissionRunEnvironment(mission: mission, assignments: [row])
        env.status = .running
        env.setSessionPhase(.executing)
        env.markMissionTaskAbortWindDownIssued(forTaskID: task.id)

        let issued = MissionRunIssuedCommand(
            assignmentID: aid,
            slotName: "S1",
            vehicleTokenKey: "tok",
            dispatch: .catalogue(name: .fleetVehicleDoPark, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        env.applySlotPolicyPushEvidence(issued: issued, success: true)
        let autoAckCount1 = env.events.filter { $0.templateKey == MissionRunLogTemplateKey.slotEvidenceAutoAcknowledgedMissionEndBatch }.count
        XCTAssertEqual(autoAckCount1, 1)

        env.applySlotPolicyPushEvidence(issued: issued, success: true)
        let autoAckCount2 = env.events.filter { $0.templateKey == MissionRunLogTemplateKey.slotEvidenceAutoAcknowledgedMissionEndBatch }.count
        XCTAssertEqual(autoAckCount2, 1)
    }
}
