import Foundation

/// Vehicle selection for Mission Run **completed** SIM cleanup — sequential ``recipe.fleet.vehicle.do.park`` (see README).
@MainActor
enum MissionRunSimCleanupParkPolicy {
    /// Roster rows in ``assignments`` order, then floating reserve pool slots (task id ascending, slot id ascending within each task).
    ///
    /// Dedupes by resolved ``vehicleID`` so the same SITL is parked once. Only **SITL** fleet tokens with a running instance,
    /// Guardian-managed stream, and non-unknown autopilot stack (same spirit as roster SIM home restore + pool staging eligibility).
    static func orderedCleanupParkTargets(
        assignments: [MissionRunAssignment],
        reservePoolByTaskID: [UUID: MissionRunReservePool],
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> [(vehicleID: String, assignment: MissionRunAssignment)] {
        var seenVehicleIDs = Set<String>()
        var out: [(vehicleID: String, assignment: MissionRunAssignment)] = []

        func appendIfQualifying(_ assignment: MissionRunAssignment) {
            guard assignmentHasSitlFleetTokenForCleanup(assignment) else { return }
            guard let raw = assignment.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  let token = FleetMissionVehicleToken(storageKey: raw),
                  let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
            else { return }
            guard fleetLink.isGuardianManagedSitlStream(vehicleID: vehicleID) else { return }
            let stack = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.telemetry?.autopilotStack
                ?? fleetLink.hubTelemetry(forVehicleID: vehicleID)?.autopilotStack
                ?? .unknown
            guard stack != .unknown else { return }
            guard seenVehicleIDs.insert(vehicleID).inserted else { return }
            out.append((vehicleID, assignment))
        }

        for assignment in assignments {
            appendIfQualifying(assignment)
        }

        for taskID in reservePoolByTaskID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let pool = reservePoolByTaskID[taskID] else { continue }
            let sortedSlots = pool.entries.sorted(by: { $0.id.uuidString < $1.id.uuidString })
            for slot in sortedSlots {
                guard MCSReservePoolHomeStagingMapEligibility.isEligibleSitlReservePoolSlot(
                    slot: slot,
                    sitl: sitl,
                    fleetLink: fleetLink
                ) else { continue }
                appendIfQualifying(MissionRunAssignment.syntheticForReservePool(slot: slot))
            }
        }

        return out
    }

    private static func assignmentHasSitlFleetTokenForCleanup(_ assignment: MissionRunAssignment) -> Bool {
        guard assignment.hasFleetOrLegacyAssignment else { return false }
        guard let raw = assignment.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let token = FleetMissionVehicleToken(storageKey: raw)
        else { return false }
        if case .sitl = token { return true }
        return false
    }
}
