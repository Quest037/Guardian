import Foundation

@MainActor
final class MissionRunLifecycleSubsystem {
    weak var environment: MissionRunEnvironment?

    func markCompiled() {
        environment?.setSessionPhase(.compiled)
    }

    func markExecuting() {
        environment?.status = .running
        environment?.setSessionPhase(.executing)
    }

    func pauseRun() {
        environment?.status = .paused
        environment?.refreshDerivedTaskStates()
    }

    func resumeRun() {
        environment?.status = .running
        environment?.refreshDerivedTaskStates()
    }

    func markCompleted(kind: MissionRunCompletionKind? = nil) {
        guard let environment else { return }
        environment.status = .completed
        environment.completedAt = Date()
        if let kind {
            environment.completionKind = kind
        }
        environment.reportCyclesCompleted = environment.reportCyclesCompleted ?? environment.cyclesCompleted
        environment.setSessionPhase(.completed)
        environment.clearOperatorLiveDriveHandoffsWhenRunFinished()
        environment.cancelPendingCommandBatchesAndFleetHintsAfterRunCompleted()
        environment.systems.scheduling.cancelAllScheduledTasks()
        UserNotificationService.shared.notifyMissionControlRunCompleted(
            runID: environment.id,
            missionName: environment.missionName,
            summary: "Mission run completed."
        )
        environment.scheduleMissionRunSimCleanupIfNeeded()
    }

    func markFailed(detail: String? = nil) {
        guard let environment else { return }
        environment.status = .completed
        environment.completedAt = Date()
        environment.setSessionPhase(.aborted)
        environment.clearOperatorLiveDriveHandoffsWhenRunFinished()
        if let detail {
            environment.appendEvent(
                MissionRunEvent(
                    level: .error,
                    templateKey: MissionRunLogTemplateKey.lifecycleRunFailed,
                    templateParams: ["detail": detail]
                )
            )
        }
        environment.systems.scheduling.cancelAllScheduledTasks()
    }

    func resetToSetup() {
        guard let environment else { return }
        environment.systems.scheduling.cancelAllScheduledTasks()
        environment.status = .setup
        environment.setSessionPhase(.draft)
        environment.gracefulStopKind = .none
        environment.systems.scheduling.setDeferredOneOffExecution(nil)
        environment.startedAt = nil
        environment.completedAt = nil
        environment.reportCyclesCompleted = nil
        environment.completionKind = nil
        environment.setMissionCycleCount(0)
        environment.clearFinishedMissionCycleVehicleIDs()
        environment.clearActiveCycleTasks()
        environment.clearTaskCycleCompletionCounts()
        environment.clearTaskMissionEndRecoveryAcknowledgements()
        environment.clearTaskMissionEndAbortAcknowledgements()
        environment.clearMissionTaskScopedOrchestrationState()
        environment.clearAssignmentSlotLifecycleLanesOnAllRows()
        environment.clearEvents()
        environment.systems.planner.clearCompiledPlan()
        environment.systems.logging.clearState()
        environment.systems.executor.clearCommandQueue()
        environment.captureExecutionContext(nil)
        environment.refreshDerivedTaskStates()
    }
}

extension MissionRunLogTemplateKey {
    static let lifecycleRunFailed = "missioncontrol.mre.lifecycle.run_failed"
    /// SIM pose restore batch after a qualifying successful run completion (see README SIM home reset).
    static let lifecycleSimHomeRestoreBatch = "missioncontrol.mre.lifecycle.sim_home_restore_batch"
    /// ``templateParams``: `removedCount` — executor batches revoked at run **completed** (Mission Run SIM clean up Phase A).
    static let executorPendingBatchesCancelledForRunCompleted =
        "missioncontrol.mre.executor.pending_batches_cancelled_run_completed"
    /// Params: `vehicleCount` — best-effort manual stream / mission pause / offboard stop for Guardian SITLs at SIM cleanup start (Phase A motion damp).
    static let guardianSitlMotionStopPassAfterRunCompleted =
        "missioncontrol.mre.lifecycle.guardian_sitl_motion_stop_pass_run_completed"
    /// Params: `vehicleCount` — SIM cleanup Phase A: MAVSDK ``Action/kill`` acknowledged for that many Guardian SITL streams (excludes no-session skips).
    static let guardianSitlKillPassAfterRunCompleted =
        "missioncontrol.mre.lifecycle.guardian_sitl_kill_pass_run_completed"
    /// Params: `dispatch` — ``MissionRunQueuedCommandBatch/dispatchLogLabel``; mission-start batch dropped because the run is already ``MissionRunSessionPhase/completed``.
    static let executorMissionStartBatchSuppressedRunCompleted =
        "missioncontrol.mre.executor.mission_start_batch_suppressed_run_completed"
    /// Params: `attempted`, `succeeded`, `failed` — run-complete sequential park batch (SIM cleanup).
    static let lifecycleSimCleanupParkBatch = "missioncontrol.mre.lifecycle.sim_cleanup_park_batch"
    /// Params: `attempted`, `succeeded`, `failed` — run-complete waved SIM ``Action/kill`` batch (force disarm).
    static let lifecycleSimCleanupKillBatch = "missioncontrol.mre.lifecycle.sim_cleanup_kill_batch"
    /// Params: `sitlKill`, `teleport`, `union`, `completion` — async SIM cleanup pass begins (after ``markCompleted``); `sitlKill` is Guardian SITL session count targeted for kill.
    static let lifecycleSimCleanupRunStarted = "missioncontrol.mre.lifecycle.sim_cleanup_run_started"
    /// Params: `killAttempted`, `killFailed`, `missionClear`, `geofenceClear`, `rTeleApplied`, `rTeleSkipped`, `pTeleApplied`, `pTeleSkipped`, `battery` — one-line end summary for the same pass.
    static let lifecycleSimCleanupRunFinished = "missioncontrol.mre.lifecycle.sim_cleanup_run_finished"
}
