import Foundation

/// When MCS **Set reserve pool home** is armed, disarm if the mission snapshot or target task is no longer valid (``MCSReservePoolMapToDo.md`` Phase G).
enum MCSReservePoolHomePlacementTemplateGuard {
    /// `true` when an armed task id should **clear** pool-home placement (template missing, task removed, or task disabled).
    static func shouldDisarmPoolHomeArm(armedTaskID: UUID?, mission: Mission?) -> Bool {
        guard let tid = armedTaskID else { return false }
        guard let mission else { return true }
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == tid }) else { return true }
        return !task.enabled
    }
}
