import XCTest
@testable import GuardianHQ

final class SetupStagingMapStructureIdentityTests: XCTestCase {
    func test_selectedTaskPathID_participatesInEquality() {
        let chrome = MissionControlSetupRosterStagingMissionPointChrome(listTab: .tasks, selectedPointID: nil)
        let base = SetupStagingMapStructureIdentity(
            missionID: nil,
            homeCoord: nil,
            allTasksCoords: [],
            taskPathIDs: [],
            missionPointTopologySignature: "",
            assignmentFleetBindingSignature: "",
            rosterStagingMissionPointChrome: chrome,
            selectedTaskPathID: nil,
            selectedStagingRosterAssignmentID: nil
        )
        let withPath = SetupStagingMapStructureIdentity(
            missionID: nil,
            homeCoord: nil,
            allTasksCoords: [],
            taskPathIDs: [],
            missionPointTopologySignature: "",
            assignmentFleetBindingSignature: "",
            rosterStagingMissionPointChrome: chrome,
            selectedTaskPathID: UUID(),
            selectedStagingRosterAssignmentID: nil
        )
        XCTAssertNotEqual(base, withPath)
    }

    func test_selectedStagingRosterAssignmentID_participatesInEquality() {
        let chrome = MissionControlSetupRosterStagingMissionPointChrome(listTab: .tasks, selectedPointID: nil)
        let a = SetupStagingMapStructureIdentity(
            missionID: nil,
            homeCoord: nil,
            allTasksCoords: [],
            taskPathIDs: [],
            missionPointTopologySignature: "",
            assignmentFleetBindingSignature: "",
            rosterStagingMissionPointChrome: chrome,
            selectedTaskPathID: nil,
            selectedStagingRosterAssignmentID: nil
        )
        let b = SetupStagingMapStructureIdentity(
            missionID: nil,
            homeCoord: nil,
            allTasksCoords: [],
            taskPathIDs: [],
            missionPointTopologySignature: "",
            assignmentFleetBindingSignature: "",
            rosterStagingMissionPointChrome: chrome,
            selectedTaskPathID: nil,
            selectedStagingRosterAssignmentID: UUID()
        )
        XCTAssertNotEqual(a, b)
    }
}
