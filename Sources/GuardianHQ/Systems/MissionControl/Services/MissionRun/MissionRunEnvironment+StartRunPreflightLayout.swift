import Foundation

extension MissionRunEnvironment {
    /// Same rule as Mission Control roster UI: assignment rows belong to a task via `taskId`, or implicitly to the only enabled task.
    func missionControlAssignmentBelongsToTask(_ assignment: MissionRunAssignment, task: MissionTask, mission: Mission) -> Bool {
        if assignment.taskId == task.id { return true }
        if assignment.taskId == nil {
            let enabled = mission.routeMacro.tasks.filter(\.enabled)
            if enabled.count == 1, enabled.first?.id == task.id { return true }
        }
        return false
    }

    /// Same ordering as MCS roster accordion: primaries in roster order, then each primary’s wingmen and reserves.
    func missionControlTaskRosterOrderedSlotAssignmentIndices(task: MissionTask, mission: Mission) -> [(assignmentIndex: Int, indent: Int)] {
        let ids = task.rosterDeviceIds
        func device(for rosterId: UUID) -> RosterDevice? {
            mission.rosterDevices.first { $0.id == rosterId }
        }
        func slot(for rosterId: UUID, indent: Int) -> (assignmentIndex: Int, indent: Int)? {
            guard let idx = assignments.firstIndex(where: {
                $0.rosterDeviceId == rosterId && missionControlAssignmentBelongsToTask($0, task: task, mission: mission)
            }) else { return nil }
            return (idx, indent)
        }
        var emitted = Set<UUID>()
        var rows: [(assignmentIndex: Int, indent: Int)] = []
        let primaryIds = ids.filter { device(for: $0)?.slot == .primary }
        for pid in primaryIds {
            guard device(for: pid)?.slot == .primary else { continue }
            if let r = slot(for: pid, indent: 0) {
                rows.append(r)
                emitted.insert(pid)
            }
            let wingmanIds = ids.filter {
                guard let d = device(for: $0), d.slot == .wingman, d.leaderRosterDeviceId == pid else { return false }
                return true
            }
            let reserveIds = ids.filter {
                guard let d = device(for: $0), d.slot == .reserve, d.leaderRosterDeviceId == pid else { return false }
                return true
            }
            for wid in wingmanIds {
                if let r = slot(for: wid, indent: 1) {
                    rows.append(r)
                    emitted.insert(wid)
                }
            }
            for rid in reserveIds {
                if let r = slot(for: rid, indent: 1) {
                    rows.append(r)
                    emitted.insert(rid)
                }
            }
        }
        for id in ids where !emitted.contains(id) {
            let d = device(for: id)
            let indent = (d?.slot == .wingman || d?.slot == .reserve) ? 1 : 0
            if let r = slot(for: id, indent: indent) {
                rows.append(r)
                emitted.insert(id)
            }
        }
        return rows
    }

    /// Stable section id for roster rows that are not placed under any mission task slice (should be rare).
    static let missionPreflightRemainderSectionID = UUID(uuidString: "00000000-0000-0000-0000-00000000EF01")!

    /// Task-grouped roster slots for Mission Preflight UI (reserve pool berths excluded — same default as ``orderedStartRunPreflightProbeTargets()``).
    func orderedStartRunPreflightProbeSections(mission: Mission?) -> [MissionRunPreflightUIProbeSection] {
        let rosterFlat = orderedStartRunPreflightProbeTargets()
            .filter {
                if case .rosterAssignment = $0.identity { return true }
                return false
            }
        guard let mission else {
            guard !rosterFlat.isEmpty else { return [] }
            let targets = rosterFlat.map {
                MissionRunPreflightUITarget(identity: $0.identity, displayTitle: $0.displayTitle, assignment: $0.assignment)
            }
            return [
                MissionRunPreflightUIProbeSection(
                    id: Self.missionPreflightRemainderSectionID,
                    title: "Roster",
                    titleMuted: false,
                    targets: targets
                ),
            ]
        }

        var placed = Set<UUID>()
        var sections: [MissionRunPreflightUIProbeSection] = []

        for task in mission.routeMacro.tasks {
            let rows = missionControlTaskRosterOrderedSlotAssignmentIndices(task: task, mission: mission)
            var targets: [MissionRunPreflightUITarget] = []
            for row in rows {
                guard row.assignmentIndex < assignments.count else { continue }
                let a = assignments[row.assignmentIndex]
                targets.append(
                    MissionRunPreflightUITarget(
                        identity: .rosterAssignment(a.id),
                        displayTitle: a.slotName,
                        assignment: a
                    )
                )
                placed.insert(a.id)
            }
            if !targets.isEmpty {
                sections.append(
                    MissionRunPreflightUIProbeSection(
                        id: task.id,
                        title: task.name,
                        titleMuted: !task.enabled,
                        targets: targets
                    )
                )
            }
        }

        let remainder: [MissionRunPreflightUITarget] = rosterFlat.compactMap { triple in
            guard case .rosterAssignment(let rid) = triple.identity else { return nil }
            guard !placed.contains(rid) else { return nil }
            return MissionRunPreflightUITarget(
                identity: triple.identity,
                displayTitle: triple.displayTitle,
                assignment: triple.assignment
            )
        }
        if !remainder.isEmpty {
            sections.append(
                MissionRunPreflightUIProbeSection(
                    id: Self.missionPreflightRemainderSectionID,
                    title: "Other roster",
                    titleMuted: false,
                    targets: remainder
                )
            )
        }

        return sections
    }

    /// Arm-probe sweep order for start run: grouped by mission task when `mission` is known, otherwise roster list order.
    func orderedStartRunPreflightProbeSequence(mission: Mission?) -> [(identity: MissionRunPreflightSlotIdentity, displayTitle: String, assignment: MissionRunAssignment)] {
        let sections = orderedStartRunPreflightProbeSections(mission: mission)
        if !sections.isEmpty {
            return sections.flatMap(\.targets).map { ($0.identity, $0.displayTitle, $0.assignment) }
        }
        return orderedStartRunPreflightProbeTargets()
    }
}
