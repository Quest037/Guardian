import XCTest
@testable import GuardianCore

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
        XCTAssertTrue(w?.help.contains("written off") ?? false)
    }

    func test_worstAmong_all_idle_returns_nil() {
        let a = MissionRunAssignment(rosterDeviceId: UUID(), slotName: "A")
        XCTAssertNil(MissionControlAssignmentSlotRosterAttention.worstAmong(assignments: [a]))
    }

    func test_worstAmongForTaskRow_skips_between_cycles_only() {
        let a = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "A",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .betweenCycles, observed: .betweenCycles)
        )
        XCTAssertNotNil(MissionControlAssignmentSlotRosterAttention.worstAmong(assignments: [a]))
        XCTAssertNil(MissionControlAssignmentSlotRosterAttention.worstAmongForTaskRow(assignments: [a]))
    }

    func test_worstAmongForTaskRow_still_surfaces_warning_over_between_cycles() {
        let between = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "B",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .betweenCycles, observed: .betweenCycles)
        )
        let aborting = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "C",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policyAborting, observed: .idle)
        )
        let w = MissionControlAssignmentSlotRosterAttention.worstAmongForTaskRow(assignments: [between, aborting])
        XCTAssertEqual(w?.severity, .warning)
        XCTAssertEqual(w?.title, "Abort in progress")
    }
}
