import Foundation

@MainActor
final class MissionRunSchedulingSubsystem {
    weak var environment: MissionRunEnvironment?
    private var deferredTaskStartTasks: [UUID: Task<Void, Never>] = [:]
    private var deferredOneOffStartTask: Task<Void, Never>?

    /// Operator intent: abort after the current autopilot mission cycle. Queues a tagged batch (replaceable/revocable).
    func abortAfterCycle() {
        guard let environment else { return }
        _ = environment.systems.planner.buildAbortPlan(trigger: .afterCycle)
        let commands = (environment.systems.planner.lastBuiltAbortPlan?.entries ?? [])
            .compactMap(\.issuedCommand)
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
                message: "Abort-after-cycle plan built but not queued — no execution context yet (start or cycle activity first)."
            )
        }
        environment.pendingGracefulCycleStop = true
    }

    /// Operator intent: abort immediately (dispatch abort plan, complete run).
    func abortNow() {
        guard let environment else { return }
        _ = environment.systems.planner.buildAbortPlan(trigger: .now)
        let commands = (environment.systems.planner.lastBuiltAbortPlan?.entries ?? [])
            .compactMap(\.issuedCommand)
            .map { $0.reattributed(issuer: .operator, issuerKey: MissionRunCommandIssuerKey.localOperator) }
        guard let ctx = environment.lastExecutionContext else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                message: "Abort now skipped — no execution context (fleet session not captured)."
            )
            return
        }
        environment.systems.executor.performImmediateAbort(commands: commands, context: ctx)
    }

    /// Clears graceful abort-after-cycle intent and removes the matching queued batch (if any).
    func revokeAbortAfterCycle() {
        guard let environment else { return }
        environment.pendingGracefulCycleStop = false
        _ = environment.systems.executor.cancelPendingCommandBatches(
            tags: [.abort],
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

    func postponeDeferredOneOffExecution(byMinutes additionalMinutes: Int) {
        guard let environment, let current = environment.oneOffDeferredExecution else { return }
        let mins = min(30, max(1, additionalMinutes))
        let executeAt = current.executeAt.addingTimeInterval(Double(mins) * 60)
        environment.setOneOffDeferredExecution(MissionOneOffDeferredExecution(executeAt: executeAt, countdownStartedAt: Date()))
        environment.oneOffStartAt = executeAt
    }

    func postponeDeferredOneOffExecutionByMinutes(
        _ additionalMinutes: Int,
        onExecutionReady: @escaping @MainActor () -> Void
    ) {
        postponeDeferredOneOffExecution(byMinutes: additionalMinutes)
        guard let executeAt = environment?.oneOffDeferredExecution?.executeAt else { return }
        armDeferredOneOffExecutionTask(executeAt: executeAt, onExecutionReady: onExecutionReady)
    }

    func beginDeferredOneOffNow() {
        clearDeferredOneOffExecution()
        environment?.beginRun()
    }

    func beginDeferredOneOffImmediately() {
        beginDeferredOneOffNow()
    }

    /// Operator-triggered task run (manual fire while mission is running).
    func triggerOperatorTaskStart(taskID: UUID) {
        guard let environment else { return }
        guard let mission = environment.lastExecutionContext?.missionProvider(),
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
              task.enabled,
              task.regularity == .operatorTriggered
        else { return }
        guard let ctx = environment.lastExecutionContext else { return }
        _ = environment.systems.executor.handleEvent(.deferredTaskStartDue(taskID: taskID), context: ctx)
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
        guard let environment, let def = environment.taskStartDeferralByTaskID[taskID] else { return }
        let mins = min(30, max(1, additionalMinutes))
        cancelScheduledTaskMissionStarts(forTaskID: taskID)
        let addSec = Double(mins) * 60
        let newStart = def.startAt.addingTimeInterval(addSec)
        let newTotal = def.totalDelay + addSec
        setTaskStartDeferral(MissionTaskStartDeferral(startAt: newStart, totalDelay: newTotal), forTaskID: taskID)
        armTaskMissionStartTask(taskID: taskID, startAt: newStart) { [weak self] in
            self?.startDeferredTaskNow(taskID: taskID)
        }
    }

    private func startDeferredTaskNow(taskID: UUID) {
        guard let environment else { return }
        guard let ctx = environment.lastExecutionContext else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                message: "Task start-now skipped — no execution context."
            )
            return
        }
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
}
