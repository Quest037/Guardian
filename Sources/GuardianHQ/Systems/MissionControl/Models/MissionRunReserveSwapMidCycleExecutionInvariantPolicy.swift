import Foundation

// MARK: - Reserve swap while execution is live (scheduler / queue coherence)

/// Policy for **floating reserve → roster** commits that land while Mission Control is already **executing**
/// (autopilot mission cycles, queued command batches, per-task cycle counters).
///
/// ``MissionRunEnvironment/swapRosterAssignmentWithRandomFloatingReserve`` mutates ``assignments`` in place
/// (same ``MissionRunAssignment/id``, new ``attachedFleetVehicleToken``) and calls ``refreshDerivedTaskStates``.
/// It does **not** reset ``taskCyclesCompletedByTaskID``, ``cyclesCompleted``, ``activeCycleTaskIDs``, or the
/// executor command queue — those are intentional so a mid-mission swap does not fabricate a fresh “cycle zero”.
enum MissionRunReserveSwapMidCycleExecutionInvariantPolicy: Sendable {

    /// **True** while the run has left setup and is in the **executing** session phase — i.e. normal mission
    /// execution windows where autopilot cycle gating and ``MissionRunQueuedCommandDispatch/afterMissionCycle``
    /// batches apply. Paused runs keep phase + queue state; recovery keeps the same vocabulary for “live body”.
    static func isLiveExecutingSession(status: MissionRunStatus, sessionPhase: MissionRunSessionPhase) -> Bool {
        guard sessionPhase == .executing else { return false }
        switch status {
        case .running, .paused, .recovery:
            return true
        case .setup, .completed:
            return false
        }
    }

    /// Per-task cycle counters and whole-run ``MissionRunEnvironment/cyclesCompleted`` are **not** cleared by a
    /// reserve roster swap; only **derived** UI state is refreshed. Executors must not assume swap implies a new task
    /// attempt index.
    static let swapDoesNotResetTaskOrRunCycleCounters = true

    /// ``MissionRunIssuedCommand`` embeds ``vehicleTokenKey`` from issuance time. After a swap, pending batches may
    /// still list commands for the same ``assignmentID`` with the **pre-swap** token while ``assignments`` already
    /// carries the reserve token — dispatch would target the wrong **vehicle** if delivered verbatim.
    static func pendingBatchesContainStaleVehicleTokenForAssignment(
        batches: [MissionRunQueuedCommandBatch],
        assignmentID: UUID,
        currentAssignmentFleetToken: String?
    ) -> Bool {
        let current = normalizedFleetStorageKey(currentAssignmentFleetToken)
        for batch in batches {
            for cmd in batch.commands where cmd.assignmentID == assignmentID {
                if normalizedFleetStorageKey(cmd.vehicleTokenKey) != current {
                    return true
                }
            }
        }
        return false
    }

    /// v1 limitation: ``MissionRunExecutionSubsystem/cancelPendingCommandBatches`` filters by **queue tag** and
    /// optional **dispatch** predicate only — there is no built-in “drop only commands whose token mismatches roster”
    /// slice. Mid-cycle swap executors must add explicit reconciliation (rebuild/cancel affected batches) when they
    /// wire live swap-in.
    static let selectiveStaleTokenBatchCancellationRequiresExecutorWork = true

    private static func normalizedFleetStorageKey(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
