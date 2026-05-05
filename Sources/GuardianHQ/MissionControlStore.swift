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
}
