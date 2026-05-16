import Foundation

/// Primary-squad ordering and ``TaskName:1`` display labels for planner / MRE / logs.
enum MissionControlSquadUtilities {
    /// 1-based squad label under a task, e.g. **Dagger:1**.
    static func squadDisplayName(taskName: String, squadIndex: Int) -> String {
        let base = taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = base.isEmpty ? "Task" : base
        return "\(name):\(squadIndex + 1)"
    }

    /// Task id + squad label for run logs and map chrome.
    static func squadLogContext(
        taskID: UUID,
        taskName: String,
        squadIndex: Int
    ) -> (id: UUID, label: String) {
        (taskID, squadDisplayName(taskName: taskName, squadIndex: squadIndex))
    }

    /// Bound primary roster rows for a task in template ``MissionTask/rosterDeviceIds`` order.
    static func orderedPrimarySquads(
        task: MissionTask,
        assignments: [MissionRunAssignment],
        rosterDevices: [RosterDevice],
        enabledTaskCount: Int
    ) -> [(assignment: MissionRunAssignment, primary: RosterDevice)] {
        let rosterByID = Dictionary(uniqueKeysWithValues: rosterDevices.map { ($0.id, $0) })
        let rosterOrder = Dictionary(uniqueKeysWithValues: task.rosterDeviceIds.enumerated().map { ($1, $0) })
        let primaries = assignments.compactMap { assignment -> (MissionRunAssignment, RosterDevice)? in
            guard assignmentMatchesTask(assignment, task: task, enabledTaskCount: enabledTaskCount) else { return nil }
            guard assignment.attachedFleetVehicleToken != nil else { return nil }
            guard let rosterDevice = rosterByID[assignment.rosterDeviceId], rosterDevice.slot == .primary else { return nil }
            return (assignment, rosterDevice)
        }
        return primaries.sorted { lhs, rhs in
            let li = rosterOrder[lhs.1.id] ?? Int.max
            let ri = rosterOrder[rhs.1.id] ?? Int.max
            if li != ri { return li < ri }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }
    }

    /// Count of bound primaries per task id (squad cardinality for plan topology).
    static func boundPrimaryCountByTaskID(
        mission: Mission,
        assignments: [MissionRunAssignment]
    ) -> [UUID: Int] {
        let enabledTasks = mission.routeMacro.tasks.filter(\.enabled)
        var counts: [UUID: Int] = [:]
        let rosterByID = Dictionary(uniqueKeysWithValues: mission.rosterDevices.map { ($0.id, $0) })
        for assignment in assignments {
            guard assignment.attachedFleetVehicleToken != nil,
                  let device = rosterByID[assignment.rosterDeviceId],
                  device.slot == .primary
            else { continue }
            guard let taskID = resolvedTaskID(for: assignment, enabledTasks: enabledTasks) else { continue }
            counts[taskID, default: 0] += 1
        }
        return counts
    }

    private static func assignmentMatchesTask(
        _ assignment: MissionRunAssignment,
        task: MissionTask,
        enabledTaskCount: Int
    ) -> Bool {
        if assignment.taskId == task.id { return true }
        if assignment.taskId == nil, enabledTaskCount == 1 { return true }
        return false
    }

    private static func resolvedTaskID(
        for assignment: MissionRunAssignment,
        enabledTasks: [MissionTask]
    ) -> UUID? {
        if let tid = assignment.taskId { return tid }
        if enabledTasks.count == 1 { return enabledTasks.first?.id }
        return nil
    }

    /// When this roster row is a **bound primary** on a path with **multiple** primaries, returns that squad’s task id and **Task:1** chip label for MC‑R live log chips / ``MissionRunLoggingSubsystem/effectiveTaskFields``.
    static func liveLogPrimarySquadTaskChipIfApplicable(
        assignmentID: UUID,
        mission: Mission,
        assignments: [MissionRunAssignment]
    ) -> (taskID: UUID, chipLabel: String)? {
        guard let row = assignments.first(where: { $0.id == assignmentID }) else { return nil }
        let enabledTasks = mission.routeMacro.tasks.filter(\.enabled)
        let enabledCount = enabledTasks.count
        guard let taskID = resolvedTaskID(for: row, enabledTasks: enabledTasks),
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
              task.enabled
        else { return nil }
        let primaries = orderedPrimarySquads(
            task: task,
            assignments: assignments,
            rosterDevices: mission.rosterDevices,
            enabledTaskCount: enabledCount
        )
        guard primaries.count > 1,
              let idx = primaries.firstIndex(where: { $0.assignment.id == assignmentID })
        else { return nil }
        return (task.id, squadDisplayName(taskName: task.name, squadIndex: idx))
    }

    /// Bridges ``MissionSquadState`` to ``MissionTaskState`` for live UI (same mapping as MC-R triage).
    static func missionTaskStateBridgedFromSquadState(_ state: MissionSquadState) -> MissionTaskState {
        switch state {
        case .ready: return .ready
        case .staging: return .staging
        case .executing: return .executing
        case .between: return .between
        case .paused: return .between
        case .recovery: return .recovery
        case .aborting: return .aborting
        case .aborted: return .aborted
        case .completed: return .completed
        }
    }

    /// Per-squad MC-R row label uses **that squad’s** derived state (multi-primary finite-cycle “race”: the task rollup
    /// can lag behind or differ while other primaries are still executing).
    static func liveSquadRowDisplayTaskState(taskRollup _: MissionTaskState, squadState: MissionSquadState) -> MissionTaskState {
        missionTaskStateBridgedFromSquadState(squadState)
    }
}

/// MC-R task triage: which mission-end wind-down chrome rows appear for a settled task or squad lifecycle label.
enum MissionControlMissionEndWindDownControlVisibility {
    /// Abort now / after-cycle controls (may still be disabled by run gates).
    static func showsAbortOptions(for squadState: MissionSquadState) -> Bool {
        switch squadState {
        case .aborting, .aborted:
            return false
        default:
            return true
        }
    }

    /// Complete now / after-cycle controls (may still be disabled by run gates).
    static func showsCompleteOptions(for squadState: MissionSquadState) -> Bool {
        switch squadState {
        case .executing, .ready, .staging, .between:
            return true
        case .paused, .recovery, .completed, .aborting, .aborted:
            return false
        }
    }

    static func showsAbortOptions(for taskState: MissionTaskState) -> Bool {
        switch taskState {
        case .aborting, .aborted:
            return false
        default:
            return true
        }
    }

    static func showsCompleteOptions(for taskState: MissionTaskState) -> Bool {
        switch taskState {
        case .executing, .compiling, .ready, .staging, .between:
            return true
        case .recovery, .completed, .aborting, .aborted:
            return false
        }
    }

    /// MC-R triage path-level **Abort Task** row: hidden while abort-after-cycle is scheduled for this path (or a squad on it).
    static func showsTaskPathAbortWindDownCard(
        protocolShowsAbort: Bool,
        taskPending: MissionRunMissionTaskGracefulPendingKind?,
        anySquadGracefulPending: Bool
    ) -> Bool {
        guard protocolShowsAbort, !anySquadGracefulPending else { return false }
        return taskPending != .abortAfterCycle
    }

    /// MC-R triage path-level **Complete Task** row: hidden while complete-after-cycle is scheduled, or while abort-after-cycle is scheduled (abort locks out all wind-down cards).
    static func showsTaskPathCompleteWindDownCard(
        protocolShowsComplete: Bool,
        taskPending: MissionRunMissionTaskGracefulPendingKind?,
        anySquadGracefulPending: Bool
    ) -> Bool {
        guard protocolShowsComplete, !anySquadGracefulPending else { return false }
        switch taskPending {
        case .abortAfterCycle, .completeAfterCycle:
            return false
        case nil:
            return true
        }
    }

    /// MC-R triage per-squad Abort / Complete rows: complete hides on complete-after-cycle; **both** hide on abort-after-cycle (squad or path-wide).
    static func showsSquadAbortWindDownCard(
        protocolShowsAbort: Bool,
        squadPending: MissionRunMissionTaskGracefulPendingKind?,
        taskPending: MissionRunMissionTaskGracefulPendingKind?
    ) -> Bool {
        guard protocolShowsAbort else { return false }
        if squadPending == .abortAfterCycle || taskPending == .abortAfterCycle { return false }
        return true
    }

    static func showsSquadCompleteWindDownCard(
        protocolShowsComplete: Bool,
        squadPending: MissionRunMissionTaskGracefulPendingKind?,
        taskPending: MissionRunMissionTaskGracefulPendingKind?
    ) -> Bool {
        guard protocolShowsComplete else { return false }
        if squadPending == .abortAfterCycle || taskPending == .abortAfterCycle { return false }
        if squadPending == .completeAfterCycle || taskPending == .completeAfterCycle { return false }
        return true
    }

    /// MC-R triage scheduled after-cycle banner title (path-wide or per-squad).
    static func scheduledEndPolicyNoticeTitle(for kind: MissionRunMissionTaskGracefulPendingKind) -> String {
        switch kind {
        case .abortAfterCycle:
            return "Scheduled abort policy"
        case .completeAfterCycle:
            return "Scheduled complete policy"
        }
    }

    /// Prefer path-wide pending; otherwise any squad abort, then any squad complete.
    static func resolvedScheduledGracefulNoticeKind(
        taskPending: MissionRunMissionTaskGracefulPendingKind?,
        squadPendings: [MissionRunMissionTaskGracefulPendingKind]
    ) -> MissionRunMissionTaskGracefulPendingKind? {
        if let taskPending { return taskPending }
        if squadPendings.contains(.abortAfterCycle) { return .abortAfterCycle }
        if squadPendings.contains(.completeAfterCycle) { return .completeAfterCycle }
        return nil
    }
}

/// What a single **Trigger next squad** press does for an operator-triggered task.
enum MissionControlOperatorTriggerNextSquadAction: Equatable {
    /// First path start: lead primary only; following primaries enter the first-wave deferral queue per stagger policy.
    case coldStartTask
    /// One primary’s next MAVLink lap (lead between cycles, or a non-deferred primary after the first wave).
    case launchPrimary(UUID)
    /// Release the head of ``MissionRunEnvironment/deferredFirstWaveSquadAssignmentIDsByTaskID`` (stagger **operator starts each squad**).
    case releaseDeferredFirstWaveHead(UUID)
}

/// MC-R operator-triggered tasks: visibility and **one** primary per button press (task trigger vs first-wave stagger).
@MainActor
enum MissionControlOperatorTriggerNextSquadPolicy {
    static func showsTriggerButton(
        run: MissionRunEnvironment,
        task: MissionTask,
        mission: Mission,
        now: Date = Date()
    ) -> Bool {
        nextLaunchAction(run: run, task: task, mission: mission, now: now) != nil
    }

    /// Next single action when the operator presses **Trigger next squad** (nil = hide control).
    static func nextLaunchAction(
        run: MissionRunEnvironment,
        task: MissionTask,
        mission: Mission,
        now: Date = Date()
    ) -> MissionControlOperatorTriggerNextSquadAction? {
        guard task.enabled, task.regularity == .operatorTriggered else { return nil }
        guard run.status == .running, run.sessionPhase == .executing else { return nil }

        let primaries = run.primarySquads(forTaskID: task.id, mission: mission)
        guard !primaries.isEmpty else { return nil }

        if isColdStart(run: run, task: task, mission: mission) {
            return .coldStartTask
        }

        // First-wave stagger: release queued primaries before offering the lead’s next lap while the queue
        // still holds squads waiting for operator release (avoids relaunching the lead when squad 2+ are ready).
        if task.staggerTrigger.defersSubsequentPrimariesInFirstWave {
            let deferred = run.deferredFirstWaveSquadAssignmentIDsByTaskID[task.id] ?? []
            if let head = deferred.first,
               let squad = primaries.first(where: { $0.assignment.id == head }),
               isPrimaryEligible(run: run, task: task, mission: mission, squad: squad, now: now)
            {
                return .releaseDeferredFirstWaveHead(head)
            }
        }

        if let lead = primaries.first,
           isLeadEligibleForOperatorLap(run: run, task: task, mission: mission, squad: lead, now: now)
        {
            return .launchPrimary(lead.assignment.id)
        }

        for squad in primaries.dropFirst() {
            let aid = squad.assignment.id
            let deferred = run.deferredFirstWaveSquadAssignmentIDsByTaskID[task.id] ?? []
            if deferred.contains(aid) { continue }
            guard (run.squadCyclesCompletedByAssignmentID[aid] ?? 0) > 0 else { continue }
            if isPrimaryEligible(run: run, task: task, mission: mission, squad: squad, now: now) {
                return .launchPrimary(aid)
            }
        }

        return nil
    }

    /// First lap for the path: no squad has completed a MAVLink cycle yet and none are in-flight.
    static func isColdStart(
        run: MissionRunEnvironment,
        task: MissionTask,
        mission: Mission
    ) -> Bool {
        let primaries = run.primarySquads(forTaskID: task.id, mission: mission)
        guard !primaries.isEmpty else { return false }
        let noneActive = primaries.allSatisfy {
            !run.activeCycleSquadAssignmentIDs.contains($0.assignment.id)
        }
        let allZero = primaries.allSatisfy {
            (run.squadCyclesCompletedByAssignmentID[$0.assignment.id] ?? 0) == 0
        }
        return noneActive && allZero
    }

    private static func isLeadEligibleForOperatorLap(
        run: MissionRunEnvironment,
        task: MissionTask,
        mission: Mission,
        squad: (assignment: MissionRunAssignment, squadIndex: Int),
        now: Date
    ) -> Bool {
        guard squad.squadIndex == 0 else { return false }
        return isPrimaryEligible(run: run, task: task, mission: mission, squad: squad, now: now)
    }

    private static func isPrimaryEligible(
        run: MissionRunEnvironment,
        task: MissionTask,
        mission: Mission,
        squad: (assignment: MissionRunAssignment, squadIndex: Int),
        now: Date
    ) -> Bool {
        let aid = squad.assignment.id
        if run.activeCycleSquadAssignmentIDs.contains(aid) { return false }
        if run.shouldSuppressAutopilotAutostart(forSquadAssignmentID: aid, taskID: task.id, mission: mission) {
            return false
        }
        if let def = run.squadStartDeferralByAssignmentID[aid], now < def.startAt { return false }

        let state = MissionRunEnvironment.deriveMissionSquadState(
            task: task,
            assignment: squad.assignment,
            squadIndex: squad.squadIndex,
            run: run,
            now: now
        )
        return squadStateAllowsOperatorTriggerStart(state)
    }

    private static func squadStateAllowsOperatorTriggerStart(_ state: MissionSquadState) -> Bool {
        switch state {
        case .ready, .between:
            return true
        case .staging, .executing, .paused, .recovery, .aborting, .aborted, .completed:
            return false
        }
    }
}
