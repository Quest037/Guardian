import Foundation

@MainActor
final class MissionControlStore: ObservableObject {
    @Published private(set) var runs: [MissionRunEnvironment] = []
    private struct ObserverRegistration {
        weak var observer: (any MissionControlRunObserver)?
        let permissions: MissionRunObserverPermissions
    }
    private var runObserverRegistrations: [UUID: ObserverRegistration] = [:]

    private func runEnvironment(for runID: UUID) -> MissionRunEnvironment? {
        runs.first(where: { $0.id == runID })
    }

    private func cancelScheduledMissionCycle(for runID: UUID) {
        runEnvironment(for: runID)?.systems.scheduling.cancelScheduledMissionCycle()
    }

    private func clearMissionTaskStartDeferral(for runID: UUID, taskID: UUID?) {
        runEnvironment(for: runID)?.systems.scheduling.clearMissionTaskStartDeferral(forTaskID: taskID)
    }

    private func cancelScheduledTaskMissionStarts(for runID: UUID) {
        runEnvironment(for: runID)?.systems.scheduling.cancelScheduledTaskMissionStarts()
    }

    private func cancelScheduledTaskMissionStarts(for runID: UUID, taskID: UUID) {
        runEnvironment(for: runID)?.systems.scheduling.cancelScheduledTaskMissionStarts(forTaskID: taskID)
    }

    private func cancelDeferredOneOffExecution(for runID: UUID) {
        runEnvironment(for: runID)?.systems.scheduling.registerDeferredOneOffTask(nil)
        runEnvironment(for: runID)?.systems.scheduling.setDeferredOneOffExecution(nil)
    }

    func createRun(from mission: Mission) -> MissionRunEnvironment {
        var assignments: [MissionRunAssignment] = []
        for path in mission.routeMacro.tasks {
            for deviceId in path.rosterDeviceIds {
                guard let device = mission.rosterDevices.first(where: { $0.id == deviceId }) else { continue }
                assignments.append(
                    MissionRunAssignment(
                        taskId: path.id,
                        rosterDeviceId: device.id,
                        slotName: device.name
                    )
                )
            }
        }
        if assignments.isEmpty {
            assignments = mission.rosterDevices.map {
                MissionRunAssignment(
                    taskId: nil,
                    rosterDeviceId: $0.id,
                    slotName: $0.name
                )
            }
        }
        let run = MissionRunEnvironment(
            missionId: mission.id,
            missionName: mission.name,
            assignments: assignments
        )
        runs.insert(run, at: 0)
        run.refreshDerivedTaskStates()
        notifyRunCreated(run)
        return run
    }

    func updateRun(_ run: MissionRunEnvironment) {
        guard let idx = runs.firstIndex(where: { $0.id == run.id }) else { return }
        run.refreshDerivedTaskStates()
        runs[idx] = run
    }

    func startRun(
        id: UUID,
        mission: Mission?,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission] = { [] }
    ) {
        guard let idx = runs.firstIndex(where: { $0.id == id }) else { return }
        cancelDeferredOneOffExecution(for: id)
        cancelScheduledMissionCycle(for: id)
        cancelScheduledTaskMissionStarts(for: id)
        let run = runs[idx]
        run.updateTemplate(mission)
        let ctx = MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            missionProvider: { [missionsProvider, run] in
                missionsProvider().first { $0.id == run.missionId }
            }
        )
        run.captureExecutionContext(ctx)
        _ = run.systems.executor.startExecution(context: ctx)
        notifyRunStarted(
            run,
            context: MissionRunStartContext(
                mission: mission,
                fleetLink: fleetLink,
                sitl: sitl,
                missionsProvider: missionsProvider
            )
        )
        run.refreshDerivedTaskStates()
    }

    func deleteRun(id: UUID) {
        if let run = runEnvironment(for: id) {
            notifyRunWillDelete(run)
        }
        cancelScheduledMissionCycle(for: id)
        cancelScheduledTaskMissionStarts(for: id)
        cancelDeferredOneOffExecution(for: id)
        runEnvironment(for: id)?.systems.executor.clearCommandQueue()
        runEnvironment(for: id)?.captureExecutionContext(nil)
        runEnvironment(for: id)?.setMissionCycleCount(0)
        runs.removeAll { $0.id == id }
    }

    /// Returns true when any run for this mission is currently active and should block mission deletion.
    func hasLiveRun(forMissionID missionID: UUID) -> Bool {
        runs.contains {
            $0.missionId == missionID
                && ($0.status == .running || $0.status == .paused || $0.status == .recovery)
        }
    }

    /// Deletes non-live runs bound to a mission template. Live runs are preserved.
    func deleteNonLiveRuns(forMissionID missionID: UUID) {
        let removable = runs
            .filter {
                $0.missionId == missionID
                    && !($0.status == .running || $0.status == .paused || $0.status == .recovery)
            }
            .map(\.id)
        for runID in removable {
            deleteRun(id: runID)
        }
    }

    /// Move a completed run back to setup for another configured launch.
    func resetRunToSetup(id: UUID) {
        guard let idx = runs.firstIndex(where: { $0.id == id }) else { return }
        cancelScheduledMissionCycle(for: id)
        cancelScheduledTaskMissionStarts(for: id)
        cancelDeferredOneOffExecution(for: id)
        runEnvironment(for: id)?.setMissionCycleCount(0)
        runEnvironment(for: id)?.systems.logging.clearState()
        runs[idx].status = .setup
        runs[idx].gracefulStopKind = .none
        runs[idx].reportCyclesCompleted = nil
        runs[idx].completionKind = nil
        runs[idx].systems.executor.clearCommandQueue()
        runs[idx].captureExecutionContext(nil)
        runs[idx].refreshDerivedTaskStates()
        // Intentionally preserve mission prep state (schedule, assignments, and chosen vehicles).
    }

    /// Routes cycle-finished callbacks to active run environments.
    func ingestAutopilotMissionCycleFinished(
        vehicleID: String,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission]
    ) {
        for run in runs where run.status == .running || run.status == .recovery {
            let ctx = MissionRunExecutionContext(
                mission: nil,
                fleetLink: fleetLink,
                sitl: sitl,
                missionProvider: { [missionsProvider, run] in
                    missionsProvider().first { $0.id == run.missionId }
                }
            )
            run.captureExecutionContext(ctx)
            _ = run.systems.executor.handleEvent(.missionCycleFinished(vehicleID: vehicleID), context: ctx)
        }
    }

    func compileMissionControlPlan(
        run: MissionRunEnvironment,
        mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle]
    ) {
        run.updateTemplate(mission)
        guard let planningResult = run.systems.planner.compileInitialPlan(
            mission: mission,
            fleetVehicles: fleetVehicles
        ) else { return }
        let plan = planningResult.plan
        run.systems.logging.clearState()
        run.systems.logging.setTaskContextFromRoleTracks(plan.roleTracks)
        run.systems.lifecycle.markCompiled()
        run.systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.compileSummary,
            templateParams: [
                "tracks": String(plan.roleTracks.count),
                "taskTopology": plan.taskTopology.rawValue,
                "teamTopology": plan.teamTopology.rawValue,
            ]
        )
        UserNotificationService.shared.notifyMissionControlPlanCompiled(
            runID: run.id,
            missionName: run.missionName
        )
        run.refreshDerivedTaskStates()
    }

    func ingestFleetMirrorLine(
        vehicleID: String,
        line: String,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        for run in runs where run.status == .running || run.status == .paused || run.status == .recovery {
            run.systems.logging.appendFleetMirrorLine(vehicleID: vehicleID, line: line, fleetLink: fleetLink, sitl: sitl)
        }
    }

    /// A vehicle already committed to another **running or paused** mission cannot be picked again.
    func isFleetVehicleLockedByOtherLiveMission(tokenKey: String, excludingRunId: UUID) -> Bool {
        for r in runs where r.id != excludingRunId && (r.status == .running || r.status == .paused || r.status == .recovery) {
            if r.assignments.contains(where: { $0.attachedFleetVehicleToken == tokenKey }) {
                return true
            }
        }
        return false
    }

    /// The same fleet vehicle cannot be on two roster slots within one mission run.
    func isFleetVehicleUsedOnOtherSlotInRun(tokenKey: String, run: MissionRunEnvironment, assignmentId: UUID) -> Bool {
        run.assignments.contains {
            $0.id != assignmentId && $0.attachedFleetVehicleToken == tokenKey
        }
    }


    // MARK: - Start run preflight (arm probe)

    /// No `FleetVehicleModel` for this stream key (same notion as the Vehicles grid).
    static let preflightProbeNoVehicleDetail = "No vehicle."

    /// `FleetVehicleModel` exists but lifecycle is not **`.live`** (only `.live` yields green on the fleet card).
    static let preflightProbeNotConnectedDetail = "Not connected."

    /// Default-deny gate: vehicle is currently bound to a `.running` / `.paused` / `.recovery` Mission Control run.
    /// Operators can opt in to mid-mission preflight via the `allowDuringLiveMission` parameter on
    /// ``runSingleVehiclePreflightProbe`` once the override surfaces (reserve swap-in, recovery flow,
    /// plugin-authored auto-preflight) are wired — see `TODO.md`.
    static let preflightProbeBlockedByLiveMissionDetail =
        "Preflight is locked while this vehicle is assigned to an active Mission Control run."

    /// Before sending arm:
    /// 1. require the same lifecycle gate as the fleet UI (green = `stage == .live`),
    /// 2. unless explicitly overridden, refuse to probe a vehicle that is bound to a live mission run
    ///    (`.running` / `.paused` / `.recovery`).
    private func preflightProbeReadinessBlocker(
        vehicleID: String,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        allowDuringLiveMission: Bool
    ) -> SingleVehiclePreflightProbeResult? {
        guard let model = fleetLink.vehicleModel(forVehicleID: vehicleID) else {
            return SingleVehiclePreflightProbeResult(
                passed: false,
                armedDuringProbe: false,
                detail: Self.preflightProbeNoVehicleDetail,
                remediationAdvice: nil
            )
        }
        guard model.collections.lifecycleStatus.stage == .live else {
            return SingleVehiclePreflightProbeResult(
                passed: false,
                armedDuringProbe: false,
                detail: Self.preflightProbeNotConnectedDetail,
                remediationAdvice: nil
            )
        }
        if !allowDuringLiveMission,
           isVehicleStreamUsedInLiveMission(vehicleID: vehicleID, fleetLink: fleetLink, sitl: sitl) {
            return SingleVehiclePreflightProbeResult(
                passed: false,
                armedDuringProbe: false,
                detail: Self.preflightProbeBlockedByLiveMissionDetail,
                remediationAdvice: nil
            )
        }
        return nil
    }

    /// True when this bridge vehicle id is bound to any **running or paused** Mission Control run roster slot.
    func isVehicleStreamUsedInLiveMission(vehicleID: String, fleetLink: FleetLinkService, sitl: SitlService) -> Bool {
        for r in runs where r.status == .running || r.status == .paused || r.status == .recovery {
            for a in r.assignments {
                guard let vid = resolvedFleetStreamVehicleID(assignment: a, fleetLink: fleetLink, sitl: sitl) else { continue }
                if vid == vehicleID { return true }
            }
        }
        return false
    }

    private func isVehicleSimulationStream(vehicleID: String, fleetLink: FleetLinkService, sitl: SitlService) -> Bool {
        for inst in sitl.instances {
            let sid = inst.stackInstanceIndex + 1
            let vid = fleetLink.vehicleID(forSystemID: sid) ?? "sysid:\(sid)"
            if vid == vehicleID { return true }
        }
        return false
    }

    /// Single-vehicle preflight check (same semantics as one slot in `runSingleVehiclePreflightProbeForStartRun`).
    ///
    /// - Parameter allowDuringLiveMission: Default `false`. When `false`, the call is **blocked** if
    ///   the vehicle is bound to any `.running` / `.paused` / `.recovery` Mission Control run, returning
    ///   ``preflightProbeBlockedByLiveMissionDetail``. Pass `true` only from explicit operator override
    ///   surfaces (reserve drone swap-in, recovery / re-link flows) or from plugin-authored auto-preflight
    ///   that owns its own safety reasoning. The default keeps every UI caller (Vehicle Inspector,
    ///   LiveDrive pre-session probe, etc.) safe by construction.
    /// - Parameter preflightAuditSource: Passed through to ``FleetRecipeRunner/run`` as `source`
    ///   for catalogue dispatch audit (e.g. `vehicles.preflightProbe` vs `missionControl.preflightProbe`).
    func runSingleVehiclePreflightProbe(
        vehicleID: String,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        leaveArmed: Bool = false,
        allowDuringLiveMission: Bool = false,
        preflightAuditSource: String = "vehicles.preflightProbe"
    ) async -> SingleVehiclePreflightProbeResult {
        if let blocked = preflightProbeReadinessBlocker(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl,
            allowDuringLiveMission: allowDuringLiveMission
        ) {
            return blocked
        }

        let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
        if hub?.isArmed == true {
            return SingleVehiclePreflightProbeResult(
                passed: true,
                armedDuringProbe: false,
                detail: "Already armed — no arm command sent.",
                remediationAdvice: nil
            )
        }

        await Task.yield()
        let recipeName: FleetRecipeName = leaveArmed
            ? FleetRecipeName.literal("recipe.fleet.diagnose.armprobe.hold")
            : FleetRecipeName.literal("recipe.fleet.diagnose.armprobe")
        let recipeOutcome = await FleetRecipeRunner.shared.run(
            recipe: recipeName,
            vehicleID: vehicleID,
            source: preflightAuditSource,
            fleetLink: fleetLink,
            allowDuringLiveMission: allowDuringLiveMission
        )
        let isSim = isVehicleSimulationStream(vehicleID: vehicleID, fleetLink: fleetLink, sitl: sitl)
        return MissionControlPreflightRecipeOutcomeMapper.singleVehiclePreflightProbeResult(
            recipeOutcome: recipeOutcome,
            hub: hub,
            isSimulation: isSim
        )
    }

    /// Attempts to **arm** every roster slot that has a fleet token + resolvable vehicle ID. Rows are reported via `rowUpdated` as each step completes.
    /// - Returns: whether every slot passed, and vehicle IDs that **became armed** during this probe (for optional disarm on abandon).
    func runSingleVehiclePreflightProbeForStartRun(
        run: MissionRunEnvironment,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        rowUpdated: @escaping @MainActor (MissionRunPreflightSlotRow) -> Void
    ) async -> (allPassed: Bool, vehicleIDsArmedDuringProbe: [String]) {
        var armedDuringProbe: [String] = []
        var allPassed = true

        for assignment in run.assignments {
            var row = MissionRunPreflightSlotRow(
                assignmentID: assignment.id,
                slotName: assignment.slotName,
                phase: .testing,
                detail: "Requesting arm…"
            )
            rowUpdated(row)

            guard let tokenKey = assignment.attachedFleetVehicleToken,
                  FleetMissionVehicleToken(storageKey: tokenKey) != nil
            else {
                row.phase = .failed
                row.detail =
                    "No fleet vehicle on this roster slot — pick a vehicle from the fleet list so Paladin can verify arming."
                rowUpdated(row)
                allPassed = false
                continue
            }

            guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl) else {
                row.phase = .failed
                row.detail =
                    "No live MAVLink session for this slot (SIM not running, vehicle offline, or live bridge not connected)."
                rowUpdated(row)
                allPassed = false
                continue
            }

            let probe = await runSingleVehiclePreflightProbe(
                vehicleID: vehicleID,
                fleetLink: fleetLink,
                sitl: sitl,
                leaveArmed: true,
                allowDuringLiveMission: false,
                preflightAuditSource: "missionControl.preflightProbe"
            )
            if probe.passed {
                if probe.armedDuringProbe {
                    armedDuringProbe.append(vehicleID)
                }
                row.phase = .passed
                row.detail = probe.detail
                rowUpdated(row)
            } else {
                row.phase = .failed
                row.detail = probe.detail
                row.remediationAdvice = probe.remediationAdvice
                rowUpdated(row)
                allPassed = false
            }
        }

        return (allPassed, armedDuringProbe)
    }

    func registerRunObserver(
        _ observer: any MissionControlRunObserver,
        permissions: MissionRunObserverPermissions
    ) -> UUID {
        pruneObserverRegistrations()
        let token = UUID()
        runObserverRegistrations[token] = ObserverRegistration(observer: observer, permissions: permissions)
        return token
    }

    func unregisterRunObserver(token: UUID) {
        runObserverRegistrations.removeValue(forKey: token)
    }

    private func pruneObserverRegistrations() {
        runObserverRegistrations = runObserverRegistrations.filter { $0.value.observer != nil }
    }

    private func observerPermissions(for token: UUID) -> MissionRunObserverPermissions? {
        pruneObserverRegistrations()
        guard let registration = runObserverRegistrations[token], registration.observer != nil else { return nil }
        return registration.permissions
    }

    /// Observers with ``MissionRunObserverPermissions/manageExecutionQueue`` may enqueue tagged command batches.
    @discardableResult
    func enqueueMissionRunCommandBatch(
        runID: UUID,
        batch: MissionRunQueuedCommandBatch,
        replacingTags: Set<MissionRunCommandQueueTag>? = nil,
        observerToken: UUID
    ) -> Bool {
        guard let permissions = observerPermissions(for: observerToken),
              permissions.contains(.manageExecutionQueue),
              let run = runEnvironment(for: runID),
              let ctx = run.lastExecutionContext
        else { return false }
        run.systems.executor.enqueueCommandBatch(batch, context: ctx, replacingTags: replacingTags)
        return true
    }

    /// Cancels pending executor batches whose tags intersect `tags`, optionally filtered by dispatch.
    @discardableResult
    func cancelMissionRunCommandBatches(
        runID: UUID,
        tags: Set<MissionRunCommandQueueTag>,
        whereDispatch: ((MissionRunQueuedCommandDispatch) -> Bool)? = nil,
        observerToken: UUID
    ) -> Int {
        guard let permissions = observerPermissions(for: observerToken),
              permissions.contains(.manageExecutionQueue),
              let run = runEnvironment(for: runID)
        else { return 0 }
        return run.systems.executor.cancelPendingCommandBatches(tags: tags, whereDispatch: whereDispatch)
    }

    private func notifyRunCreated(_ run: MissionRunEnvironment) {
        pruneObserverRegistrations()
        for registration in runObserverRegistrations.values {
            registration.observer?.missionControlStore(
                self,
                didCreate: run,
                permissions: registration.permissions
            )
        }
    }

    private func notifyRunStarted(_ run: MissionRunEnvironment, context: MissionRunStartContext) {
        pruneObserverRegistrations()
        for registration in runObserverRegistrations.values {
            registration.observer?.missionControlStore(
                self,
                didStart: run,
                context: context,
                permissions: registration.permissions
            )
        }
    }

    private func notifyRunWillDelete(_ run: MissionRunEnvironment) {
        pruneObserverRegistrations()
        for registration in runObserverRegistrations.values {
            registration.observer?.missionControlStore(
                self,
                willDelete: run,
                permissions: registration.permissions
            )
        }
    }

    /// Swap-in-reserve operator prompts are not implemented in this build; Paladin may call this hook when ready.
    @discardableResult
    func raiseOperatorPromptSwapInReserve(
        runID: UUID,
        primaryAssignmentID: UUID,
        reserveAssignmentID: UUID,
        issuerKey: String,
        observerToken: UUID
    ) -> Bool {
        _ = primaryAssignmentID
        _ = reserveAssignmentID
        _ = issuerKey
        guard observerPermissions(for: observerToken)?.contains(.act) == true,
              runEnvironment(for: runID) != nil
        else { return false }
        return false
    }

}
