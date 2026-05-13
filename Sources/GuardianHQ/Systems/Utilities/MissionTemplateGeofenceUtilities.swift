import Foundation

/// Template geofence merge for Mission Control **planning** (MRE) before any run-time policy overrides exist.
struct MissionTemplateGeofenceUtilities: Sendable {
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
