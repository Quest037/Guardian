import Foundation

extension MissionRunEnvironment {
    /// Every built-in SITL instance UUID referenced by **roster assignments** or **floating reserve pool** slots on this run.
    ///
    /// Order: assignments in roster order, then reserve pool slots grouped by sorted task id, each pool’s ``MissionRunReservePool/entries`` order.
    /// Duplicates are de-duplicated while preserving first-seen order.
    func allSitlInstanceUUIDsBoundOnRun() -> [UUID] {
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        func visit(_ raw: String?) {
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let token = FleetMissionVehicleToken(storageKey: trimmed),
                  case .sitl(let uuid) = token
            else { return }
            if seen.insert(uuid).inserted {
                ordered.append(uuid)
            }
        }
        for assignment in assignments {
            visit(assignment.attachedFleetVehicleToken)
        }
        for taskID in reservePoolByTaskID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let entries = reservePoolByTaskID[taskID]?.entries ?? []
            for slot in entries {
                visit(slot.attachedFleetVehicleToken)
            }
        }
        return ordered
    }

    /// **Delete-run path:** stop every Guardian-managed SITL listed on this run and remove it from the app. Does **not**
    /// run ``performMissionRunSimCleanupPassIfNeeded`` (no mission clear / geofence / teleport / battery cleanup waves).
    ///
    /// Each ``SitlService/stop(id:)`` tears down the child process and calls through to ``FleetLinkService/unregisterSimulatedVehicle``,
    /// which ends the MAVSDK session for that stream key.
    func hardStopAndRemoveAllRunBoundSitlsForDeletion(fleetLink _: FleetLinkService, sitl: SitlService) async {
        for uuid in allSitlInstanceUUIDsBoundOnRun() {
            sitl.stop(id: uuid)
            await Task.yield()
        }
    }
}
