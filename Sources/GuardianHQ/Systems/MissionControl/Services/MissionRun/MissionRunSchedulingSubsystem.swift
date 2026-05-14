import Foundation

@MainActor
final class MissionRunSchedulingSubsystem {
    weak var environment: MissionRunEnvironment?
    private var deferredTaskStartTasks: [UUID: Task<Void, Never>] = [:]
    private var deferredOneOffStartTask: Task<Void, Never>?

    private func enabledMissionTaskIDsWithBoundAssignments(in environment: MissionRunEnvironment) -> [UUID] {
        guard let mission = environment.template else { return [] }
        return mission.routeMacro.tasks.filter(\.enabled).compactMap { task in
            environment.assignmentsBoundToMissionTask(taskID: task.id).isEmpty ? nil : task.id
        }
    }

    /// Mission-level **complete** / **complete after cycle** leaves tasks in abort or recovery wind-down untouched.
    private func shouldLeaveTaskUnchangedForMissionLevelComplete(state: MissionTaskState) -> Bool {
        switch state {
        case .aborting, .aborted, .recovery, .completed:
            return true
        case .compiling, .ready, .staging, .executing, .between:
            return false
        }
    }

    /// Mission-level **abort** / **abort after cycle** leaves tasks already in terminal abort or completed paths untouched.
    private func shouldLeaveTaskUnchangedForMissionLevelAbort(state: MissionTaskState) -> Bool {
        switch state {
        case .aborting, .aborted, .completed:
            return true
        case .compiling, .ready, .staging, .executing, .between, .recovery:
            return false
        }
    }

    /// Operator intent: abort after each task’s current autopilot mission cycle. Delegates to each bound path’s
    /// ``abortMissionTaskAfterCycle`` (or ``abortMissionTaskNow`` when the task is already in **recovery**, switching it
    /// into abort protocol). Does **not** bulk-cancel other tasks’ deferrals.
    func abortAfterCycle() {
        guard let environment else { return }
        environment.refreshDerivedTaskStates()
        revokeGracefulAfterCycleStop()
        let targets = enabledMissionTaskIDsWithBoundAssignments(in: environment)
        let ctx = environment.lastExecutionContext ?? environment.effectiveExecutionContextForDispatch()
        var anyEngaged = false
        var needsContextForRecoveryAbort = false
        for taskID in targets {
            let state = environment.taskStateByTaskID[taskID] ?? .ready
            guard !shouldLeaveTaskUnchangedForMissionLevelAbort(state: state) else { continue }
            if state == .recovery {
                guard let ctx else {
                    needsContextForRecoveryAbort = true
                    continue
                }
                if abortMissionTaskNow(target: .task(taskID), context: ctx) {
                    anyEngaged = true
                }
                continue
            }
            if abortMissionTaskAfterCycle(target: .task(taskID)) {
                anyEngaged = true
            }
        }
        if needsContextForRecoveryAbort {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.scheduleAbortAfterCycleNotQueuedNoContext
            )
        }
        if anyEngaged {
            environment.gracefulStopKind = .abortAfterCycle
        }
    }

    /// Operator intent: finish after each task’s current autopilot cycle using per-slot recovery wind-down. Delegates to
    /// each bound path’s ``completeMissionTaskAfterCycle`` (skipping tasks already in abort or recovery wind-down).
    func completeAfterCycle() {
        guard let environment else { return }
        environment.refreshDerivedTaskStates()
        revokeGracefulAfterCycleStop()
        let targets = enabledMissionTaskIDsWithBoundAssignments(in: environment)
        var anyEngaged = false
        var needsDispatchContextForIdle = false
        for taskID in targets {
            let state = environment.taskStateByTaskID[taskID] ?? .ready
            guard !shouldLeaveTaskUnchangedForMissionLevelComplete(state: state) else { continue }
            if !environment.activeCycleTaskIDs.contains(taskID),
               environment.lastExecutionContext == nil,
               environment.effectiveExecutionContextForDispatch() == nil {
                needsDispatchContextForIdle = true
            }
            if completeMissionTaskAfterCycle(target: .task(taskID)) {
                anyEngaged = true
            }
        }
        if needsDispatchContextForIdle {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.scheduleCompleteAfterCycleNotQueuedNoContext
            )
        }
        if anyEngaged {
            environment.gracefulStopKind = .completeAfterCycle
        }
    }

    /// Immediate recovery wind-down per bound path, then run enters recovery for operator “mark completed”.
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
        environment.refreshDerivedTaskStates()
        environment.systems.executor.clearCommandQueue()
        let targets = enabledMissionTaskIDsWithBoundAssignments(in: environment)
        var anyEngaged = false
        for taskID in targets {
            let state = environment.taskStateByTaskID[taskID] ?? .ready
            guard !shouldLeaveTaskUnchangedForMissionLevelComplete(state: state) else { continue }
            if completeMissionTaskNow(target: .task(taskID), context: ctx) {
                anyEngaged = true
            }
        }
        guard anyEngaged else { return }
        environment.captureExecutionContext(ctx)
        environment.completionKind = .operatorCompletedImmediate
        environment.status = .recovery
        environment.setSessionPhase(.recovery)
        environment.systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.runCompleteWindDownImmediate,
            templateParams: [:]
        )
    }

    /// Operator intent: abort immediately — dispatches each eligible path’s abort plan (``abortMissionTaskNow``).
    func abortNow() {
        guard let environment else { return }
        revokeGracefulAfterCycleStop()
        guard let ctx = environment.lastExecutionContext else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.scheduleAbortNowSkippedNoContext
            )
            return
        }
        environment.refreshDerivedTaskStates()
        environment.systems.executor.clearCommandQueue()
        let targets = enabledMissionTaskIDsWithBoundAssignments(in: environment)
        var anyEngaged = false
        for taskID in targets {
            let state = environment.taskStateByTaskID[taskID] ?? .ready
            guard !shouldLeaveTaskUnchangedForMissionLevelAbort(state: state) else { continue }
            if abortMissionTaskNow(target: .task(taskID), context: ctx) {
                anyEngaged = true
            }
        }
        guard anyEngaged else { return }
        cancelAllScheduledTasks()
        environment.captureExecutionContext(ctx)
        environment.completionKind = .operatorStoppedImmediate
        environment.setSessionPhase(.aborting)
        environment.systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.runStoppedImmediate,
            templateParams: [:]
        )
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

    /// Cancels the wall-clock waiter for a deferred MAVLink mission start **without** clearing ``taskStartDeferralByTaskID`` (so UI/derivation stays in deferral until ``beginStartMissionTask`` clears it).
    ///
    /// **Discipline:** Any path that will run ``beginStartMissionTask`` should cancel the waiter first (skip, operator start, reschedule, or ``beginStartMissionTask`` itself as a no-op if already cleared). The waiter’s own ``Task`` must not call this immediately before ``onStartNow`` — it uses ``dropDeferredTaskMissionStartWaiterSlotWithoutCancelling(forTaskID:)`` instead so the running task is not self-cancelled.
    func cancelDeferredTaskMissionStartWaiter(forTaskID taskID: UUID) {
        deferredTaskStartTasks[taskID]?.cancel()
        deferredTaskStartTasks.removeValue(forKey: taskID)
    }

    /// Drops the waiter registry entry **without** ``Task/cancel`` — only for the waiter task’s own fire path, right before ``onStartNow`` (which calls ``beginStartMissionTask`` → ``cancelDeferredTaskMissionStartWaiter`` on an already-empty slot).
    private func dropDeferredTaskMissionStartWaiterSlotWithoutCancelling(forTaskID taskID: UUID) {
        deferredTaskStartTasks.removeValue(forKey: taskID)
    }

    func cancelScheduledTaskMissionStarts(forTaskID taskID: UUID? = nil) {
        if let taskID {
            cancelDeferredTaskMissionStartWaiter(forTaskID: taskID)
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
        clearDeferredOneOffExecution()
    }

    func skipMissionTaskStartDeferral(taskID: UUID) {
        guard let environment, environment.taskStartDeferralByTaskID[taskID] != nil else { return }
        cancelDeferredTaskMissionStartWaiter(forTaskID: taskID)
        startDeferredTaskMissionNow(taskID: taskID)
        if environment.taskStartDeferralByTaskID[taskID] != nil {
            clearMissionTaskStartDeferral(forTaskID: taskID)
        }
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
        cancelDeferredTaskMissionStartWaiter(forTaskID: taskID)
        setTaskStartDeferral(MissionTaskStartDeferral(startAt: newStart, totalDelay: newTotal), forTaskID: taskID)
        armTaskMissionStartTask(taskID: taskID, startAt: newStart) { [weak self] in
            self?.startDeferredTaskMissionNow(taskID: taskID)
        }
    }

    /// Dispatches ``MissionRunExecutionEvent/deferredTaskStartDue`` when an execution context exists.
    private func startDeferredTaskMissionNow(taskID: UUID) {
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
            self.dropDeferredTaskMissionStartWaiterSlotWithoutCancelling(forTaskID: taskID)
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

    /// Cancels this task’s deferred MAVLink start (initial or between-cycle). If the task is **not** in an in-flight
    /// autopilot cycle, delivers any **already-set** pending graceful wind-down immediately when dispatch context exists.
    private func cancelDeferredStartsAndDeliverGracefulIfIdle(taskID: UUID, environment: MissionRunEnvironment) {
        cancelScheduledTaskMissionStarts(forTaskID: taskID)
        guard !environment.activeCycleTaskIDs.contains(taskID) else { return }
        guard let ctx = environment.lastExecutionContext ?? environment.effectiveExecutionContextForDispatch() else {
            return
        }
        environment.captureExecutionContext(ctx)
        environment.systems.executor.deliverPendingMissionTaskGracefulWindDownsIfNeeded(
            completedCycleTaskIDs: [taskID],
            context: ctx
        )
    }

    func revokeMissionTaskGracefulWindDown(forTaskID taskID: UUID?) {
        environment?.clearPendingMissionTaskGracefulWindDown(forTaskID: taskID)
    }

    /// Schedules abort-policy fleet commands for one path’s bound slots after its **current** autopilot mission cycle ends, or **immediately** if the path is idle (including between-cycle delay: the deferral is cancelled).
    @discardableResult
    func abortMissionTaskAfterCycle(target: MissionRunCommandTarget) -> Bool {
        guard let environment, case .task(let taskID) = target else { return false }
        guard environment.gracefulStopKind == .none else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskAbortGracefulSkippedWholeRunStopActive
            )
            return false
        }
        guard let mission = environment.template,
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
              task.enabled
        else { return false }
        if environment.assignmentsBoundToMissionTask(taskID: taskID).isEmpty {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: task.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskAbortGracefulSkippedNoSlots,
                templateParams: [:]
            )
            return false
        }
        environment.clearPendingMissionTaskGracefulWindDown(forTaskID: taskID)
        environment.setPendingMissionTaskGracefulWindDown(kind: .abortAfterCycle, forTaskID: taskID)
        cancelDeferredStartsAndDeliverGracefulIfIdle(taskID: taskID, environment: environment)
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: task.name,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionTaskAbortGracefulScheduled,
            templateParams: ["task": task.name]
        )
        return true
    }

    /// Schedules complete-policy recovery wind-down for one path’s bound slots after its **current** autopilot mission cycle ends, or **immediately** if the path is idle (including between-cycle delay: the deferral is cancelled).
    @discardableResult
    func completeMissionTaskAfterCycle(target: MissionRunCommandTarget) -> Bool {
        guard let environment, case .task(let taskID) = target else { return false }
        guard environment.gracefulStopKind == .none else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulSkippedWholeRunStopActive
            )
            return false
        }
        guard let mission = environment.template,
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
              task.enabled
        else { return false }
        if environment.assignmentsBoundToMissionTask(taskID: taskID).isEmpty {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: task.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulSkippedNoSlots,
                templateParams: [:]
            )
            return false
        }
        environment.clearPendingMissionTaskGracefulWindDown(forTaskID: taskID)
        environment.setPendingMissionTaskGracefulWindDown(kind: .completeAfterCycle, forTaskID: taskID)
        cancelDeferredStartsAndDeliverGracefulIfIdle(taskID: taskID, environment: environment)
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: task.name,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulScheduled,
            templateParams: ["task": task.name]
        )
        return true
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
