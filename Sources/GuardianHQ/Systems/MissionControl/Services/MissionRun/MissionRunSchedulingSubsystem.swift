import Foundation

@MainActor
final class MissionRunSchedulingSubsystem {
    weak var environment: MissionRunEnvironment?
    private var deferredTaskStartTasks: [UUID: Task<Void, Never>] = [:]
    private var deferredOneOffStartTask: Task<Void, Never>?

    /// Operator intent: abort after the current autopilot mission cycle. Queues a tagged batch (replaceable/revocable).
    func abortAfterCycle() {
        guard let environment else { return }
        revokeGracefulAfterCycleStop()
        _ = environment.systems.planner.buildAbortPlan(trigger: .afterCycle)
        let commands = (environment.systems.planner.lastBuiltAbortPlan?.entries ?? [])
            .flatMap(\.issuedCommands)
            .map { $0.reattributed(issuer: .operator, issuerKey: MissionRunCommandIssuerKey.localOperator) }
        if let ctx = environment.lastExecutionContext {
            let batch = MissionRunQueuedCommandBatch(
                tag: .abort,
                dispatch: .afterMissionCycle,
                commands: commands
            )
            environment.systems.executor.enqueueCommandBatch(batch, context: ctx)
        } else if !commands.isEmpty {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.scheduleAbortAfterCycleNotQueuedNoContext
            )
        }
        environment.gracefulStopKind = .abortAfterCycle
    }

    /// Operator intent: finish after the current cycle using recovery wind-down (RTL), then recovery → completed in UI.
    func completeAfterCycle() {
        guard let environment else { return }
        revokeGracefulAfterCycleStop()
        let commands = environment.systems.executor.buildCompletePolicyWindDownCommands()
        if let ctx = environment.lastExecutionContext {
            let batch = MissionRunQueuedCommandBatch(
                tag: .complete,
                dispatch: .afterMissionCycle,
                commands: commands
            )
            environment.systems.executor.enqueueCommandBatch(batch, context: ctx)
        } else if !commands.isEmpty {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.scheduleCompleteAfterCycleNotQueuedNoContext
            )
        }
        environment.gracefulStopKind = .completeAfterCycle
    }

    /// Immediate recovery wind-down (RTL per slot), then run enters recovery for operator “mark completed”.
    func completeNow() {
        guard let environment else { return }
        revokeGracefulAfterCycleStop()
        guard let ctx = environment.lastExecutionContext else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.scheduleCompleteNowSkippedNoContext
            )
            return
        }
        environment.systems.executor.performImmediateComplete(context: ctx)
    }

    /// Operator intent: abort immediately (dispatch abort plan, complete run).
    func abortNow() {
        guard let environment else { return }
        revokeGracefulAfterCycleStop()
        _ = environment.systems.planner.buildAbortPlan(trigger: .now)
        let commands = (environment.systems.planner.lastBuiltAbortPlan?.entries ?? [])
            .flatMap(\.issuedCommands)
            .map { $0.reattributed(issuer: .operator, issuerKey: MissionRunCommandIssuerKey.localOperator) }
        guard let ctx = environment.lastExecutionContext else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.scheduleAbortNowSkippedNoContext
            )
            return
        }
        environment.systems.executor.performImmediateAbort(commands: commands, context: ctx)
    }

    /// Clears graceful after-cycle intent and removes queued abort / complete wind-down batches (if any).
    func revokeGracefulAfterCycleStop() {
        guard let environment else { return }
        environment.gracefulStopKind = .none
        environment.clearPendingMissionTaskGracefulWindDown(forTaskID: nil)
        _ = environment.systems.executor.cancelPendingCommandBatches(
            tags: [.abort, .complete],
            whereDispatch: {
                if case .afterMissionCycle = $0 { return true }
                return false
            }
        )
    }

    func setDeferredOneOffExecution(_ value: MissionOneOffDeferredExecution?) {
        environment?.setOneOffDeferredExecution(value)
    }

    func setTaskStartDeferral(_ value: MissionTaskStartDeferral?, forTaskID taskID: UUID) {
        guard let environment else { return }
        environment.mutateTaskStartDeferral(forTaskID: taskID, value: value)
    }

    func clearMissionTaskStartDeferral(forTaskID taskID: UUID? = nil) {
        guard let environment else { return }
        environment.clearTaskStartDeferral(forTaskID: taskID)
    }

    func scheduleDeferredOneOffExecution(executeAt: Date) {
        let snapshot = MissionOneOffDeferredExecution(executeAt: executeAt, countdownStartedAt: Date())
        environment?.setOneOffDeferredExecution(snapshot)
        environment?.setSessionPhase(.staging)
    }

    func scheduleDeferredOneOffExecution(
        executeAt: Date,
        onExecutionReady: @escaping @MainActor () -> Void
    ) {
        scheduleDeferredOneOffExecution(executeAt: executeAt)
        armDeferredOneOffExecutionTask(executeAt: executeAt, onExecutionReady: onExecutionReady)
    }

    func clearDeferredOneOffExecution() {
        environment?.setOneOffDeferredExecution(nil)
        registerDeferredOneOffTask(nil)
    }

    /// Shifts the scheduled one-off mission start by `deltaSeconds` (negative = sooner). If the new time is not after `referenceNow`, behaves like **Start now** (`beginRun` + `onExecutionReady`).
    func adjustDeferredOneOffExecutionBySeconds(
        _ deltaSeconds: Int,
        referenceNow: Date = Date(),
        onExecutionReady: @escaping @MainActor () -> Void
    ) {
        guard let environment, let current = environment.oneOffDeferredExecution else { return }
        let newExecuteAt = current.executeAt.addingTimeInterval(Double(deltaSeconds))
        if newExecuteAt <= referenceNow {
            clearDeferredOneOffExecution()
            environment.beginRun()
            onExecutionReady()
        } else {
            environment.setOneOffDeferredExecution(
                MissionOneOffDeferredExecution(executeAt: newExecuteAt, countdownStartedAt: Date())
            )
            environment.oneOffStartAt = newExecuteAt
            armDeferredOneOffExecutionTask(executeAt: newExecuteAt, onExecutionReady: onExecutionReady)
        }
    }

    func postponeDeferredOneOffExecutionByMinutes(
        _ additionalMinutes: Int,
        onExecutionReady: @escaping @MainActor () -> Void
    ) {
        adjustDeferredOneOffExecutionBySeconds(additionalMinutes * 60, referenceNow: Date(), onExecutionReady: onExecutionReady)
    }

    func postponeDeferredOneOffExecutionBySeconds(
        _ additionalSeconds: Int,
        onExecutionReady: @escaping @MainActor () -> Void
    ) {
        adjustDeferredOneOffExecutionBySeconds(max(0, additionalSeconds), referenceNow: Date(), onExecutionReady: onExecutionReady)
    }

    func beginDeferredOneOffNow() {
        clearDeferredOneOffExecution()
        environment?.beginRun()
    }

    func beginDeferredOneOffImmediately() {
        beginDeferredOneOffNow()
    }

    /// Mission runs no longer schedule a follow-on autopilot cycle.
    func cancelScheduledMissionCycle(forTaskID _: UUID? = nil) {}

    func registerDeferredTaskStartTask(_ task: Task<Void, Never>?, forTaskID taskID: UUID) {
        deferredTaskStartTasks[taskID]?.cancel()
        deferredTaskStartTasks[taskID] = task
    }

    func cancelScheduledTaskMissionStarts(forTaskID taskID: UUID? = nil) {
        if let taskID {
            deferredTaskStartTasks[taskID]?.cancel()
            deferredTaskStartTasks.removeValue(forKey: taskID)
            clearMissionTaskStartDeferral(forTaskID: taskID)
        } else {
            deferredTaskStartTasks.values.forEach { $0.cancel() }
            deferredTaskStartTasks.removeAll()
            clearMissionTaskStartDeferral()
        }
    }

    func registerDeferredOneOffTask(_ task: Task<Void, Never>?) {
        deferredOneOffStartTask?.cancel()
        deferredOneOffStartTask = task
    }

    func cancelAllScheduledTasks() {
        cancelScheduledMissionCycle()
        cancelScheduledTaskMissionStarts()
        deferredOneOffStartTask?.cancel()
        deferredOneOffStartTask = nil
    }

    func skipMissionTaskStartDeferral(taskID: UUID) {
        guard environment?.taskStartDeferralByTaskID[taskID] != nil else { return }
        cancelScheduledTaskMissionStarts(forTaskID: taskID)
        startDeferredTaskNow(taskID: taskID)
    }

    func extendMissionTaskStartDeferralByMinutes(
        taskID: UUID,
        additionalMinutes: Int
    ) {
        extendMissionTaskStartDeferralBySeconds(taskID: taskID, additionalSeconds: additionalMinutes * 60)
    }

    func extendMissionTaskStartDeferralBySeconds(
        taskID: UUID,
        additionalSeconds: Int
    ) {
        adjustMissionTaskStartDeferralBySeconds(taskID: taskID, deltaSeconds: max(0, additionalSeconds), referenceNow: Date())
    }

    /// Shifts a pending MAVLink mission start (initial or between-cycle deferral) by `deltaSeconds` (negative = sooner). If the new start is not after `referenceNow`, starts immediately like **Start**.
    func adjustMissionTaskStartDeferralBySeconds(
        taskID: UUID,
        deltaSeconds: Int,
        referenceNow: Date = Date()
    ) {
        guard let environment, let def = environment.taskStartDeferralByTaskID[taskID] else { return }
        let delta = Double(deltaSeconds)
        let newStart = def.startAt.addingTimeInterval(delta)
        if newStart <= referenceNow {
            skipMissionTaskStartDeferral(taskID: taskID)
            return
        }
        let newTotal = max(1, def.totalDelay + delta)
        cancelScheduledTaskMissionStarts(forTaskID: taskID)
        setTaskStartDeferral(MissionTaskStartDeferral(startAt: newStart, totalDelay: newTotal), forTaskID: taskID)
        armTaskMissionStartTask(taskID: taskID, startAt: newStart) { [weak self] in
            self?.startDeferredTaskNow(taskID: taskID)
        }
    }

    private func startDeferredTaskNow(taskID: UUID) {
        guard let environment else { return }
        guard let ctx = environment.effectiveExecutionContextForDispatch() else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.startMissionTaskNoExecutionContext
            )
            return
        }
        environment.captureExecutionContext(ctx)
        _ = environment.systems.executor.handleEvent(.deferredTaskStartDue(taskID: taskID), context: ctx)
    }

    func armTaskMissionStartTask(taskID: UUID, startAt: Date, onStartNow: @escaping @MainActor () -> Void) {
        registerDeferredTaskStartTask(nil, forTaskID: taskID)
        let captured = startAt
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = captured.timeIntervalSince(Date())
                if remaining <= 0.05 { break }
                let chunk = min(remaining, 3600)
                let rawNs = chunk * 1_000_000_000
                guard rawNs.isFinite, rawNs > 0 else { break }
                let ns = UInt64(min(Double(UInt64.max), max(1_000_000, rawNs)))
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            guard let stored = self.environment?.taskStartDeferralByTaskID[taskID],
                  abs(stored.startAt.timeIntervalSince(captured)) < 0.5
            else { return }
            onStartNow()
        }
        registerDeferredTaskStartTask(task, forTaskID: taskID)
    }

    private func armDeferredOneOffExecutionTask(
        executeAt: Date,
        onExecutionReady: @escaping @MainActor () -> Void
    ) {
        registerDeferredOneOffTask(nil)
        let captured = executeAt
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = captured.timeIntervalSince(Date())
                if remaining <= 0.05 { break }
                let chunk = min(remaining, 3600)
                let rawNs = chunk * 1_000_000_000
                guard rawNs.isFinite, rawNs > 0 else { break }
                let clamped = min(rawNs, Double(UInt64.max))
                let ns = UInt64(max(1_000_000, clamped))
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            guard let environment = self.environment,
                  environment.status == .running,
                  let stored = environment.oneOffDeferredExecution,
                  stored.executeAt == captured
            else { return }
            self.registerDeferredOneOffTask(nil)
            self.setDeferredOneOffExecution(nil)
            onExecutionReady()
        }
        registerDeferredOneOffTask(task)
    }

    // MARK: - Task-scoped wind-down (abort / complete)

    func revokeMissionTaskGracefulWindDown(forTaskID taskID: UUID?) {
        environment?.clearPendingMissionTaskGracefulWindDown(forTaskID: taskID)
    }

    /// Schedules abort-policy fleet commands for one path’s bound slots at the next shared autopilot cycle boundary.
    func abortMissionTaskAfterCycle(target: MissionRunCommandTarget) {
        guard let environment, case .task(let taskID) = target else { return }
        guard environment.gracefulStopKind == .none else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskAbortGracefulSkippedWholeRunStopActive
            )
            return
        }
        guard let mission = environment.template,
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
              task.enabled
        else { return }
        if environment.assignmentsBoundToMissionTask(taskID: taskID).isEmpty {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: task.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskAbortGracefulSkippedNoSlots,
                templateParams: [:]
            )
            return
        }
        environment.clearPendingMissionTaskGracefulWindDown(forTaskID: taskID)
        environment.setPendingMissionTaskGracefulWindDown(kind: .abortAfterCycle, forTaskID: taskID)
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: task.name,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionTaskAbortGracefulScheduled,
            templateParams: ["task": task.name]
        )
    }

    /// Schedules complete-policy recovery wind-down for one path’s bound slots at the next shared autopilot cycle boundary.
    func completeMissionTaskAfterCycle(target: MissionRunCommandTarget) {
        guard let environment, case .task(let taskID) = target else { return }
        guard environment.gracefulStopKind == .none else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulSkippedWholeRunStopActive
            )
            return
        }
        guard let mission = environment.template,
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
              task.enabled
        else { return }
        if environment.assignmentsBoundToMissionTask(taskID: taskID).isEmpty {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: task.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulSkippedNoSlots,
                templateParams: [:]
            )
            return
        }
        environment.clearPendingMissionTaskGracefulWindDown(forTaskID: taskID)
        environment.setPendingMissionTaskGracefulWindDown(kind: .completeAfterCycle, forTaskID: taskID)
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: task.name,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulScheduled,
            templateParams: ["task": task.name]
        )
    }

    @discardableResult
    func abortMissionTaskNow(target: MissionRunCommandTarget, context: MissionRunExecutionContext) -> Bool {
        guard let environment else { return false }
        return environment.systems.executor.performImmediateMissionTaskAbort(target: target, context: context)
    }

    @discardableResult
    func completeMissionTaskNow(target: MissionRunCommandTarget, context: MissionRunExecutionContext) -> Bool {
        guard let environment else { return false }
        return environment.systems.executor.performImmediateMissionTaskComplete(target: target, context: context)
    }
}
