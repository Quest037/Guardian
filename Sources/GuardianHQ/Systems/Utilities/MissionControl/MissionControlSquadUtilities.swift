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
