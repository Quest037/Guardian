import XCTest
@testable import GuardianHQ

final class MissionRunSlotEvidenceAutoMissionEndAckRulesTests: XCTestCase {

    func test_boundRosterRowsBlocking_empty_when_all_policy_succeeded() {
        let rid = UUID()
        let rows = [
            MissionRunAssignment(
                rosterDeviceId: rid,
                slotName: "Alpha",
                slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policySucceeded, observed: .policySucceeded)
            ),
        ]
        XCTAssertTrue(MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded(rows))
        XCTAssertTrue(MissionRunSlotEvidenceAutoMissionEndAckRules.boundRosterRowsBlockingAutoMissionEndAck(rows).isEmpty)
    }

    func test_boundRosterRowsBlocking_lists_non_succeeded_sorted_by_slot_name() {
        let idSlow = UUID()
        let idFast = UUID()
        let rows = [
            MissionRunAssignment(
                id: idSlow,
                rosterDeviceId: UUID(),
                slotName: "Zebra",
                slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .executingMission, observed: .executingMission)
            ),
            MissionRunAssignment(
                id: idFast,
                rosterDeviceId: UUID(),
                slotName: "Alpha",
                slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .blockedNoVehicle, observed: .idle)
            ),
        ]
        let b = MissionRunSlotEvidenceAutoMissionEndAckRules.boundRosterRowsBlockingAutoMissionEndAck(rows)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b[0].slotName, "Alpha")
        XCTAssertEqual(b[0].mergedState, .blockedNoVehicle)
        XCTAssertEqual(b[1].slotName, "Zebra")
        XCTAssertEqual(b[1].mergedState, .executingMission)
    }

    func test_boundRosterRowsBlocking_blank_slot_name_becomes_roster_slot_label() {
        let rows = [
            MissionRunAssignment(
                rosterDeviceId: UUID(),
                slotName: "   ",
                slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(commanded: .policyFailed, observed: .policyFailed)
            ),
        ]
        let b = MissionRunSlotEvidenceAutoMissionEndAckRules.boundRosterRowsBlockingAutoMissionEndAck(rows)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0].slotName, "Roster slot")
        XCTAssertEqual(b[0].mergedState, .policyFailed)
    }
}
