import Foundation

/// Template geofence merge for Mission Control **planning** (MRE) before any run-time policy overrides exist.
struct MissionTemplateGeofenceUtilities: Sendable {
    /// **Authoring / template lock:** at most one **inclusion** fence may apply per task from the mission template,
    /// and any **exclusion** must sit with at least one **inclusion** in the same effective set (mission-wide + that task).
    ///
    /// - At most **one** mission-wide inclusion in ``Mission/missionGeofences``.
    /// - Per ``MissionTask``, at most **one** task-scoped inclusion in ``MissionTask/geofences``.
    /// - A task **cannot** combine a mission-wide inclusion with any task-scoped inclusion (task-level is the preferred scope when both would exist — reject the combined state).
    /// - For each task, merged fences are ``Mission/missionGeofences`` + that task’s ``MissionTask/geofences``. If that merged list contains any exclusion, it must also contain at least one inclusion. With **no** tasks, only ``Mission/missionGeofences`` is checked the same way.
    ///
    /// Returns `nil` when valid, otherwise a short message for operator toasts.
    func inclusionConstraintViolationMessage(for mission: Mission) -> String? {
        let missionInclusions = mission.missionGeofences.filter { $0.boundary == .inclusion }
        if missionInclusions.count > 1 {
            return "Only one mission-wide inclusion fence is allowed. Change extras to exclusion or remove them."
        }
        for task in mission.routeMacro.tasks {
            let taskInclusions = task.geofences.filter { $0.boundary == .inclusion }
            if taskInclusions.count > 1 {
                let label = taskLabelForFencePolicy(task)
                return "Each task may have at most one inclusion fence. Remove or change extras on \(label)."
            }
            if !missionInclusions.isEmpty && !taskInclusions.isEmpty {
                let label = taskLabelForFencePolicy(task)
                return "Cannot use a mission-wide inclusion fence together with a task inclusion fence on \(label). Use only a task-level inclusion, or remove task inclusions to keep the mission-wide fence."
            }
        }
        if let msg = exclusionRequiresInclusionViolationMessage(for: mission) {
            return msg
        }
        return nil
    }

    private func exclusionRequiresInclusionViolationMessage(for mission: Mission) -> String? {
        let wide = mission.missionGeofences
        func hasExclusionWithoutInclusion(_ fences: [MissionGeofence]) -> Bool {
            let hasExclusion = fences.contains { $0.boundary == .exclusion }
            let hasInclusion = fences.contains { $0.boundary == .inclusion }
            return hasExclusion && !hasInclusion
        }
        if mission.routeMacro.tasks.isEmpty {
            if hasExclusionWithoutInclusion(wide) {
                return "Exclusion fences need an inclusion fence. Add a mission-wide inclusion fence."
            }
            return nil
        }
        for task in mission.routeMacro.tasks {
            let merged = wide + task.geofences
            if hasExclusionWithoutInclusion(merged) {
                let label = taskLabelForFencePolicy(task)
                return "Exclusion fences need an inclusion fence. Add an inclusion on \(label) or as mission-wide."
            }
        }
        return nil
    }

    private func taskLabelForFencePolicy(_ task: MissionTask) -> String {
        let n = task.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "this task" : "“\(n)”"
    }

    /// v1 **additive** merge for a route task when compiling MRE plans (and any future MAVLink fence payloads):
    ///
    /// 1. All ``Mission/missionGeofences`` (mission-wide).
    /// 2. All ``MissionTask/geofences`` for the task identified by `taskID`.
    ///
    /// Run-time policy overrides (per-assignment geometry, enable/disable, …) are **not** applied here — extend via ``MissionRunPolicyAuthoritySubsystem`` when that slice lands.
    func effectiveTemplateGeofencesForPlanning(taskID: UUID, mission: Mission) -> [MissionGeofence] {
        let missionWide = mission.missionGeofences
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }) else {
            return missionWide
        }
        return missionWide + task.geofences
    }
}
