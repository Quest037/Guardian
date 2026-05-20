import XCTest
@testable import GuardianCore

@MainActor
final class MCRLiveTaskListPrimaryHubMergeTests: XCTestCase {

    private func singlePrimaryTaskMission() -> (Mission, MissionRunEnvironment, MissionTask, MissionRunAssignment) {
        let rd = UUID()
        let task = MissionTask(
            name: "Alpha",
            enabled: true,
            cycles: 0,
            regularity: .continuous,
            rosterDeviceIds: [rd]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assign = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Alpha:1",
            attachedFleetVehicleToken: "legacy:1"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [assign])
        return (mission, run, task, assign)
    }

    func test_snapshot_mergedWithPrimaryPathHubTelemetry_updates_mission_fraction_and_waypoints_line() {
        let (mission, run, task, assign) = singlePrimaryTaskMission()
        run.status = .running
        run.setSessionPhase(.executing)
        run.markSquadActiveInCurrentCycle(assign.id)
        run.refreshDerivedTaskStates()

        let fleet = FleetLinkService()
        let sitl = SitlService()
        let now = Date()

        var hub = FleetHubVehicleTelemetry.empty
        hub.missionProgressCurrent = 3
        hub.missionProgressTotal = 10

        let base = MCRLiveTaskListRowSnapshot(
            taskID: task.id,
            taskIndex: 0,
            taskName: task.name,
            taskEnabled: true,
            taskState: .executing,
            slotAttention: nil,
            attemptingState: nil,
            cyclesLineText: nil,
            waypointsLineText: "Waypoints: —",
            showPerSquadBars: true,
            inlineTaskDeferralOnSquadRow: false,
            squadRows: [],
            showMissionProgressBar: false,
            missionProgressFraction: 0,
            triageCombinedBarFraction: 0,
            inTaskStartDeferral: false,
            liveTaskStartDeferral: nil,
            showStandaloneDeferralBlock: false,
            taskStartDeferralForStandaloneBlock: nil,
            footerKind: .none
        )

        let merged = base.mergedWithPrimaryPathHubTelemetry(
            hub,
            run: run,
            fleetLink: fleet,
            sitl: sitl,
            task: task,
            mission: mission,
            now: now
        )

        XCTAssertEqual(merged.missionProgressFraction, 0.3, accuracy: 0.0001)
        XCTAssertEqual(merged.triageCombinedBarFraction, 0.3, accuracy: 0.0001)
        XCTAssertEqual(merged.waypointsLineText, "Waypoints: 3/10")
        XCTAssertEqual(merged.taskName, base.taskName)
        XCTAssertEqual(merged.squadRows, base.squadRows)
    }

    func test_presentation_mergedWithPrimaryPathHubTelemetry_nil_is_identity() {
        let (mission, run, task, _) = singlePrimaryTaskMission()

        let baseSnap = MCRLiveTaskListRowSnapshot(
            taskID: task.id,
            taskIndex: 0,
            taskName: task.name,
            taskEnabled: true,
            taskState: .executing,
            slotAttention: nil,
            attemptingState: nil,
            cyclesLineText: nil,
            waypointsLineText: "Waypoints: —",
            showPerSquadBars: false,
            inlineTaskDeferralOnSquadRow: false,
            squadRows: [],
            showMissionProgressBar: true,
            missionProgressFraction: 0.2,
            triageCombinedBarFraction: 0.2,
            inTaskStartDeferral: false,
            liveTaskStartDeferral: nil,
            showStandaloneDeferralBlock: false,
            taskStartDeferralForStandaloneBlock: nil,
            footerKind: .none
        )
        let row = MCRLiveTaskListRowPresentation(taskID: task.id, taskIndex: 0, snapshot: baseSnap)
        let fleet = FleetLinkService()
        let sitl = SitlService()
        let out = row.mergedWithPrimaryPathHubTelemetry(
            nil,
            run: run,
            fleetLink: fleet,
            sitl: sitl,
            task: task,
            mission: mission,
            now: Date()
        )
        XCTAssertEqual(out, row)
    }
}
