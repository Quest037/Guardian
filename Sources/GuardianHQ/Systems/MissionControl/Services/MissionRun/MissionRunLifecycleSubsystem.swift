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
        environment.systems.scheduling.cancelAllScheduledTasks()
        UserNotificationService.shared.notifyMissionControlRunCompleted(
            runID: environment.id,
            missionName: environment.missionName,
            summary: "Mission run completed."
        )
    }

    func markFailed(detail: String? = nil) {
        guard let environment else { return }
        environment.status = .completed
        environment.completedAt = Date()
        environment.setSessionPhase(.aborted)
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
}
