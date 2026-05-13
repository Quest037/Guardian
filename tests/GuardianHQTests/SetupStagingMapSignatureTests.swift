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
            selectedStagingRosterAssignmentID: nil,
            mcsReservePoolHomePlacementTaskID: nil,
            stagingReservePoolBerthSelectionSignature: ""
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
            selectedStagingRosterAssignmentID: nil,
            mcsReservePoolHomePlacementTaskID: nil,
            stagingReservePoolBerthSelectionSignature: ""
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
            selectedStagingRosterAssignmentID: nil,
            mcsReservePoolHomePlacementTaskID: nil,
            stagingReservePoolBerthSelectionSignature: ""
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
            selectedStagingRosterAssignmentID: UUID(),
            mcsReservePoolHomePlacementTaskID: nil,
            stagingReservePoolBerthSelectionSignature: ""
        )
        XCTAssertNotEqual(a, b)
    }

    func test_mcsReservePoolHomePlacementTaskID_participatesInEquality() {
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
            selectedStagingRosterAssignmentID: nil,
            mcsReservePoolHomePlacementTaskID: nil,
            stagingReservePoolBerthSelectionSignature: ""
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
            selectedStagingRosterAssignmentID: nil,
            mcsReservePoolHomePlacementTaskID: UUID(),
            stagingReservePoolBerthSelectionSignature: ""
        )
        XCTAssertNotEqual(a, b)
    }

    func test_stagingReservePoolBerthSelectionSignature_participatesInEquality() {
        let chrome = MissionControlSetupRosterStagingMissionPointChrome(listTab: .tasks, selectedPointID: nil)
        let t = UUID()
        let s = UUID()
        let a = SetupStagingMapStructureIdentity(
            missionID: nil,
            homeCoord: nil,
            allTasksCoords: [],
            taskPathIDs: [],
            missionPointTopologySignature: "",
            assignmentFleetBindingSignature: "",
            rosterStagingMissionPointChrome: chrome,
            selectedTaskPathID: nil,
            selectedStagingRosterAssignmentID: nil,
            mcsReservePoolHomePlacementTaskID: nil,
            stagingReservePoolBerthSelectionSignature: ""
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
            selectedStagingRosterAssignmentID: nil,
            mcsReservePoolHomePlacementTaskID: nil,
            stagingReservePoolBerthSelectionSignature: "\(t.uuidString)|\(s.uuidString)"
        )
        XCTAssertNotEqual(a, b)
    }
}
