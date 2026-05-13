import Foundation

extension MissionRunEnvironment {

    /// Phase A (Mission Run SIM clean up): revoke graceful after-cycle intent, cancel **all** pending executor batches
    /// (every ``MissionRunCommandQueueTag`` and every ``MissionRunQueuedCommandDispatch``), and clear fleet-side
    /// operator session hints so catalogue work cannot race a finished run.
    ///
    /// Call from ``MissionRunLifecycleSubsystem/markCompleted`` after roster Live Drive handoff flags are cleared
    /// and before ``MissionRunSchedulingSubsystem/cancelAllScheduledTasks``.
    func cancelPendingCommandBatchesAndFleetHintsAfterRunCompleted() {
        systems.scheduling.revokeGracefulAfterCycleStop()
        let removed = systems.executor.cancelPendingCommandBatches(
            tags: Set(MissionRunCommandQueueTag.allCases),
            whereDispatch: nil
        )
        if removed > 0 {
            systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.executorPendingBatchesCancelledForRunCompleted,
                templateParams: ["removedCount": String(removed)]
            )
        }
        fleetLink?.clearOperatorSessionHintsAfterMissionRunCompleted()
    }
}
