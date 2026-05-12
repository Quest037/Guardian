import XCTest
@testable import GuardianHQ

final class MissionRunAssignmentSlotMissionControlRosterDisplayTests: XCTestCase {

    func test_badge_severity_idle_and_empty_slot_nil() {
        XCTAssertNil(MissionRunAssignmentSlotState.idle.missionControlRosterBadgeSeverity)
        XCTAssertNil(MissionRunAssignmentSlotState.notApplicableEmptySlot.missionControlRosterBadgeSeverity)
    }

    func test_badge_severity_policy_aborting_warning() {
        XCTAssertEqual(MissionRunAssignmentSlotState.policyAborting.missionControlRosterBadgeSeverity, .warning)
    }

    func test_badge_severity_failures_error() {
        XCTAssertEqual(MissionRunAssignmentSlotState.policyFailed.missionControlRosterBadgeSeverity, .error)
        XCTAssertEqual(MissionRunAssignmentSlotState.blockedNoVehicle.missionControlRosterBadgeSeverity, .error)
    }

    func test_worstAmong_prefers_error_over_warning() {
        let a = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "A",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policyAborting, observed: .idle)
        )
        let b = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "B",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .blockedNoVehicle, observed: .idle)
        )
        let w = MissionControlAssignmentSlotRosterAttention.worstAmong(assignments: [a, b])
        XCTAssertEqual(w?.severity, .error)
        XCTAssertEqual(w?.title, "No vehicle bound")
    }

    func test_worstAmong_all_idle_returns_nil() {
        let a = MissionRunAssignment(rosterDeviceId: UUID(), slotName: "A")
        XCTAssertNil(MissionControlAssignmentSlotRosterAttention.worstAmong(assignments: [a]))
    }
}
