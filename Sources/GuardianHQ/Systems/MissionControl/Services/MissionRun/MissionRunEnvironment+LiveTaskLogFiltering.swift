import Foundation

extension MissionRunEnvironment {
    /// Same roster / task rules as MC‑R ``MCRLiveMissionLogStripStore`` / ``MissionControlSetupView/liveLogEventsFiltered`` when a task is focused.
    static func filterEventsForLiveTaskLogFocus(
        events: [MissionRunEvent],
        assignments: [MissionRunAssignment],
        mission: Mission?,
        focusedTaskID: UUID?
    ) -> [MissionRunEvent] {
        guard let focus = focusedTaskID else { return events }
        guard let mission else {
            return events.filter { $0.taskID == focus }
        }
        let focusedSlots = Set(
            assignments
                .filter { assignmentMatchesLiveTaskLogFocus($0, mission: mission, focus: focus) }
                .map(\.slotName)
        )
        return events.filter { event in
            if event.taskID == focus { return true }
            if event.taskID == nil, case .vehicleSlot(let slot) = event.speaker {
                return focusedSlots.contains(slot)
            }
            return false
        }
    }

    private static func assignmentMatchesLiveTaskLogFocus(
        _ assignment: MissionRunAssignment,
        mission: Mission,
        focus: UUID
    ) -> Bool {
        if assignment.taskId == focus { return true }
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        if enabled.count == 1, enabled.first?.id == focus {
            return assignment.taskId == nil || assignment.taskId == focus
        }
        return false
    }

    /// Filter this run’s events to the mission task (and roster slot lines) tied to the focused task id.
    func eventsFilteredForLiveTaskLogFocus(focusedTaskID: UUID?, mission: Mission?) -> [MissionRunEvent] {
        Self.filterEventsForLiveTaskLogFocus(
            events: events,
            assignments: assignments,
            mission: mission,
            focusedTaskID: focusedTaskID
        )
    }
}
