import XCTest
@testable import GuardianHQ

final class SetupStagingMapStructureIdentityTests: XCTestCase {
    private func chrome(_ tab: MissionControlSetupRostersSidebarTab = .tasks, point: UUID? = nil) -> MissionControlSetupRosterStagingMissionPointChrome {
        MissionControlSetupRosterStagingMissionPointChrome(listTab: tab, selectedPointID: point)
    }

    func test_selectedTaskPathID_participatesInEquality() {
        let base = SetupStagingMapStructureIdentity(
            missionID: nil,
            homeCoord: nil,
            allTasksCoords: [],
            taskPathIDs: [],
            missionPointTopologySignature: "",
            assignmentFleetBindingSignature: "",
            rosterStagingMissionPointChrome: chrome(),
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
            rosterStagingMissionPointChrome: chrome(),
            selectedTaskPathID: UUID(),
            selectedStagingRosterAssignmentID: nil,
            mcsReservePoolHomePlacementTaskID: nil,
            stagingReservePoolBerthSelectionSignature: ""
        )
        XCTAssertNotEqual(base, withPath)
    }

    func test_selectedStagingRosterAssignmentID_participatesInEquality() {
        let a = SetupStagingMapStructureIdentity(
            missionID: nil,
            homeCoord: nil,
            allTasksCoords: [],
            taskPathIDs: [],
            missionPointTopologySignature: "",
            assignmentFleetBindingSignature: "",
            rosterStagingMissionPointChrome: chrome(),
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
            rosterStagingMissionPointChrome: chrome(),
            selectedTaskPathID: nil,
            selectedStagingRosterAssignmentID: UUID(),
            mcsReservePoolHomePlacementTaskID: nil,
            stagingReservePoolBerthSelectionSignature: ""
        )
        XCTAssertNotEqual(a, b)
    }

    func test_mcsReservePoolHomePlacementTaskID_participatesInEquality() {
        let a = SetupStagingMapStructureIdentity(
            missionID: nil,
            homeCoord: nil,
            allTasksCoords: [],
            taskPathIDs: [],
            missionPointTopologySignature: "",
            assignmentFleetBindingSignature: "",
            rosterStagingMissionPointChrome: chrome(),
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
            rosterStagingMissionPointChrome: chrome(),
            selectedTaskPathID: nil,
            selectedStagingRosterAssignmentID: nil,
            mcsReservePoolHomePlacementTaskID: UUID(),
            stagingReservePoolBerthSelectionSignature: ""
        )
        XCTAssertNotEqual(a, b)
    }

    func test_stagingReservePoolBerthSelectionSignature_participatesInEquality() {
        let t = UUID()
        let s = UUID()
        let a = SetupStagingMapStructureIdentity(
            missionID: nil,
            homeCoord: nil,
            allTasksCoords: [],
            taskPathIDs: [],
            missionPointTopologySignature: "",
            assignmentFleetBindingSignature: "",
            rosterStagingMissionPointChrome: chrome(),
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
            rosterStagingMissionPointChrome: chrome(),
            selectedTaskPathID: nil,
            selectedStagingRosterAssignmentID: nil,
            mcsReservePoolHomePlacementTaskID: nil,
            stagingReservePoolBerthSelectionSignature: "\(t.uuidString)|\(s.uuidString)"
        )
        XCTAssertNotEqual(a, b)
    }

    /// Fence map selection is intentionally **not** part of ``MissionControlSetupRosterStagingMissionPointChrome`` so MCS
    /// staging map ``.task(id:)`` does not refit when the operator highlights a different fence row.
    func test_roster_staging_chrome_is_tab_and_mission_point_only() {
        let a = MissionControlSetupRosterStagingMissionPointChrome(listTab: .fences, selectedPointID: nil)
        let b = MissionControlSetupRosterStagingMissionPointChrome(listTab: .fences, selectedPointID: nil)
        XCTAssertEqual(a, b)
    }
}
