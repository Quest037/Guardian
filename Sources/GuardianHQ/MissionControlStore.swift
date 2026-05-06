import Foundation

@MainActor
final class MissionControlStore: ObservableObject {
    @Published private(set) var runs: [MissionRun] = []

    func createRun(from mission: Mission) -> MissionRun {
        var assignments: [MissionRunAssignment] = []
        for path in mission.routeMacro.paths {
            for deviceId in path.rosterDeviceIds {
                guard let device = mission.rosterDevices.first(where: { $0.id == deviceId }) else { continue }
                assignments.append(
                    MissionRunAssignment(
                        pathId: path.id,
                        rosterDeviceId: device.id,
                        slotName: device.name
                    )
                )
            }
        }
        if assignments.isEmpty {
            assignments = mission.rosterDevices.map {
                MissionRunAssignment(
                    pathId: nil,
                    rosterDeviceId: $0.id,
                    slotName: $0.name
                )
            }
        }
        let run = MissionRun(
            missionId: mission.id,
            missionName: mission.name,
            assignments: assignments
        )
        runs.insert(run, at: 0)
        return run
    }

    func updateRun(_ run: MissionRun) {
        guard let idx = runs.firstIndex(where: { $0.id == run.id }) else { return }
        runs[idx] = run
    }

    func startRun(id: UUID) {
        guard let idx = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[idx].status = .running
        if runs[idx].startedAt == nil {
            runs[idx].startedAt = Date()
        }
    }

    func deleteRun(id: UUID) {
        runs.removeAll { $0.id == id }
    }

    /// Graceful stop now: vehicles hold / return to start or home (autopilot integration pending).
    func stopRunImmediate(id: UUID) {
        guard let idx = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[idx].status = .completed
        runs[idx].completedAt = Date()
        runs[idx].pendingGracefulCycleStop = false
    }

    /// Finish the current cycle, then stop; no further loop iterations or continuous scheduling.
    func stopRunAfterCurrentCycle(id: UUID) {
        guard let idx = runs.firstIndex(where: { $0.id == id }) else { return }
        guard runs[idx].status == .running || runs[idx].status == .paused else { return }
        runs[idx].pendingGracefulCycleStop = true
    }

    /// Move a completed run back to setup for another configured launch.
    func resetRunToSetup(id: UUID) {
        guard let idx = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[idx].status = .setup
        // Intentionally preserve mission prep state (schedule, assignments, and chosen vehicles).
    }

    /// A vehicle already committed to another **running or paused** mission cannot be picked again.
    func isFleetVehicleLockedByOtherLiveMission(tokenKey: String, excludingRunId: UUID) -> Bool {
        for r in runs where r.id != excludingRunId && (r.status == .running || r.status == .paused) {
            if r.assignments.contains(where: { $0.attachedFleetVehicleToken == tokenKey }) {
                return true
            }
        }
        return false
    }

    /// The same fleet vehicle cannot be on two roster slots within one mission run.
    func isFleetVehicleUsedOnOtherSlotInRun(tokenKey: String, run: MissionRun, assignmentId: UUID) -> Bool {
        run.assignments.contains {
            $0.id != assignmentId && $0.attachedFleetVehicleToken == tokenKey
        }
    }
}
