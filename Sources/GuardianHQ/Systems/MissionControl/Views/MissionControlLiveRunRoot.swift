// MissionControlLiveRunRoot.swift — MC-R live console (running / paused / recovery): hub tick + live snapshot onChange wiring (Phase 1 carve-out from ``MissionRunDetailView``).
import SwiftUI

/// MC-R **Swap in reserve** pick: vacancy roster row + task whose pool / fixed reserve list is being chosen.
struct LiveReserveSwapPickContext: Equatable {
    let vacancyAssignmentID: UUID
    let taskID: UUID
}

/// Shared roster-strip assignment ordering when a task is focused (matches Paladin / store single-task fallback).
@MainActor
enum MCRLiveRosterStripAssignmentFilter {
    static func assignmentMatchesLiveFocus(
        _ assignment: MissionRunAssignment,
        mission: Mission,
        focusedLiveTaskID: UUID?
    ) -> Bool {
        guard let focus = focusedLiveTaskID else { return true }
        if assignment.taskId == focus { return true }
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        if enabled.count == 1, enabled.first?.id == focus {
            return assignment.taskId == nil || assignment.taskId == focus
        }
        return false
    }

    static func filteredAssignments(
        run: MissionRunEnvironment,
        mission: Mission?,
        focusedLiveTaskID: UUID?
    ) -> [MissionRunAssignment] {
        guard let mission else { return Array(run.assignments) }
        return run.assignments.filter { assignmentMatchesLiveFocus($0, mission: mission, focusedLiveTaskID: focusedLiveTaskID) }
    }
}

/// Owns padding + **live-run** reactive hooks for the MC-R console column; content is normally ``MissionRunDetailView``'s `missionLiveConsole`.
///
/// **`run` / `fleetLink` are `let` (not ``@ObservedObject``):** ``MissionRunDetailView`` already observes them; duplicate observation here would register a second subscriber. This view still reads ``run`` / ``fleetLink`` in ``onChange`` keys; parent invalidation drives updates.
///
/// **Central snapshot stores (Phase 5 — hybrid locked):** ``MCRLiveRosterSnapshotStore`` and ``MCRLiveTaskListSnapshotCoordinator`` are ``@StateObject`` here and injected with ``environmentObject`` so descendant roster tiles and task rows observe **only** those publishers for equatable row payloads + ordering; **per-stream** hub-heavy fleet fields use ``FleetVehicleLiveChannel`` (Phase 4) inside row views — not a second ``@ObservedObject`` on the whole ``FleetLinkService`` on each tile.
///
/// **Live mission log strip (Phase 7):** ``MCRLiveMissionLogStripStore`` is owned by ``MissionRunDetailView`` (``@StateObject``) and passed in; this root calls ``ingestFromRun`` on hub tick (after ``onHubTick``), log count, focus, assignments, and mission fingerprint changes.
struct MissionControlLiveRunRoot<Content: View>: View {
    let run: MissionRunEnvironment
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let missionStore: MissionStore
    @ObservedObject var missionLogStripStore: MCRLiveMissionLogStripStore
    @Binding var focusedLiveTaskID: UUID?
    @Binding var liveReserveSwapPick: LiveReserveSwapPickContext?
    @Binding var liveReservePoolBrowseTaskID: UUID?

    @StateObject private var mcrLiveRosterSnapshotStore = MCRLiveRosterSnapshotStore()
    @StateObject private var mcrLiveTaskListSnapshotCoordinator = MCRLiveTaskListSnapshotCoordinator()

    private let content: Content

    let onHubTick: () -> Void
    let onLiveAppear: () -> Void
    let onEvaluateReserveSuggest: () -> Void
    let onFocusedLiveTaskIDChanged: (UUID?) -> Void

    init(
        run: MissionRunEnvironment,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionStore: MissionStore,
        missionLogStripStore: MCRLiveMissionLogStripStore,
        focusedLiveTaskID: Binding<UUID?>,
        liveReserveSwapPick: Binding<LiveReserveSwapPickContext?>,
        liveReservePoolBrowseTaskID: Binding<UUID?>,
        onHubTick: @escaping () -> Void,
        onLiveAppear: @escaping () -> Void,
        onEvaluateReserveSuggest: @escaping () -> Void,
        onFocusedLiveTaskIDChanged: @escaping (UUID?) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.run = run
        self.fleetLink = fleetLink
        self.sitl = sitl
        self.missionStore = missionStore
        self.missionLogStripStore = missionLogStripStore
        _focusedLiveTaskID = focusedLiveTaskID
        _liveReserveSwapPick = liveReserveSwapPick
        _liveReservePoolBrowseTaskID = liveReservePoolBrowseTaskID
        self.content = content()
        self.onHubTick = onHubTick
        self.onLiveAppear = onLiveAppear
        self.onEvaluateReserveSuggest = onEvaluateReserveSuggest
        self.onFocusedLiveTaskIDChanged = onFocusedLiveTaskIDChanged
    }

    private var resolvedMission: Mission? {
        run.template ?? missionStore.missions.first { $0.id == run.missionId }
    }

    /// Cheap fingerprint so template/catalog edits refresh roster + task snapshots without observing the whole ``Mission`` graph.
    private var resolvedMissionFingerprint: String {
        guard let m = resolvedMission else { return "nil:\(run.missionId.uuidString)" }
        var h = Hasher()
        h.combine(m.id)
        h.combine(m.name)
        h.combine(m.cardThumbnailVersion)
        for t in m.routeMacro.tasks {
            h.combine(t.id)
            h.combine(t.enabled)
            h.combine(t.name)
        }
        return String(h.finalize())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .padding(.vertical, GuardianSpacing.denseGutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(mcrLiveRosterSnapshotStore)
        .environmentObject(mcrLiveTaskListSnapshotCoordinator)
        /// Live-run signals only (voice, reserve suggest, slot pull) — not MCS staging SIM-drag map overlays; MC‑R map marker motion uses the live overview digest on the parent detail view.
        .onChange(of: fleetLink.hubFleetTelemetryTick) { _ in
            refreshMcrLiveTaskListSnapshotsIfNeeded()
            onHubTick()
            refreshMcrLiveMissionLogStripIfNeeded()
            DispatchQueue.main.async {
                refreshMcrLiveRosterStripSnapshotsIfNeeded()
            }
        }
        .onAppear {
            refreshMcrLiveRosterStripSnapshotsIfNeeded()
            refreshMcrLiveTaskListSnapshotsIfNeeded()
            refreshMcrLiveMissionLogStripIfNeeded()
            onLiveAppear()
        }
        .onChange(of: run.events.count) { _ in
            onEvaluateReserveSuggest()
            refreshMcrLiveMissionLogStripIfNeeded()
        }
        .onChange(of: run.sessionPhase) { _ in
            onEvaluateReserveSuggest()
        }
        .onChange(of: run.taskStateByTaskID) { _ in
            onEvaluateReserveSuggest()
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: focusedLiveTaskID) { newID in
            onFocusedLiveTaskIDChanged(newID)
            refreshMcrLiveRosterStripSnapshotsIfNeeded()
            refreshMcrLiveTaskListSnapshotsIfNeeded()
            refreshMcrLiveMissionLogStripIfNeeded()
        }
        .onChange(of: liveReserveSwapPick) { _ in
            refreshMcrLiveRosterStripSnapshotsIfNeeded()
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: liveReservePoolBrowseTaskID) { _ in
            refreshMcrLiveRosterStripSnapshotsIfNeeded()
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: run.assignments) { _ in
            refreshMcrLiveRosterStripSnapshotsIfNeeded()
            refreshMcrLiveTaskListSnapshotsIfNeeded()
            refreshMcrLiveMissionLogStripIfNeeded()
        }
        .onChange(of: run.squadFollowStatusRevision) { _ in
            refreshMcrLiveRosterStripSnapshotsIfNeeded()
        }
        .onChange(of: run.missionRunRosterReleasedAssignmentIDs) { _ in
            refreshMcrLiveRosterStripSnapshotsIfNeeded()
        }
        .onChange(of: run.taskAttemptingByTaskID) { _ in
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: run.taskStartDeferralByTaskID) { _ in
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: run.squadStartDeferralByAssignmentID) { _ in
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: run.squadStateByAssignmentID) { _ in
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: run.activeCycleTaskIDs) { _ in
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: run.activeCycleSquadAssignmentIDs) { _ in
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: run.deferredFirstWaveSquadAssignmentIDsByTaskID) { _ in
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: run.squadCyclesCompletedByAssignmentID) { _ in
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: run.status) { _ in
            refreshMcrLiveRosterStripSnapshotsIfNeeded()
            refreshMcrLiveTaskListSnapshotsIfNeeded()
        }
        .onChange(of: resolvedMissionFingerprint) { _ in
            refreshMcrLiveRosterStripSnapshotsIfNeeded()
            refreshMcrLiveTaskListSnapshotsIfNeeded()
            refreshMcrLiveMissionLogStripIfNeeded()
        }
    }

    /// Recomputes the MC-R live log strip tail (task filter + last 80 lines); publishes only when the tail differs.
    private func refreshMcrLiveMissionLogStripIfNeeded() {
        missionLogStripStore.ingestFromRun(run, mission: resolvedMission, focusedTaskID: focusedLiveTaskID)
    }

    /// Rebuilds equatable MC-R roster strip snapshots; only ``mcrLiveRosterSnapshotStore`` publishes when tile payloads differ.
    private func refreshMcrLiveRosterStripSnapshotsIfNeeded() {
        guard run.status == .running || run.status == .paused || run.status == .recovery else {
            mcrLiveRosterSnapshotStore.setPresentationsIfChanged([])
            return
        }
        if liveReserveSwapPick != nil || liveReservePoolBrowseTaskID != nil {
            mcrLiveRosterSnapshotStore.setPresentationsIfChanged([])
            return
        }
        let mission = resolvedMission
        let assignments = MCRLiveRosterStripAssignmentFilter.filteredAssignments(
            run: run,
            mission: mission,
            focusedLiveTaskID: focusedLiveTaskID
        )
        let rows: [MCRLiveRosterRowPresentation] = assignments.map { a in
            let projection = MissionRunAssignmentLiveProjection.make(
                assignment: a,
                mission: mission,
                fleetLink: fleetLink,
                sitl: sitl,
                liveReserveSwapPick: liveReserveSwapPick,
                focusedLiveTaskID: focusedLiveTaskID
            )
            return MCRLiveRosterRowPresentation(
                assignmentID: a.id,
                assignmentProjection: projection,
                snapshot: MCRLiveRosterRowSnapshotFactory.make(
                    projection: projection,
                    assignment: a,
                    mission: mission,
                    run: run,
                    runStatus: run.status,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    liveReserveSwapPick: liveReserveSwapPick,
                    focusedLiveTaskID: focusedLiveTaskID
                )
            )
        }
        mcrLiveRosterSnapshotStore.setPresentationsIfChanged(rows)
    }

    /// Rebuilds equatable MC-R **Tasks** list snapshots via ``mcrLiveTaskListSnapshotCoordinator`` (single writer); publishes only when row payloads differ.
    private func refreshMcrLiveTaskListSnapshotsIfNeeded() {
        mcrLiveTaskListSnapshotCoordinator.apply(
            run: run,
            mission: resolvedMission,
            fleetLink: fleetLink,
            sitl: sitl,
            now: Date()
        )
    }
}
