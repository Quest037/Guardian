import Foundation

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
        case .failed:
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
            message: "Mission execution started.",
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
                message: "Mission template missing from store; cannot upload MAVLink mission.",
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
            startDeferredTask(taskID: taskID, context: context)
            return .progressed
        }
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
                message: "Applied plan revision \(revision) immediately."
            )
        case .safePoint:
            environment.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                message: "Queued plan revision \(revision) for next safe point."
            )
        case .nextCycle:
            environment.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                message: "Queued plan revision \(revision) for next mission cycle."
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
            message: "Run aborted immediately; fleet commands issued per abort plan.",
            templateKey: MissionRunLogTemplateKey.runStoppedImmediate,
            kind: .operatorStoppedImmediate,
            skipImplicitReturnToLaunch: !commands.isEmpty
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
                category: .paladin
            )
            environment.appendEvent(environment.systems.commands.dispatchCommand(issued, fleetLink: fleetLink, sitl: sitl))
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

        if environment.pendingGracefulCycleStop {
            let hadQueuedAbortCommands = environment.systems.executor.dispatchAfterMissionCycleBatchesIfPending(context: context)
            completeRun(
                context: context,
                message: "Current mission cycle finished; graceful stop - returning to launch / home.",
                templateKey: MissionRunLogTemplateKey.runGracefulAfterCycle,
                kind: .operatorStoppedAfterCycle,
                skipImplicitReturnToLaunch: hadQueuedAbortCommands
            )
            return .completed(.operatorStoppedAfterCycle)
        }

        let nextPlan = planNextAutoCycleStarts(
            mission: mission,
            completedCycleTaskIDs: completedCycleTaskIDs
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
                let mins = max(1, task?.regularityDelayMinutes ?? 1)
                let delaySeconds = Double(mins) * 60
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
                speaker: .paladin,
                message: "Mission remains running (unbounded task regularity). Stop manually when ready."
            )
            return .progressed
        }

        completeRun(
            context: context,
            message: "Mission cycle finished; run complete - returning to launch / home.",
            templateKey: MissionRunLogTemplateKey.runOneOffFinished,
            kind: .oneOffAutopilotFinished,
            skipImplicitReturnToLaunch: false
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
            case .onceAtStart, .twiceStartEnd, .operatorTriggered:
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
        completedCycleTaskIDs: Set<UUID>
    ) -> NextCycleStartPlan {
        guard let environment else { return NextCycleStartPlan() }
        var plan = NextCycleStartPlan()
        let tasksByID = Dictionary(uniqueKeysWithValues: mission.routeMacro.tasks.map { ($0.id, $0) })
        for taskID in completedCycleTaskIDs {
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
            case .onceAtStart, .twiceStartEnd, .operatorTriggered:
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
                category: .paladin
            )
        }
    }

    private func startDeferredTask(taskID: UUID, context: MissionRunExecutionContext) {
        guard let environment else { return }
        environment.systems.scheduling.registerDeferredTaskStartTask(nil, forTaskID: taskID)
        environment.systems.scheduling.clearMissionTaskStartDeferral(forTaskID: taskID)
        guard environment.status == .running else { return }
        guard let mission = context.missionProvider() else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .paladin,
                message: "Deferred path mission start skipped - mission template not found in store.",
                templateKey: MissionRunLogTemplateKey.scheduleSkipNoMission
            )
            return
        }
        startTaskExecution(taskID: taskID, mission: mission, context: context)
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
                speaker: .paladin,
                message: "MAVLink mission not started (need enabled path(es) with assigned vehicle(s) and waypoints).",
                templateKey: MissionRunLogTemplateKey.missionNotStarted
            )
            return
        }
        for entry in buildable {
            let mins = environment.startDelayMinutes(forTask: entry.taskId, mission: mission)
            guard mins > 0 else {
                startTaskExecution(taskID: entry.taskId, mission: mission, context: .init(mission: mission, fleetLink: fleetLink, sitl: sitl, missionProvider: missionProvider))
                continue
            }
            let delaySeconds = Double(mins) * 60
            let startAt = Date().addingTimeInterval(delaySeconds)
            environment.systems.scheduling.setTaskStartDeferral(
                MissionTaskStartDeferral(startAt: startAt, totalDelay: delaySeconds),
                forTaskID: entry.taskId
            )
            let taskContext = environment.systems.logging.effectiveTaskFields(forAssignmentID: entry.assignment.id)
            environment.systems.logging.appendLogEvent(
                level: .info,
                taskID: taskContext.0,
                taskLabel: taskContext.1,
                speaker: .paladin,
                message: "MAVLink mission start for this path deferred \(mins) minute(s).",
                templateKey: MissionRunLogTemplateKey.scheduleTaskMissionStartDeferred,
                templateParams: ["minutes": String(mins)]
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

    private func startTaskExecution(taskID: UUID, mission: Mission, context: MissionRunExecutionContext) {
        guard let environment, environment.sessionPhase == .executing else { return }
        let pass = buildPrimaryMissionPass(mission: mission, explicitTaskId: taskID)
        if !pass.immediateCommands.isEmpty || !pass.queuedBatches.isEmpty {
            environment.markTaskActiveInCurrentCycle(taskID)
        }
        pass.events.forEach { environment.appendEvent($0) }
        for issued in pass.immediateCommands {
            environment.appendEvent(environment.systems.commands.dispatchCommand(issued, fleetLink: context.fleetLink, sitl: context.sitl))
        }
        for batch in pass.queuedBatches {
            environment.systems.executor.enqueueCommandBatch(batch, context: context, replacingTags: [])
        }
    }

    private func buildStagingPass(mission: Mission?) -> MissionRunPassResult {
        guard let environment else { return MissionRunPassResult(events: [], commands: []) }
        var events: [MissionRunEvent] = []
        var commands: [MissionRunIssuedCommand] = []
        events.append(
            MissionRunEvent(
                level: .info,
                message: "Mission Control staging pass started.",
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
                        message: "No fleet vehicle token; skipping staging.",
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
                                category: .paladin
                            )
                        )
                    } else {
                        events.append(
                            MissionRunEvent(
                                level: .info,
                                taskID: taskID,
                                taskLabel: taskLabel,
                                speaker: .missionControl,
                                message: "SIM staging location folded into MAVLink mission (no separate goto).",
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
                            message: String(format: "SIM staging target set to %.6f, %.6f.", coord.lat, coord.lon),
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
                            message: "SIM has no staging override; default spawn position will be used.",
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
                        message: "Live vehicle staging is telemetry-driven (read-only).",
                        templateKey: MissionRunLogTemplateKey.stagingLiveReadonly
                    )
                )
            }
        }
        events.append(
            MissionRunEvent(
                level: .info,
                message: "Mission Control staging pass complete (\(environment.assignments.count) slot(s) evaluated).",
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
                    message: "MAVLink mission not started (need enabled path with assigned primary vehicle(s) and waypoints).",
                    templateKey: MissionRunLogTemplateKey.missionNotStarted
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
                    message: "MAVLink mission not started (task has no assigned primaries).",
                    templateKey: MissionRunLogTemplateKey.missionNotStarted
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
                category: .paladin
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
                    message: "Executing MAVLink mission for \"\(squad.squad.primaryAssignment.slotName)\" (\(squad.missionItems.count) item(s), \(formationLabel), \(timingLabel)).",
                    templateKey: MissionRunLogTemplateKey.missionExecuting,
                    templateParams: ["slot": squad.squad.primaryAssignment.slotName, "itemCount": String(squad.missionItems.count)]
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
        message: String,
        templateKey: String?,
        templateParams: [String: String] = [:],
        kind: MissionRunCompletionKind,
        skipImplicitReturnToLaunch: Bool = false
    ) {
        guard let environment else { return }
        environment.systems.scheduling.cancelAllScheduledTasks()
        environment.systems.scheduling.clearDeferredOneOffExecution()
        var cycleSnap = environment.cyclesCompleted
        if kind == .oneOffAutopilotFinished {
            cycleSnap = max(1, cycleSnap)
        }
        environment.clearFinishedMissionCycleVehicleIDs()
        environment.clearActiveCycleTasks()
        environment.clearTaskCycleCompletionCounts()
        environment.status = .recovery
        environment.completedAt = nil
        environment.pendingGracefulCycleStop = false
        environment.reportCyclesCompleted = cycleSnap
        environment.completionKind = kind
        environment.setSessionPhase(.recovery)
        environment.systems.logging.appendLogEvent(
            level: .info,
            speaker: .paladin,
            message: message,
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
    static let missionNotStarted = "missioncontrol.mre.mission.not_started"
    static let missionExecuting = "missioncontrol.mre.mission.executing"
}


