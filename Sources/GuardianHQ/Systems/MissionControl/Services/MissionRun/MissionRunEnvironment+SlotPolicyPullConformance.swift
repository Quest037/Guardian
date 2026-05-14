import Foundation

extension MissionRunEnvironment {

    /// §3 **pull** path: on hub updates, promote slot lanes to ``policySucceeded`` when abort/complete wind-down is active
    /// and telemetry matches a conservative “settled / disarmed” proxy (``MissionRunPolicySlotPullConformance``).
    ///
    /// **SITL vs live:** uses the same lane machine and the same hub thresholds as live MAVLink streams; only
    /// ``FleetLinkService`` is required — ``SitlService`` is optional (live-only Mission Control still runs pull).
    /// If live link cadence ever needs different debounce or max-age, add a **single** env-tunable override on
    /// ``MissionRunPolicySlotPullConformance`` rather than branching slot states by sim vs hardware.
    ///
    /// Call from Mission Control live surfaces on ``fleetLink.hubTelemetry`` changes; debounced per assignment.
    func applySlotPolicyPullConformanceFromHubIfNeeded(now: Date = Date()) {
        guard let fleetLink else { return }
        // Recovery status is entered as soon as the operator (or automation) ends execution for “mark completed” flows;
        // hub pull must keep promoting §3 terminals until each **task-scoped** wind-down row settles, otherwise
        // ``applySlotEvidenceAutoMissionEndAckIfNeeded`` never runs and ``MissionTaskState`` stays stuck in **Recovery**.
        guard status == .running || status == .paused || status == .recovery else { return }
        guard sessionPhase == .executing || sessionPhase == .aborting || sessionPhase == .recovery else { return }
        guard let mission = template else { return }

        var promotedAssignmentIDs = Set<UUID>()
        for assignment in assignments {
            let lanes = assignment.effectiveSlotLifecycleLanes
            if lanes.observed == .policySucceeded { continue }
            if lanes.commanded == .policySucceeded { continue }

            guard assignmentHasActivePolicyWindDownContext(assignment, mission: mission) else { continue }

            guard let tokenKey = assignment.attachedFleetVehicleToken,
                  FleetMissionVehicleToken(storageKey: tokenKey) != nil
            else { continue }
            guard let vehicleID = resolvedFleetStreamVehicleID(
                assignment: assignment,
                fleetLink: fleetLink,
                sitl: sitl
            ) else { continue }
            guard let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID) else { continue }
            guard MissionRunPolicySlotPullConformance.hubSuggestsPolicyWindDownSettled(hub, now: now) else { continue }

            if let last = slotPolicyPullConformanceLastSuccessByAssignmentID[assignment.id],
               now.timeIntervalSince(last) < MissionRunPolicySlotPullConformance.successDebounceSeconds {
                continue
            }

            let changed = setSlotPolicyLanesBoth(assignmentID: assignment.id, terminal: .policySucceeded)
            if changed {
                slotPolicyPullConformanceLastSuccessByAssignmentID[assignment.id] = now
                promotedAssignmentIDs.insert(assignment.id)
            }
        }
        if !promotedAssignmentIDs.isEmpty {
            applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs: promotedAssignmentIDs)
        }
    }

    private func assignmentHasActivePolicyWindDownContext(_ assignment: MissionRunAssignment, mission: Mission) -> Bool {
        guard let tid = MissionRunPolicyResolution.resolvedTaskId(for: assignment, mission: mission) else { return false }
        return missionTaskAbortWindDownIssuedTaskIDs.contains(tid)
            || missionTaskCompleteWindDownIssuedTaskIDs.contains(tid)
    }
}
