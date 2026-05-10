import Foundation

/// Whether a wind-down ends in **recovery** (success protocol) or **abort** (``MissionRunSessionPhase/aborting``).
private enum MissionRunOperatorWindDown {
    case recoveryPhase
    case abortProtocolPhase
}

@MainActor
final class MissionRunExecutionSubsystem {
    weak var environment: MissionRunEnvironment?

    private var pendingCommandBatches: [MissionRunQueuedCommandBatch] = []
    private var wallClockBatchTasks: [UUID: Task<Void, Never>] = [:]

    /// Pending batches not yet delivered (e.g. after-cycle or wall-clock); for UI/diagnostics.
    var pendingCommandBatchesSnapshot: [MissionRunQueuedCommandBatch] { pendingCommandBatches }

    var stage: MissionRunExecutionStage {
        guard let environment else { return .idle }
        switch environment.sessionPhase {
        case .draft, .compiled:
            return .idle
        case .staging:
            return .staging
        case .executing:
            return environment.status == .paused ? .paused : .running
        case .recovery:
            return .teardown
        case .completed:
            return .completed
        case .aborting:
            return .teardown
        case .aborted:
            return .failed
        }
    }

    var cursor: MissionRunExecutionCursor {
        MissionRunExecutionCursor(activeTaskID: nil, cycleCount: environment?.cyclesCompleted ?? 0)
    }

    @discardableResult
    func startExecution(context: MissionRunExecutionContext) -> MissionRunExecutionDecision {
        guard let environment else { return .noOp }
        clearCommandQueue()
        environment.captureExecutionContext(context)
        environment.clearMissionTaskScopedOrchestrationState()
        environment.clearFinishedMissionCycleVehicleIDs()
        environment.clearActiveCycleTasks()
        environment.clearTaskCycleCompletionCounts()
        environment.systems.scheduling.cancelScheduledMissionCycle()
        environment.systems.scheduling.cancelScheduledTaskMissionStarts()
        environment.systems.scheduling.clearDeferredOneOffExecution()
        environment.setMissionCycleCount(0)
        environment.systems.logging.clearState()
        environment.systems.lifecycle.markExecuting()
        if environment.startedAt == nil {
            environment.startedAt = Date()
        }
        environment.systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.executionStarted
        )

        let staging = buildStagingPass(mission: context.mission)
        staging.events.forEach { environment.appendEvent($0) }
        for issued in staging.commands {
            environment.appendEvent(environment.systems.commands.dispatchCommand(issued, fleetLink: context.fleetLink, sitl: context.sitl))
        }

        guard let mission = context.mission else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.executionMissionMissing
            )
            return .started
        }

        launchInitialMissionBatches(
            mission: mission,
            fleetLink: context.fleetLink,
            sitl: context.sitl,
            missionProvider: context.missionProvider
        )
        return .started
    }

    @discardableResult
    func pauseExecution() -> MissionRunExecutionDecision {
        environment?.systems.lifecycle.pauseRun()
        return .paused
    }

    @discardableResult
    func resumeExecution() -> MissionRunExecutionDecision {
        environment?.systems.lifecycle.resumeRun()
        return .resumed
    }

    @discardableResult
    func requestStop(mode: MissionRunExecutionStopMode) -> MissionRunExecutionDecision {
        guard let environment else { return .noOp }
        switch mode {
        case .immediate:
            environment.systems.scheduling.abortNow()
        case .afterCycle:
            environment.systems.scheduling.abortAfterCycle()
        }
        return .stopRequested(mode)
    }

    @discardableResult
    func handleEvent(
        _ event: MissionRunExecutionEvent,
        context: MissionRunExecutionContext
    ) -> MissionRunExecutionDecision {
        environment?.captureExecutionContext(context)
        switch event {
        case .missionCycleFinished(let vehicleID):
            return processMissionCycleFinished(vehicleID: vehicleID, context: context)
        case .deferredTaskStartDue(let taskID):
            return beginStartMissionTask(taskID: taskID, context: context, allowDuringStaging: false) ? .progressed : .noOp
        }
    }

    /// Explicit per-task MAVLink start (operator trigger, retry, etc.). Allows **staging** or **executing** session phase.
    @discardableResult
    func startMissionTask(taskID: UUID, context: MissionRunExecutionContext) -> Bool {
        return beginStartMissionTask(taskID: taskID, context: context, allowDuringStaging: true)
    }

    /// Shared path for timer-driven deferrals and ``startMissionTask``.
    @discardableResult
    private func beginStartMissionTask(
        taskID: UUID,
        context: MissionRunExecutionContext,
        allowDuringStaging: Bool
    ) -> Bool {
        guard let environment else { return false }
        if environment.taskStateByTaskID[taskID] == .executing { return false }
        environment.systems.scheduling.registerDeferredTaskStartTask(nil, forTaskID: taskID)
        environment.systems.scheduling.clearMissionTaskStartDeferral(forTaskID: taskID)
        guard environment.status == .running else { return false }
        guard let mission = context.missionProvider() else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.scheduleSkipNoMission
            )
            return false
        }
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }), task.enabled else { return false }
        environment.prepareMissionTaskForOperatorRestart(taskID: taskID)
        return startTaskExecution(
            taskID: taskID,
            mission: mission,
            context: context,
            allowDuringStaging: allowDuringStaging
        )
    }

    @discardableResult
    func applyPlanRevision(_ revision: Int, strategy: MissionRunExecutionStrategy) -> MissionRunExecutionDecision {
        guard let environment else { return .noOp }
        guard environment.systems.planner.revision >= revision else { return .noOp }
        switch strategy {
        case .immediate:
            environment.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.planRevisionAppliedImmediate,
                templateParams: ["revision": String(revision)]
            )
        case .safePoint:
            environment.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.planRevisionQueuedSafePoint,
                templateParams: ["revision": String(revision)]
            )
        case .nextCycle:
            environment.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.planRevisionQueuedNextCycle,
                templateParams: ["revision": String(revision)]
            )
        }
        return .progressed
    }

    @discardableResult
    func tick(context: MissionRunExecutionContext) -> MissionRunExecutionDecision {
        guard let environment else { return .noOp }
        environment.captureExecutionContext(context)
        guard environment.status == .running else { return .noOp }
        return .noOp
    }

    /// Drops all pending batches and cancels wall-clock waiters.
    func clearCommandQueue() {
        for (_, task) in wallClockBatchTasks {
            task.cancel()
        }
        wallClockBatchTasks.removeAll()
        pendingCommandBatches.removeAll()
    }

    /// Removes pending batches matching `tags`, optionally narrowed by `whereDispatch`.
    @discardableResult
    func cancelPendingCommandBatches(
        tags: Set<MissionRunCommandQueueTag>,
        whereDispatch matches: ((MissionRunQueuedCommandDispatch) -> Bool)? = nil
    ) -> Int {
        let removed = pendingCommandBatches.filter { batch in
            guard tags.contains(batch.tag) else { return false }
            if let matches {
                return matches(batch.dispatch)
            }
            return true
        }
        for batch in removed {
            wallClockBatchTasks[batch.id]?.cancel()
            wallClockBatchTasks.removeValue(forKey: batch.id)
        }
        let removedIDs = Set(removed.map(\.id))
        pendingCommandBatches.removeAll { removedIDs.contains($0.id) }
        return removed.count
    }

    /// - Parameter replacingTags: `nil` → cancel pending batches with the same `tag` as `batch` before enqueueing. Empty set → do not cancel.
    func enqueueCommandBatch(
        _ batch: MissionRunQueuedCommandBatch,
        context: MissionRunExecutionContext,
        replacingTags: Set<MissionRunCommandQueueTag>? = nil
    ) {
        if let explicit = replacingTags {
            if !explicit.isEmpty {
                _ = cancelPendingCommandBatches(tags: explicit)
            }
        } else {
            _ = cancelPendingCommandBatches(tags: Set([batch.tag]))
        }

        switch batch.dispatch {
        case .immediate:
            dispatchCommands(batch.commands, context: context)
        case .at(let fireDate):
            pendingCommandBatches.append(batch)
            armWallClockBatch(batchID: batch.id, fireDate: fireDate, context: context)
        case .afterMissionCycle:
            pendingCommandBatches.append(batch)
        }
    }

    /// Dispatches every `.afterMissionCycle` pending batch. Returns whether any fleet commands were sent.
    @discardableResult
    func dispatchAfterMissionCycleBatchesIfPending(context: MissionRunExecutionContext) -> Bool {
        let toDeliver = pendingCommandBatches.filter {
            if case .afterMissionCycle = $0.dispatch { return true }
            return false
        }
        guard !toDeliver.isEmpty else { return false }
        let commandCount = toDeliver.reduce(0) { $0 + $1.commands.count }
        pendingCommandBatches.removeAll { batch in
            if case .afterMissionCycle = batch.dispatch { return true }
            return false
        }
        for batch in toDeliver {
            dispatchCommands(batch.commands, context: context)
        }
        return commandCount > 0
    }

    /// Immediate abort: clear queue, cancel scheduling tasks, dispatch commands, complete run.
    func performImmediateAbort(commands: [MissionRunIssuedCommand], context: MissionRunExecutionContext) {
        guard let environment else { return }
        clearCommandQueue()
        environment.captureExecutionContext(context)
        environment.systems.scheduling.cancelAllScheduledTasks()
        dispatchCommands(commands, context: context)
        completeRun(
            context: context,
            templateKey: MissionRunLogTemplateKey.runStoppedImmediate,
            kind: .operatorStoppedImmediate,
            skipImplicitReturnToLaunch: !commands.isEmpty,
            operatorWindDown: .abortProtocolPhase
        )
    }

    private func armWallClockBatch(batchID: UUID, fireDate: Date, context: MissionRunExecutionContext) {
        wallClockBatchTasks[batchID]?.cancel()
        let capturedID = batchID
        let capturedFire = fireDate
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = capturedFire.timeIntervalSince(Date())
                if remaining <= 0.05 { break }
                let chunk = min(remaining, 3600)
                let rawNs = chunk * 1_000_000_000
                guard rawNs.isFinite, rawNs > 0 else { break }
                let ns = UInt64(min(Double(UInt64.max), max(1_000_000, rawNs)))
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            self.deliverWallClockBatchIfStillPending(batchID: capturedID, context: context)
        }
        wallClockBatchTasks[batchID] = task
    }

    private func deliverWallClockBatchIfStillPending(batchID: UUID, context: MissionRunExecutionContext) {
        guard let idx = pendingCommandBatches.firstIndex(where: { $0.id == batchID }) else { return }
        let batch = pendingCommandBatches[idx]
        guard case .at = batch.dispatch else { return }
        pendingCommandBatches.remove(at: idx)
        wallClockBatchTasks.removeValue(forKey: batchID)
        dispatchCommands(batch.commands, context: context)
    }

    private func dispatchCommands(_ commands: [MissionRunIssuedCommand], context: MissionRunExecutionContext) {
        guard let environment else { return }
        for issued in commands {
            environment.appendEvent(
                environment.systems.commands.dispatchCommand(issued, fleetLink: context.fleetLink, sitl: context.sitl)
            )
        }
    }

    func issueReturnToLaunchForAllAssignments() {
        guard let environment, let fleetLink = environment.fleetLink, let sitl = environment.sitl else { return }
        for assignment in environment.assignments {
            guard let key = assignment.attachedFleetVehicleToken,
                  FleetMissionVehicleToken(storageKey: key) != nil
            else { continue }
            let issued = MissionRunIssuedCommand(
                assignmentID: assignment.id,
                slotName: assignment.slotName,
                vehicleTokenKey: key,
                command: .returnToLaunch,
                issuer: .missionControl,
                issuerKey: MissionRunCommandIssuerKey.runTeardown,
                category: .missionControl
            )
            environment.appendEvent(environment.systems.commands.dispatchCommand(issued, fleetLink: fleetLink, sitl: sitl))
        }
    }

    /// Per-assignment fleet commands for orderly recovery wind-down from ``MissionRunCompletePolicy`` (run default + per-slot overrides).
    /// - Parameter limitedToAssignmentIDs: When non-nil, only these assignment rows are included (task / future squad scoping).
    func buildCompletePolicyWindDownCommands(limitedToAssignmentIDs: Set<UUID>? = nil) -> [MissionRunIssuedCommand] {
        guard let environment else { return [] }
        var out: [MissionRunIssuedCommand] = []
        for assignment in environment.assignments {
            if let limitedToAssignmentIDs, !limitedToAssignmentIDs.contains(assignment.id) { continue }
            let resolved = MissionRunPolicyResolution.resolvedCompletePolicy(
                assignment: assignment,
                mission: environment.template
            )
            guard let baseCommand = Self.fleetVehicleCommand(forCompletePolicy: resolved),
                  let key = assignment.attachedFleetVehicleToken,
                  FleetMissionVehicleToken(storageKey: key) != nil
            else { continue }
            out.append(
                MissionRunIssuedCommand(
                    assignmentID: assignment.id,
                    slotName: assignment.slotName,
                    vehicleTokenKey: key,
                    command: baseCommand,
                    issuer: .operator,
                    issuerKey: MissionRunCommandIssuerKey.localOperator,
                    category: .missionControl
                )
            )
        }
        return out
    }

    private static func fleetVehicleCommand(forCompletePolicy policy: MissionRunCompletePolicy) -> FleetVehicleCommand? {
        switch policy {
        case .returnToLaunch: return .returnToLaunch
        case .holdPosition: return .holdPosition
        case .land: return .land
        case .none: return nil
        }
    }

    /// Immediate recovery wind-down from complete policy, then run enters recovery phase.
    func performImmediateComplete(context: MissionRunExecutionContext) {
        guard let environment else { return }
        clearCommandQueue()
        environment.captureExecutionContext(context)
        environment.systems.scheduling.cancelAllScheduledTasks()
        environment.gracefulStopKind = .none
        let windDown = buildCompletePolicyWindDownCommands()
        dispatchCommands(windDown, context: context)
        completeRun(
            context: context,
            templateKey: MissionRunLogTemplateKey.runCompleteWindDownImmediate,
            kind: .operatorCompletedImmediate,
            skipImplicitReturnToLaunch: !windDown.isEmpty,
            operatorWindDown: .recoveryPhase
        )
    }

    /// Task-scoped immediate abort: dispatch abort-plan commands for assignments bound to the target task only (run continues).
    @discardableResult
    func performImmediateMissionTaskAbort(target: MissionRunCommandTarget, context: MissionRunExecutionContext) -> Bool {
        guard let environment, case .task(let taskID) = target else { return false }
        let bound = environment.assignmentsBoundToMissionTask(taskID: taskID)
        let ids = Set(bound.map(\.id))
        guard !ids.isEmpty else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskAbortNowSkippedNoSlots,
                templateParams: [:]
            )
            return false
        }
        _ = environment.systems.planner.buildAbortPlan(trigger: .now)
        let commands = (environment.systems.planner.lastBuiltAbortPlan?.entries ?? [])
            .filter { ids.contains($0.assignmentID) }
            .compactMap(\.issuedCommand)
            .map { $0.reattributed(issuer: .operator, issuerKey: MissionRunCommandIssuerKey.localOperator) }
        guard !commands.isEmpty else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskAbortSkippedNoCommands
            )
            return false
        }
        environment.captureExecutionContext(context)
        dispatchCommands(commands, context: context)
        environment.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        environment.systems.scheduling.cancelScheduledTaskMissionStarts(forTaskID: taskID)
        let taskLabel = environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name ?? taskID.uuidString
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionTaskAbortNowDispatched,
            templateParams: ["task": taskLabel]
        )
        return true
    }

    /// Task-scoped immediate complete: dispatch complete-policy wind-down for bound slots only (run continues).
    @discardableResult
    func performImmediateMissionTaskComplete(target: MissionRunCommandTarget, context: MissionRunExecutionContext) -> Bool {
        guard let environment, case .task(let taskID) = target else { return false }
        let bound = environment.assignmentsBoundToMissionTask(taskID: taskID)
        let ids = Set(bound.map(\.id))
        guard !ids.isEmpty else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskCompleteNowSkippedNoSlots,
                templateParams: [:]
            )
            return false
        }
        let windDown = buildCompletePolicyWindDownCommands(limitedToAssignmentIDs: ids)
        guard !windDown.isEmpty else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskCompleteSkippedNoCommands
            )
            return false
        }
        environment.captureExecutionContext(context)
        dispatchCommands(windDown, context: context)
        environment.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
        environment.systems.scheduling.cancelScheduledTaskMissionStarts(forTaskID: taskID)
        let taskLabel = environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name ?? taskID.uuidString
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionTaskCompleteNowDispatched,
            templateParams: ["task": taskLabel]
        )
        return true
    }

    private func deliverPendingMissionTaskGracefulWindDownsIfNeeded(
        completedCycleTaskIDs: Set<UUID>,
        context: MissionRunExecutionContext
    ) {
        guard let environment else { return }
        for taskID in completedCycleTaskIDs {
            guard let kind = environment.consumePendingMissionTaskGracefulWindDown(forTaskID: taskID) else { continue }
            let bound = environment.assignmentsBoundToMissionTask(taskID: taskID)
            let ids = Set(bound.map(\.id))
            guard !ids.isEmpty else { continue }
            switch kind {
            case .abortAfterCycle:
                _ = environment.systems.planner.buildAbortPlan(trigger: .afterCycle)
                let commands = (environment.systems.planner.lastBuiltAbortPlan?.entries ?? [])
                    .filter { ids.contains($0.assignmentID) }
                    .compactMap(\.issuedCommand)
                    .map { $0.reattributed(issuer: .operator, issuerKey: MissionRunCommandIssuerKey.localOperator) }
                guard !commands.isEmpty else {
                    environment.systems.logging.appendLogEvent(
                        level: .warning,
                        taskID: taskID,
                        taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.missionTaskAbortGracefulSkippedNoCommands
                    )
                    continue
                }
                dispatchCommands(commands, context: context)
                environment.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
                environment.systems.scheduling.cancelScheduledTaskMissionStarts(forTaskID: taskID)
                let label = environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name ?? taskID.uuidString
                environment.systems.logging.appendLogEvent(
                    level: .info,
                    taskID: taskID,
                    taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.missionTaskAbortGracefulDispatched,
                    templateParams: ["task": label]
                )
            case .completeAfterCycle:
                let windDown = buildCompletePolicyWindDownCommands(limitedToAssignmentIDs: ids)
                guard !windDown.isEmpty else {
                    environment.systems.logging.appendLogEvent(
                        level: .warning,
                        taskID: taskID,
                        taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulSkippedNoCommands
                    )
                    continue
                }
                dispatchCommands(windDown, context: context)
                environment.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
                environment.systems.scheduling.cancelScheduledTaskMissionStarts(forTaskID: taskID)
                let label = environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name ?? taskID.uuidString
                environment.systems.logging.appendLogEvent(
                    level: .info,
                    taskID: taskID,
                    taskLabel: environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulDispatched,
                    templateParams: ["task": label]
                )
            }
        }
    }

    private func processMissionCycleFinished(
        vehicleID: String,
        context: MissionRunExecutionContext
    ) -> MissionRunExecutionDecision {
        guard let environment, environment.status == .running else { return .noOp }
        guard let mission = context.missionProvider() else { return .noOp }
        let activeMissionVehicleIDs = activePrimaryMissionVehicleIDs(
            mission: mission,
            restrictToTaskIDs: environment.activeCycleTaskIDs,
            fleetLink: context.fleetLink,
            sitl: context.sitl
        )
        guard activeMissionVehicleIDs.contains(vehicleID) else { return .noOp }
        environment.markFinishedMissionCycleVehicleID(vehicleID)
        let allActiveCyclesFinished = !activeMissionVehicleIDs.isEmpty
            && activeMissionVehicleIDs.isSubset(of: environment.finishedMissionCycleVehicleIDs)
        guard allActiveCyclesFinished else { return .progressed }
        environment.setMissionCycleCount(environment.cyclesCompleted + 1)
        let completedCycleTaskIDs = environment.activeCycleTaskIDs
        environment.clearFinishedMissionCycleVehicleIDs()
        environment.clearActiveCycleTasks()
        environment.recordTaskCycleCompletions(forTaskIDs: completedCycleTaskIDs)

        if environment.gracefulStopKind != .none {
            let hadQueuedWindDownCommands = environment.systems.executor.dispatchAfterMissionCycleBatchesIfPending(context: context)
            let stopKind = environment.gracefulStopKind
            let resultKind: MissionRunCompletionKind
            if stopKind == .abortAfterCycle {
                completeRun(
                    context: context,
                    templateKey: MissionRunLogTemplateKey.runGracefulAfterCycle,
                    kind: .operatorStoppedAfterCycle,
                    skipImplicitReturnToLaunch: hadQueuedWindDownCommands,
                    operatorWindDown: .abortProtocolPhase
                )
                resultKind = .operatorStoppedAfterCycle
            } else {
                completeRun(
                    context: context,
                    templateKey: MissionRunLogTemplateKey.runCompleteWindDownAfterCycle,
                    kind: .operatorCompletedAfterCycle,
                    skipImplicitReturnToLaunch: hadQueuedWindDownCommands,
                    operatorWindDown: .recoveryPhase
                )
                resultKind = .operatorCompletedAfterCycle
            }
            return .completed(resultKind)
        }

        deliverPendingMissionTaskGracefulWindDownsIfNeeded(
            completedCycleTaskIDs: completedCycleTaskIDs,
            context: context
        )

        let nextPlan = planNextAutoCycleStarts(
            mission: mission,
            completedCycleTaskIDs: completedCycleTaskIDs,
            suppressAutostartForTaskIDs: environment.missionTaskAutopilotAutostartSuppressedTaskIDs
        )
        if !nextPlan.immediateTaskIDs.isEmpty || !nextPlan.delayedTaskIDs.isEmpty {
            if !nextPlan.betweenCyclesCommands.isEmpty {
                for issued in nextPlan.betweenCyclesCommands {
                    environment.appendEvent(environment.systems.commands.dispatchCommand(issued, fleetLink: context.fleetLink, sitl: context.sitl))
                }
            }
            for taskID in nextPlan.immediateTaskIDs {
                startTaskExecution(taskID: taskID, mission: mission, context: context)
            }
            for taskID in nextPlan.delayedTaskIDs {
                let task = mission.routeMacro.tasks.first(where: { $0.id == taskID })
                let delaySeconds = max(1, task?.regularityDelayTotalSeconds ?? 1)
                let startAt = Date().addingTimeInterval(delaySeconds)
                environment.systems.scheduling.setTaskStartDeferral(
                    MissionTaskStartDeferral(startAt: startAt, totalDelay: delaySeconds),
                    forTaskID: taskID
                )
                environment.systems.scheduling.armTaskMissionStartTask(taskID: taskID, startAt: startAt) { [weak self] in
                    guard let self else { return }
                    _ = self.handleEvent(.deferredTaskStartDue(taskID: taskID), context: context)
                }
            }
            return .progressed
        }

        if !missionHasOnlyBoundedTasks(mission) {
            environment.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionRunningUnboundedRegularity
            )
            return .progressed
        }

        completeRun(
            context: context,
            templateKey: MissionRunLogTemplateKey.runOneOffFinished,
            kind: .oneOffAutopilotFinished,
            skipImplicitReturnToLaunch: false,
            operatorWindDown: .recoveryPhase
        )
        return .completed(.oneOffAutopilotFinished)
    }

    private func missionHasOnlyBoundedTasks(_ mission: Mission) -> Bool {
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        guard !enabled.isEmpty else { return true }
        return enabled.allSatisfy { task in
            switch task.regularity {
            case .continuous, .continuousWithDelay:
                return task.cycles > 0
            case .onceAtStart, .operatorTriggered:
                return false
            }
        }
    }

    private func activePrimaryMissionVehicleIDs(
        mission: Mission,
        restrictToTaskIDs: Set<UUID>,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> Set<String> {
        guard let environment else { return [] }
        let enabledTasks = mission.routeMacro.tasks.filter(\.enabled).filter { task in
            restrictToTaskIDs.isEmpty || restrictToTaskIDs.contains(task.id)
        }
        var ids: Set<String> = []
        for task in enabledTasks {
            let squads = environment.systems.planner.buildTaskSquadMissions(mission: mission, taskId: task.id)
            for squadMission in squads {
                guard let resolvedID = resolvedFleetStreamVehicleID(
                    assignment: squadMission.squad.primaryAssignment,
                    fleetLink: fleetLink,
                    sitl: sitl
                ) else { continue }
                ids.insert(resolvedID)
            }
        }
        return ids
    }

    private struct NextCycleStartPlan {
        var immediateTaskIDs: [UUID] = []
        var delayedTaskIDs: [UUID] = []
        var betweenCyclesCommands: [MissionRunIssuedCommand] = []
    }

    private func planNextAutoCycleStarts(
        mission: Mission,
        completedCycleTaskIDs: Set<UUID>,
        suppressAutostartForTaskIDs: Set<UUID>
    ) -> NextCycleStartPlan {
        guard let environment else { return NextCycleStartPlan() }
        var plan = NextCycleStartPlan()
        let tasksByID = Dictionary(uniqueKeysWithValues: mission.routeMacro.tasks.map { ($0.id, $0) })
        for taskID in completedCycleTaskIDs {
            guard !suppressAutostartForTaskIDs.contains(taskID) else { continue }
            guard let task = tasksByID[taskID], task.enabled else { continue }
            switch task.regularity {
            case .continuous:
                let done = environment.taskCyclesCompletedByTaskID[task.id] ?? 0
                let shouldStart = task.cycles == 0 || done < task.cycles
                if shouldStart {
                    plan.immediateTaskIDs.append(task.id)
                }
            case .continuousWithDelay:
                let done = environment.taskCyclesCompletedByTaskID[task.id] ?? 0
                let shouldStart = task.cycles == 0 || done < task.cycles
                if shouldStart {
                    plan.delayedTaskIDs.append(task.id)
                    plan.betweenCyclesCommands.append(contentsOf: betweenCyclesCommands(for: task, mission: mission))
                }
            case .onceAtStart, .operatorTriggered:
                // Non-continuous regularities do not auto-start next cycles.
                break
            }
        }
        return plan
    }

    private func betweenCyclesCommands(for task: MissionTask, mission: Mission) -> [MissionRunIssuedCommand] {
        guard let environment else { return [] }
        let command: FleetVehicleCommand?
        switch task.betweenCycles {
        case .returnToLaunch:
            command = .returnToLaunch
        case .holdPosition:
            command = .holdPosition
        case .land:
            command = .land
        case .none:
            command = nil
        }
        guard let command else { return [] }
        let squads = environment.systems.planner.buildTaskSquadMissions(mission: mission, taskId: task.id)
        return squads.compactMap { squad in
            guard let tokenKey = squad.squad.primaryAssignment.attachedFleetVehicleToken else { return nil }
            return MissionRunIssuedCommand(
                assignmentID: squad.squad.primaryAssignment.id,
                slotName: squad.squad.primaryAssignment.slotName,
                vehicleTokenKey: tokenKey,
                command: command,
                issuer: .missionControl,
                issuerKey: MissionRunCommandIssuerKey.missionExecute,
                category: .missionControl
            )
        }
    }

    private func launchInitialMissionBatches(
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionProvider: @escaping @MainActor () -> Mission?
    ) {
        guard let environment else { return }
        let orderedEnabled = mission.routeMacro.tasks.filter(\.enabled).filter {
            $0.regularity != .operatorTriggered
        }
        struct BuildEntry { let taskId: UUID; let assignment: MissionRunAssignment }
        let buildable: [BuildEntry] = orderedEnabled.compactMap { path in
            let squads = environment.systems.planner.buildTaskSquadMissions(mission: mission, taskId: path.id)
            guard let first = squads.first else { return nil }
            return BuildEntry(taskId: path.id, assignment: first.squad.primaryAssignment)
        }
        if buildable.isEmpty {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionNotStartedNeedsPath
            )
            return
        }
        for entry in buildable {
            let delaySeconds = environment.startDelayTotalSeconds(forTask: entry.taskId, mission: mission)
            guard delaySeconds > 0 else {
                startTaskExecution(taskID: entry.taskId, mission: mission, context: .init(mission: mission, fleetLink: fleetLink, sitl: sitl, missionProvider: missionProvider))
                continue
            }
            let startAt = Date().addingTimeInterval(delaySeconds)
            environment.systems.scheduling.setTaskStartDeferral(
                MissionTaskStartDeferral(startAt: startAt, totalDelay: delaySeconds),
                forTaskID: entry.taskId
            )
            let taskContext = environment.systems.logging.effectiveTaskFields(forAssignmentID: entry.assignment.id)
            let durationLabel = MissionDelayPolicy.humanReadableDuration(seconds: delaySeconds)
            environment.systems.logging.appendLogEvent(
                level: .info,
                taskID: taskContext.0,
                taskLabel: taskContext.1,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.scheduleTaskMissionStartDeferred,
                templateParams: ["duration": durationLabel, "seconds": String(Int(delaySeconds.rounded()))]
            )
            environment.systems.scheduling.armTaskMissionStartTask(
                taskID: entry.taskId,
                startAt: startAt,
                onStartNow: { [weak self] in
                    guard let self else { return }
                    _ = self.handleEvent(
                        .deferredTaskStartDue(taskID: entry.taskId),
                        context: .init(mission: mission, fleetLink: fleetLink, sitl: sitl, missionProvider: missionProvider)
                    )
                }
            )
        }
    }

    @discardableResult
    private func startTaskExecution(
        taskID: UUID,
        mission: Mission,
        context: MissionRunExecutionContext,
        allowDuringStaging: Bool = false
    ) -> Bool {
        guard let environment else { return false }
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }) else { return false }
        let phaseOK: Bool = {
            if allowDuringStaging {
                return environment.sessionPhase == .executing || environment.sessionPhase == .staging
            }
            return environment.sessionPhase == .executing
        }()
        guard phaseOK else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: task.id,
                taskLabel: task.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.startMissionTaskSkippedPhase,
                templateParams: ["phase": environment.sessionPhase.rawValue]
            )
            return false
        }
        let pass = buildPrimaryMissionPass(mission: mission, explicitTaskId: taskID)
        let dispatched = !pass.immediateCommands.isEmpty || !pass.queuedBatches.isEmpty
        if dispatched {
            environment.markTaskActiveInCurrentCycle(taskID)
        }
        pass.events.forEach { environment.appendEvent($0) }
        for issued in pass.immediateCommands {
            environment.appendEvent(environment.systems.commands.dispatchCommand(issued, fleetLink: context.fleetLink, sitl: context.sitl))
        }
        for batch in pass.queuedBatches {
            environment.systems.executor.enqueueCommandBatch(batch, context: context, replacingTags: [])
        }
        return dispatched
    }

    private func buildStagingPass(mission: Mission?) -> MissionRunPassResult {
        guard let environment else { return MissionRunPassResult(events: [], commands: []) }
        var events: [MissionRunEvent] = []
        var commands: [MissionRunIssuedCommand] = []
        events.append(
            MissionRunEvent(
                level: .info,
                templateKey: MissionRunLogTemplateKey.stagingPassStarted
            )
        )
        let skipRelocate = mission.map { mission in
            mission.routeMacro.tasks.filter(\.enabled).contains { task in
                !environment.systems.planner.buildTaskSquadMissions(mission: mission, taskId: task.id).isEmpty
            }
        } ?? false
        for assignment in environment.assignments {
            let slot = assignment.slotName
            let pc = MissionControlTaskTagName.taskContext(for: assignment, mission: mission)
            let taskID = pc?.id
            let taskLabel = pc?.label
            guard let tokenKey = assignment.attachedFleetVehicleToken,
                  let token = FleetMissionVehicleToken(storageKey: tokenKey)
            else {
                events.append(
                    MissionRunEvent(
                        level: .warning,
                        taskID: taskID,
                        taskLabel: taskLabel,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.stagingNoToken
                    )
                )
                continue
            }
            switch token {
            case .sitl:
                if let coord = assignment.simStartOverrideCoord {
                    if !skipRelocate {
                        commands.append(
                            MissionRunIssuedCommand(
                                assignmentID: assignment.id,
                                slotName: slot,
                                vehicleTokenKey: tokenKey,
                                command: .gotoCoordinate(coord, relativeAltitudeM: 20, yawDeg: 0),
                                issuer: .missionControl,
                                issuerKey: MissionRunCommandIssuerKey.staging,
                                category: .missionControl
                            )
                        )
                    } else {
                        events.append(
                            MissionRunEvent(
                                level: .info,
                                taskID: taskID,
                                taskLabel: taskLabel,
                                speaker: .missionControl,
                                templateKey: MissionRunLogTemplateKey.stagingSimFoldedMission
                            )
                        )
                    }
                    events.append(
                        MissionRunEvent(
                            level: .info,
                            taskID: taskID,
                            taskLabel: taskLabel,
                            speaker: .missionControl,
                            templateKey: MissionRunLogTemplateKey.stagingSimTarget,
                            templateParams: [
                                "lat": String(format: "%.6f", coord.lat),
                                "lon": String(format: "%.6f", coord.lon),
                            ]
                        )
                    )
                } else {
                    events.append(
                        MissionRunEvent(
                            level: .warning,
                            taskID: taskID,
                            taskLabel: taskLabel,
                            speaker: .missionControl,
                            templateKey: MissionRunLogTemplateKey.stagingSimNoOverride
                        )
                    )
                }
            case .live:
                events.append(
                    MissionRunEvent(
                        level: .info,
                        taskID: taskID,
                        taskLabel: taskLabel,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.stagingLiveReadonly
                    )
                )
            }
        }
        events.append(
            MissionRunEvent(
                level: .info,
                templateKey: MissionRunLogTemplateKey.stagingPassComplete,
                templateParams: ["slotCount": String(environment.assignments.count)]
            )
        )
        return MissionRunPassResult(events: events, commands: commands)
    }

    private struct TaskMissionLaunchPass {
        var events: [MissionRunEvent]
        var immediateCommands: [MissionRunIssuedCommand]
        var queuedBatches: [MissionRunQueuedCommandBatch]
    }

    private enum TaskFormationIntent {
        case cluster
        case line
    }

    private func buildPrimaryMissionPass(mission: Mission, explicitTaskId: UUID? = nil) -> TaskMissionLaunchPass {
        guard let environment else { return TaskMissionLaunchPass(events: [], immediateCommands: [], queuedBatches: []) }
        var events: [MissionRunEvent] = []
        var immediateCommands: [MissionRunIssuedCommand] = []
        var queuedBatches: [MissionRunQueuedCommandBatch] = []
        let resolvedTaskId: UUID? = {
            if let explicitTaskId { return explicitTaskId }
            let enabledTasks = mission.routeMacro.tasks.filter(\.enabled)
            return enabledTasks.count == 1 ? enabledTasks.first?.id : nil
        }()
        guard let pid = resolvedTaskId,
              let task = mission.routeMacro.tasks.first(where: { $0.id == pid })
        else {
            events.append(
                MissionRunEvent(
                    level: .warning,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.missionNotStartedNeedsPath
                )
            )
            return TaskMissionLaunchPass(events: events, immediateCommands: immediateCommands, queuedBatches: queuedBatches)
        }
        let squads = environment.systems.planner.buildTaskSquadMissions(mission: mission, taskId: pid)
        guard !squads.isEmpty else {
            events.append(
                MissionRunEvent(
                    level: .warning,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.missionNotStartedNoPrimaries
                )
            )
            return TaskMissionLaunchPass(events: events, immediateCommands: immediateCommands, queuedBatches: queuedBatches)
        }

        let formation: TaskFormationIntent = (task.pattern == .convoy) ? .line : .cluster
        let fallbackStep = fallbackStaggerStepSeconds(task: task, squads: squads, mission: mission)
        let staggerStep = task.executionMethod == .staggered ? fallbackStep : 0
        let now = Date()

        for squad in squads {
            guard let tokenKey = squad.squad.primaryAssignment.attachedFleetVehicleToken else { continue }
            let issued = MissionRunIssuedCommand(
                assignmentID: squad.squad.primaryAssignment.id,
                slotName: squad.squad.primaryAssignment.slotName,
                vehicleTokenKey: tokenKey,
                command: .uploadAndStartMission(items: squad.missionItems),
                issuer: .missionControl,
                issuerKey: MissionRunCommandIssuerKey.missionExecute,
                category: .missionControl
            )
            let offset = Double(squad.squadIndex) * staggerStep
            let dispatchAt = now.addingTimeInterval(offset)
            let pc = MissionControlTaskTagName.taskContext(for: squad.squad.primaryAssignment, mission: mission)
            let formationLabel = (formation == .line) ? "line" : "cluster"
            let timingLabel = offset > 0 ? "stagger +\(Int(offset))s" : "start now"
            events.append(
                MissionRunEvent(
                    level: .info,
                    taskID: pc?.id,
                    taskLabel: pc?.label,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.missionExecuting,
                    templateParams: [
                        "slot": squad.squad.primaryAssignment.slotName,
                        "itemCount": String(squad.missionItems.count),
                        "formation": formationLabel,
                        "timing": timingLabel,
                    ]
                )
            )
            if offset <= 0 {
                immediateCommands.append(issued)
            } else {
                queuedBatches.append(
                    MissionRunQueuedCommandBatch(
                        tag: .missionStart,
                        dispatch: .at(dispatchAt),
                        commands: [issued]
                    )
                )
            }
        }
        return TaskMissionLaunchPass(events: events, immediateCommands: immediateCommands, queuedBatches: queuedBatches)
    }

    private func fallbackStaggerStepSeconds(
        task: MissionTask,
        squads: [MissionRunPlannerSubsystem.PlannedTaskSquadMission],
        mission: Mission
    ) -> TimeInterval {
        guard task.executionMethod == .staggered else { return 0 }
        guard let firstWaypoint = task.waypoints.first else { return 20 }
        let startCoord = squads.compactMap { $0.squad.primaryAssignment.simStartOverrideCoord }.first
        let distanceM: Double = {
            if let startCoord {
                return MissionTelemetryGeo.horizontalDistanceM(
                    lat1: startCoord.lat,
                    lon1: startCoord.lon,
                    lat2: firstWaypoint.coord.lat,
                    lon2: firstWaypoint.coord.lon
                )
            }
            if task.waypoints.count > 1 {
                let second = task.waypoints[1]
                return MissionTelemetryGeo.horizontalDistanceM(
                    lat1: firstWaypoint.coord.lat,
                    lon1: firstWaypoint.coord.lon,
                    lat2: second.coord.lat,
                    lon2: second.coord.lon
                )
            }
            return 100
        }()
        let speedMps: Double = {
            let maybeWaypoint = firstWaypoint.transition.targetSpeed
            let waypointUnit = firstWaypoint.transition.speedUnit
            let fromWaypoint = waypointUnit == .kilometersPerHour ? (maybeWaypoint * 1000 / 3600) : maybeWaypoint
            let fallback = mission.routeMacro.rules.defaultSpeed
            return max(1, fromWaypoint > 0 ? fromWaypoint : fallback)
        }()
        let estimate = distanceM / speedMps
        return min(300, max(5, estimate))
    }

    private func completeRun(
        context: MissionRunExecutionContext,
        templateKey: String,
        templateParams: [String: String] = [:],
        kind: MissionRunCompletionKind,
        skipImplicitReturnToLaunch: Bool = false,
        operatorWindDown: MissionRunOperatorWindDown
    ) {
        guard let environment else { return }
        environment.clearMissionTaskScopedOrchestrationState()
        environment.systems.scheduling.cancelAllScheduledTasks()
        environment.systems.scheduling.clearDeferredOneOffExecution()
        var cycleSnap = environment.cyclesCompleted
        if kind == .oneOffAutopilotFinished {
            cycleSnap = max(1, cycleSnap)
        }
        environment.clearFinishedMissionCycleVehicleIDs()
        environment.clearActiveCycleTasks()
        environment.clearTaskCycleCompletionCounts()
        environment.completedAt = nil
        environment.gracefulStopKind = .none
        environment.reportCyclesCompleted = cycleSnap
        environment.completionKind = kind
        switch operatorWindDown {
        case .recoveryPhase:
            environment.status = .recovery
            environment.setSessionPhase(.recovery)
        case .abortProtocolPhase:
            environment.setSessionPhase(.aborting)
        }
        environment.systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            templateKey: templateKey,
            templateParams: templateParams
        )
        if !skipImplicitReturnToLaunch {
            issueReturnToLaunchForAllAssignments()
        }
    }
}

// MARK: - Log template keys (execution, staging, schedule, mission launch)

extension MissionRunLogTemplateKey {
    static let executionStarted = "missioncontrol.mre.execution.started"
    static let executionMissionMissing = "missioncontrol.mre.execution.mission_missing_store"
    static let runStoppedImmediate = "missioncontrol.mre.run.stopped_immediate"
    static let runGracefulAfterCycle = "missioncontrol.mre.run.graceful_after_cycle"
    static let runOneOffFinished = "missioncontrol.mre.run.one_off_finished"
    static let scheduleSkipNoMission = "missioncontrol.mre.schedule.skip_no_mission"
    static let scheduleTaskMissionStartDeferred = "missioncontrol.mre.schedule.task_mission_start_deferred"
    static let stagingPassStarted = "missioncontrol.mre.staging.pass_started"
    static let stagingPassComplete = "missioncontrol.mre.staging.pass_complete"
    static let stagingNoToken = "missioncontrol.mre.staging.no_token"
    static let stagingSimFoldedMission = "missioncontrol.mre.staging.sim_folded_mission"
    static let stagingSimTarget = "missioncontrol.mre.staging.sim_target"
    static let stagingSimNoOverride = "missioncontrol.mre.staging.sim_no_override"
    static let stagingLiveReadonly = "missioncontrol.mre.staging.live_readonly"
    static let missionNotStartedNeedsPath = "missioncontrol.mre.mission.not_started_needs_path"
    static let missionNotStartedNoPrimaries = "missioncontrol.mre.mission.not_started_no_primaries"
    static let missionExecuting = "missioncontrol.mre.mission.executing"
    static let startMissionTaskSkippedPhase = "missioncontrol.mre.mission.start_skipped_phase"
    static let startMissionTaskNoDispatchContext = "missioncontrol.mre.mission.start_no_dispatch_context"
    static let startMissionTaskNoExecutionContext = "missioncontrol.mre.mission.start_no_execution_context"
    static let startMissionTaskSkippedAlreadyExecuting = "missioncontrol.mre.mission.start_skipped_already_executing"
    static let abortMissionTaskNoDispatchContext = "missioncontrol.mre.mission.abort_task_no_dispatch_context"
    static let completeMissionTaskNoDispatchContext = "missioncontrol.mre.mission.complete_task_no_dispatch_context"
    static let missionTaskAbortNowSkippedNoSlots = "missioncontrol.mre.mission.task_abort_now_skipped_no_slots"
    static let missionTaskCompleteNowSkippedNoSlots = "missioncontrol.mre.mission.task_complete_now_skipped_no_slots"
    static let missionTaskAbortGracefulSkippedNoSlots = "missioncontrol.mre.mission.task_abort_graceful_skipped_no_slots"
    static let missionTaskCompleteGracefulSkippedNoSlots = "missioncontrol.mre.mission.task_complete_graceful_skipped_no_slots"
    static let missionTaskAbortSkippedNoCommands = "missioncontrol.mre.mission.task_abort_skipped_no_commands"
    static let missionTaskCompleteSkippedNoCommands = "missioncontrol.mre.mission.task_complete_skipped_no_commands"
    static let missionTaskAbortNowDispatched = "missioncontrol.mre.mission.task_abort_now_dispatched"
    static let missionTaskCompleteNowDispatched = "missioncontrol.mre.mission.task_complete_now_dispatched"
    static let missionTaskAbortGracefulSkippedNoCommands = "missioncontrol.mre.mission.task_abort_graceful_skipped_no_commands"
    static let missionTaskCompleteGracefulSkippedNoCommands = "missioncontrol.mre.mission.task_complete_graceful_skipped_no_commands"
    static let missionTaskAbortGracefulDispatched = "missioncontrol.mre.mission.task_abort_graceful_dispatched"
    static let missionTaskCompleteGracefulDispatched = "missioncontrol.mre.mission.task_complete_graceful_dispatched"
    static let missionTaskAbortGracefulScheduled = "missioncontrol.mre.mission.task_abort_graceful_scheduled"
    static let missionTaskCompleteGracefulScheduled = "missioncontrol.mre.mission.task_complete_graceful_scheduled"
    static let missionTaskAbortGracefulSkippedWholeRunStopActive = "missioncontrol.mre.mission.task_abort_graceful_skipped_whole_run_stop"
    static let missionTaskCompleteGracefulSkippedWholeRunStopActive = "missioncontrol.mre.mission.task_complete_graceful_skipped_whole_run_stop"
    static let scheduleAbortAfterCycleNotQueuedNoContext = "missioncontrol.mre.schedule.abort_after_cycle_not_queued_no_context"
    static let scheduleCompleteAfterCycleNotQueuedNoContext = "missioncontrol.mre.schedule.complete_after_cycle_not_queued_no_context"
    static let scheduleCompleteNowSkippedNoContext = "missioncontrol.mre.schedule.complete_now_skipped_no_context"
    static let scheduleAbortNowSkippedNoContext = "missioncontrol.mre.schedule.abort_now_skipped_no_context"
    static let missionRunningUnboundedRegularity = "missioncontrol.mre.mission.running_unbounded"
    static let planRevisionAppliedImmediate = "missioncontrol.mre.plan.revision_applied_immediate"
    static let planRevisionQueuedSafePoint = "missioncontrol.mre.plan.revision_queued_safe_point"
    static let planRevisionQueuedNextCycle = "missioncontrol.mre.plan.revision_queued_next_cycle"
    static let runCompleteWindDownImmediate = "missioncontrol.mre.run.complete_wind_down_immediate"
    static let runCompleteWindDownAfterCycle = "missioncontrol.mre.run.complete_wind_down_after_cycle"
}


