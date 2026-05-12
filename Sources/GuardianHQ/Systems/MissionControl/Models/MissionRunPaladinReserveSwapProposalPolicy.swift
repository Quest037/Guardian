import Foundation

// MARK: - Paladin fixed-reserve → active roster swap (proposal validation)

/// Pure validation for **Paladin** (or any observer with ``MissionRunObserverPermissions/act``) proposing a
/// **template `.reserve` roster row** replace a **primary or wingman** roster binding on the same task.
///
/// Floating **pool** swap picks stay on the MC-R operator UI (`swapRosterAssignmentWithFloatingReservePoolSlot`);
/// this policy only covers **fixed** reserve template rows on the compiled mission roster.
enum MissionRunPaladinReserveSwapProposalPolicy {

    enum Failure: String, Equatable, Sendable, Error {
        case assignmentsNotFound
        case rosterDeviceMissing
        case reserveNotTemplateReserveRow
        case primaryIsReserveSlot
        case taskNotFound
        case notOnSameEnabledTask
        case missingFleetTokenOnPrimary
        case missingFleetTokenOnReserve
    }

    /// Validates both assignments, shared task path, roster roles, and fleet token presence.
    @MainActor
    static func evaluate(
        run: MissionRunEnvironment,
        mission: Mission,
        primaryAssignmentID: UUID,
        reserveAssignmentID: UUID
    ) -> Result<(task: MissionTask, primary: MissionRunAssignment, reserve: MissionRunAssignment), Failure> {
        guard let primary = run.assignments.first(where: { $0.id == primaryAssignmentID }),
              let reserve = run.assignments.first(where: { $0.id == reserveAssignmentID })
        else { return .failure(.assignmentsNotFound) }
        guard primary.id != reserve.id else { return .failure(.assignmentsNotFound) }

        let rosterByID = Dictionary(uniqueKeysWithValues: mission.rosterDevices.map { ($0.id, $0) })
        guard let primaryDevice = rosterByID[primary.rosterDeviceId],
              let reserveDevice = rosterByID[reserve.rosterDeviceId]
        else { return .failure(.rosterDeviceMissing) }

        guard reserveDevice.slot == .reserve else { return .failure(.reserveNotTemplateReserveRow) }
        guard primaryDevice.slot != .reserve else { return .failure(.primaryIsReserveSlot) }

        guard let pt = primary.attachedFleetVehicleToken, !pt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.missingFleetTokenOnPrimary)
        }
        guard let rt = reserve.attachedFleetVehicleToken, !rt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.missingFleetTokenOnReserve)
        }
        _ = (pt, rt)

        guard let tid = primary.taskId ?? reserve.taskId else { return .failure(.notOnSameEnabledTask) }
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == tid && $0.enabled }) else {
            return .failure(.taskNotFound)
        }
        guard run.missionControlAssignmentBelongsToTask(primary, task: task, mission: mission),
              run.missionControlAssignmentBelongsToTask(reserve, task: task, mission: mission)
        else { return .failure(.notOnSameEnabledTask) }

        return .success((task, primary, reserve))
    }
}
