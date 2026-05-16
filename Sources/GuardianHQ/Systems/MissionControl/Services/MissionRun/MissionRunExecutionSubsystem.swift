import Foundation
import Mavsdk

/// Whether a wind-down ends in **recovery** (success protocol) or **abort** (``MissionRunSessionPhase/aborting``).
enum MissionRunOperatorWindDown {
    case recoveryPhase
    case abortProtocolPhase
}

/// Operator **Retry recovery / abort protocol** jolt outcome (assignment triage Continue).
enum MissionRunOperatorPolicyWindDownJoltOutcome: Equatable, Sendable {
    /// Resumed the in-flight recipe via pending wizard escalation ``FleetRecipeResumptionVerb/retry``.
    case joltedEscalation
    /// Cleared a stuck fleet recipe slot and redispatched end-policy commands (awaited, single pass).
    case redispatched
    case failedNoCommands
    case failedNoVehicle
}

enum MissionRunOperatorPolicyWindDownJoltMode: Equatable, Sendable {
    case complete
    case abort
}

@MainActor
final class MissionRunExecutionSubsystem {
    weak var environment: MissionRunEnvironment?

    private var pendingCommandBatches: [MissionRunQueuedCommandBatch] = []
    private var wallClockBatchTasks: [UUID: Task<Void, Never>] = [:]

    /// Set when an immediate ``MissionRunCommandQueueTag/reserveSwapPostCommit`` batch is enqueued (for diagnostics / unit tests).
    private(set) var lastEnqueuedReserveSwapPostCommitAckContext: MissionRunReserveSwapPostCommitBatchAckContext?

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
        environment.clearTaskMissionEndRecoveryAcknowledgements()
        environment.clearTaskMissionEndAbortAcknowledgements()
        environment.clearAssignmentSlotLifecycleLanesOnAllRows()
        environment.clearFinishedMissionCycleVehicleIDs()
        environment.clearActiveCycleTasks()
        environment.clearTaskCycleCompletionCounts()
        environment.systems.scheduling.cancelScheduledMissionCycle()
        environment.systems.scheduling.cancelScheduledTaskMissionStarts()
        environment.systems.scheduling.clearDeferredOneOffExecution()
        environment.setMissionCycleCount(0)
        environment.systems.logging.clearState()
        environment.systems.lifecycle.markExecuting()
        environment.captureRosterSimStartPoseSnapshotsIfNeeded(fleetLink: context.fleetLink, sitl: context.sitl)
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
        environment.syncRosterRoleResolutions(from: mission)
        environment.logRosterBehaviorRolesSnapshotAtExecutionStart()
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
        case .deferredSquadStartDue(let taskID, let assignmentID):
            return startSquadExecution(
                taskID: taskID,
                primaryAssignmentID: assignmentID,
                mission: context.missionProvider(),
                context: context
            ) ? .progressed : .noOp
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
        environment.systems.scheduling.cancelDeferredTaskMissionStartWaiter(forTaskID: taskID)
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

    /// Rewrites each pending command’s ``MissionRunIssuedCommand/vehicleTokenKey`` from the current roster row for its ``assignmentID``.
    ///
    /// **Reserve swap-in:** ``MissionRunEnvironment`` mutates ``MissionRunAssignment/attachedFleetVehicleToken`` before
    /// ``MissionControlStore/recompileMissionControlPlanAfterFloatingReserveSwap`` refreshes the compiled plan. Pending
    /// ``MissionRunQueuedCommandBatch`` rows are still keyed by the **prior** stream binding — without this pass, the next
    /// cycle or wall-clock delivery would address the **old** aircraft while the vacancy row already shows the reserve.
    func synchronizePendingCommandBatchesWithAssignmentFleetTokens() {
        guard let environment else { return }
        let byAssignmentID = Dictionary(uniqueKeysWithValues: environment.assignments.map { ($0.id, $0) })
        var next: [MissionRunQueuedCommandBatch] = []
        next.reserveCapacity(pendingCommandBatches.count)
        for batch in pendingCommandBatches {
            let newCommands = batch.commands.map { cmd -> MissionRunIssuedCommand in
                guard let row = byAssignmentID[cmd.assignmentID],
                      let key = row.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !key.isEmpty
                else { return cmd }
                if cmd.vehicleTokenKey == key { return cmd }
                return MissionRunIssuedCommand(
                    id: cmd.id,
                    assignmentID: cmd.assignmentID,
                    slotName: cmd.slotName,
                    vehicleTokenKey: key,
                    dispatch: cmd.dispatch,
                    issuer: cmd.issuer,
                    issuerKey: cmd.issuerKey,
                    category: cmd.category
                )
            }
            next.append(
                MissionRunQueuedCommandBatch(
                    id: batch.id,
                    tag: batch.tag,
                    dispatch: batch.dispatch,
                    commands: newCommands,
                    reserveSwapPostCommitAckContext: batch.reserveSwapPostCommitAckContext
                )
            )
        }
        pendingCommandBatches = next
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
        guard let environment else { return }
        if batch.tag == .missionStart, environment.sessionPhase == .completed {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.executorMissionStartBatchSuppressedRunCompleted,
                templateParams: [
                    "dispatch": batch.dispatchLogLabel,
                ]
            )
            return
        }

        if let explicit = replacingTags {
            if !explicit.isEmpty {
                _ = cancelPendingCommandBatches(tags: explicit)
            }
        } else {
            _ = cancelPendingCommandBatches(tags: Set([batch.tag]))
        }

        if batch.tag == .reserveSwapPostCommit {
            lastEnqueuedReserveSwapPostCommitAckContext = batch.reserveSwapPostCommitAckContext
        }

        switch batch.dispatch {
        case .immediate:
            let postCommitSequential = batch.tag == .reserveSwapPostCommit && !batch.commands.isEmpty
            if Self.commandsContainCatalogueMissionClear(batch.commands) || postCommitSequential {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if batch.tag == .reserveSwapPostCommit, batch.reserveSwapPostCommitAckContext != nil {
                        await self.dispatchReserveSwapPostCommitBatch(batch, context: context)
                    } else {
                        await self.dispatchCommandsRespectingMissionClearBarrier(batch.commands, context: context)
                    }
                }
            } else {
                dispatchCommands(batch.commands, context: context)
            }
        case .at(let fireDate):
            pendingCommandBatches.append(batch)
            armWallClockBatch(batchID: batch.id, fireDate: fireDate, context: context)
        case .afterMissionCycle:
            pendingCommandBatches.append(batch)
        }
    }

    /// Removes and returns every pending `.afterMissionCycle` batch (caller dispatches).
    private func extractAfterMissionCycleBatchesFromQueue() -> [MissionRunQueuedCommandBatch] {
        let toDeliver = pendingCommandBatches.filter {
            if case .afterMissionCycle = $0.dispatch { return true }
            return false
        }
        guard !toDeliver.isEmpty else { return [] }
        pendingCommandBatches.removeAll { batch in
            if case .afterMissionCycle = batch.dispatch { return true }
            return false
        }
        return toDeliver
    }

    /// Immediate abort: clear queue, cancel scheduling tasks, dispatch commands, complete run.
    func performImmediateAbort(commands: [MissionRunIssuedCommand], context: MissionRunExecutionContext) {
        guard let environment else { return }
        clearCommandQueue()
        environment.captureExecutionContext(context)
        environment.systems.scheduling.cancelAllScheduledTasks()
        if Self.commandsContainCatalogueMissionClear(commands) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.dispatchCommandsRespectingMissionClearBarrier(commands, context: context)
                self.completeRun(
                    context: context,
                    templateKey: MissionRunLogTemplateKey.runStoppedImmediate,
                    kind: .operatorStoppedImmediate,
                    operatorWindDown: .abortProtocolPhase
                )
            }
            return
        }
        dispatchCommands(commands, context: context)
        completeRun(
            context: context,
            templateKey: MissionRunLogTemplateKey.runStoppedImmediate,
            kind: .operatorStoppedImmediate,
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

    /// Catalogue mission clear must finish before later commands in the same batch (e.g. move+park) are dispatched;
    /// otherwise the recipe’s move step races an active MAVLink mission. **Reserve swap post-commit** batches also use
    /// this path so mission-clear → vacancy mission recipe → displaced wind-down recipes dispatch **sequentially** with
    /// proper awaits between catalogue clears and nested recipes.
    private static func isCatalogueMissionClearCommand(_ issued: MissionRunIssuedCommand) -> Bool {
        if case .catalogue(let name, _) = issued.dispatch {
            return name == .fleetVehicleDoMissionClear
        }
        return false
    }

    /// Exposed for unit tests (`@testable import`).
    internal static func commandsContainCatalogueMissionClear(_ commands: [MissionRunIssuedCommand]) -> Bool {
        commands.contains(where: isCatalogueMissionClearCommand)
    }

    private func dispatchCommandsRespectingMissionClearBarrier(
        _ commands: [MissionRunIssuedCommand],
        context: MissionRunExecutionContext
    ) async {
        guard let environment else { return }
        for issued in commands {
            if Self.isCatalogueMissionClearCommand(issued) {
                _ = await environment.systems.commands.awaitCatalogueMissionClearDispatchAndAckLogs(
                    issued: issued,
                    fleetLink: context.fleetLink,
                    sitl: context.sitl
                )
            } else if case .recipe = issued.dispatch {
                _ = await environment.systems.commands.awaitRecipeDispatchAppendingDispatchedThenAckLogs(
                    issued: issued,
                    fleetLink: context.fleetLink,
                    sitl: context.sitl
                )
            } else {
                environment.appendEvent(
                    environment.systems.commands.dispatchCommand(issued, fleetLink: context.fleetLink, sitl: context.sitl)
                )
            }
        }
    }

    /// Sequential post–reserve-swap handoff: log ``MissionRunReserveSwapPipelinePhase`` pass/fail **after** fleet acks,
    /// post operator toasts on failure, and **stop** the chain on the first awaited failure (later steps are skipped).
    private func dispatchReserveSwapPostCommitBatch(_ batch: MissionRunQueuedCommandBatch, context: MissionRunExecutionContext) async {
        guard let environment, let ack = batch.reserveSwapPostCommitAckContext else {
            await dispatchCommandsRespectingMissionClearBarrier(batch.commands, context: context)
            return
        }
        let correlation = ack.correlation
        let trigger = ack.triggerSource
        for issued in batch.commands {
            let phase = MissionRunReserveSwapPostCommitPipelinePhaseResolver.phase(for: issued, correlation: correlation)
            if Self.isCatalogueMissionClearCommand(issued) {
                let ok = await environment.systems.commands.awaitCatalogueMissionClearDispatchAndAckLogs(
                    issued: issued,
                    fleetLink: context.fleetLink,
                    sitl: context.sitl
                )
                let detail = ok
                    ? "Displaced mission clear fleet ack succeeded (\(trigger))."
                    : "Displaced mission clear fleet ack failed — see mission log for reason (\(trigger))."
                environment.appendReserveSwapPipelinePhaseLog(
                    phase: .displacedMissionClear,
                    passed: ok,
                    correlation: correlation,
                    detail: detail
                )
                if !ok {
                    Self.postReserveSwapPostCommitOperatorToast(
                        message: MissionRunReserveSwapOperatorCopy.toastReserveSwapPostCommitDisplacedMissionClearFailed,
                        style: .error
                    )
                    return
                }
            } else if case .recipe = issued.dispatch {
                let ok = await environment.systems.commands.awaitRecipeDispatchAppendingDispatchedThenAckLogs(
                    issued: issued,
                    fleetLink: context.fleetLink,
                    sitl: context.sitl
                )
                let recipeRaw: String? = {
                    if case .recipe(let n, _) = issued.dispatch { return n.rawValue }
                    return nil
                }()
                let detail: String
                if ok {
                    detail = phase == .missionUpload
                        ? "Vacancy mission handoff recipe fleet ack succeeded (\(trigger))."
                        : "Displaced wind-down recipe fleet ack succeeded (\(trigger))."
                } else {
                    detail = phase == .missionUpload
                        ? "Vacancy mission handoff recipe fleet ack failed — see mission log (\(trigger))."
                        : "Displaced wind-down recipe fleet ack failed (\(trigger))."
                }
                environment.appendReserveSwapPipelinePhaseLog(
                    phase: phase,
                    passed: ok,
                    correlation: correlation,
                    detail: detail,
                    recipeRaw: recipeRaw
                )
                if !ok {
                    if phase == .missionUpload {
                        Self.postReserveSwapPostCommitOperatorToast(
                            message: MissionRunReserveSwapOperatorCopy.toastReserveSwapPostCommitVacancyMissionHandoffFailed,
                            style: .error
                        )
                    } else {
                        Self.postReserveSwapPostCommitOperatorToast(
                            message: MissionRunReserveSwapOperatorCopy.toastReserveSwapPostCommitDisplacedWindDownFailed,
                            style: .error
                        )
                    }
                    return
                }
            } else if case .catalogue = issued.dispatch {
                let ok = await environment.systems.commands.awaitCatalogueDispatchAndAckLogs(
                    issued: issued,
                    fleetLink: context.fleetLink,
                    sitl: context.sitl
                )
                let detail = ok
                    ? "Displaced wind-down catalogue fleet ack succeeded (\(trigger))."
                    : "Displaced wind-down catalogue fleet ack failed — see mission log (\(trigger))."
                environment.appendReserveSwapPipelinePhaseLog(
                    phase: .displacedFleetWindDown,
                    passed: ok,
                    correlation: correlation,
                    detail: detail
                )
                if !ok {
                    Self.postReserveSwapPostCommitOperatorToast(
                        message: MissionRunReserveSwapOperatorCopy.toastReserveSwapPostCommitDisplacedWindDownFailed,
                        style: .error
                    )
                    return
                }
            } else {
                environment.appendEvent(
                    environment.systems.commands.dispatchCommand(issued, fleetLink: context.fleetLink, sitl: context.sitl)
                )
                environment.appendReserveSwapPipelinePhaseLog(
                    phase: .displacedFleetWindDown,
                    passed: true,
                    correlation: correlation,
                    detail: "Dispatched displaced wind-down vehicle command (fleet ack follows standard mission log path; \(trigger))."
                )
            }
        }
    }

    private static func postReserveSwapPostCommitOperatorToast(message: String, style: GuardianFeedbackSeverity) {
        NotificationCenter.default.post(
            name: GuardianReserveSwapPostCommitOperatorToastNotification.name,
            object: nil,
            userInfo: [
                GuardianReserveSwapPostCommitOperatorToastNotification.messageKey: message,
                GuardianReserveSwapPostCommitOperatorToastNotification.severityRawKey: style.rawValue,
            ]
        )
    }

    /// Per-assignment fleet commands for orderly recovery wind-down from the resolved **complete preference chain**
    /// (assignment → task → mission), using the same optimistic dispatch rules as abort planning for map-point tactics.
    ///
    /// **Roster scope:** with `limitedToAssignmentIDs == nil`, every roster row with a bound stream token is
    /// considered; a row is skipped only when the resolved chain yields no dispatchable tactic (e.g. map-point needs
    /// hub position and telemetry is missing for that stream). Wingmen therefore appear only when those preconditions
    /// succeed — not because of a separate wingman gate.
    /// - Parameter limitedToAssignmentIDs: When non-nil, only these assignment rows are included (task / squad scoping).
    func buildCompletePolicyWindDownCommands(limitedToAssignmentIDs: Set<UUID>? = nil) -> [MissionRunIssuedCommand] {
        guard let environment else { return [] }
        var out: [MissionRunIssuedCommand] = []
        for assignment in environment.assignments {
            if let limitedToAssignmentIDs, !limitedToAssignmentIDs.contains(assignment.id) { continue }
            guard let mission = environment.template else { continue }
            let chain = MissionRunPolicyResolution.resolvedCompletePreferenceChain(
                assignment: assignment,
                mission: mission
            )
            guard let issued = Self.optimisticCompleteIssuedCommand(
                assignment: assignment,
                preferenceChain: chain,
                environment: environment,
                mission: mission
            ) else { continue }
            out.append(
                issued.reattributed(issuer: .operator, issuerKey: MissionRunCommandIssuerKey.completePolicyWindDown)
            )
        }
        return out
    }

    private static func optimisticCompleteIssuedCommand(
        assignment: MissionRunAssignment,
        preferenceChain: [MissionRunCompleteTactic],
        environment: MissionRunEnvironment,
        mission: Mission
    ) -> MissionRunIssuedCommand? {
        guard let tokenKey = assignment.attachedFleetVehicleToken,
              FleetMissionVehicleToken(storageKey: tokenKey) != nil
        else {
            return nil
        }
        let hub = environment.abortPlanningHubTelemetry(for: assignment)
        let taskId = MissionRunPolicyResolution.resolvedTaskId(for: assignment, mission: mission)
        let points = environment.runtimeMissionPoints

        for tactic in preferenceChain {
            switch tactic.kind {
            case .none:
                continue
            case .nearestOpenMapPoint:
                guard let tid = taskId else { continue }
                let pointKind = tactic.mapPointKind ?? .rally
                guard let hub,
                      let lat = hub.latitudeDeg,
                      let lon = hub.longitudeDeg
                else { continue }
                let relAlt = hub.guardianAbortPlanningRelativeAltitudeM
                guard let params = try? MissionRunMovePointParkPlanner.buildMovePointParkRecipeParameters(
                    kind: pointKind,
                    parentTaskID: tid,
                    missionPoints: points,
                    vehicleLatitudeDeg: lat,
                    vehicleLongitudeDeg: lon,
                    currentRelativeAltitudeM: relAlt,
                    yawDeg: hub.yawDeg ?? 0
                ) else { continue }
                return MissionRunIssuedCommand(
                    assignmentID: assignment.id,
                    slotName: assignment.slotName,
                    vehicleTokenKey: tokenKey,
                    dispatch: .recipe(
                        name: FleetMovePointParkRecipeRegistrations.movePointParkRecipeName,
                        parameters: params
                    ),
                    issuer: .operator,
                    issuerKey: MissionRunCommandIssuerKey.completePolicyWindDown,
                    category: .missionControl
                )

            case .returnToLaunch, .loiter, .park:
                guard let dispatch = MissionRunFleetDispatch.preferentialCompleteTacticDispatch(tactic.kind) else { continue }
                return MissionRunIssuedCommand(
                    assignmentID: assignment.id,
                    slotName: assignment.slotName,
                    vehicleTokenKey: tokenKey,
                    dispatch: dispatch,
                    issuer: .operator,
                    issuerKey: MissionRunCommandIssuerKey.completePolicyWindDown,
                    category: .missionControl
                )
            }
        }
        return nil
    }

    /// Per-assignment fleet commands from the resolved **reserve swap** preference chain (assignment → task → mission),
    /// using the same optimistic dispatch rules as ``buildCompletePolicyWindDownCommands`` for map-point tactics.
    func buildReserveSwapPolicyWindDownCommands(limitedToAssignmentIDs: Set<UUID>? = nil) -> [MissionRunIssuedCommand] {
        guard let environment else { return [] }
        var out: [MissionRunIssuedCommand] = []
        guard let mission = environment.template else { return [] }
        for assignment in environment.assignments {
            if let limitedToAssignmentIDs, !limitedToAssignmentIDs.contains(assignment.id) { continue }
            guard let issued = Self.optimisticReserveSwapIssuedCommand(
                assignment: assignment,
                preferenceChain: MissionRunReserveSwapTactic.normalizedPreferenceChain(
                    MissionRunPolicyResolution.resolvedReserveSwapPreferenceChain(
                        assignment: assignment,
                        mission: mission
                    )
                ),
                environment: environment,
                mission: mission
            ) else { continue }
            out.append(issued)
        }
        return out
    }

    /// Single-assignment reserve-swap wind-down for a row that may **not** appear in ``environment.assignments`` (e.g. synthetic pool berth from ``MissionRunAssignment/syntheticForReservePool``).
    func buildReserveSwapPolicyWindDownCommand(forExplicitAssignment assignment: MissionRunAssignment) -> MissionRunIssuedCommand? {
        guard let environment, let mission = environment.template else { return nil }
        return Self.optimisticReserveSwapIssuedCommand(
            assignment: assignment,
            preferenceChain: MissionRunReserveSwapTactic.normalizedPreferenceChain(
                MissionRunPolicyResolution.resolvedReserveSwapPreferenceChain(
                    assignment: assignment,
                    mission: mission
                )
            ),
            environment: environment,
            mission: mission
        )
    }

    private static func optimisticReserveSwapIssuedCommand(
        assignment: MissionRunAssignment,
        preferenceChain: [MissionRunReserveSwapTactic],
        environment: MissionRunEnvironment,
        mission: Mission
    ) -> MissionRunIssuedCommand? {
        guard let tokenKey = assignment.attachedFleetVehicleToken,
              FleetMissionVehicleToken(storageKey: tokenKey) != nil
        else {
            return nil
        }
        let hub = environment.abortPlanningHubTelemetry(for: assignment)
        let taskId = MissionRunPolicyResolution.resolvedTaskId(for: assignment, mission: mission)
        let points = environment.runtimeMissionPoints

        for tactic in preferenceChain {
            switch tactic.kind {
            case .none:
                continue
            case .nearestOpenMapPoint:
                guard let tid = taskId else { continue }
                let pointKind = tactic.mapPointKind ?? .rally
                guard let hub,
                      let lat = hub.latitudeDeg,
                      let lon = hub.longitudeDeg
                else { continue }
                let relAlt = hub.guardianAbortPlanningRelativeAltitudeM
                guard let params = try? MissionRunMovePointParkPlanner.buildMovePointParkRecipeParameters(
                    kind: pointKind,
                    parentTaskID: tid,
                    missionPoints: points,
                    vehicleLatitudeDeg: lat,
                    vehicleLongitudeDeg: lon,
                    currentRelativeAltitudeM: relAlt,
                    yawDeg: hub.yawDeg ?? 0
                ) else { continue }
                return MissionRunIssuedCommand(
                    assignmentID: assignment.id,
                    slotName: assignment.slotName,
                    vehicleTokenKey: tokenKey,
                    dispatch: .recipe(
                        name: FleetMovePointParkRecipeRegistrations.movePointParkRecipeName,
                        parameters: params
                    ),
                    issuer: .missionControl,
                    issuerKey: MissionRunCommandIssuerKey.plannerReserveSwapPostCommit,
                    category: .missionControl
                )

            case .returnToLaunch, .loiter, .park:
                guard let dispatch = MissionRunFleetDispatch.preferentialReserveSwapTacticDispatch(tactic.kind) else { continue }
                return MissionRunIssuedCommand(
                    assignmentID: assignment.id,
                    slotName: assignment.slotName,
                    vehicleTokenKey: tokenKey,
                    dispatch: dispatch,
                    issuer: .missionControl,
                    issuerKey: MissionRunCommandIssuerKey.plannerReserveSwapPostCommit,
                    category: .missionControl
                )
            }
        }
        return nil
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
            operatorWindDown: .recoveryPhase
        )
    }

    /// Task-scoped immediate abort: dispatch abort-plan commands for assignments bound to the target task only (run continues).
    @discardableResult
    func performImmediateMissionTaskAbort(target: MissionRunCommandTarget, context: MissionRunExecutionContext) -> Bool {
        guard let environment,
              let scope = commandTargetScope(target: target, environment: environment)
        else { return false }
        let taskID = scope.taskID
        let ids = scope.assignmentIDs
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
            .flatMap(\.issuedCommands)
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
        let taskLabel = environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name ?? taskID.uuidString
        let taskLabelForLog = environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: taskLabelForLog,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionTaskAbortEndAttemptNoted,
            templateParams: ["task": taskLabel]
        )
        environment.noteMissionTaskEndAttempt(.abortMissionEnd, forTaskID: taskID)
        if Self.commandsContainCatalogueMissionClear(commands) {
            Task { @MainActor [weak self] in
                guard let self, let environment = self.environment else { return }
                await self.dispatchCommandsRespectingMissionClearBarrier(commands, context: context)
                if case .squad(let assignmentID) = target {
                    environment.markMissionSquadAutostartSuppressed(forAssignmentID: assignmentID)
                    environment.markSquadAbortPolicyWindDownDispatchIssued(forAssignmentID: assignmentID)
                } else {
                    environment.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
                }
                environment.systems.scheduling.cancelScheduledTaskMissionStarts(forTaskID: taskID)
                environment.systems.logging.appendLogEvent(
                    level: .info,
                    taskID: taskID,
                    taskLabel: taskLabelForLog,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.missionTaskAbortNowDispatched,
                    templateParams: ["task": taskLabel]
                )
            }
            return true
        }
        dispatchCommands(commands, context: context)
        if case .squad(let assignmentID) = target {
            environment.markMissionSquadAutostartSuppressed(forAssignmentID: assignmentID)
            environment.markSquadAbortPolicyWindDownDispatchIssued(forAssignmentID: assignmentID)
        } else {
            environment.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        }
        environment.systems.scheduling.cancelScheduledTaskMissionStarts(forTaskID: taskID)
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: taskLabelForLog,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionTaskAbortNowDispatched,
            templateParams: ["task": taskLabel]
        )
        return true
    }

    /// Task-scoped immediate complete: dispatch complete-policy wind-down for bound slots only (run continues).
    @discardableResult
    func performImmediateMissionTaskComplete(target: MissionRunCommandTarget, context: MissionRunExecutionContext) -> Bool {
        guard let environment,
              let scope = commandTargetScope(target: target, environment: environment)
        else { return false }
        let taskID = scope.taskID
        let ids = scope.assignmentIDs
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
        let taskLabel = environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name ?? taskID.uuidString
        let taskLabelForLog = environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: taskLabelForLog,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionTaskRecoveryEndAttemptNoted,
            templateParams: ["task": taskLabel]
        )
        environment.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: taskID)
        if case .squad(let assignmentID) = target {
            environment.markSquadCompletePolicyWindDownDispatchIssued(forAssignmentID: assignmentID)
        }
        dispatchCommands(windDown, context: context)
        if case .squad(let assignmentID) = target {
            environment.markMissionSquadAutostartSuppressed(forAssignmentID: assignmentID)
        } else {
            environment.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
        }
        environment.systems.scheduling.cancelScheduledTaskMissionStarts(forTaskID: taskID)
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: taskLabelForLog,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionTaskCompleteNowDispatched,
            templateParams: ["task": taskLabel]
        )
        return true
    }

    /// Operator **Retry recovery / abort protocol**: jolt a blocked in-flight recipe when possible; otherwise cancel/wait,
    /// run the same awaited **Park** stabilisation as Engage triage, then redispatch end-policy commands once (awaited).
    func performOperatorJoltPolicyWindDown(
        target: MissionRunCommandTarget,
        mode: MissionRunOperatorPolicyWindDownJoltMode,
        context: MissionRunExecutionContext
    ) async -> MissionRunOperatorPolicyWindDownJoltOutcome {
        guard let environment,
              let scope = commandTargetScope(target: target, environment: environment)
        else { return .failedNoCommands }
        let taskID = scope.taskID
        let ids = scope.assignmentIDs
        let taskLabelForLog = environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name
        let commands: [MissionRunIssuedCommand]
        switch mode {
        case .complete:
            commands = buildCompletePolicyWindDownCommands(limitedToAssignmentIDs: ids)
                .map {
                    $0.reattributed(
                        issuer: .operator,
                        issuerKey: "operator.engageLiveDrive.retryPolicyWindDown.complete"
                    )
                }
        case .abort:
            _ = environment.systems.planner.buildAbortPlan(trigger: .now)
            commands = (environment.systems.planner.lastBuiltAbortPlan?.entries ?? [])
                .filter { ids.contains($0.assignmentID) }
                .flatMap(\.issuedCommands)
                .map {
                    $0.reattributed(
                        issuer: .operator,
                        issuerKey: "operator.engageLiveDrive.retryPolicyWindDown.abort"
                    )
                }
        }
        guard !commands.isEmpty else { return .failedNoCommands }
        guard let lead = commands.first,
              let token = FleetMissionVehicleToken(storageKey: lead.vehicleTokenKey),
              let vehicleID = resolvedFleetStreamVehicleID(
                token: token,
                fleetLink: context.fleetLink,
                sitl: context.sitl
              )
        else { return .failedNoVehicle }

        if FleetRecipeRunner.shared.joltPendingWizardEscalationRetry(forVehicleID: vehicleID) {
            return .joltedEscalation
        }

        await context.fleetLink.awaitOperatorPolicyWindDownJoltPreparation(vehicleID: vehicleID)
        let parkStabilized = await context.fleetLink.awaitOperatorEngageStabilizePark(vehicleID: vehicleID)
        if !parkStabilized {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: taskLabelForLog,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.operatorPolicyWindDownJoltParkStabilizationFailed,
                templateParams: [
                    "task": taskLabelForLog ?? taskID.uuidString,
                    "vehicleID": vehicleID,
                ]
            )
        }

        environment.captureExecutionContext(context)
        let taskLabel = taskLabelForLog ?? taskID.uuidString
        switch mode {
        case .complete:
            environment.systems.logging.appendLogEvent(
                level: .info,
                taskID: taskID,
                taskLabel: taskLabelForLog,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskRecoveryEndAttemptNoted,
                templateParams: ["task": taskLabel]
            )
            environment.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: taskID)
            if case .squad(let assignmentID) = target {
                environment.markSquadCompletePolicyWindDownDispatchIssued(forAssignmentID: assignmentID)
                environment.markMissionSquadAutostartSuppressed(forAssignmentID: assignmentID)
            } else {
                environment.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
            }
        case .abort:
            environment.systems.logging.appendLogEvent(
                level: .info,
                taskID: taskID,
                taskLabel: taskLabelForLog,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskAbortEndAttemptNoted,
                templateParams: ["task": taskLabel]
            )
            environment.noteMissionTaskEndAttempt(.abortMissionEnd, forTaskID: taskID)
            if case .squad(let assignmentID) = target {
                environment.markSquadAbortPolicyWindDownDispatchIssued(forAssignmentID: assignmentID)
                environment.markMissionSquadAutostartSuppressed(forAssignmentID: assignmentID)
            } else {
                environment.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
            }
        }
        environment.systems.scheduling.cancelScheduledTaskMissionStarts(forTaskID: taskID)
        await dispatchCommandsRespectingMissionClearBarrier(commands, context: context)
        return .redispatched
    }

    /// Delivers queued per-primary-squad abort/complete wind-downs when **that squad’s** MAVLink cycle ends.
    internal func deliverPendingSquadGracefulWindDownsIfNeeded(
        completedSquadAssignmentIDs: Set<UUID>,
        context: MissionRunExecutionContext
    ) {
        guard let environment, !completedSquadAssignmentIDs.isEmpty else { return }
        guard let mission = context.missionProvider() else { return }
        for assignmentID in completedSquadAssignmentIDs {
            guard let kind = environment.consumePendingMissionSquadGracefulWindDown(forAssignmentID: assignmentID) else { continue }
            guard let taskID = environment.resolvedTaskID(forSquadAssignmentID: assignmentID, mission: mission),
                  let task = mission.routeMacro.tasks.first(where: { $0.id == taskID })
            else { continue }
            let ids: Set<UUID> = [assignmentID]
            switch kind {
            case .abortAfterCycle:
                _ = environment.systems.planner.buildAbortPlan(trigger: .afterCycle)
                let commands = (environment.systems.planner.lastBuiltAbortPlan?.entries ?? [])
                    .filter { ids.contains($0.assignmentID) }
                    .flatMap(\.issuedCommands)
                    .map { $0.reattributed(issuer: .operator, issuerKey: MissionRunCommandIssuerKey.localOperator) }
                guard !commands.isEmpty else {
                    environment.systems.logging.appendLogEvent(
                        level: .warning,
                        taskID: taskID,
                        taskLabel: task.name,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.missionTaskAbortGracefulSkippedNoCommands
                    )
                    continue
                }
                let label = task.name
                let taskLabelForLog = task.name
                environment.noteMissionTaskEndAttempt(.abortMissionEnd, forTaskID: taskID)
                if Self.commandsContainCatalogueMissionClear(commands) {
                    Task { @MainActor [weak self] in
                        guard let self, let environment = self.environment else { return }
                        await self.dispatchCommandsRespectingMissionClearBarrier(commands, context: context)
                        environment.markMissionSquadAutostartSuppressed(forAssignmentID: assignmentID)
                        environment.systems.scheduling.cancelDeferredSquadMissionStartScheduling(forAssignmentID: assignmentID)
                        environment.systems.logging.appendLogEvent(
                            level: .info,
                            taskID: taskID,
                            taskLabel: taskLabelForLog,
                            speaker: .missionControl,
                            templateKey: MissionRunLogTemplateKey.missionTaskAbortGracefulDispatched,
                            templateParams: ["task": label]
                        )
                    }
                    continue
                }
                dispatchCommands(commands, context: context)
                environment.markMissionSquadAutostartSuppressed(forAssignmentID: assignmentID)
                environment.systems.scheduling.cancelDeferredSquadMissionStartScheduling(forAssignmentID: assignmentID)
                environment.systems.logging.appendLogEvent(
                    level: .info,
                    taskID: taskID,
                    taskLabel: task.name,
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
                        taskLabel: task.name,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulSkippedNoCommands
                    )
                    continue
                }
                environment.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: taskID)
                environment.markSquadCompletePolicyWindDownDispatchIssued(forAssignmentID: assignmentID)
                dispatchCommands(windDown, context: context)
                environment.markMissionSquadAutostartSuppressed(forAssignmentID: assignmentID)
                environment.systems.scheduling.cancelDeferredSquadMissionStartScheduling(forAssignmentID: assignmentID)
                let label = task.name
                environment.systems.logging.appendLogEvent(
                    level: .info,
                    taskID: taskID,
                    taskLabel: task.name,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulDispatched,
                    templateParams: ["task": label]
                )
            }
        }
    }

    /// Delivers queued per-task abort/complete wind-downs for any of ``completedCycleTaskIDs`` that have
    /// ``MissionRunEnvironment/pendingMissionTaskGracefulWindDownKindByTaskID`` set (including whole-run graceful
    /// armings, which seed one pending row per task).
    internal func deliverPendingMissionTaskGracefulWindDownsIfNeeded(
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
                    .flatMap(\.issuedCommands)
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
                let label = environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name ?? taskID.uuidString
                let taskLabelForLog = environment.template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name
                environment.noteMissionTaskEndAttempt(.abortMissionEnd, forTaskID: taskID)
                if Self.commandsContainCatalogueMissionClear(commands) {
                    Task { @MainActor [weak self] in
                        guard let self, let environment = self.environment else { return }
                        await self.dispatchCommandsRespectingMissionClearBarrier(commands, context: context)
                        environment.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
                        environment.systems.scheduling.cancelScheduledTaskMissionStarts(forTaskID: taskID)
                        environment.systems.logging.appendLogEvent(
                            level: .info,
                            taskID: taskID,
                            taskLabel: taskLabelForLog,
                            speaker: .missionControl,
                            templateKey: MissionRunLogTemplateKey.missionTaskAbortGracefulDispatched,
                            templateParams: ["task": label]
                        )
                    }
                    continue
                }
                dispatchCommands(commands, context: context)
                environment.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
                environment.systems.scheduling.cancelScheduledTaskMissionStarts(forTaskID: taskID)
                environment.systems.logging.appendLogEvent(
                    level: .info,
                    taskID: taskID,
                    taskLabel: taskLabelForLog,
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
                environment.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: taskID)
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

        let activeSquads = environment.activeCycleSquadAssignmentIDs
        guard !activeSquads.isEmpty else { return .noOp }

        var touchesActiveSquad = false
        for assignmentID in activeSquads {
            guard let assignment = environment.assignments.first(where: { $0.id == assignmentID }),
                  let streamID = resolvedFleetStreamVehicleID(
                      assignment: assignment,
                      fleetLink: context.fleetLink,
                      sitl: context.sitl
                  )
            else { continue }
            if streamID == vehicleID {
                touchesActiveSquad = true
                break
            }
        }
        guard touchesActiveSquad else { return .noOp }

        var newlyCompletedSquadAssignmentIDs: Set<UUID> = []
        for assignmentID in activeSquads {
            guard let assignment = environment.assignments.first(where: { $0.id == assignmentID }),
                  let streamID = resolvedFleetStreamVehicleID(
                      assignment: assignment,
                      fleetLink: context.fleetLink,
                      sitl: context.sitl
                  ),
                  streamID == vehicleID
            else { continue }
            environment.markFinishedMissionCycleVehicleID(vehicleID, forSquadAssignmentID: assignmentID)
            newlyCompletedSquadAssignmentIDs.insert(assignmentID)
        }

        guard !newlyCompletedSquadAssignmentIDs.isEmpty else { return .progressed }

        environment.setMissionCycleCount(environment.cyclesCompleted + newlyCompletedSquadAssignmentIDs.count)
        for assignmentID in newlyCompletedSquadAssignmentIDs {
            environment.clearFinishedMissionCycleVehicleIDs(forSquadAssignmentID: assignmentID)
            environment.removeSquadFromActiveCycle(assignmentID)
        }
        let newlyCompletedTaskIDs = environment.recordSquadCycleCompletions(
            assignmentIDs: newlyCompletedSquadAssignmentIDs,
            mission: mission
        )
        deliverPendingSquadGracefulWindDownsIfNeeded(
            completedSquadAssignmentIDs: newlyCompletedSquadAssignmentIDs,
            context: context
        )
        autoDeliverPerSquadFiniteCycleCompletePolicyIfNeeded(
            newlyCompletedSquadAssignmentIDs: newlyCompletedSquadAssignmentIDs,
            mission: mission,
            context: context
        )
        if !newlyCompletedTaskIDs.isEmpty {
            deliverPendingMissionTaskGracefulWindDownsIfNeeded(
                completedCycleTaskIDs: newlyCompletedTaskIDs,
                context: context
            )
            autoDeliverBoundedRepeatingTaskCompleteWindDownIfNeeded(
                taskIDs: newlyCompletedTaskIDs,
                mission: mission,
                context: context
            )
        }

        let missionWideAutostartFrozen = environment.shouldSuppressMissionWideBetweenCycleAutostart()
        let operatorTriggeredTaskIDs = Set(
            mission.routeMacro.tasks
                .filter { $0.enabled && $0.regularity == .operatorTriggered }
                .map(\.id)
        )
        let completedOperatorTriggered = newlyCompletedSquadAssignmentIDs.contains { assignmentID in
            guard let taskID = environment.resolvedTaskID(forSquadAssignmentID: assignmentID, mission: mission) else {
                return false
            }
            return operatorTriggeredTaskIDs.contains(taskID)
        }
        if !missionWideAutostartFrozen, !completedOperatorTriggered {
            let nextPlan = planNextAutoCycleStartsForSquads(
                mission: mission,
                completedSquadAssignmentIDs: newlyCompletedSquadAssignmentIDs
            )
            if !nextPlan.immediateSquads.isEmpty || !nextPlan.delayedSquads.isEmpty {
                if !nextPlan.betweenCyclesCommands.isEmpty {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.environment != nil else { return }
                        for issued in nextPlan.betweenCyclesCommands {
                            await self.dispatchBetweenCyclesIssuedCommandWithOptionalFallback(issued, context: context)
                        }
                        self.startPlannedImmediateSquads(nextPlan.immediateSquads, mission: mission, context: context)
                        self.scheduleAutoCycleDelayedSquads(nextPlan.delayedSquads, mission: mission, context: context)
                    }
                    return .progressed
                }
                startPlannedImmediateSquads(nextPlan.immediateSquads, mission: mission, context: context)
                scheduleAutoCycleDelayedSquads(nextPlan.delayedSquads, mission: mission, context: context)
                return .progressed
            }
        }

        if !missionHasOnlyBoundedTasks(mission) {
            environment.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionRunningUnboundedRegularity
            )
            // Whole-run finalize requires ``gracefulStopKind`` + empty active set — not per-task wind-down alone.
            if missionWideAutostartFrozen, environment.activeCycleTaskIDs.isEmpty {
                return finalizeWholeRunGracefulAfterLastAutopilotCycle(context: context)
            }
            return .progressed
        }

        if !missionWideAutostartFrozen {
            if allBoundedRepeatingTasksFinishedWithNoActiveInFlightCycle(environment: environment, mission: mission) {
                completeRun(
                    context: context,
                    templateKey: MissionRunLogTemplateKey.runOneOffFinished,
                    kind: .oneOffAutopilotFinished,
                    operatorWindDown: .recoveryPhase
                )
                return .completed(.oneOffAutopilotFinished)
            }
        } else if environment.activeCycleTaskIDs.isEmpty {
            return finalizeWholeRunGracefulAfterLastAutopilotCycle(context: context)
        }

        return .progressed
    }

    /// When a finite repeating task’s **aggregated** cycle boundary closes, operator-scheduled
    /// ``completeMissionTaskAfterCycle`` is optional — without a pending row the next MAVLink cycle would still
    /// autostart (``planNextAutoCycleStartsForSquads``). Seed the same ``.completeAfterCycle`` delivery path so
    /// complete-policy recovery dispatches and per-task autostart suppresses for that path.
    private func autoDeliverBoundedRepeatingTaskCompleteWindDownIfNeeded(
        taskIDs: Set<UUID>,
        mission: Mission,
        context: MissionRunExecutionContext
    ) {
        guard let environment else { return }
        for taskID in taskIDs {
            guard let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
                  task.enabled
            else { continue }
            let repeats = task.regularity == .continuous || task.regularity == .continuousWithDelay
            guard repeats, task.cycles > 0 else { continue }
            let done = environment.taskCyclesCompletedByTaskID[taskID] ?? 0
            guard done >= task.cycles else { continue }
            guard environment.boundPrimarySquadCount(forTaskID: taskID, mission: mission) <= 1 else { continue }
            guard !environment.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskID),
                  !environment.missionTaskAbortWindDownIssuedTaskIDs.contains(taskID)
            else { continue }
            environment.setPendingMissionTaskGracefulWindDown(kind: .completeAfterCycle, forTaskID: taskID)
            deliverPendingMissionTaskGracefulWindDownsIfNeeded(
                completedCycleTaskIDs: [taskID],
                context: context
            )
        }
    }

    /// Multi-primary finite-cycle: when **one** primary’s MAVLink cycle closes and that squad has exhausted its
    /// ``MissionTask/cycles`` allotment, dispatch complete-policy wind-down for **that row only** (task rollup stays
    /// ``executing`` until every primary has finished the race).
    private func autoDeliverPerSquadFiniteCycleCompletePolicyIfNeeded(
        newlyCompletedSquadAssignmentIDs: Set<UUID>,
        mission: Mission,
        context: MissionRunExecutionContext
    ) {
        guard let environment, !newlyCompletedSquadAssignmentIDs.isEmpty else { return }
        for assignmentID in newlyCompletedSquadAssignmentIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let taskID = environment.resolvedTaskID(forSquadAssignmentID: assignmentID, mission: mission),
                  let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
                  task.enabled
            else { continue }
            let repeats = task.regularity == .continuous || task.regularity == .continuousWithDelay
            guard repeats, task.cycles > 0 else { continue }
            guard environment.boundPrimarySquadCount(forTaskID: taskID, mission: mission) > 1 else { continue }
            let squadDone = environment.squadCyclesCompletedByAssignmentID[assignmentID] ?? 0
            guard squadDone >= task.cycles else { continue }
            guard !environment.missionTaskAbortWindDownIssuedTaskIDs.contains(taskID),
                  !environment.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskID)
            else { continue }
            guard !environment.squadCompletePolicyWindDownIssuedAssignmentIDs.contains(assignmentID) else { continue }
            let ids: Set<UUID> = [assignmentID]
            let windDown = buildCompletePolicyWindDownCommands(limitedToAssignmentIDs: ids)
            guard !windDown.isEmpty else {
                environment.systems.logging.appendLogEvent(
                    level: .warning,
                    taskID: taskID,
                    taskLabel: task.name,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulSkippedNoCommands
                )
                continue
            }
            environment.markSquadCompletePolicyWindDownDispatchIssued(forAssignmentID: assignmentID)
            environment.noteMissionTaskEndAttempt(.recoveryMissionEnd, forTaskID: taskID)
            dispatchCommands(windDown, context: context)
            environment.markMissionSquadAutostartSuppressed(forAssignmentID: assignmentID)
            environment.systems.scheduling.cancelDeferredSquadMissionStartScheduling(forAssignmentID: assignmentID)
            let label = task.name
            environment.systems.logging.appendLogEvent(
                level: .info,
                taskID: taskID,
                taskLabel: task.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionTaskCompleteGracefulDispatched,
                templateParams: ["task": label]
            )
        }
    }

    /// Whole-run “after cycle” stop: once no task is still inside an in-flight autopilot cycle, end the run the same way
    /// the legacy single queued batch did (optional mission-clear barrier, then ``completeRun``).
    private func finalizeWholeRunGracefulAfterLastAutopilotCycle(
        context: MissionRunExecutionContext
    ) -> MissionRunExecutionDecision {
        guard let environment else { return .progressed }
        let toDeliver = extractAfterMissionCycleBatchesFromQueue()
        let stopKind = environment.gracefulStopKind
        let needsClearBarrier = toDeliver.contains { Self.commandsContainCatalogueMissionClear($0.commands) }
        if needsClearBarrier {
            Task { @MainActor [weak self] in
                guard let self, self.environment != nil else { return }
                for batch in toDeliver {
                    await self.dispatchCommandsRespectingMissionClearBarrier(batch.commands, context: context)
                }
                if stopKind == .abortAfterCycle {
                    self.completeRun(
                        context: context,
                        templateKey: MissionRunLogTemplateKey.runGracefulAfterCycle,
                        kind: .operatorStoppedAfterCycle,
                        operatorWindDown: .abortProtocolPhase
                    )
                } else {
                    self.completeRun(
                        context: context,
                        templateKey: MissionRunLogTemplateKey.runCompleteWindDownAfterCycle,
                        kind: .operatorCompletedAfterCycle,
                        operatorWindDown: .recoveryPhase
                    )
                }
            }
            return .progressed
        }
        for batch in toDeliver {
            dispatchCommands(batch.commands, context: context)
        }
        if stopKind == .abortAfterCycle {
            completeRun(
                context: context,
                templateKey: MissionRunLogTemplateKey.runGracefulAfterCycle,
                kind: .operatorStoppedAfterCycle,
                operatorWindDown: .abortProtocolPhase
            )
            return .completed(.operatorStoppedAfterCycle)
        }
        completeRun(
            context: context,
            templateKey: MissionRunLogTemplateKey.runCompleteWindDownAfterCycle,
            kind: .operatorCompletedAfterCycle,
            operatorWindDown: .recoveryPhase
        )
        return .completed(.operatorCompletedAfterCycle)
    }

    /// True when every enabled task is a **finite** continuous / continuous-with-delay path, every such task has reached
    /// its configured cycle cap, and no task is still in the in-flight autopilot cycle set (others may be in deferral).
    private func allBoundedRepeatingTasksFinishedWithNoActiveInFlightCycle(
        environment: MissionRunEnvironment,
        mission: Mission
    ) -> Bool {
        guard missionHasOnlyBoundedTasks(mission) else { return false }
        guard environment.activeCycleTaskIDs.isEmpty else { return false }
        for task in mission.routeMacro.tasks where task.enabled {
            switch task.regularity {
            case .continuous, .continuousWithDelay:
                let done = environment.taskCyclesCompletedByTaskID[task.id] ?? 0
                if done < task.cycles { return false }
            case .onceAtStart, .operatorTriggered:
                break
            }
        }
        return true
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

    private struct SquadCycleLaunchRef: Equatable {
        let taskID: UUID
        let primaryAssignmentID: UUID
    }

    private struct NextCycleStartPlan {
        var immediateSquads: [SquadCycleLaunchRef] = []
        var delayedSquads: [SquadCycleLaunchRef] = []
        var betweenCyclesCommands: [MissionRunIssuedCommand] = []
    }

    private func planNextAutoCycleStartsForSquads(
        mission: Mission,
        completedSquadAssignmentIDs: Set<UUID>
    ) -> NextCycleStartPlan {
        guard let environment else { return NextCycleStartPlan() }
        var plan = NextCycleStartPlan()
        let tasksByID = Dictionary(uniqueKeysWithValues: mission.routeMacro.tasks.map { ($0.id, $0) })
        for assignmentID in completedSquadAssignmentIDs {
            guard let taskID = environment.resolvedTaskID(forSquadAssignmentID: assignmentID, mission: mission),
                  let task = tasksByID[taskID], task.enabled
            else { continue }
            if environment.shouldSuppressAutopilotAutostart(
                forSquadAssignmentID: assignmentID,
                taskID: taskID,
                mission: mission
            ) { continue }
            let aggregatedCyclesDone = environment.taskCyclesCompletedByTaskID[taskID] ?? 0
            if task.cycles > 0, aggregatedCyclesDone >= task.cycles { continue }
            let squadCyclesDone = environment.squadCyclesCompletedByAssignmentID[assignmentID] ?? 0
            let shouldStart = task.cycles == 0 || squadCyclesDone < task.cycles
            guard shouldStart else { continue }
            let ref = SquadCycleLaunchRef(taskID: taskID, primaryAssignmentID: assignmentID)
            switch task.regularity {
            case .continuous:
                plan.immediateSquads.append(ref)
            case .continuousWithDelay:
                plan.delayedSquads.append(ref)
                plan.betweenCyclesCommands.append(
                    contentsOf: betweenCyclesCommands(
                        for: task,
                        mission: mission,
                        restrictToPrimaryAssignmentIDs: Set([assignmentID])
                    )
                )
            case .onceAtStart, .operatorTriggered:
                break
            }
        }
        return plan
    }

    private func betweenCyclesCommands(
        for task: MissionTask,
        mission: Mission,
        restrictToPrimaryAssignmentIDs: Set<UUID>? = nil
    ) -> [MissionRunIssuedCommand] {
        guard let environment else { return [] }
        guard let dispatch = MissionRunFleetDispatch.betweenCyclesTaskDispatch(task.betweenCycles) else { return [] }
        let squads = environment.systems.planner.buildTaskSquadMissions(mission: mission, taskId: task.id)
        return squads.compactMap { squad in
            let aid = squad.squad.primaryAssignment.id
            if let restrict = restrictToPrimaryAssignmentIDs, !restrict.contains(aid) { return nil }
            guard let tokenKey = squad.squad.primaryAssignment.attachedFleetVehicleToken else { return nil }
            return MissionRunIssuedCommand(
                assignmentID: aid,
                slotName: squad.squad.primaryAssignment.slotName,
                vehicleTokenKey: tokenKey,
                dispatch: dispatch,
                issuer: .missionControl,
                issuerKey: MissionRunCommandIssuerKey.missionExecute,
                category: .missionControl
            )
        }
    }

    private func startPlannedImmediateSquads(
        _ squads: [SquadCycleLaunchRef],
        mission: Mission,
        context: MissionRunExecutionContext
    ) {
        for ref in squads {
            _ = startSquadExecution(
                taskID: ref.taskID,
                primaryAssignmentID: ref.primaryAssignmentID,
                mission: mission,
                context: context
            )
        }
    }

    private func scheduleAutoCycleDelayedSquads(
        _ squads: [SquadCycleLaunchRef],
        mission: Mission,
        context: MissionRunExecutionContext
    ) {
        guard let environment else { return }
        for ref in squads {
            let task = mission.routeMacro.tasks.first(where: { $0.id == ref.taskID })
            let delaySeconds = max(1, task?.regularityDelayTotalSeconds ?? 1)
            let startAt = Date().addingTimeInterval(delaySeconds)
            environment.setSquadStartDeferral(
                MissionTaskStartDeferral(startAt: startAt, totalDelay: delaySeconds),
                forAssignmentID: ref.primaryAssignmentID
            )
            environment.systems.scheduling.armSquadMissionStartTask(
                taskID: ref.taskID,
                primaryAssignmentID: ref.primaryAssignmentID,
                startAt: startAt
            ) { [weak self] in
                guard let self else { return }
                _ = self.handleEvent(
                    .deferredSquadStartDue(taskID: ref.taskID, primaryAssignmentID: ref.primaryAssignmentID),
                    context: context
                )
            }
        }
    }

    /// Awaits catalogue or recipe acknowledgement for a between-cycles primary; on failure, dispatches class-based fallback (UAV → loiter, else park) when it differs from the primary.
    private func dispatchBetweenCyclesIssuedCommandWithOptionalFallback(
        _ issued: MissionRunIssuedCommand,
        context: MissionRunExecutionContext
    ) async {
        guard let environment else { return }
        let cmds = environment.systems.commands
        let primaryOK: Bool
        switch issued.dispatch {
        case .vehicleCommand:
            primaryOK = false
        case .catalogue:
            primaryOK = await cmds.awaitCatalogueDispatchAndAckLogs(
                issued: issued,
                fleetLink: context.fleetLink,
                sitl: context.sitl
            )
        case .recipe:
            primaryOK = await cmds.awaitRecipeDispatchAppendingDispatchedThenAckLogs(
                issued: issued,
                fleetLink: context.fleetLink,
                sitl: context.sitl
            )
        }
        if primaryOK { return }
        let vClass = environment.assignments.first(where: { $0.id == issued.assignmentID })
            .map { environment.expectedFleetVehicleClassForRosterAssignment($0) } ?? .unknown
        let fallbackDispatch = MissionRunFleetDispatch.betweenCyclesFailureFallbackDispatch(expectedGranularClass: vClass)
        if fallbackDispatch == issued.dispatch { return }
        let fields = environment.systems.logging.effectiveTaskFields(forAssignmentID: issued.assignmentID)
        environment.systems.logging.appendLogEvent(
            level: .warning,
            taskID: fields.0,
            taskLabel: fields.1,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.betweenCyclesPrimaryFailedDispatchingFallback,
            templateParams: [
                "slot": issued.slotName,
                "slotID": issued.assignmentID.uuidString,
                "primary": issued.dispatch.betweenCyclesPolicyLogLabel,
                "fallback": fallbackDispatch.betweenCyclesPolicyLogLabel,
                "vehicleClass": vClass.classCode,
            ]
        )
        let fallbackIssued = MissionRunIssuedCommand(
            assignmentID: issued.assignmentID,
            slotName: issued.slotName,
            vehicleTokenKey: issued.vehicleTokenKey,
            dispatch: fallbackDispatch,
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.betweenCyclesFallback,
            category: .missionControl
        )
        _ = await cmds.awaitCatalogueDispatchAndAckLogs(
            issued: fallbackIssued,
            fleetLink: context.fleetLink,
            sitl: context.sitl
        )
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
            environment.markFirstWaveSquadsActiveInCurrentCycle(taskID: taskID, mission: mission)
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

    /// Launches one primary squad’s MAVLink mission (next-cycle autostart or operator release of a deferred first-wave squad).
    @discardableResult
    func startSquadExecution(
        taskID: UUID,
        primaryAssignmentID: UUID,
        mission: Mission?,
        context: MissionRunExecutionContext
    ) -> Bool {
        guard let environment else { return false }
        guard environment.sessionPhase == .executing else { return false }
        guard let mission = mission ?? context.missionProvider() else { return false }
        if environment.activeCycleSquadAssignmentIDs.contains(primaryAssignmentID) {
            return false
        }
        if environment.shouldSuppressAutopilotAutostart(
            forSquadAssignmentID: primaryAssignmentID,
            taskID: taskID,
            mission: mission
        ) {
            return false
        }
        if let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
           task.enabled,
           (task.regularity == .continuous || task.regularity == .continuousWithDelay),
           task.cycles > 0 {
            let squadDone = environment.squadCyclesCompletedByAssignmentID[primaryAssignmentID] ?? 0
            if squadDone >= task.cycles { return false }
            let aggregated = environment.taskCyclesCompletedByTaskID[taskID] ?? 0
            if aggregated >= task.cycles { return false }
        }
        let pass = buildPrimaryMissionPass(
            mission: mission,
            explicitTaskId: taskID,
            nextCyclePrimaryAssignmentIDs: Set([primaryAssignmentID])
        )
        let dispatched = !pass.immediateCommands.isEmpty || !pass.queuedBatches.isEmpty
        if dispatched {
            environment.markSquadActiveInCurrentCycle(primaryAssignmentID)
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

    /// Operator / automation: launch the next deferred first-wave primary for this task (waypoint / operator stagger gate).
    @discardableResult
    func releaseNextDeferredFirstWaveSquad(taskID: UUID, context: MissionRunExecutionContext) -> Bool {
        guard let environment,
              let assignmentID = environment.consumeNextDeferredFirstWaveSquadAssignmentID(forTaskID: taskID)
        else { return false }
        guard let mission = context.missionProvider(),
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID })
        else { return false }
        let squadIndex = environment.primarySquads(forTaskID: taskID, mission: mission)
            .firstIndex(where: { $0.assignment.id == assignmentID }) ?? 0
        let squadLog = MissionControlSquadUtilities.squadLogContext(
            taskID: task.id,
            taskName: task.name,
            squadIndex: squadIndex
        )
        let ok = startSquadExecution(
            taskID: taskID,
            primaryAssignmentID: assignmentID,
            mission: mission,
            context: context
        )
        if ok {
            environment.systems.logging.appendLogEvent(
                level: .info,
                taskID: squadLog.id,
                taskLabel: squadLog.label,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.missionSquadFirstWaveReleased,
                templateParams: ["squad": squadLog.label, "slotID": assignmentID.uuidString]
            )
        }
        return ok
    }

    /// Operator-triggered path: exactly one launch per operator press (no autopilot cycle loop).
    @discardableResult
    func performOperatorTriggerNextSquadAction(
        taskID: UUID,
        action: MissionControlOperatorTriggerNextSquadAction,
        context: MissionRunExecutionContext
    ) -> Bool {
        guard let environment,
              let mission = context.missionProvider(),
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
              task.regularity == .operatorTriggered
        else { return false }

        switch action {
        case .coldStartTask:
            return startTaskExecution(
                taskID: taskID,
                mission: mission,
                context: context,
                allowDuringStaging: true
            )
        case .releaseDeferredFirstWaveHead:
            return releaseNextDeferredFirstWaveSquad(taskID: taskID, context: context)
        case .launchPrimary(let assignmentID):
            return startSquadExecution(
                taskID: taskID,
                primaryAssignmentID: assignmentID,
                mission: mission,
                context: context
            )
        }
    }

    private struct CommandTargetScope {
        let taskID: UUID
        let assignmentIDs: Set<UUID>
    }

    private func commandTargetScope(
        target: MissionRunCommandTarget,
        environment: MissionRunEnvironment
    ) -> CommandTargetScope? {
        switch target {
        case .task(let taskID):
            let ids = Set(environment.assignmentsBoundToMissionTask(taskID: taskID).map(\.id))
            return ids.isEmpty ? nil : CommandTargetScope(taskID: taskID, assignmentIDs: ids)
        case .squad(let assignmentID):
            guard let mission = environment.template,
                  let taskID = environment.resolvedTaskID(forSquadAssignmentID: assignmentID, mission: mission)
            else { return nil }
            return CommandTargetScope(taskID: taskID, assignmentIDs: Set([assignmentID]))
        }
    }

    private func buildStagingPass(mission: Mission?) -> MissionRunPassResult {
        guard let environment else { return MissionRunPassResult(events: [], commands: []) }
        var events: [MissionRunEvent] = []
        events.append(
            MissionRunEvent(
                level: .info,
                templateKey: MissionRunLogTemplateKey.stagingPassStarted
            )
        )
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
                events.append(
                    MissionRunEvent(
                        level: .info,
                        taskID: taskID,
                        taskLabel: taskLabel,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.stagingSimPoseFromSetup,
                        templateParams: ["slot": slot]
                    )
                )
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
        return MissionRunPassResult(events: events, commands: [])
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

    private func buildPrimaryMissionPass(
        mission: Mission,
        explicitTaskId: UUID? = nil,
        nextCyclePrimaryAssignmentIDs: Set<UUID>? = nil
    ) -> TaskMissionLaunchPass {
        guard let environment else { return TaskMissionLaunchPass(events: [], immediateCommands: [], queuedBatches: []) }
        let fleetLink = environment.fleetLink
        let sitl = environment.sitl
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
        let staggerStep = MissionTaskStaggerPolicy.firstWaveStepSeconds(task: task, mission: mission, squads: squads)
        let now = Date()

        let isNextCyclePass = nextCyclePrimaryAssignmentIDs != nil
        var deferredFirstWaveAssignmentIDs: [UUID] = []

        for squad in squads {
            let primaryID = squad.squad.primaryAssignment.id
            if let restrict = nextCyclePrimaryAssignmentIDs {
                guard restrict.contains(primaryID) else { continue }
            } else if !MissionTaskStaggerPolicy.includesSquadInAutomaticFirstWave(
                task: task,
                squadIndex: squad.squadIndex
            ) {
                deferredFirstWaveAssignmentIDs.append(primaryID)
                continue
            }
            guard let tokenKey = squad.squad.primaryAssignment.attachedFleetVehicleToken else { continue }
            let squadLog = MissionControlSquadUtilities.squadLogContext(
                taskID: task.id,
                taskName: task.name,
                squadIndex: squad.squadIndex
            )
            let plan = Mavsdk.Mission.MissionPlan(missionItems: squad.missionItems)
            let missionItemsJSON: String
            do {
                missionItemsJSON = try FleetVehicleCommandMissionItemPayload.encodeMissionPlanToJSON(plan: plan)
            } catch {
                events.append(
                    MissionRunEvent(
                        level: .error,
                        taskID: squadLog.id,
                        taskLabel: squadLog.label,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.missionPlanItemsEncodeFailed,
                        templateParams: [
                            "slot": squad.squad.primaryAssignment.slotName,
                            "slotID": squad.squad.primaryAssignment.id.uuidString,
                            "reason": error.localizedDescription,
                        ]
                    )
                )
                continue
            }
            let geofencePolygonsJSON: String
            do {
                let hubForPx4Filter: FleetHubVehicleTelemetry? = {
                    guard let fleetLink, let sitl,
                          let token = FleetMissionVehicleToken(storageKey: tokenKey),
                          let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
                    else { return nil }
                    return fleetLink.hubTelemetry(forVehicleID: vehicleID)
                }()
                let px4FilterHome = MissionGeofenceMavsdkGeofenceUtilities.px4GeofenceFilterHome(
                    routeMacroHome: mission.routeMacro.home?.coord,
                    hub: hubForPx4Filter
                )
                let (geofencesForPx4, omittedPx4Inclusions) = MissionGeofenceMavsdkGeofenceUtilities.fencesFilteredForPX4GeofenceUpload(
                    fences: squad.effectiveGeofencesForSquad,
                    home: px4FilterHome
                )
                if omittedPx4Inclusions > 0 {
                    events.append(
                        MissionRunEvent(
                            level: .warning,
                            taskID: squadLog.id,
                            taskLabel: squadLog.label,
                            speaker: .missionControl,
                            templateKey: MissionRunLogTemplateKey.missionGeofencePx4InclusionFencesOmitted,
                            templateParams: [
                                "count": String(omittedPx4Inclusions),
                                "slot": squad.squad.primaryAssignment.slotName,
                                "slotID": squad.squad.primaryAssignment.id.uuidString,
                            ]
                        )
                    )
                }
                geofencePolygonsJSON = try MissionGeofenceMavsdkGeofenceUtilities.encodeGeofencePolygonsJSON(
                    forGeofences: geofencesForPx4
                )
            } catch {
                events.append(
                    MissionRunEvent(
                        level: .error,
                        taskID: squadLog.id,
                        taskLabel: squadLog.label,
                        speaker: .missionControl,
                        templateKey: MissionRunLogTemplateKey.missionGeofencePolygonsEncodeFailed,
                        templateParams: [
                            "slot": squad.squad.primaryAssignment.slotName,
                            "slotID": squad.squad.primaryAssignment.id.uuidString,
                            "reason": error.localizedDescription,
                        ]
                    )
                )
                continue
            }
            let issued = MissionRunIssuedCommand(
                assignmentID: squad.squad.primaryAssignment.id,
                slotName: squad.squad.primaryAssignment.slotName,
                vehicleTokenKey: tokenKey,
                dispatch: .recipe(
                    name: FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName,
                    parameters: FleetRecipeParameters(values: [
                        "missionItemsJSON": .string(missionItemsJSON),
                        "geofencePolygonsJSON": .string(geofencePolygonsJSON),
                    ])
                ),
                issuer: .missionControl,
                issuerKey: MissionRunCommandIssuerKey.missionExecute,
                category: .missionControl
            )
            let offset = isNextCyclePass ? 0 : Double(squad.squadIndex) * staggerStep
            let dispatchAt = now.addingTimeInterval(offset)
            let formationLabel = (formation == .line) ? "line" : "cluster"
            let timingLabel = offset > 0 ? "stagger +\(Int(offset))s" : "start now"
            events.append(
                MissionRunEvent(
                    level: .info,
                    taskID: squadLog.id,
                    taskLabel: squadLog.label,
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
        if !isNextCyclePass, !deferredFirstWaveAssignmentIDs.isEmpty {
            environment.registerDeferredFirstWaveSquads(
                taskID: pid,
                assignmentIDs: deferredFirstWaveAssignmentIDs
            )
        }
        return TaskMissionLaunchPass(events: events, immediateCommands: immediateCommands, queuedBatches: queuedBatches)
    }

    private func completeRun(
        context: MissionRunExecutionContext,
        templateKey: String,
        templateParams: [String: String] = [:],
        kind: MissionRunCompletionKind,
        operatorWindDown: MissionRunOperatorWindDown
    ) {
        guard let environment else { return }
        _ = context
        environment.enterRunEndMode(
            kind: kind,
            operatorWindDown: operatorWindDown,
            oneOffAutopilotFinished: kind == .oneOffAutopilotFinished
        )
        environment.systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            templateKey: templateKey,
            templateParams: templateParams
        )
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
    static let stagingSimPoseFromSetup = "missioncontrol.mre.staging.sim_pose_from_setup"
    static let stagingLiveReadonly = "missioncontrol.mre.staging.live_readonly"
    static let missionNotStartedNeedsPath = "missioncontrol.mre.mission.not_started_needs_path"
    static let missionNotStartedNoPrimaries = "missioncontrol.mre.mission.not_started_no_primaries"
    static let missionPlanItemsEncodeFailed = "missioncontrol.mre.mission.plan_items_encode_failed"
    static let missionGeofencePolygonsEncodeFailed = "missioncontrol.mre.mission.geofence_polygons_encode_failed"
    static let missionGeofencePx4InclusionFencesOmitted = "missioncontrol.mre.mission.geofence_px4_inclusion_fences_omitted"
    static let missionExecuting = "missioncontrol.mre.mission.executing"
    static let missionSquadFirstWaveReleased = "missioncontrol.mre.mission.squad_first_wave_released"
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
    static let missionTaskAbortEndAttemptNoted = "missioncontrol.mre.mission.task_abort_end_attempt_noted"
    static let missionTaskCompleteSkippedNoCommands = "missioncontrol.mre.mission.task_complete_skipped_no_commands"
    static let missionTaskRecoveryEndAttemptNoted = "missioncontrol.mre.mission.task_recovery_end_attempt_noted"
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
    static let betweenCyclesPrimaryFailedDispatchingFallback = "missioncontrol.mre.between_cycles.primary_failed_fallback"
    static let planRevisionAppliedImmediate = "missioncontrol.mre.plan.revision_applied_immediate"
    static let planRevisionQueuedSafePoint = "missioncontrol.mre.plan.revision_queued_safe_point"
    static let planRevisionQueuedNextCycle = "missioncontrol.mre.plan.revision_queued_next_cycle"
    static let runCompleteWindDownImmediate = "missioncontrol.mre.run.complete_wind_down_immediate"
    static let runCompleteWindDownAfterCycle = "missioncontrol.mre.run.complete_wind_down_after_cycle"
}


