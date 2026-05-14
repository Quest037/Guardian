import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunSlotLifecycleLaneMutationTests: XCTestCase {

    func test_apply_mutation_idempotent_second_apply_unchanged() {
        let mission = Mission(name: "M", description: "", type: .mobile)
        let aid = UUID()
        let row = MissionRunAssignment(id: aid, rosterDeviceId: UUID(), slotName: "S")
        let env = MissionRunEnvironment(mission: mission, assignments: [row])
        XCTAssertTrue(
            env.applySlotLifecycleLaneMutation(.setCommandedAndObservedToSame(assignmentID: aid, terminal: .policySucceeded))
        )
        XCTAssertFalse(
            env.applySlotLifecycleLaneMutation(.setCommandedAndObservedToSame(assignmentID: aid, terminal: .policySucceeded))
        )
    }

    func test_setSlotPolicyLanesBoth_forwards_to_mutation_writer() {
        let mission = Mission(name: "M", description: "", type: .mobile)
        let aid = UUID()
        let row = MissionRunAssignment(id: aid, rosterDeviceId: UUID(), slotName: "S")
        let env = MissionRunEnvironment(mission: mission, assignments: [row])
        XCTAssertTrue(env.setSlotPolicyLanesBoth(assignmentID: aid, terminal: .policyFailed))
        XCTAssertEqual(
            env.assignments[0].slotLifecycleLanes?.commanded,
            .policyFailed
        )
    }

    func test_sync_observed_non_policy_outcome_idempotent() {
        let mission = Mission(name: "M", description: "", type: .mobile)
        let aid = UUID()
        let row = MissionRunAssignment(id: aid, rosterDeviceId: UUID(), slotName: "S")
        let env = MissionRunEnvironment(mission: mission, assignments: [row])
        env.applySlotLifecycleLaneMutation(.advanceCommandedLaneForDispatchStart(assignmentID: aid, commanded: .executingMission))
        XCTAssertTrue(env.applySlotLifecycleLaneMutation(.syncObservedAfterNonPolicyFleetOutcome(assignmentID: aid, success: true)))
        XCTAssertFalse(env.applySlotLifecycleLaneMutation(.syncObservedAfterNonPolicyFleetOutcome(assignmentID: aid, success: true)))
    }
}
