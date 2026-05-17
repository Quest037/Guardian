import Foundation

/// MCS roster / floating-reserve **bulk SIM spawn** counting and preset selection (``MissionRunDetailView``).
@MainActor
enum MissionControlMcsBulkSimSpawnUtilities {
    static func emptyReservePoolSlotCount(run: MissionRunEnvironment, taskID: UUID) -> Int {
        run.reservePool(forTaskID: taskID).entries.filter { !$0.hasFleetOrLegacyBinding }.count
    }

    static func emptyReservePoolSlotCountAcrossMission(run: MissionRunEnvironment, mission: Mission) -> Int {
        mission.routeMacro.tasks.reduce(0) { partial, task in
            partial + emptyReservePoolSlotCount(run: run, taskID: task.id)
        }
    }

    /// Built-in SITL preset for auto-spawn into empty floating reserve berths on a task (manual pick uses the sim sidebar).
    static func builtInSimulationPresetForTaskReservePoolBulkSpawn(
        task: MissionTask,
        mission: Mission
    ) -> SimulationVehiclePreset {
        let deviceIds = Set(task.rosterDeviceIds)
        let classes = mission.rosterDevices
            .filter { deviceIds.contains($0.id) }
            .map(\.vehicleClass)
        if let typed = classes.first(where: { $0 != .unknown }) {
            return typed.builtInSimulationVehiclePreset
        }
        return FleetVehicleType.unknown.builtInSimulationVehiclePreset
    }
}
