import Foundation

// MARK: - Focus & presentation (pure value types)

/// Task-focus filter for roster rows (MC-R triage / map isolation). `nil` includes every assignment.
struct LiveLeafletMapMarkerRosterScope: Equatable, Sendable {
    var taskFocusID: UUID?
}

/// Which tasks contribute **floating reserve pool** hub markers.
struct LiveLeafletMapFloatingReservePoolScope: Equatable, Sendable {
    var taskIDs: [UUID]
}

/// MC-R reserve swap-in picker context for map marker chrome (a11y / selection pulse).
struct LiveLeafletMapReserveSwapPickContext: Equatable, Sendable {
    var vacancyAssignmentID: UUID
    var taskID: UUID
}

/// Focused floating reserve **berth** (pool browser), not a roster assignment row.
struct LiveLeafletMapPoolBerthFocus: Equatable, Sendable {
    var taskID: UUID
    var slotID: UUID
}

/// Reserve-pool marker selection / swap-picker presentation (no hub data).
struct LiveLeafletMapReservePoolPresentationState: Equatable, Sendable {
    var reserveSwapPick: LiveLeafletMapReserveSwapPickContext?
    var eligiblePoolSlotIDsForSwapPick: Set<UUID> = []
    var browsingPoolBerth: LiveLeafletMapPoolBerthFocus?
}

/// Roster marker selection and Live Drive stream highlight.
struct LiveLeafletMapMarkerPresentationState: Equatable, Sendable {
    var selectedAssignmentID: UUID?
    /// Fleet hub stream vehicle id (e.g. Live Drive). When set, matching marker is selected.
    var highlightedFleetVehicleID: String?
    /// When `true`, only the highlighted vehicle shows its slot label on the map.
    var highlightShowsLabel: Bool = false
}

// MARK: - Build inputs

/// Pure inputs for the shared live Leaflet marker builder (Phase B). Holds roster rows, mission template
/// slice, fleet/SITL services for hub + roster art resolution, and focus filters — **no SwiftUI**.
@MainActor
struct LiveLeafletMapMarkerBuildInputs {
    var rosterAssignments: [MissionRunAssignment]
    var mission: Mission
    /// Task id → floating reserve pool envelope (only tasks in ``floatingReservePoolScope`` need entries).
    var reservePoolsByTaskID: [UUID: MissionRunReservePool]
    var fleetLink: FleetLinkService
    var sitl: SitlService
    var rosterScope: LiveLeafletMapMarkerRosterScope
    var floatingReservePoolScope: LiveLeafletMapFloatingReservePoolScope
    var presentation: LiveLeafletMapMarkerPresentationState
    var reservePoolPresentation: LiveLeafletMapReservePoolPresentationState

    /// Roster rows after ``LiveLeafletMapMarkerRosterScope`` filtering.
    var filteredRosterAssignments: [MissionRunAssignment] {
        LiveLeafletMapMarkerFocus.filteredRosterAssignments(
            rosterAssignments,
            mission: mission,
            scope: rosterScope
        )
    }
}

// MARK: - Assembly factories

extension LiveLeafletMapMarkerBuildInputs {

    /// MC-R live overview map (hub markers for roster + floating reserve pool).
    static func missionControlLiveOverview(
        run: MissionRunEnvironment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        isolateMapToSelectedTask: Bool,
        triageFocusedTaskID: UUID?,
        presentation: LiveLeafletMapMarkerPresentationState,
        reservePoolPresentation: LiveLeafletMapReservePoolPresentationState
    ) -> LiveLeafletMapMarkerBuildInputs {
        let mapFocusedTaskID = isolateMapToSelectedTask ? triageFocusedTaskID : nil
        let rosterScope = LiveLeafletMapMarkerRosterScope(
            taskFocusID: mapFocusedTaskID != nil ? triageFocusedTaskID : nil
        )
        let poolScope = LiveLeafletMapFloatingReservePoolScope(
            taskIDs: LiveLeafletMapMarkerFocus.floatingReservePoolTaskIDs(
                mission: mission,
                mapFocusedTaskID: mapFocusedTaskID
            )
        )
        var pools: [UUID: MissionRunReservePool] = [:]
        for tid in poolScope.taskIDs {
            pools[tid] = run.reservePool(forTaskID: tid)
        }
        return LiveLeafletMapMarkerBuildInputs(
            rosterAssignments: run.assignments,
            mission: mission,
            reservePoolsByTaskID: pools,
            fleetLink: fleetLink,
            sitl: sitl,
            rosterScope: rosterScope,
            floatingReservePoolScope: poolScope,
            presentation: presentation,
            reservePoolPresentation: reservePoolPresentation
        )
    }

    /// Live Drive mission overlay (roster + pool markers; highlights the LD stream vehicle).
    static func liveDriveMissionOverlay(
        run: MissionRunEnvironment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        focusedTaskID: UUID?,
        ldStreamVehicleID: String
    ) -> LiveLeafletMapMarkerBuildInputs {
        let poolScope = LiveLeafletMapFloatingReservePoolScope(
            taskIDs: LiveLeafletMapMarkerFocus.floatingReservePoolTaskIDs(
                mission: mission,
                mapFocusedTaskID: focusedTaskID
            )
        )
        var pools: [UUID: MissionRunReservePool] = [:]
        for tid in poolScope.taskIDs {
            pools[tid] = run.reservePool(forTaskID: tid)
        }
        return LiveLeafletMapMarkerBuildInputs(
            rosterAssignments: run.assignments,
            mission: mission,
            reservePoolsByTaskID: pools,
            fleetLink: fleetLink,
            sitl: sitl,
            rosterScope: LiveLeafletMapMarkerRosterScope(taskFocusID: focusedTaskID),
            floatingReservePoolScope: poolScope,
            presentation: LiveLeafletMapMarkerPresentationState(
                highlightedFleetVehicleID: ldStreamVehicleID,
                highlightShowsLabel: true
            ),
            reservePoolPresentation: LiveLeafletMapReservePoolPresentationState()
        )
    }
}

// MARK: - Focus helpers (shared with legacy overlay until Phase C migration)

enum LiveLeafletMapMarkerFocus {

    /// Matches ``MissionControlLiveDriveMapOverlay/assignmentMatchesLiveFocus`` / MC-R triage rules.
    static func assignmentMatchesTaskFocus(
        _ assignment: MissionRunAssignment,
        mission: Mission,
        taskFocusID: UUID?
    ) -> Bool {
        guard let focus = taskFocusID else { return true }
        if assignment.taskId == focus { return true }
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        if enabled.count == 1, enabled.first?.id == focus {
            return assignment.taskId == nil || assignment.taskId == focus
        }
        return false
    }

    static func filteredRosterAssignments(
        _ assignments: [MissionRunAssignment],
        mission: Mission,
        scope: LiveLeafletMapMarkerRosterScope
    ) -> [MissionRunAssignment] {
        guard let focus = scope.taskFocusID else { return assignments }
        return assignments.filter { assignmentMatchesTaskFocus($0, mission: mission, taskFocusID: focus) }
    }

    /// Task ids that supply floating-reserve pool markers (single focused task or all enabled tasks).
    static func floatingReservePoolTaskIDs(mission: Mission, mapFocusedTaskID: UUID?) -> [UUID] {
        if let f = mapFocusedTaskID { return [f] }
        return mission.routeMacro.tasks.filter(\.enabled).map(\.id)
    }
}
