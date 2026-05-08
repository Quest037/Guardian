import Foundation

/// Ensures `awaitArmCommandOutcome` resumes its continuation **at most once** (defensive against MAVSDK / Rx edge cases).
private final class PaladinArmOutcomeContinuationGate: @unchecked Sendable {
    private var hasResumed = false
    private let lock = NSLock()

    func resume(
        _ continuation: CheckedContinuation<PaladinFleetCommandAsyncOutcome, Never>,
        returning outcome: PaladinFleetCommandAsyncOutcome
    ) {
        lock.lock()
        let shouldFire = !hasResumed
        if shouldFire { hasResumed = true }
        lock.unlock()
        if shouldFire {
            continuation.resume(returning: outcome)
        }
    }
}

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

    private func cancelScheduledMissionCycle(for runID: UUID, pathID: UUID) {
        runEnvironment(for: runID)?.systems.scheduling.cancelScheduledMissionCycle(forPathID: pathID)
    }

    private func clearMissionCycleIntermission(for runID: UUID, pathID: UUID?) {
        runEnvironment(for: runID)?.systems.scheduling.clearMissionCycleIntermission(forPathID: pathID)
    }

    private func clearMissionPathStartDeferral(for runID: UUID, pathID: UUID?) {
        runEnvironment(for: runID)?.systems.scheduling.clearMissionPathStartDeferral(forPathID: pathID)
    }

    private func cancelScheduledPathMissionStarts(for runID: UUID) {
        runEnvironment(for: runID)?.systems.scheduling.cancelScheduledPathMissionStarts()
    }

    private func cancelScheduledPathMissionStarts(for runID: UUID, pathID: UUID) {
        runEnvironment(for: runID)?.systems.scheduling.cancelScheduledPathMissionStarts(forPathID: pathID)
    }

    private func assignmentForPaladinPath(run: MissionRunEnvironment, mission: Mission?, pathID: UUID) -> MissionRunAssignment? {
        if let a = run.assignments.first(where: { $0.pathId == pathID }) { return a }
        let enabled = mission?.routeMacro.paths.filter(\.enabled) ?? []
        if enabled.count == 1, enabled.first?.id == pathID {
            return run.assignments.first(where: { $0.pathId == nil }) ?? run.assignments.first
        }
        return nil
    }

    private func cancelDeferredOneOffExecution(for runID: UUID) {
        runEnvironment(for: runID)?.systems.scheduling.registerDeferredOneOffTask(nil)
        runEnvironment(for: runID)?.systems.scheduling.setDeferredOneOffExecution(nil)
    }

    func createRun(from mission: Mission) -> MissionRunEnvironment {
        var assignments: [MissionRunAssignment] = []
        for path in mission.routeMacro.paths {
            for deviceId in path.rosterDeviceIds {
                guard let device = mission.rosterDevices.first(where: { $0.id == deviceId }) else { continue }
                assignments.append(
                    MissionRunAssignment(
                        pathId: path.id,
                        rosterDeviceId: device.id,
                        slotName: device.name
                    )
                )
            }
        }
        if assignments.isEmpty {
            assignments = mission.rosterDevices.map {
                MissionRunAssignment(
                    pathId: nil,
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
        notifyRunCreated(run)
        return run
    }

    func updateRun(_ run: MissionRunEnvironment) {
        guard let idx = runs.firstIndex(where: { $0.id == run.id }) else { return }
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
        cancelScheduledPathMissionStarts(for: id)
        let run = runs[idx]
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
    }

    func deleteRun(id: UUID) {
        if let run = runEnvironment(for: id) {
            notifyRunWillDelete(run)
        }
        cancelScheduledMissionCycle(for: id)
        cancelScheduledPathMissionStarts(for: id)
        cancelDeferredOneOffExecution(for: id)
        runEnvironment(for: id)?.systems.executor.clearCommandQueue()
        runEnvironment(for: id)?.captureExecutionContext(nil)
        runEnvironment(for: id)?.setMissionCycleCount(0)
        runs.removeAll { $0.id == id }
    }

    /// Move a completed run back to setup for another configured launch.
    func resetRunToSetup(id: UUID) {
        guard let idx = runs.firstIndex(where: { $0.id == id }) else { return }
        cancelScheduledMissionCycle(for: id)
        cancelScheduledPathMissionStarts(for: id)
        cancelDeferredOneOffExecution(for: id)
        runEnvironment(for: id)?.setMissionCycleCount(0)
        runEnvironment(for: id)?.systems.logging.clearState()
        runs[idx].status = .setup
        runs[idx].pendingGracefulCycleStop = false
        runs[idx].reportCyclesCompleted = nil
        runs[idx].completionKind = nil
        runs[idx].systems.executor.clearCommandQueue()
        runs[idx].captureExecutionContext(nil)
        // Intentionally preserve mission prep state (schedule, assignments, and chosen vehicles).
    }

    /// Routes cycle-finished callbacks to active run environments.
    func ingestAutopilotMissionCycleFinished(
        vehicleID: String,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission]
    ) {
        for run in runs where run.status == .running {
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
        guard let planningResult = run.systems.planner.compileInitialPlan(
            mission: mission,
            fleetVehicles: fleetVehicles
        ) else { return }
        let plan = planningResult.plan
        let summary = "Compiled \(plan.roleTracks.count) role track(s), \(plan.pathTopology.rawValue), \(plan.teamTopology.rawValue)."
        run.systems.logging.clearState()
        run.systems.logging.setPathContextFromRoleTracks(plan.roleTracks)
        run.systems.lifecycle.markCompiled()
        run.systems.logging.appendLogEvent(
            level: .info,
            speaker: .paladin,
            message: summary,
            templateKey: PaladinLogTemplateKey.compileSummary,
            templateParams: [
                "tracks": String(plan.roleTracks.count),
                "pathTopology": plan.pathTopology.rawValue,
                "teamTopology": plan.teamTopology.rawValue,
            ]
        )
        UserNotificationService.shared.notifyMissionControlPlanCompiled(
            runID: run.id,
            missionName: run.missionName
        )
    }

    func ingestFleetMirrorLine(
        vehicleID: String,
        line: String,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        for run in runs where run.status == .running || run.status == .paused {
            run.systems.logging.appendFleetMirrorLine(vehicleID: vehicleID, line: line, fleetLink: fleetLink, sitl: sitl)
        }
    }

    /// A vehicle already committed to another **running or paused** mission cannot be picked again.
    func isFleetVehicleLockedByOtherLiveMission(tokenKey: String, excludingRunId: UUID) -> Bool {
        for r in runs where r.id != excludingRunId && (r.status == .running || r.status == .paused) {
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

    /// Before sending arm: require the same lifecycle gate as the fleet UI (green = `stage == .live`).
    private func preflightProbeReadinessBlocker(vehicleID: String, fleetLink: FleetLinkService) -> SingleVehiclePreflightProbeResult? {
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
        return nil
    }

    /// If MAVLink / MAVSDK never completes the arm Completable, the UI must not hang forever (e.g. PX4 still booting).
    private static let armCommandWaitTimeoutNanoseconds: UInt64 = 90 * 1_000_000_000
    private static let armCommandTimeoutFailureDetail =
        "Timed out waiting for arm (vehicle may still be booting, link interrupted, or autopilot did not respond)."

    private func awaitArmCommandOutcome(
        fleetLink: FleetLinkService,
        vehicleID: String,
        source: String
    ) async -> PaladinFleetCommandAsyncOutcome {
        await withCheckedContinuation { continuation in
            let gate = PaladinArmOutcomeContinuationGate()
            let timeout = Task {
                do {
                    try await Task.sleep(nanoseconds: Self.armCommandWaitTimeoutNanoseconds)
                } catch {
                    return
                }
                await MainActor.run {
                    gate.resume(continuation, returning: .failed(Self.armCommandTimeoutFailureDetail))
                }
            }
            _ = fleetLink.executeVehicleCommand(
                vehicleID: vehicleID,
                command: .arm,
                source: source,
                category: .paladin,
                onPaladinCommandOutcome: { outcome in
                    timeout.cancel()
                    gate.resume(continuation, returning: outcome)
                }
            )
        }
    }

    /// True when this bridge vehicle id is bound to any **running or paused** Mission Control run roster slot.
    func isVehicleStreamUsedInLiveMission(vehicleID: String, fleetLink: FleetLinkService, sitl: SitlService) -> Bool {
        for r in runs where r.status == .running || r.status == .paused {
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

    private func preflightArmFailureDetail(hub: FleetHubVehicleTelemetry?, reason: String) -> String {
        if hub?.healthArmable == false {
            return "Arm failed: \(reason) (telemetry: not armable — resolve pre-arm / health on the vehicle.)"
        }
        if hub?.healthArmable == nil {
            return "Arm failed: \(reason) (armable health not yet reported — check link and autopilot messages.)"
        }
        return "Arm failed: \(reason)"
    }

    /// Single-vehicle preflight check (same semantics as one slot in `runSingleVehiclePreflightProbeForStartRun`).
    func runSingleVehiclePreflightProbe(
        vehicleID: String,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        leaveArmed: Bool = false
    ) async -> SingleVehiclePreflightProbeResult {
        if let blocked = preflightProbeReadinessBlocker(vehicleID: vehicleID, fleetLink: fleetLink) {
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
        let outcome = await awaitArmCommandOutcome(
            fleetLink: fleetLink,
            vehicleID: vehicleID,
            source: "vehicles.preflightProbe"
        )
        let isSim = isVehicleSimulationStream(vehicleID: vehicleID, fleetLink: fleetLink, sitl: sitl)

        switch outcome {
        case .succeeded:
            let result = SingleVehiclePreflightProbeResult(
                passed: true,
                armedDuringProbe: true,
                detail: "Arm succeeded.",
                remediationAdvice: nil
            )
            if !leaveArmed {
                _ = fleetLink.executeVehicleCommand(
                    vehicleID: vehicleID,
                    command: .disarm,
                    source: "missionControl.preflightAutoDisarm",
                    category: .paladin,
                    onPaladinCommandOutcome: nil
                )
            }
            return result
        case .failed(let reason):
            let advice = PreflightFailureAdvisor.advice(
                for: PreflightFailureRemediationContext(
                    autopilotStack: hub?.autopilotStack ?? .unknown,
                    rawFailureDetail: reason,
                    hubSnapshot: hub,
                    isSimulation: isSim
                )
            )
            return SingleVehiclePreflightProbeResult(
                passed: false,
                armedDuringProbe: false,
                detail: preflightArmFailureDetail(hub: hub, reason: reason),
                remediationAdvice: advice
            )
        }
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

            if let blocked = preflightProbeReadinessBlocker(vehicleID: vehicleID, fleetLink: fleetLink) {
                row.phase = .failed
                row.detail = blocked.detail
                rowUpdated(row)
                allPassed = false
                continue
            }

            let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
            if hub?.isArmed == true {
                row.phase = .passed
                row.detail = "Already armed — no arm command sent."
                rowUpdated(row)
                continue
            }

            let outcome = await awaitArmCommandOutcome(
                fleetLink: fleetLink,
                vehicleID: vehicleID,
                source: "missionControl.preflightProbe"
            )
            switch outcome {
            case .succeeded:
                armedDuringProbe.append(vehicleID)
                row.phase = .passed
                row.detail = "Arm succeeded."
                rowUpdated(row)
            case .failed(let reason):
                row.phase = .failed
                let isSim: Bool = {
                    guard let key = assignment.attachedFleetVehicleToken,
                          let token = FleetMissionVehicleToken(storageKey: key)
                    else { return false }
                    if case .sitl = token { return true }
                    return false
                }()
                let advice = PreflightFailureAdvisor.advice(
                    for: PreflightFailureRemediationContext(
                        autopilotStack: hub?.autopilotStack ?? .unknown,
                        rawFailureDetail: reason,
                        hubSnapshot: hub,
                        isSimulation: isSim
                    )
                )
                row.remediationAdvice = advice
                row.detail = preflightArmFailureDetail(hub: hub, reason: reason)
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

}
