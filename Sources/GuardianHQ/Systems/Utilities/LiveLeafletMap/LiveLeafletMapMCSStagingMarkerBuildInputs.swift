import Foundation

/// Inputs for ``LiveLeafletMapMCSStagingMarkerBuilder`` (MCS roster staging map — SIM drag, pool berths, selection).
@MainActor
struct LiveLeafletMapMCSStagingMarkerBuildInputs {
    var assignments: [MissionRunAssignment]
    var mission: Mission
    var reservePoolsByTaskID: [UUID: MissionRunReservePool]
    var fleetLink: FleetLinkService
    var sitl: SitlService
    var selectedAssignmentID: UUID?
    var selectedReservePoolTaskID: UUID?
    var selectedReservePoolSlotID: UUID?
    var rosterSimDragByAssignmentID: [UUID: MissionRunStagingSimDragOverlay]
    var poolSimDragByMarkerID: [String: MissionRunStagingSimDragOverlay]
    var now: Date = Date()

    static func missionControlSetupStaging(
        run: MissionRunEnvironment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        selectedAssignmentID: UUID?,
        selectedReservePoolTaskID: UUID?,
        selectedReservePoolSlotID: UUID?,
        rosterSimDragByAssignmentID: [UUID: MissionRunStagingSimDragOverlay],
        poolSimDragByMarkerID: [String: MissionRunStagingSimDragOverlay],
        now: Date = Date()
    ) -> LiveLeafletMapMCSStagingMarkerBuildInputs {
        var pools: [UUID: MissionRunReservePool] = [:]
        for task in mission.routeMacro.tasks where task.enabled {
            pools[task.id] = run.reservePool(forTaskID: task.id)
        }
        return LiveLeafletMapMCSStagingMarkerBuildInputs(
            assignments: run.assignments,
            mission: mission,
            reservePoolsByTaskID: pools,
            fleetLink: fleetLink,
            sitl: sitl,
            selectedAssignmentID: selectedAssignmentID,
            selectedReservePoolTaskID: selectedReservePoolTaskID,
            selectedReservePoolSlotID: selectedReservePoolSlotID,
            rosterSimDragByAssignmentID: rosterSimDragByAssignmentID,
            poolSimDragByMarkerID: poolSimDragByMarkerID,
            now: now
        )
    }
}
