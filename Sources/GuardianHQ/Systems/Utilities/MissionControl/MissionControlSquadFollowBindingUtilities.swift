import Foundation

/// Resolves wingman roster rows and run assignments for a primary squad (§A — squad follow binding).
enum MissionControlSquadFollowBindingUtilities {

    /// True when any wingman on this task is bound to a primary roster row on the same task.
    static func taskHasWingmen(mission: Mission, task: MissionTask) -> Bool {
        taskHasWingmen(rosterDevices: mission.rosterDevices, task: task)
    }

    static func taskHasWingmen(rosterDevices: [RosterDevice], task: MissionTask) -> Bool {
        let onTask = Set(task.rosterDeviceIds)
        let primaryIDs = Set(
            rosterDevices
                .filter { onTask.contains($0.id) && $0.slot == .primary }
                .map(\.id)
        )
        guard !primaryIDs.isEmpty else { return false }
        return rosterDevices.contains { device in
            device.slot == .wingman
                && device.leaderRosterDeviceId.map(primaryIDs.contains) == true
        }
    }

    /// Wingmen bound to `primaryRosterDeviceID` on `taskID`, in template roster order.
    static func wingmanBindings(
        primaryRosterDeviceID: UUID,
        taskID: UUID,
        mission: Mission,
        assignments: [MissionRunAssignment]
    ) -> [MissionRunSquadWingmanBinding] {
        let rosterOrder = Dictionary(uniqueKeysWithValues: mission.rosterDevices.enumerated().map { ($1.id, $0) })
        let enabledTasks = mission.routeMacro.tasks.filter(\.enabled)
        let wingmanDevices = mission.rosterDevices.filter { rd in
            rd.slot == .wingman && rd.leaderRosterDeviceId == primaryRosterDeviceID
        }
        let sortedDevices = wingmanDevices.sorted { lhs, rhs in
            let li = rosterOrder[lhs.id] ?? Int.max
            let ri = rosterOrder[rhs.id] ?? Int.max
            if li != ri { return li < ri }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var out: [MissionRunSquadWingmanBinding] = []
        out.reserveCapacity(sortedDevices.count)
        for device in sortedDevices {
            guard let row = assignments.first(where: { $0.rosterDeviceId == device.id }),
                  row.hasFleetOrLegacyAssignment,
                  assignmentMatchesTask(row, taskID: taskID, enabledTaskCount: enabledTasks.count)
            else { continue }
            out.append(MissionRunSquadWingmanBinding(assignment: row, rosterDevice: device))
        }
        return out
    }

    private static func assignmentMatchesTask(
        _ assignment: MissionRunAssignment,
        taskID: UUID,
        enabledTaskCount: Int
    ) -> Bool {
        if assignment.taskId == taskID { return true }
        if assignment.taskId == nil, enabledTaskCount == 1 { return true }
        return false
    }
}
