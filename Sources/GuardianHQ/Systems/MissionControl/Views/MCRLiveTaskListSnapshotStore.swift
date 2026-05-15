// MCRLiveTaskListSnapshotStore.swift — MC-R Tasks list: equatable row snapshots + **single-writer** coordinator (``MCRLiveTaskListSnapshotCoordinator``) to limit redundant SwiftUI churn.
import Foundation
import SwiftUI

/// One primary squad row inside a task’s live progress card (compact list layout).
struct MCRLiveTaskListSquadRowSnapshot: Identifiable, Equatable {
    let assignmentID: UUID
    let squadLabel: String
    let displayState: MissionTaskState
    let progressFraction: Double
    /// Active MAVLink start deferral for this squad row (task-level or squad-scoped), when `now < startAt` at snapshot time.
    let activeStartDeferral: MissionTaskStartDeferral?

    var id: UUID { assignmentID }
}

/// Footer chrome below the tappable task summary (deferral controls, trigger, stagger release, end-protocol ack).
enum MCRLiveTaskListRowFooterKind: Equatable {
    case none
    case deferralControls(taskStartDef: MissionTaskStartDeferral)
    case missionTrigger
    case deferredFirstWaveSquadRelease
    case endProtocolAcknowledgement
}

/// Immutable UI payload for one MC-R task progress row; compared on each refresh so unchanged rows skip ``ObservableObject`` churn.
struct MCRLiveTaskListRowSnapshot: Equatable {
    let taskID: UUID
    let taskIndex: Int
    let taskName: String
    let taskEnabled: Bool
    let taskState: MissionTaskState
    let slotAttention: MCRLiveRosterSlotAttentionSnapshot?
    let attemptingState: MissionTaskAttemptState?
    let cyclesLineText: String?
    let waypointsLineText: String
    let showPerSquadBars: Bool
    let inlineTaskDeferralOnSquadRow: Bool
    let squadRows: [MCRLiveTaskListSquadRowSnapshot]
    let showMissionProgressBar: Bool
    let missionProgressFraction: Double
    /// Same as ``MCRLiveTaskListProgressFormatting/MCRLiveTaskProgressCore/triageCombinedBarFraction`` (mission vs scheduled-start countdown) for hero triage when not using per-squad bars.
    let triageCombinedBarFraction: Double
    let inTaskStartDeferral: Bool
    /// Task-level MAVLink start deferral when ``inTaskStartDeferral`` (triage deferral controls + cyan bar styling).
    let liveTaskStartDeferral: MissionTaskStartDeferral?
    let showStandaloneDeferralBlock: Bool
    let taskStartDeferralForStandaloneBlock: MissionTaskStartDeferral?
    let footerKind: MCRLiveTaskListRowFooterKind
}

struct MCRLiveTaskListRowPresentation: Identifiable, Equatable {
    let taskID: UUID
    let taskIndex: Int
    let snapshot: MCRLiveTaskListRowSnapshot

    var id: UUID { taskID }
}

extension MCRLiveTaskListRowSnapshot {
    /// Recomputes primary-path hub fields (mission fraction, triage single-bar fraction, waypoint caption) using ``hub`` as the MAVLink slice for the task’s primary stream.
    @MainActor
    func mergedWithPrimaryPathHubTelemetry(
        _ hub: FleetHubVehicleTelemetry,
        run: MissionRunEnvironment,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        task: RoutePath,
        mission: Mission,
        now: Date
    ) -> MCRLiveTaskListRowSnapshot {
        let core = MCRLiveTaskListProgressFormatting.deriveLiveTaskProgressCore(
            run: run,
            fleetLink: fleetLink,
            sitl: sitl,
            task: task,
            mission: mission,
            now: now,
            primaryHubOverride: hub
        )
        let wpt = MCRLiveTaskListProgressFormatting.waypointsLineText(
            task: task,
            taskActiveInCycle: core.taskActiveInCycle,
            inTaskStartDeferral: core.inTaskStartDeferral,
            hub: core.hub
        )
        return MCRLiveTaskListRowSnapshot(
            taskID: taskID,
            taskIndex: taskIndex,
            taskName: taskName,
            taskEnabled: taskEnabled,
            taskState: taskState,
            slotAttention: slotAttention,
            attemptingState: attemptingState,
            cyclesLineText: cyclesLineText,
            waypointsLineText: wpt,
            showPerSquadBars: showPerSquadBars,
            inlineTaskDeferralOnSquadRow: inlineTaskDeferralOnSquadRow,
            squadRows: squadRows,
            showMissionProgressBar: showMissionProgressBar,
            missionProgressFraction: core.missionProgressFraction,
            triageCombinedBarFraction: core.triageCombinedBarFraction,
            inTaskStartDeferral: inTaskStartDeferral,
            liveTaskStartDeferral: liveTaskStartDeferral,
            showStandaloneDeferralBlock: showStandaloneDeferralBlock,
            taskStartDeferralForStandaloneBlock: taskStartDeferralForStandaloneBlock,
            footerKind: footerKind
        )
    }
}

extension MCRLiveTaskListRowPresentation {
    /// When ``hub`` is non-nil, overlays primary-path mission progress from a ``FleetVehicleLiveChannel`` (narrow fleet observation).
    @MainActor
    func mergedWithPrimaryPathHubTelemetry(
        _ hub: FleetHubVehicleTelemetry?,
        run: MissionRunEnvironment,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        task: RoutePath,
        mission: Mission,
        now: Date
    ) -> MCRLiveTaskListRowPresentation {
        guard let hub else { return self }
        let next = snapshot.mergedWithPrimaryPathHubTelemetry(
            hub,
            run: run,
            fleetLink: fleetLink,
            sitl: sitl,
            task: task,
            mission: mission,
            now: now
        )
        if next == snapshot { return self }
        return MCRLiveTaskListRowPresentation(taskID: taskID, taskIndex: taskIndex, snapshot: next)
    }
}

/// MRE-only inputs for one **primary squad** row under a task (``README_FULL.md`` — *MC-R live UI row contracts*, squad row).
struct MissionRunSquadLiveSlice: Equatable, Identifiable {
    let assignmentID: UUID
    /// Display index from ``MissionRunEnvironment/primarySquads(forTaskID:mission:)`` (same source as ``MissionControlSquadUtilities/squadDisplayName``).
    let squadIndex: Int
    let rawSquadState: MissionSquadState
    let squadCyclesCompleted: Int
    let activeInSquadCycle: Bool
    /// Whether this assignment id appears in ``MissionRunEnvironment/deferredFirstWaveSquadAssignmentIDsByTaskID`` for the task.
    let inDeferredFirstWaveQueue: Bool
    /// Squad-scoped or merged single-primary task deferral active at ``now`` (same rules as ``squadRowStartDeferral``).
    let activeStartDeferral: MissionTaskStartDeferral?

    var id: UUID { assignmentID }
}

/// Task-scoped slice of ``MissionRunEnvironment`` for one ``RoutePath`` / ``MissionTask`` row.
/// Matches ``README_FULL.md`` — *MC-R live UI row contracts* (task list row + embedded primary squad slices). Hub merge for progress bars stays in ``deriveLiveTaskProgressCore``.
struct MissionRunTaskLiveProjection: Equatable {
    let taskID: UUID
    let taskState: MissionTaskState
    let taskAttempting: MissionTaskAttemptState?
    let operatorTriageMarkedState: MissionTaskState?
    let activeInTaskCycle: Bool
    let taskCyclesCompleted: Int
    let taskStartDeferral: MissionTaskStartDeferral?
    /// Primary squads in display order with per-squad MRE fields (small N per task — Equatable diff).
    let primarySquadSlices: [MissionRunSquadLiveSlice]
    let deferredFirstWaveSquadAssignmentIDs: [UUID]
    let abortWindDownIssued: Bool
    let completeWindDownIssued: Bool
    let pendingGracefulWindDownKind: MissionRunMissionTaskGracefulPendingKind?
    let slotAttention: MCRLiveRosterSlotAttentionSnapshot?
    let cyclesLineText: String?
    let showPerSquadBars: Bool
    let boundPrimarySquadsCount: Int
    let showOperatorMissionTrigger: Bool
    let showDeferredFirstWaveRelease: Bool
    let endProtocolAcknowledgementVisible: Bool
}

// MARK: - Formatting & math (shared with list chrome / TimelineView)

@MainActor
enum MCRLiveTaskListProgressFormatting {
    static func formattedTaskStartDeferralStatus(remaining: TimeInterval, totalDelay: TimeInterval) -> String {
        if totalDelay < 1 {
            return remaining > 0.08 ? "Starting mission…" : "Starting mission…"
        }
        if remaining <= 0 {
            return "Starting mission…"
        }
        let secs = max(1, Int(ceil(remaining)))
        let m = secs / 60
        let s = secs % 60
        let clock = String(format: "%d:%02d", m, s)
        return "\(clock) until mission start"
    }

    static func missionTaskStartDeferralBarFraction(taskStartDef: MissionTaskStartDeferral, now: Date) -> Double {
        let remaining = taskStartDef.startAt.timeIntervalSince(now)
        let elapsed = taskStartDef.totalDelay - max(0, remaining)
        if taskStartDef.totalDelay > 0 {
            return min(1, max(0, elapsed / taskStartDef.totalDelay))
        }
        return 1
    }

    static func missionLiveTaskFraction(task: RoutePath, taskActiveInCycle: Bool, hub: FleetHubVehicleTelemetry?) -> Double {
        guard task.enabled, taskActiveInCycle, let hub, let tot = hub.missionProgressTotal, tot > 0,
              let cur = hub.missionProgressCurrent
        else { return 0 }
        let t = Double(tot)
        let c = Double(cur)
        if c >= t { return 1 }
        return min(1, max(0, c / t))
    }

    /// Hub + cycle/deferral + MAVLink mission fraction + triage single-bar fraction (mission vs deferral countdown).
    struct MCRLiveTaskProgressCore: Equatable {
        let hub: FleetHubVehicleTelemetry?
        let taskActiveInCycle: Bool
        let inTaskStartDeferral: Bool
        let taskStartDef: MissionTaskStartDeferral?
        let missionProgressFraction: Double
        let triageCombinedBarFraction: Double
    }

    static func deriveLiveTaskProgressCore(
        run: MissionRunEnvironment,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        task: RoutePath,
        mission: Mission,
        now: Date,
        primaryHubOverride: FleetHubVehicleTelemetry? = nil
    ) -> MCRLiveTaskProgressCore {
        let hub = primaryHubOverride ?? liveHubForTask(run: run, fleetLink: fleetLink, sitl: sitl, task: task, mission: mission)
        let taskActiveInCycle = run.activeCycleTaskIDs.contains(task.id)
        let taskStartDef = run.taskStartDeferralByTaskID[task.id]
        var inTaskStartDeferral = false
        if task.enabled, run.status == .running, let d = taskStartDef, now < d.startAt {
            inTaskStartDeferral = true
        }
        let missionProgressFraction = missionLiveTaskFraction(task: task, taskActiveInCycle: taskActiveInCycle, hub: hub)
        let triageCombinedBarFraction: Double
        if inTaskStartDeferral, let def = taskStartDef {
            triageCombinedBarFraction = missionTaskStartDeferralBarFraction(taskStartDef: def, now: now)
        } else {
            triageCombinedBarFraction = missionProgressFraction
        }
        return MCRLiveTaskProgressCore(
            hub: hub,
            taskActiveInCycle: taskActiveInCycle,
            inTaskStartDeferral: inTaskStartDeferral,
            taskStartDef: taskStartDef,
            missionProgressFraction: missionProgressFraction,
            triageCombinedBarFraction: triageCombinedBarFraction
        )
    }

    static func hubTelemetry(
        forPrimaryAssignment assignment: MissionRunAssignment,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> FleetHubVehicleTelemetry? {
        guard let id = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl) else { return nil }
        return fleetLink.hubTelemetry(forVehicleID: id)
    }

    static func squadProgressFraction(
        run: MissionRunEnvironment,
        assignmentID: UUID,
        task: RoutePath,
        hub: FleetHubVehicleTelemetry?
    ) -> Double {
        let done = run.squadCyclesCompletedByAssignmentID[assignmentID] ?? 0
        if task.cycles > 0 {
            let cap = max(task.cycles, 1)
            if done >= task.cycles { return 1 }
            let base = Double(done) / Double(cap)
            let inSquadCycle = run.activeCycleSquadAssignmentIDs.contains(assignmentID)
            if inSquadCycle, let hub, let tot = hub.missionProgressTotal, tot > 0, let cur = hub.missionProgressCurrent {
                let hubFrac = min(1, max(0, Double(cur) / Double(tot)))
                return min(1, base + (1 / Double(cap)) * hubFrac)
            }
            return min(1, base)
        }
        let inSquadCycle = run.activeCycleSquadAssignmentIDs.contains(assignmentID)
        if inSquadCycle, let hub, let tot = hub.missionProgressTotal, tot > 0, let cur = hub.missionProgressCurrent {
            let t = Double(tot)
            let c = Double(cur)
            return min(1, max(0, c / t))
        }
        return done > 0 ? 1 : 0
    }

    /// Same math as ``squadProgressFraction(run:assignmentID:task:hub:)`` using a pre-captured MRE squad slice (no second dictionary read).
    static func squadProgressFraction(
        slice: MissionRunSquadLiveSlice,
        task: RoutePath,
        hub: FleetHubVehicleTelemetry?
    ) -> Double {
        let done = slice.squadCyclesCompleted
        if task.cycles > 0 {
            let cap = max(task.cycles, 1)
            if done >= task.cycles { return 1 }
            let base = Double(done) / Double(cap)
            if slice.activeInSquadCycle, let hub, let tot = hub.missionProgressTotal, tot > 0, let cur = hub.missionProgressCurrent {
                let hubFrac = min(1, max(0, Double(cur) / Double(tot)))
                return min(1, base + (1 / Double(cap)) * hubFrac)
            }
            return min(1, base)
        }
        if slice.activeInSquadCycle, let hub, let tot = hub.missionProgressTotal, tot > 0, let cur = hub.missionProgressCurrent {
            let t = Double(tot)
            let c = Double(cur)
            return min(1, max(0, c / t))
        }
        return done > 0 ? 1 : 0
    }

    static func squadRowStartDeferral(
        run: MissionRunEnvironment,
        task: RoutePath,
        assignmentID: UUID,
        mission: Mission,
        now: Date
    ) -> MissionTaskStartDeferral? {
        let primaries = run.primarySquads(forTaskID: task.id, mission: mission)
        if let d = run.squadStartDeferralByAssignmentID[assignmentID], now < d.startAt { return d }
        if primaries.count == 1, primaries.first?.assignment.id == assignmentID,
           let d = run.taskStartDeferralByTaskID[task.id], now < d.startAt
        {
            return d
        }
        return nil
    }

    private static func cyclesLineText(task: RoutePath, run: MissionRunEnvironment) -> String? {
        guard task.enabled,
              task.regularity == .continuous || task.regularity == .continuousWithDelay
        else { return nil }
        let done = run.taskCyclesCompletedByTaskID[task.id] ?? 0
        if task.cycles > 0 { return "Cycles: \(done)/\(task.cycles)" }
        return "Cycles: \(done)/∞"
    }

    fileprivate static func waypointsLineText(
        task: RoutePath,
        taskActiveInCycle: Bool,
        inTaskStartDeferral: Bool,
        hub: FleetHubVehicleTelemetry?
    ) -> String {
        guard task.enabled else { return "Waypoints: —" }
        if inTaskStartDeferral { return "Waypoints: —" }
        if taskActiveInCycle, let hub, let tot = hub.missionProgressTotal, tot > 0, let cur = hub.missionProgressCurrent {
            return "Waypoints: \(cur)/\(tot)"
        }
        return "Waypoints: —"
    }

    /// Bridge stream key for this task’s **primary-path** hub (same resolution as live mission progress in ``makeRowSnapshot``).
    static func resolvedPrimaryFleetStreamVehicleID(
        run: MissionRunEnvironment,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        task: RoutePath,
        mission: Mission
    ) -> String? {
        resolvedLiveVehicleID(run: run, fleetLink: fleetLink, sitl: sitl, task: task, mission: mission)
    }

    private static func resolvedLiveVehicleID(
        run: MissionRunEnvironment,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        task: RoutePath,
        mission: Mission
    ) -> String? {
        let assignment =
            run.assignments.first(where: { $0.taskId == task.id })
            ?? {
                let enabled = mission.routeMacro.tasks.filter(\.enabled)
                if enabled.count == 1, enabled.first?.id == task.id {
                    return run.assignments.first(where: { $0.taskId == nil }) ?? run.assignments.first
                }
                return nil
            }()
        guard let assignment else { return nil }
        return resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl)
    }

    private static func liveHubForTask(
        run: MissionRunEnvironment,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        task: RoutePath,
        mission: Mission
    ) -> FleetHubVehicleTelemetry? {
        guard let id = resolvedLiveVehicleID(run: run, fleetLink: fleetLink, sitl: sitl, task: task, mission: mission) else { return nil }
        return fleetLink.hubTelemetry(forVehicleID: id)
    }

    private static func missionLiveTaskSlotAttention(
        run: MissionRunEnvironment,
        task: RoutePath,
        mission: Mission
    ) -> MCRLiveRosterSlotAttentionSnapshot? {
        guard run.status == .running || run.status == .paused || run.status == .recovery else { return nil }
        let rows = run.assignments.filter { run.missionControlAssignmentBelongsToTask($0, task: task, mission: mission) }
        guard let w = MissionControlAssignmentSlotRosterAttention.worstAmongForTaskRow(assignments: rows) else { return nil }
        return MCRLiveRosterSlotAttentionSnapshot(severity: w.severity, title: w.title, help: w.help)
    }

    private static func showMissionTaskTrigger(run: MissionRunEnvironment, task: RoutePath) -> Bool {
        guard run.status == .running, task.enabled, task.regularity == .operatorTriggered else { return false }
        return run.taskStateByTaskID[task.id] != .executing
    }

    private static func showDeferredFirstWaveSquadRelease(run: MissionRunEnvironment, task: RoutePath) -> Bool {
        guard task.enabled else { return false }
        guard run.status == .running, run.sessionPhase == .executing else { return false }
        return !(run.deferredFirstWaveSquadAssignmentIDsByTaskID[task.id] ?? []).isEmpty
    }

    private static func missionLiveTaskEndProtocolAcknowledgementVisible(run: MissionRunEnvironment, task: RoutePath) -> Bool {
        switch run.taskStateByTaskID[task.id] ?? .ready {
        case .recovery, .aborting: return true
        default: return false
        }
    }

    static func makeTaskLiveProjection(
        run: MissionRunEnvironment,
        mission: Mission,
        task: RoutePath,
        now: Date
    ) -> MissionRunTaskLiveProjection {
        let tid = task.id
        let deferred = (run.deferredFirstWaveSquadAssignmentIDsByTaskID[tid] ?? []).sorted { $0.uuidString < $1.uuidString }
        let deferredSet = Set(deferred)
        let primaries = run.primarySquads(forTaskID: tid, mission: mission)
        let squadSlices: [MissionRunSquadLiveSlice] = primaries.map { squad in
            let aid = squad.assignment.id
            return MissionRunSquadLiveSlice(
                assignmentID: aid,
                squadIndex: squad.squadIndex,
                rawSquadState: run.squadStateByAssignmentID[aid] ?? .ready,
                squadCyclesCompleted: run.squadCyclesCompletedByAssignmentID[aid] ?? 0,
                activeInSquadCycle: run.activeCycleSquadAssignmentIDs.contains(aid),
                inDeferredFirstWaveQueue: deferredSet.contains(aid),
                activeStartDeferral: squadRowStartDeferral(
                    run: run,
                    task: task,
                    assignmentID: aid,
                    mission: mission,
                    now: now
                )
            )
        }
        return MissionRunTaskLiveProjection(
            taskID: tid,
            taskState: run.taskStateByTaskID[tid] ?? .ready,
            taskAttempting: run.taskAttemptingByTaskID[tid],
            operatorTriageMarkedState: run.operatorTriageMarkedMissionTaskStateByTaskID[tid],
            activeInTaskCycle: run.activeCycleTaskIDs.contains(tid),
            taskCyclesCompleted: run.taskCyclesCompletedByTaskID[tid] ?? 0,
            taskStartDeferral: run.taskStartDeferralByTaskID[tid],
            primarySquadSlices: squadSlices,
            deferredFirstWaveSquadAssignmentIDs: deferred,
            abortWindDownIssued: run.missionTaskAbortWindDownIssuedTaskIDs.contains(tid),
            completeWindDownIssued: run.missionTaskCompleteWindDownIssuedTaskIDs.contains(tid),
            pendingGracefulWindDownKind: run.pendingMissionTaskGracefulWindDownKindByTaskID[tid],
            slotAttention: missionLiveTaskSlotAttention(run: run, task: task, mission: mission),
            cyclesLineText: cyclesLineText(task: task, run: run),
            showPerSquadBars: !primaries.isEmpty,
            boundPrimarySquadsCount: primaries.count,
            showOperatorMissionTrigger: showMissionTaskTrigger(run: run, task: task),
            showDeferredFirstWaveRelease: showDeferredFirstWaveSquadRelease(run: run, task: task),
            endProtocolAcknowledgementVisible: missionLiveTaskEndProtocolAcknowledgementVisible(run: run, task: task)
        )
    }

    private static func footerKind(
        row: MissionRunTaskLiveProjection,
        inTaskStartDeferral: Bool,
        taskStartDef: MissionTaskStartDeferral?,
        inlineTaskDeferralOnSquadRow: Bool
    ) -> MCRLiveTaskListRowFooterKind {
        if inTaskStartDeferral, let def = taskStartDef, !inlineTaskDeferralOnSquadRow {
            return .deferralControls(taskStartDef: def)
        }
        if row.showOperatorMissionTrigger {
            return .missionTrigger
        }
        if row.showDeferredFirstWaveRelease {
            return .deferredFirstWaveSquadRelease
        }
        if row.endProtocolAcknowledgementVisible {
            return .endProtocolAcknowledgement
        }
        return .none
    }

    static func makeRowSnapshot(
        run: MissionRunEnvironment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        task: RoutePath,
        taskIndex: Int,
        now: Date
    ) -> MCRLiveTaskListRowSnapshot {
        let row = makeTaskLiveProjection(run: run, mission: mission, task: task, now: now)
        let core = deriveLiveTaskProgressCore(
            run: run,
            fleetLink: fleetLink,
            sitl: sitl,
            task: task,
            mission: mission,
            now: now
        )
        let hub = core.hub
        let taskActiveInCycle = core.taskActiveInCycle
        let taskStartDef = core.taskStartDef
        let inTaskStartDeferral = core.inTaskStartDeferral
        let missionProgressFraction = core.missionProgressFraction

        let showPerSquadBars = row.showPerSquadBars
        let inlineTaskDeferralOnSquadRow = showPerSquadBars
            && row.boundPrimarySquadsCount == 1
            && inTaskStartDeferral

        var squadRows: [MCRLiveTaskListSquadRowSnapshot] = []
        if showPerSquadBars {
            let squads = run.primarySquads(forTaskID: task.id, mission: mission)
            precondition(squads.count == row.primarySquadSlices.count)
            squadRows.reserveCapacity(squads.count)
            for (squad, slice) in zip(squads, row.primarySquadSlices) {
                precondition(squad.assignment.id == slice.assignmentID)
                let aHub = hubTelemetry(forPrimaryAssignment: squad.assignment, fleetLink: fleetLink, sitl: sitl)
                let frac = squadProgressFraction(slice: slice, task: task, hub: aHub)
                let displayState = MissionControlSquadUtilities.liveSquadRowDisplayTaskState(
                    taskRollup: row.taskState,
                    squadState: slice.rawSquadState
                )
                squadRows.append(
                    MCRLiveTaskListSquadRowSnapshot(
                        assignmentID: squad.assignment.id,
                        squadLabel: MissionControlSquadUtilities.squadDisplayName(
                            taskName: task.name,
                            squadIndex: squad.squadIndex
                        ),
                        displayState: displayState,
                        progressFraction: frac,
                        activeStartDeferral: slice.activeStartDeferral
                    )
                )
            }
        }

        let showStandaloneDeferralBlock = inTaskStartDeferral && taskStartDef != nil && !inlineTaskDeferralOnSquadRow

        return MCRLiveTaskListRowSnapshot(
            taskID: task.id,
            taskIndex: taskIndex,
            taskName: task.name,
            taskEnabled: task.enabled,
            taskState: row.taskState,
            slotAttention: row.slotAttention,
            attemptingState: row.taskAttempting,
            cyclesLineText: row.cyclesLineText,
            waypointsLineText: waypointsLineText(
                task: task,
                taskActiveInCycle: taskActiveInCycle,
                inTaskStartDeferral: inTaskStartDeferral,
                hub: hub
            ),
            showPerSquadBars: showPerSquadBars,
            inlineTaskDeferralOnSquadRow: inlineTaskDeferralOnSquadRow,
            squadRows: squadRows,
            showMissionProgressBar: !showPerSquadBars,
            missionProgressFraction: missionProgressFraction,
            triageCombinedBarFraction: core.triageCombinedBarFraction,
            inTaskStartDeferral: inTaskStartDeferral,
            liveTaskStartDeferral: inTaskStartDeferral ? taskStartDef : nil,
            showStandaloneDeferralBlock: showStandaloneDeferralBlock,
            taskStartDeferralForStandaloneBlock: showStandaloneDeferralBlock ? taskStartDef : nil,
            footerKind: footerKind(
                row: row,
                inTaskStartDeferral: inTaskStartDeferral,
                taskStartDef: taskStartDef,
                inlineTaskDeferralOnSquadRow: inlineTaskDeferralOnSquadRow
            )
        )
    }

    static func makePresentations(
        run: MissionRunEnvironment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        now: Date
    ) -> [MCRLiveTaskListRowPresentation] {
        var rows: [MCRLiveTaskListRowPresentation] = []
        rows.reserveCapacity(mission.routeMacro.tasks.count)
        for index in mission.routeMacro.tasks.indices {
            let task = mission.routeMacro.tasks[index]
            let snap = makeRowSnapshot(
                run: run,
                mission: mission,
                fleetLink: fleetLink,
                sitl: sitl,
                task: task,
                taskIndex: index,
                now: now
            )
            rows.append(MCRLiveTaskListRowPresentation(taskID: task.id, taskIndex: index, snapshot: snap))
        }
        return rows
    }
}

/// Single writer for MC-R **Tasks** list row snapshots: all materialization goes through ``apply(run:mission:fleetLink:sitl:now:)`` (hub tick + live-root ``onChange`` paths). Optional future: per-row ``@StateObject`` row models if profiling demands (``README_FULL.md`` → **MC-R observation restructure — archived reference (v1 complete)**).
@MainActor
final class MCRLiveTaskListSnapshotCoordinator: ObservableObject {
    @Published private(set) var presentations: [MCRLiveTaskListRowPresentation] = []

    /// Rebuilds row payloads from MRE + mission + fleet hub context; publishes only when ``MCRLiveTaskListRowPresentation`` values differ (Equatable diff).
    func apply(
        run: MissionRunEnvironment,
        mission: Mission?,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        now: Date
    ) {
        guard let mission else {
            setPresentationsIfChanged([])
            return
        }
        let rows = MCRLiveTaskListProgressFormatting.makePresentations(
            run: run,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            now: now
        )
        setPresentationsIfChanged(rows)
    }

    /// Package-internal for tests and rare direct injection; production UI should use ``apply``.
    func setPresentationsIfChanged(_ new: [MCRLiveTaskListRowPresentation]) {
        if new == presentations { return }
        presentations = new
    }
}
