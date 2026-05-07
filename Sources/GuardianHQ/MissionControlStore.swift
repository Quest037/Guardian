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
    @Published private(set) var runs: [MissionRun] = []
    @Published private(set) var paladinSessionsByRunID: [UUID: PaladinSession] = [:]

    private struct VehicleVoiceSnapshot: Equatable {
        var flightMode: String
        var isArmed: Bool
        var relativeAltM: Double?
        var latitudeDeg: Double?
        var longitudeDeg: Double?
        var inAir: Bool?
        var lastTrackLogAt: Date?
        /// Last coordinates written to a Paladin “Track” line (movement is measured from here).
        var lastTrackLoggedLat: Double?
        var lastTrackLoggedLon: Double?
        var lastAltTrendLogAt: Date?
        var lastRouteProgressLogAt: Date?
        var announcedApproachWP1: Bool
    }

    /// Keyed by `"\(runID)|\(assignment.id)"` for debounced “vehicle voice” lines in the Paladin log.
    private var vehicleVoiceSnapshots: [String: VehicleVoiceSnapshot] = [:]

    /// Delayed mission restarts for loop / continuous schedules (cancel on stop, delete, or reset). Per-path so multi-path runs can stagger cycles.
    private var scheduledMissionCycleTasks: [UUID: [UUID: Task<Void, Never>]] = [:]

    /// Deferred **first** MAVLink mission start per path after execution begins (see ``PathStartDelay``).
    private var scheduledPathMissionStartTasks: [UUID: [UUID: Task<Void, Never>]] = [:]

    private func cancelScheduledMissionCycle(for runID: UUID) {
        if let inner = scheduledMissionCycleTasks[runID] {
            for (_, t) in inner { t.cancel() }
        }
        scheduledMissionCycleTasks[runID] = nil
        clearMissionCycleIntermission(for: runID, pathID: nil)
    }

    private func cancelScheduledMissionCycle(for runID: UUID, pathID: UUID) {
        scheduledMissionCycleTasks[runID]?[pathID]?.cancel()
        if var inner = scheduledMissionCycleTasks[runID] {
            inner.removeValue(forKey: pathID)
            if inner.isEmpty {
                scheduledMissionCycleTasks[runID] = nil
            } else {
                scheduledMissionCycleTasks[runID] = inner
            }
        }
        clearMissionCycleIntermission(for: runID, pathID: pathID)
    }

    private func clearMissionCycleIntermission(for runID: UUID, pathID: UUID?) {
        var copy = missionCycleIntermissionByRunID
        if let pathID {
            guard var paths = copy[runID] else { return }
            paths.removeValue(forKey: pathID)
            if paths.isEmpty {
                copy.removeValue(forKey: runID)
            } else {
                copy[runID] = paths
            }
        } else {
            copy.removeValue(forKey: runID)
        }
        missionCycleIntermissionByRunID = copy
    }

    private func clearMissionPathStartDeferral(for runID: UUID, pathID: UUID?) {
        var copy = missionPathStartDeferralByRunID
        if let pathID {
            guard var paths = copy[runID] else { return }
            paths.removeValue(forKey: pathID)
            if paths.isEmpty {
                copy.removeValue(forKey: runID)
            } else {
                copy[runID] = paths
            }
        } else {
            copy.removeValue(forKey: runID)
        }
        missionPathStartDeferralByRunID = copy
    }

    private func cancelScheduledPathMissionStarts(for runID: UUID) {
        if let inner = scheduledPathMissionStartTasks[runID] {
            for (_, t) in inner { t.cancel() }
        }
        scheduledPathMissionStartTasks[runID] = nil
        clearMissionPathStartDeferral(for: runID, pathID: nil)
    }

    private func cancelScheduledPathMissionStarts(for runID: UUID, pathID: UUID) {
        scheduledPathMissionStartTasks[runID]?[pathID]?.cancel()
        if var inner = scheduledPathMissionStartTasks[runID] {
            inner.removeValue(forKey: pathID)
            if inner.isEmpty {
                scheduledPathMissionStartTasks[runID] = nil
            } else {
                scheduledPathMissionStartTasks[runID] = inner
            }
        }
        clearMissionPathStartDeferral(for: runID, pathID: pathID)
    }

    private func assignmentForPaladinPath(run: MissionRun, mission: Mission?, pathID: UUID) -> MissionRunAssignment? {
        if let a = run.assignments.first(where: { $0.pathId == pathID }) { return a }
        let enabled = mission?.routeMacro.paths.filter(\.enabled) ?? []
        if enabled.count == 1, enabled.first?.id == pathID {
            return run.assignments.first(where: { $0.pathId == nil }) ?? run.assignments.first
        }
        return nil
    }

    /// Wait until **`restartAt`** then run the next MAVLink cycle for **`pathID`** (unless intermission was cleared or rescheduled).
    private func armMissionCycleRestartTask(
        runID: UUID,
        pathID: UUID,
        restartAt: Date,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission]
    ) {
        scheduledMissionCycleTasks[runID]?[pathID]?.cancel()
        let capturedRestart = restartAt
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = capturedRestart.timeIntervalSince(Date())
                if remaining <= 0.05 { break }
                let chunk = min(remaining, 3600)
                let rawNs = chunk * 1_000_000_000
                guard rawNs.isFinite, rawNs > 0 else { break }
                let ns = UInt64(min(Double(UInt64.max), max(1_000_000, rawNs)))
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            guard let stored = self.missionCycleIntermissionByRunID[runID]?[pathID],
                  abs(stored.restartAt.timeIntervalSince(capturedRestart)) < 0.5
            else { return }

            self.performScheduledMissionCycleRestart(
                runID: runID,
                pathID: pathID,
                fleetLink: fleetLink,
                sitl: sitl,
                missionsProvider: missionsProvider
            )
        }
        if scheduledMissionCycleTasks[runID] == nil {
            scheduledMissionCycleTasks[runID] = [:]
        }
        scheduledMissionCycleTasks[runID]![pathID] = task
    }

    /// After **`startAt`**, upload/start MAVLink mission for **`pathID`** (unless deferral was cleared or rescheduled).
    private func armPathMissionStartTask(
        runID: UUID,
        pathID: UUID,
        startAt: Date,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission]
    ) {
        scheduledPathMissionStartTasks[runID]?[pathID]?.cancel()
        let capturedStart = startAt
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = capturedStart.timeIntervalSince(Date())
                if remaining <= 0.05 { break }
                let chunk = min(remaining, 3600)
                let rawNs = chunk * 1_000_000_000
                guard rawNs.isFinite, rawNs > 0 else { break }
                let ns = UInt64(min(Double(UInt64.max), max(1_000_000, rawNs)))
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            guard let stored = self.missionPathStartDeferralByRunID[runID]?[pathID],
                  abs(stored.startAt.timeIntervalSince(capturedStart)) < 0.5
            else { return }

            self.performDeferredPathMissionStart(
                runID: runID,
                pathID: pathID,
                fleetLink: fleetLink,
                sitl: sitl,
                missionsProvider: missionsProvider
            )
        }
        if scheduledPathMissionStartTasks[runID] == nil {
            scheduledPathMissionStartTasks[runID] = [:]
        }
        scheduledPathMissionStartTasks[runID]![pathID] = task
    }

    private func cancelDeferredOneOffExecution(for runID: UUID) {
        deferredOneOffStartTasks[runID]?.cancel()
        deferredOneOffStartTasks[runID] = nil
        guard oneOffDeferredExecutionByRunID[runID] != nil else { return }
        var copy = oneOffDeferredExecutionByRunID
        copy.removeValue(forKey: runID)
        oneOffDeferredExecutionByRunID = copy
    }

    /// After preflight: Paladin plan is compiled; if one-off `executeAt` is in the future, wait then call `startRun`.
    func scheduleDeferredOneOffPaladinExecution(
        runID: UUID,
        executeAt: Date,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionProvider: @escaping @MainActor () -> Mission?
    ) {
        cancelDeferredOneOffExecution(for: runID)
        let countdownStartedAt = Date()
        let snapshot = MissionOneOffDeferredExecution(executeAt: executeAt, countdownStartedAt: countdownStartedAt)
        var dictCopy = oneOffDeferredExecutionByRunID
        dictCopy[runID] = snapshot
        oneOffDeferredExecutionByRunID = dictCopy

        let deferredUntilPhrase = executeAt.guardianScheduleDateAtTimePhrase
        if var session = paladinSessionsByRunID[runID] {
            session.phase = .staging
            session.events.append(
                PaladinEvent(
                    level: .info,
                    speaker: .paladin,
                    message: "Staging: plan ready — waiting for scheduled execution.",
                    templateKey: PaladinLogTemplateKey.sessionStaging
                )
            )
            session.events.append(
                PaladinEvent(
                    level: .info,
                    speaker: .paladin,
                    message: "Paladin execution deferred until \(deferredUntilPhrase). The mission will begin automatically at that time.",
                    templateKey: PaladinLogTemplateKey.scheduleOneOffDeferred,
                    templateParams: ["executeAt": deferredUntilPhrase]
                )
            )
            paladinSessionsByRunID[runID] = session
        }

        beginDeferredOneOffWaitTask(
            runID: runID,
            executeAt: executeAt,
            fleetLink: fleetLink,
            sitl: sitl,
            missionProvider: missionProvider
        )
    }

    /// Add **additionalMinutes** (1…30) to the current deferred one-off `executeAt`, update the run’s `oneOffStartAt`, and reschedule the wait task.
    func postponeDeferredOneOffExecutionByMinutes(
        runID: UUID,
        additionalMinutes: Int,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionProvider: @escaping @MainActor () -> Mission?
    ) {
        let mins = min(30, max(1, additionalMinutes))
        guard let previous = oneOffDeferredExecutionByRunID[runID] else { return }

        deferredOneOffStartTasks[runID]?.cancel()
        deferredOneOffStartTasks[runID] = nil

        let newExecuteAt = previous.executeAt.addingTimeInterval(Double(mins) * 60)
        let snapshot = MissionOneOffDeferredExecution(executeAt: newExecuteAt, countdownStartedAt: Date())
        var dictCopy = oneOffDeferredExecutionByRunID
        dictCopy[runID] = snapshot
        oneOffDeferredExecutionByRunID = dictCopy

        if let idx = runs.firstIndex(where: { $0.id == runID }) {
            runs[idx].oneOffStartAt = newExecuteAt
        }

        let newPhrase = newExecuteAt.guardianScheduleDateAtTimePhrase
        if var session = paladinSessionsByRunID[runID] {
            session.events.append(
                PaladinEvent(
                    level: .info,
                    speaker: .paladin,
                    message: "Scheduled start postponed by \(mins) minute(s); execution now \(newPhrase).",
                    templateKey: PaladinLogTemplateKey.scheduleOneOffPostponed,
                    templateParams: [
                        "minutes": String(mins),
                        "executeAt": newPhrase,
                    ]
                )
            )
            paladinSessionsByRunID[runID] = session
        }

        beginDeferredOneOffWaitTask(
            runID: runID,
            executeAt: newExecuteAt,
            fleetLink: fleetLink,
            sitl: sitl,
            missionProvider: missionProvider
        )
    }

    /// Cancel the scheduled wait and begin Paladin execution now (operator override while the countdown banner is shown).
    func beginDeferredOneOffPaladinImmediately(
        runID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionProvider: @escaping @MainActor () -> Mission?
    ) {
        guard oneOffDeferredExecutionByRunID[runID] != nil else { return }
        cancelDeferredOneOffExecution(for: runID)
        if var session = paladinSessionsByRunID[runID] {
            session.events.append(
                PaladinEvent(
                    level: .info,
                    speaker: .paladin,
                    message: "Operator started Paladin now; scheduled wait was skipped.",
                    templateKey: PaladinLogTemplateKey.scheduleOneOffStartedImmediately
                )
            )
            paladinSessionsByRunID[runID] = session
        }
        let mission = missionProvider()
        startRun(id: runID, mission: mission, fleetLink: fleetLink, sitl: sitl, missionsProvider: { missionProvider().map { [$0] } ?? [] })
    }

    private func beginDeferredOneOffWaitTask(
        runID: UUID,
        executeAt: Date,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionProvider: @escaping @MainActor () -> Mission?
    ) {
        let capturedExecuteAt = executeAt
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = capturedExecuteAt.timeIntervalSince(Date())
                if remaining <= 0.05 { break }
                let chunk = min(remaining, 3600)
                let rawNs = chunk * 1_000_000_000
                guard rawNs.isFinite, rawNs > 0 else { break }
                let clamped = min(rawNs, Double(UInt64.max))
                let ns = UInt64(max(1_000_000, clamped))
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            guard let idx = self.runs.firstIndex(where: { $0.id == runID }),
                  self.runs[idx].status == .running,
                  let stored = self.oneOffDeferredExecutionByRunID[runID],
                  stored.executeAt == capturedExecuteAt
            else { return }

            self.deferredOneOffStartTasks[runID] = nil
            var cleared = self.oneOffDeferredExecutionByRunID
            cleared.removeValue(forKey: runID)
            self.oneOffDeferredExecutionByRunID = cleared

            let mission = missionProvider()
            self.startRun(id: runID, mission: mission, fleetLink: fleetLink, sitl: sitl, missionsProvider: { missionProvider().map { [$0] } ?? [] })
        }
        deferredOneOffStartTasks[runID] = task
    }

    /// Full autopilot mission cycles already finished this run (loop / continuous). Published so live progress UI updates.
    @Published private(set) var autopilotLoopCycleCountByRunID: [UUID: Int] = [:]

    /// Per-path delay between mission cycles (loop / continuous). Outer key: run id; inner: route path id.
    @Published private(set) var missionCycleIntermissionByRunID: [UUID: [UUID: MissionCycleIntermission]] = [:]

    /// Per-path countdown before **first** MAVLink mission upload/start once execution begins.
    @Published private(set) var missionPathStartDeferralByRunID: [UUID: [UUID: MissionPathStartDeferral]] = [:]

    func missionCycleIntermission(for runID: UUID, pathID: UUID) -> MissionCycleIntermission? {
        missionCycleIntermissionByRunID[runID]?[pathID]
    }

    func hasMissionCycleIntermission(for runID: UUID) -> Bool {
        guard let inner = missionCycleIntermissionByRunID[runID] else { return false }
        return !inner.isEmpty
    }

    func missionPathStartDeferral(for runID: UUID, pathID: UUID) -> MissionPathStartDeferral? {
        missionPathStartDeferralByRunID[runID]?[pathID]
    }

    func hasMissionPathStartDeferral(for runID: UUID) -> Bool {
        guard let inner = missionPathStartDeferralByRunID[runID] else { return false }
        return !inner.isEmpty
    }

    /// Operator: skip this path's initial start delay and begin its first MAVLink mission cycle now.
    func skipMissionPathStartDeferralForPath(
        runID: UUID,
        pathID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission]
    ) {
        guard missionPathStartDeferralByRunID[runID]?[pathID] != nil else { return }
        scheduledPathMissionStartTasks[runID]?[pathID]?.cancel()
        if var inner = scheduledPathMissionStartTasks[runID] {
            inner.removeValue(forKey: pathID)
            scheduledPathMissionStartTasks[runID] = inner.isEmpty ? nil : inner
        }

        let missions = missionsProvider()
        let mission = missions.first(where: { $0.id == runs.first(where: { $0.id == runID })?.missionId })
        if var session = paladinSessionsByRunID[runID],
           let run = runs.first(where: { $0.id == runID }),
           let assignment = assignmentForPaladinPath(run: run, mission: mission, pathID: pathID) {
            let pf = paladinPathFields(runID: runID, assignmentID: assignment.id)
            session.events.append(
                PaladinEvent(
                    level: .info,
                    pathID: pf.pathID,
                    pathLabel: pf.pathLabel,
                    speaker: .paladin,
                    message: "Operator skipped initial path delay; starting this path mission now.",
                    templateKey: PaladinLogTemplateKey.schedulePathMissionStartSkipped
                )
            )
            paladinSessionsByRunID[runID] = session
        }

        performDeferredPathMissionStart(
            runID: runID,
            pathID: pathID,
            fleetLink: fleetLink,
            sitl: sitl,
            missionsProvider: missionsProvider
        )
    }

    /// Operator: push this path's initial mission start later by **`additionalMinutes`** (1...30).
    func extendMissionPathStartDeferralForPathByMinutes(
        runID: UUID,
        pathID: UUID,
        additionalMinutes: Int,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission]
    ) {
        let mins = min(30, max(1, additionalMinutes))
        guard var def = missionPathStartDeferralByRunID[runID]?[pathID] else { return }

        scheduledPathMissionStartTasks[runID]?[pathID]?.cancel()
        if var inner = scheduledPathMissionStartTasks[runID] {
            inner.removeValue(forKey: pathID)
            scheduledPathMissionStartTasks[runID] = inner.isEmpty ? nil : inner
        }

        let addSec = Double(mins) * 60
        let newStart = def.startAt.addingTimeInterval(addSec)
        let newTotal = def.totalDelay + addSec
        def = MissionPathStartDeferral(startAt: newStart, totalDelay: newTotal)
        var byPath = missionPathStartDeferralByRunID[runID] ?? [:]
        byPath[pathID] = def
        var copy = missionPathStartDeferralByRunID
        copy[runID] = byPath
        missionPathStartDeferralByRunID = copy

        let clock = newStart.formatted(date: .omitted, time: .shortened)
        let missions = missionsProvider()
        let mission = missions.first(where: { $0.id == runs.first(where: { $0.id == runID })?.missionId })
        if var session = paladinSessionsByRunID[runID],
           let run = runs.first(where: { $0.id == runID }),
           let assignment = assignmentForPaladinPath(run: run, mission: mission, pathID: pathID) {
            let pf = paladinPathFields(runID: runID, assignmentID: assignment.id)
            session.events.append(
                PaladinEvent(
                    level: .info,
                    pathID: pf.pathID,
                    pathLabel: pf.pathLabel,
                    speaker: .paladin,
                    message: "Initial path mission delay extended by \(mins) minute(s); now starts at \(clock).",
                    templateKey: PaladinLogTemplateKey.schedulePathMissionStartExtended,
                    templateParams: [
                        "minutes": String(mins),
                        "clock": clock,
                    ]
                )
            )
            paladinSessionsByRunID[runID] = session
        }

        armPathMissionStartTask(
            runID: runID,
            pathID: pathID,
            startAt: newStart,
            fleetLink: fleetLink,
            sitl: sitl,
            missionsProvider: missionsProvider
        )
    }

    /// Operator: end this path’s loop wait and start the next MAVLink cycle now.
    func skipMissionCycleIntermissionForPath(
        runID: UUID,
        pathID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission]
    ) {
        guard missionCycleIntermissionByRunID[runID]?[pathID] != nil else { return }
        scheduledMissionCycleTasks[runID]?[pathID]?.cancel()
        if var inner = scheduledMissionCycleTasks[runID] {
            inner.removeValue(forKey: pathID)
            scheduledMissionCycleTasks[runID] = inner.isEmpty ? nil : inner
        }

        let missions = missionsProvider()
        let mission = missions.first(where: { $0.id == runs.first(where: { $0.id == runID })?.missionId })
        if var session = paladinSessionsByRunID[runID],
           let run = runs.first(where: { $0.id == runID }),
           let assignment = assignmentForPaladinPath(run: run, mission: mission, pathID: pathID) {
            let pf = paladinPathFields(runID: runID, assignmentID: assignment.id)
            session.events.append(
                PaladinEvent(
                    level: .info,
                    pathID: pf.pathID,
                    pathLabel: pf.pathLabel,
                    speaker: .paladin,
                    message: "Operator skipped loop wait; starting the next mission cycle now.",
                    templateKey: PaladinLogTemplateKey.scheduleLoopIntermissionSkipped
                )
            )
            paladinSessionsByRunID[runID] = session
        }

        performScheduledMissionCycleRestart(
            runID: runID,
            pathID: pathID,
            fleetLink: fleetLink,
            sitl: sitl,
            missionsProvider: missionsProvider
        )
    }

    /// Operator: push this path’s next loop start later by **`additionalMinutes`** (1…30).
    func extendMissionCycleIntermissionForPathByMinutes(
        runID: UUID,
        pathID: UUID,
        additionalMinutes: Int,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission]
    ) {
        let mins = min(30, max(1, additionalMinutes))
        guard var inter = missionCycleIntermissionByRunID[runID]?[pathID] else { return }

        scheduledMissionCycleTasks[runID]?[pathID]?.cancel()
        if var inner = scheduledMissionCycleTasks[runID] {
            inner.removeValue(forKey: pathID)
            scheduledMissionCycleTasks[runID] = inner.isEmpty ? nil : inner
        }

        let addSec = Double(mins) * 60
        let newRestart = inter.restartAt.addingTimeInterval(addSec)
        let newTotal = inter.totalDelay + addSec
        inter = MissionCycleIntermission(
            restartAt: newRestart,
            totalDelay: newTotal,
            scheduleMode: inter.scheduleMode
        )
        var paths = missionCycleIntermissionByRunID[runID] ?? [:]
        paths[pathID] = inter
        var copy = missionCycleIntermissionByRunID
        copy[runID] = paths
        missionCycleIntermissionByRunID = copy

        let clock = newRestart.formatted(date: .omitted, time: .shortened)
        let missions = missionsProvider()
        let mission = missions.first(where: { $0.id == runs.first(where: { $0.id == runID })?.missionId })
        if var session = paladinSessionsByRunID[runID],
           let run = runs.first(where: { $0.id == runID }),
           let assignment = assignmentForPaladinPath(run: run, mission: mission, pathID: pathID) {
            let pf = paladinPathFields(runID: runID, assignmentID: assignment.id)
            session.events.append(
                PaladinEvent(
                    level: .info,
                    pathID: pf.pathID,
                    pathLabel: pf.pathLabel,
                    speaker: .paladin,
                    message: "Loop restart delayed by \(mins) minute(s); next cycle at \(clock).",
                    templateKey: PaladinLogTemplateKey.scheduleLoopIntermissionExtended,
                    templateParams: ["minutes": String(mins), "restartAt": clock]
                )
            )
            paladinSessionsByRunID[runID] = session
        }

        armMissionCycleRestartTask(
            runID: runID,
            pathID: pathID,
            restartAt: newRestart,
            fleetLink: fleetLink,
            sitl: sitl,
            missionsProvider: missionsProvider
        )
    }

    /// One-off scheduled start: run is already **running** in the roster sense, but Paladin execution is waiting for `executeAt`.
    @Published private(set) var oneOffDeferredExecutionByRunID: [UUID: MissionOneOffDeferredExecution] = [:]

    private var deferredOneOffStartTasks: [UUID: Task<Void, Never>] = [:]

    func oneOffDeferredExecution(for runID: UUID) -> MissionOneOffDeferredExecution? {
        oneOffDeferredExecutionByRunID[runID]
    }

    func completedAutopilotCycles(for runID: UUID) -> Int {
        autopilotLoopCycleCountByRunID[runID] ?? 0
    }

    func createRun(from mission: Mission) -> MissionRun {
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
        let run = MissionRun(
            missionId: mission.id,
            missionName: mission.name,
            assignments: assignments
        )
        runs.insert(run, at: 0)
        return run
    }

    func updateRun(_ run: MissionRun) {
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
        autopilotLoopCycleCountByRunID.removeValue(forKey: id)
        clearVehicleVoiceSnapshots(runID: id)
        runs[idx].status = .running
        if runs[idx].startedAt == nil {
            runs[idx].startedAt = Date()
        }
        let hadPaladinSession = paladinSessionsByRunID[id] != nil
        if var session = paladinSessionsByRunID[id] {
            session.phase = .executing
            session.events.append(
                PaladinEvent(
                    level: .info,
                    message: "Paladin execution started.",
                    templateKey: PaladinLogTemplateKey.executionStarted
                )
            )
            let staging = PaladinRuntime.executeStagingPass(run: runs[idx], mission: mission)
            session.events.append(contentsOf: staging.events)
            for issued in staging.commands {
                session.events.append(dispatchPaladinCommand(runID: id, issued, fleetLink: fleetLink, sitl: sitl))
            }
            paladinSessionsByRunID[id] = session
            if let mission {
                enqueueInitialPrimaryMissionPasses(
                    runID: id,
                    mission: mission,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    missionsProvider: missionsProvider
                )
            } else if var sessionMissing = paladinSessionsByRunID[id] {
                sessionMissing.events.append(
                    PaladinEvent(
                        level: .warning,
                        message: "Mission template missing from store; Paladin cannot upload MAVLink mission.",
                        templateKey: PaladinLogTemplateKey.executionMissionMissing
                    )
                )
                paladinSessionsByRunID[id] = sessionMissing
            }
        }
        if hadPaladinSession {
            PaladinUserNotificationService.shared.notifyExecutionStarted(
                runID: id,
                missionName: runs[idx].missionName
            )
        }
    }

    func deleteRun(id: UUID) {
        cancelScheduledMissionCycle(for: id)
        cancelScheduledPathMissionStarts(for: id)
        cancelDeferredOneOffExecution(for: id)
        autopilotLoopCycleCountByRunID.removeValue(forKey: id)
        runs.removeAll { $0.id == id }
    }

    /// Stop now: cancel any pending loop/continuous restart, mark the run completed, command RTL/home on assigned fleet vehicles.
    func stopRunImmediate(id: UUID, fleetLink: FleetLinkService, sitl: SitlService) {
        cancelScheduledMissionCycle(for: id)
        cancelScheduledPathMissionStarts(for: id)
        guard let idx = runs.firstIndex(where: { $0.id == id }) else { return }
        clearVehicleVoiceSnapshots(runID: id)
        markRunCompletedWithTeardown(
            at: idx,
            fleetLink: fleetLink,
            sitl: sitl,
            paladinMessage: "Run stopped immediately; commanding return to launch / home.",
            templateKey: PaladinLogTemplateKey.runStoppedImmediate,
            kind: .operatorStoppedImmediate
        )
    }

    /// Finish the current cycle, then stop; no further loop iterations or continuous scheduling.
    func stopRunAfterCurrentCycle(id: UUID) {
        guard let idx = runs.firstIndex(where: { $0.id == id }) else { return }
        guard runs[idx].status == .running || runs[idx].status == .paused else { return }
        runs[idx].pendingGracefulCycleStop = true
    }

    /// Move a completed run back to setup for another configured launch.
    func resetRunToSetup(id: UUID) {
        guard let idx = runs.firstIndex(where: { $0.id == id }) else { return }
        cancelScheduledMissionCycle(for: id)
        cancelScheduledPathMissionStarts(for: id)
        cancelDeferredOneOffExecution(for: id)
        autopilotLoopCycleCountByRunID.removeValue(forKey: id)
        clearVehicleVoiceSnapshots(runID: id)
        runs[idx].status = .setup
        runs[idx].pendingGracefulCycleStop = false
        runs[idx].reportAutopilotCyclesCompleted = nil
        runs[idx].completionKind = nil
        // Intentionally preserve mission prep state (schedule, assignments, and chosen vehicles).
    }

    /// Invoked when MAVSDK mission progress reports a full cycle (`current >= total`) for `vehicleID`.
    func handleAutopilotMissionCycleFinished(
        vehicleID: String,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission]
    ) {
        let missions = missionsProvider()
        let runningIDs = runs.filter { $0.status == .running }.map(\.id)
        for runID in runningIDs {
            guard let idx = runs.firstIndex(where: { $0.id == runID }) else { continue }
            let run = runs[idx]
            guard let mission = missions.first(where: { $0.id == run.missionId }),
                  let built = PaladinMavlinkMissionBuilder.buildSingleDronePathMission(run: run, mission: mission),
                  let missionVehicleID = resolvedFleetStreamVehicleID(
                      assignment: built.assignment,
                      fleetLink: fleetLink,
                      sitl: sitl
                  ),
                  missionVehicleID == vehicleID
            else { continue }

            let pendingStop = run.pendingGracefulCycleStop
            let mode = run.scheduleMode

            if pendingStop || mode == .oneOff {
                markRunCompletedWithTeardown(
                    at: idx,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    paladinMessage: pendingStop
                        ? "Current mission cycle finished; graceful stop — returning to launch / home."
                        : "One-off mission cycle finished; run complete — returning to launch / home.",
                    templateKey: pendingStop
                        ? PaladinLogTemplateKey.runGracefulAfterCycle
                        : PaladinLogTemplateKey.runOneOffFinished,
                    kind: pendingStop ? .operatorStoppedAfterCycle : .oneOffAutopilotFinished
                )
                continue
            }

            if run.repeatsAutopilotMissionCycles {
                let next = (autopilotLoopCycleCountByRunID[runID] ?? 0) + 1
                autopilotLoopCycleCountByRunID[runID] = next
                let limit = run.loopRepeatCount
                if limit > 0, next >= limit {
                    markRunCompletedWithTeardown(
                        at: idx,
                        fleetLink: fleetLink,
                        sitl: sitl,
                        paladinMessage: "Loop schedule finished (\(limit) mission run(s)); returning to launch / home.",
                        templateKey: PaladinLogTemplateKey.runLoopAllRepeatsDone,
                        templateParams: ["limit": String(limit)],
                        kind: .loopCompletedAllRepeats
                    )
                    continue
                }
            }

            let finishedPathId: UUID
            if let pid = built.assignment.pathId {
                finishedPathId = pid
            } else {
                let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
                guard enabledPaths.count == 1, let p = enabledPaths.first else { continue }
                finishedPathId = p.id
            }

            cancelScheduledMissionCycle(for: runID, pathID: finishedPathId)

            let delayMinutes: Int
            switch run.scheduleMode {
            case .oneOff:
                continue
            case .continuous:
                delayMinutes = 0
            case .loop:
                delayMinutes = run.loopDelayMinutes(forPath: finishedPathId)
            }

            let delaySeconds = Double(delayMinutes) * 60
            let label: String
            let templateKey: String
            let templateParams: [String: String]
            if delayMinutes <= 0 {
                label = "Mission cycle complete; starting the next cycle immediately."
                templateKey = PaladinLogTemplateKey.scheduleContinuousRestart
                templateParams = [:]
            } else {
                label = "Mission cycle complete; next cycle in \(delayMinutes) minute(s) (loop)."
                templateKey = PaladinLogTemplateKey.scheduleLoopNextIn
                templateParams = ["minutes": String(delayMinutes)]
            }

            let restartAt = Date().addingTimeInterval(delaySeconds)
            var interByPath = missionCycleIntermissionByRunID[runID] ?? [:]
            interByPath[finishedPathId] = MissionCycleIntermission(
                restartAt: restartAt,
                totalDelay: delaySeconds,
                scheduleMode: run.scheduleMode
            )
            var interCopy = missionCycleIntermissionByRunID
            interCopy[runID] = interByPath
            missionCycleIntermissionByRunID = interCopy

            if var session = paladinSessionsByRunID[runID] {
                let pf = paladinPathFields(runID: runID, assignmentID: built.assignment.id)
                session.events.append(
                    PaladinEvent(
                        level: .info,
                        pathID: pf.pathID,
                        pathLabel: pf.pathLabel,
                        speaker: .paladin,
                        message: label,
                        templateKey: templateKey,
                        templateParams: templateParams
                    )
                )
                paladinSessionsByRunID[runID] = session
            }

            armMissionCycleRestartTask(
                runID: runID,
                pathID: finishedPathId,
                restartAt: restartAt,
                fleetLink: fleetLink,
                sitl: sitl,
                missionsProvider: missionsProvider
            )
        }
    }

    private func performScheduledMissionCycleRestart(
        runID: UUID,
        pathID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @MainActor () -> [Mission]
    ) {
        if var inner = scheduledMissionCycleTasks[runID] {
            inner.removeValue(forKey: pathID)
            scheduledMissionCycleTasks[runID] = inner.isEmpty ? nil : inner
        }
        clearMissionCycleIntermission(for: runID, pathID: pathID)
        guard let idx = runs.firstIndex(where: { $0.id == runID }),
              runs[idx].status == .running
        else { return }

        let missions = missionsProvider()
        guard let mission = missions.first(where: { $0.id == runs[idx].missionId }) else {
            appendPaladinEventIfSession(
                runID: runID,
                level: .warning,
                message: "Scheduled mission cycle skipped — mission template not found in store.",
                templateKey: PaladinLogTemplateKey.scheduleSkipNoMission
            )
            return
        }

        let pass = PaladinRuntime.executePrimaryMissionPass(run: runs[idx], mission: mission, pathId: pathID)
        guard var session = paladinSessionsByRunID[runID], session.phase == .executing else { return }
        session.events.append(contentsOf: pass.events)
        for issued in pass.commands {
            session.events.append(dispatchPaladinCommand(runID: runID, issued, fleetLink: fleetLink, sitl: sitl))
        }
        paladinSessionsByRunID[runID] = session
    }

    private func enqueueInitialPrimaryMissionPasses(
        runID: UUID,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission]
    ) {
        guard let idx = runs.firstIndex(where: { $0.id == runID }) else { return }
        let run = runs[idx]
        let orderedEnabled = mission.routeMacro.paths.filter(\.enabled)

        struct BuildEntry {
            let pathId: UUID
            let assignment: MissionRunAssignment
        }
        let buildable: [BuildEntry] = orderedEnabled.compactMap { path in
            guard let built = PaladinMavlinkMissionBuilder.buildDronePathMission(run: run, mission: mission, pathId: path.id)
            else { return nil }
            return BuildEntry(pathId: path.id, assignment: built.assignment)
        }

        if buildable.isEmpty {
            if var session = paladinSessionsByRunID[runID] {
                session.events.append(
                    PaladinEvent(
                        level: .warning,
                        message: "MAVLink mission not started (need enabled path(es) with assigned vehicle(s) and waypoints).",
                        templateKey: PaladinLogTemplateKey.missionNotStarted
                    )
                )
                paladinSessionsByRunID[runID] = session
            }
            return
        }

        for entry in buildable {
            let mins = runs[idx].startDelayMinutes(forPath: entry.pathId)
            guard mins > 0 else {
                dispatchPrimaryMissionPassForPath(runID: runID, pathId: entry.pathId, mission: mission, fleetLink: fleetLink, sitl: sitl)
                continue
            }

            let delaySeconds = Double(mins) * 60
            let startAt = Date().addingTimeInterval(delaySeconds)
            let pf = paladinPathFields(runID: runID, assignmentID: entry.assignment.id)

            var byPath = missionPathStartDeferralByRunID[runID] ?? [:]
            byPath[entry.pathId] = MissionPathStartDeferral(startAt: startAt, totalDelay: delaySeconds)
            var deferCopy = missionPathStartDeferralByRunID
            deferCopy[runID] = byPath
            missionPathStartDeferralByRunID = deferCopy

            if var session = paladinSessionsByRunID[runID] {
                session.events.append(
                    PaladinEvent(
                        level: .info,
                        pathID: pf.pathID,
                        pathLabel: pf.pathLabel,
                        speaker: .paladin,
                        message:
                            "MAVLink mission start for this path deferred \(mins) minute(s).",
                        templateKey: PaladinLogTemplateKey.schedulePathMissionStartDeferred,
                        templateParams: ["minutes": String(mins)]
                    )
                )
                paladinSessionsByRunID[runID] = session
            }

            armPathMissionStartTask(
                runID: runID,
                pathID: entry.pathId,
                startAt: startAt,
                fleetLink: fleetLink,
                sitl: sitl,
                missionsProvider: missionsProvider
            )
        }
    }

    /// Upload/start MAVLink mission for one path (`pathId`).
    private func dispatchPrimaryMissionPassForPath(
        runID: UUID,
        pathId: UUID,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard let idx = runs.firstIndex(where: { $0.id == runID }) else { return }
        let pass = PaladinRuntime.executePrimaryMissionPass(run: runs[idx], mission: mission, pathId: pathId)
        guard var session = paladinSessionsByRunID[runID], session.phase == .executing else { return }
        session.events.append(contentsOf: pass.events)
        for issued in pass.commands {
            session.events.append(dispatchPaladinCommand(runID: runID, issued, fleetLink: fleetLink, sitl: sitl))
        }
        paladinSessionsByRunID[runID] = session
    }

    private func performDeferredPathMissionStart(
        runID: UUID,
        pathID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionsProvider: @escaping @MainActor () -> [Mission]
    ) {
        if var inner = scheduledPathMissionStartTasks[runID] {
            inner.removeValue(forKey: pathID)
            scheduledPathMissionStartTasks[runID] = inner.isEmpty ? nil : inner
        }
        clearMissionPathStartDeferral(for: runID, pathID: pathID)
        guard let idx = runs.firstIndex(where: { $0.id == runID }),
              runs[idx].status == .running
        else { return }

        let missions = missionsProvider()
        guard let mission = missions.first(where: { $0.id == runs[idx].missionId }) else {
            appendPaladinEventIfSession(
                runID: runID,
                level: .warning,
                message: "Deferred path mission start skipped — mission template not found in store.",
                templateKey: PaladinLogTemplateKey.scheduleSkipNoMission
            )
            return
        }

        dispatchPrimaryMissionPassForPath(runID: runID, pathId: pathID, mission: mission, fleetLink: fleetLink, sitl: sitl)
    }

    private func markRunCompletedWithTeardown(
        at idx: Int,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        paladinMessage: String,
        templateKey: String? = nil,
        templateParams: [String: String] = [:],
        kind: MissionRunCompletionKind
    ) {
        let runID = runs[idx].id
        cancelScheduledMissionCycle(for: runID)
        cancelScheduledPathMissionStarts(for: runID)
        cancelDeferredOneOffExecution(for: runID)
        var cycleSnap = autopilotLoopCycleCountByRunID[runID] ?? 0
        if kind == .oneOffAutopilotFinished {
            cycleSnap = max(1, cycleSnap)
        }
        autopilotLoopCycleCountByRunID.removeValue(forKey: runID)
        runs[idx].status = .completed
        runs[idx].completedAt = Date()
        runs[idx].pendingGracefulCycleStop = false
        runs[idx].reportAutopilotCyclesCompleted = cycleSnap
        runs[idx].completionKind = kind

        guard var session = paladinSessionsByRunID[runID] else { return }
        session.phase = .completed
        session.events.append(
            PaladinEvent(
                level: .info,
                speaker: .paladin,
                message: paladinMessage,
                templateKey: templateKey,
                templateParams: templateParams
            )
        )
        appendReturnToLaunchForRun(runID: runID, run: runs[idx], fleetLink: fleetLink, sitl: sitl, to: &session)
        paladinSessionsByRunID[runID] = session
        PaladinUserNotificationService.shared.notifyRunCompleted(
            runID: runID,
            missionName: runs[idx].missionName,
            summary: paladinMessage
        )
    }

    private func appendReturnToLaunchForRun(
        runID: UUID,
        run: MissionRun,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        to session: inout PaladinSession
    ) {
        for assignment in run.assignments {
            guard let key = assignment.attachedFleetVehicleToken,
                  FleetMissionVehicleToken(storageKey: key) != nil
            else { continue }
            let issued = PaladinIssuedCommand(
                assignmentID: assignment.id,
                slotName: assignment.slotName,
                vehicleTokenKey: key,
                command: .returnToLaunch,
                source: "paladin.teardown",
                category: .paladin
            )
            session.events.append(dispatchPaladinCommand(runID: runID, issued, fleetLink: fleetLink, sitl: sitl))
        }
    }

    private func appendPaladinEventIfSession(
        runID: UUID,
        level: PaladinEventLevel,
        message: String,
        templateKey: String? = nil,
        templateParams: [String: String] = [:]
    ) {
        guard var session = paladinSessionsByRunID[runID] else { return }
        session.events.append(
            PaladinEvent(
                level: level,
                speaker: .paladin,
                message: message,
                templateKey: templateKey,
                templateParams: templateParams
            )
        )
        paladinSessionsByRunID[runID] = session
    }

    func compilePaladinSession(
        run: MissionRun,
        mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle]
    ) {
        let plan = PaladinCompiler.compile(
            run: run,
            mission: mission,
            fleetVehicles: fleetVehicles
        )
        let summary = "Compiled \(plan.roleTracks.count) role track(s), \(plan.pathTopology.rawValue), \(plan.teamTopology.rawValue)."
        paladinSessionsByRunID[run.id] = PaladinSession(
            runID: run.id,
            missionID: mission.id,
            phase: .compiled,
            plan: plan,
            events: [
                PaladinEvent(
                    level: .info,
                    message: summary,
                    templateKey: PaladinLogTemplateKey.compileSummary,
                    templateParams: [
                        "tracks": String(plan.roleTracks.count),
                        "pathTopology": plan.pathTopology.rawValue,
                        "teamTopology": plan.teamTopology.rawValue,
                    ]
                ),
            ]
        )
        PaladinUserNotificationService.shared.notifyPlanCompiled(
            runID: run.id,
            missionName: run.missionName
        )
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
    func isFleetVehicleUsedOnOtherSlotInRun(tokenKey: String, run: MissionRun, assignmentId: UUID) -> Bool {
        run.assignments.contains {
            $0.id != assignmentId && $0.attachedFleetVehicleToken == tokenKey
        }
    }

    private func paladinPathFields(runID: UUID, assignmentID: UUID) -> (pathID: UUID?, pathLabel: String?) {
        guard let track = paladinSessionsByRunID[runID]?.plan.roleTracks.first(where: { $0.assignmentID == assignmentID })
        else { return (nil, nil) }
        return (track.pathID, track.pathDisplayName)
    }

    /// Append human-readable telemetry lines (`[Scout] …`) to the Paladin log while a run is executing.
    func ingestVehicleTelemetryNarrative(
        runID: UUID,
        run: MissionRun,
        mission: Mission?,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard var session = paladinSessionsByRunID[runID] else { return }
        guard session.phase == .executing else { return }

        var anyAppended = false
        for assignment in run.assignments {
            guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
                  let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
            else { continue }

            let key = "\(runID.uuidString)|\(assignment.id.uuidString)"
            let slot = assignment.slotName
            let pathFields = paladinPathFields(runID: runID, assignmentID: assignment.id)
            let prev = vehicleVoiceSnapshots[key]
            var lastTrack = prev?.lastTrackLogAt
            var lastTrackLoggedLat = prev?.lastTrackLoggedLat
            var lastTrackLoggedLon = prev?.lastTrackLoggedLon
            var lastAlt = prev?.lastAltTrendLogAt
            var lastRoute = prev?.lastRouteProgressLogAt
            var announcedWP = prev?.announcedApproachWP1 ?? false

            if prev == nil {
                let mode = hub.flightMode.isEmpty ? "unknown" : hub.flightMode
                let arm = hub.isArmed ? "armed" : "disarmed"
                let alt = hub.relativeAltM.map { String(format: "%.1f m", $0) } ?? "—"
                session.events.append(
                    PaladinEvent(
                        level: .info,
                        pathID: pathFields.pathID,
                        pathLabel: pathFields.pathLabel,
                        speaker: .vehicleSlot(slot),
                        message: "Autopilot: mode \(mode), \(arm), rel alt \(alt).",
                        templateKey: PaladinLogTemplateKey.telemetryAutopilotSnapshot,
                        templateParams: ["mode": mode, "armState": arm, "relAlt": alt]
                    )
                )
                anyAppended = true
            } else if prev!.flightMode != hub.flightMode, !hub.flightMode.isEmpty {
                session.events.append(
                    PaladinEvent(
                        level: .info,
                        pathID: pathFields.pathID,
                        pathLabel: pathFields.pathLabel,
                        speaker: .vehicleSlot(slot),
                        message: "Flight mode: \(prev!.flightMode) → \(hub.flightMode).",
                        templateKey: PaladinLogTemplateKey.telemetryFlightModeChange,
                        templateParams: ["from": prev!.flightMode, "to": hub.flightMode]
                    )
                )
                anyAppended = true
            } else if prev!.isArmed != hub.isArmed {
                session.events.append(
                    PaladinEvent(
                        level: .info,
                        pathID: pathFields.pathID,
                        pathLabel: pathFields.pathLabel,
                        speaker: .vehicleSlot(slot),
                        message: hub.isArmed ? "Armed." : "Disarmed.",
                        templateKey: hub.isArmed
                            ? PaladinLogTemplateKey.telemetryArmed
                            : PaladinLogTemplateKey.telemetryDisarmed
                    )
                )
                anyAppended = true
            } else if let was = prev!.inAir, let now = hub.inAir, was != now {
                session.events.append(
                    PaladinEvent(
                        level: .info,
                        pathID: pathFields.pathID,
                        pathLabel: pathFields.pathLabel,
                        speaker: .vehicleSlot(slot),
                        message: now
                            ? "Airborne."
                            : "On ground (in-air flag cleared).",
                        templateKey: now
                            ? PaladinLogTemplateKey.telemetryAirborne
                            : PaladinLogTemplateKey.telemetryOnGround
                    )
                )
                anyAppended = true
            }

            if let r = hub.relativeAltM, let prevAlt = prev?.relativeAltM {
                let delta = r - prevAlt
                let since = lastAlt.map { Date().timeIntervalSince($0) } ?? 100
                if abs(delta) >= 2.5, since >= 4 {
                    let trend = delta > 0 ? "Climbing" : "Descending"
                    session.events.append(
                        PaladinEvent(
                            level: .info,
                            pathID: pathFields.pathID,
                            pathLabel: pathFields.pathLabel,
                            speaker: .vehicleSlot(slot),
                            message: "\(trend) — rel alt ~\(String(format: "%.1f", r)) m (Δ \(String(format: "%.1f", delta)) m).",
                            templateKey: PaladinLogTemplateKey.telemetryAltTrend,
                            templateParams: [
                                "trend": trend,
                                "alt": String(format: "%.1f", r),
                                "delta": String(format: "%.1f", delta),
                            ]
                        )
                    )
                    lastAlt = Date()
                    anyAppended = true
                }
            }

            if let lat = hub.latitudeDeg, let lon = hub.longitudeDeg {
                if lastTrackLoggedLat == nil || lastTrackLoggedLon == nil {
                    lastTrackLoggedLat = lat
                    lastTrackLoggedLon = lon
                } else if let refLat = lastTrackLoggedLat, let refLon = lastTrackLoggedLon {
                    let movedFromLastLog = MissionTelemetryGeo.horizontalDistanceM(
                        lat1: refLat, lon1: refLon, lat2: lat, lon2: lon
                    )
                    if movedFromLastLog >= 12 {
                        let alt = hub.relativeAltM.map { String(format: "%.1f m", $0) } ?? "—"
                        let mode = hub.flightMode.isEmpty ? "—" : hub.flightMode
                        session.events.append(
                            PaladinEvent(
                                level: .info,
                                pathID: pathFields.pathID,
                                pathLabel: pathFields.pathLabel,
                                speaker: .vehicleSlot(slot),
                                message: "Track — \(String(format: "%.5f", lat))°, \(String(format: "%.5f", lon))° · rel alt \(alt) · \(mode).",
                                templateKey: PaladinLogTemplateKey.telemetryTrack,
                                templateParams: [
                                    "lat": String(format: "%.5f", lat),
                                    "lon": String(format: "%.5f", lon),
                                    "relAlt": alt,
                                    "mode": mode,
                                ]
                            )
                        )
                        lastTrackLoggedLat = lat
                        lastTrackLoggedLon = lon
                        lastTrack = Date()
                        anyAppended = true
                    }
                }
            }

            if let mission,
               let wp = Self.firstMissionWaypoint(for: assignment, mission: mission),
               let lat = hub.latitudeDeg,
               let lon = hub.longitudeDeg,
               let heading = hub.headingDeg ?? hub.yawDeg {
                let dist = MissionTelemetryGeo.horizontalDistanceM(lat1: lat, lon1: lon, lat2: wp.lat, lon2: wp.lon)
                let bear = MissionTelemetryGeo.bearingDegrees(lat1: lat, lon1: lon, lat2: wp.lat, lon2: wp.lon)
                let turn = abs(MissionTelemetryGeo.angleDifferenceDeg(heading, bear))
                let sinceR = lastRoute.map { Date().timeIntervalSince($0) } ?? 100
                if !announcedWP, dist < 38 {
                    let mode = hub.flightMode.isEmpty ? "—" : hub.flightMode
                    session.events.append(
                        PaladinEvent(
                            level: .info,
                            pathID: pathFields.pathID,
                            pathLabel: pathFields.pathLabel,
                            speaker: .vehicleSlot(slot),
                            message: "Approaching first waypoint — ~\(Int(dist)) m out, mode \(mode).",
                            templateKey: PaladinLogTemplateKey.telemetryApproachWP1,
                            templateParams: ["distance": String(Int(dist)), "mode": mode]
                        )
                    )
                    announcedWP = true
                    lastRoute = Date()
                    anyAppended = true
                } else if sinceR >= 12 {
                    if turn > 28, dist > 22 {
                        session.events.append(
                            PaladinEvent(
                                level: .info,
                                pathID: pathFields.pathID,
                                pathLabel: pathFields.pathLabel,
                                speaker: .vehicleSlot(slot),
                                message: "Turning toward leg — heading ~\(Int(heading))°, bearing to WP1 ~\(Int(bear))° (~\(Int(dist)) m).",
                                templateKey: PaladinLogTemplateKey.telemetryTurningLeg,
                                templateParams: [
                                    "heading": String(Int(heading)),
                                    "bearing": String(Int(bear)),
                                    "distance": String(Int(dist)),
                                ]
                            )
                        )
                        lastRoute = Date()
                        anyAppended = true
                    } else if dist > 45 {
                        session.events.append(
                            PaladinEvent(
                                level: .info,
                                pathID: pathFields.pathID,
                                pathLabel: pathFields.pathLabel,
                                speaker: .vehicleSlot(slot),
                                message: "Moving toward WP1 — ~\(Int(dist)) m, aligned within ~\(Int(turn))°.",
                                templateKey: PaladinLogTemplateKey.telemetryMovingWP1,
                                templateParams: ["distance": String(Int(dist)), "turn": String(Int(turn))]
                            )
                        )
                        lastRoute = Date()
                        anyAppended = true
                    }
                }
            }

            vehicleVoiceSnapshots[key] = VehicleVoiceSnapshot(
                flightMode: hub.flightMode,
                isArmed: hub.isArmed,
                relativeAltM: hub.relativeAltM,
                latitudeDeg: hub.latitudeDeg ?? prev?.latitudeDeg,
                longitudeDeg: hub.longitudeDeg ?? prev?.longitudeDeg,
                inAir: hub.inAir ?? prev?.inAir,
                lastTrackLogAt: lastTrack,
                lastTrackLoggedLat: lastTrackLoggedLat ?? prev?.lastTrackLoggedLat,
                lastTrackLoggedLon: lastTrackLoggedLon ?? prev?.lastTrackLoggedLon,
                lastAltTrendLogAt: lastAlt,
                lastRouteProgressLogAt: lastRoute,
                announcedApproachWP1: announcedWP
            )
        }

        if anyAppended {
            paladinSessionsByRunID[runID] = session
        }
    }

    /// Mirrors global fleet-log lines (STATUSTEXT, mission progress) into the Paladin console for the run that owns `vehicleID`.
    func ingestFleetMirrorLineForPaladin(
        vehicleID: String,
        line: String,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        let level: PaladinEventLevel
        if line.contains("[CRITICAL]") || line.contains("[ERROR]")
            || line.contains("[EMERGENCY]") || line.contains("[ALERT]") {
            level = .error
        } else if line.contains("[WARN]") {
            level = .warning
        } else {
            level = .info
        }
        for idx in runs.indices where runs[idx].status == .running || runs[idx].status == .paused {
            let run = runs[idx]
            guard let assignment = run.assignments.first(where: {
                resolvedFleetStreamVehicleID(assignment: $0, fleetLink: fleetLink, sitl: sitl) == vehicleID
            }) else { continue }
            guard var session = paladinSessionsByRunID[run.id], session.phase == .executing else { continue }
            let slot = assignment.slotName
            let pf = paladinPathFields(runID: run.id, assignmentID: assignment.id)
            let classified = PaladinFleetMirrorLineClassifier.classify(line)
            session.events.append(
                PaladinEvent(
                    level: level,
                    pathID: pf.pathID,
                    pathLabel: pf.pathLabel,
                    speaker: .vehicleSlot(slot),
                    message: classified.message,
                    templateKey: classified.templateKey,
                    templateParams: classified.params
                )
            )
            paladinSessionsByRunID[run.id] = session
        }
    }

    private func clearVehicleVoiceSnapshots(runID: UUID) {
        let prefix = "\(runID.uuidString)|"
        vehicleVoiceSnapshots = vehicleVoiceSnapshots.filter { !$0.key.hasPrefix(prefix) }
    }

    private static func firstMissionWaypoint(for assignment: MissionRunAssignment, mission: Mission) -> RouteCoordinate? {
        if let pid = assignment.pathId,
           let path = mission.routeMacro.paths.first(where: { $0.id == pid }),
           let wp = path.waypoints.first {
            return wp.coord
        }
        if let path = mission.routeMacro.paths.first(where: { $0.enabled }),
           let wp = path.waypoints.first {
            return wp.coord
        }
        return mission.routeMacro.paths.first?.waypoints.first?.coord
    }

    private func dispatchPaladinCommand(
        runID: UUID,
        _ issued: PaladinIssuedCommand,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> PaladinEvent {
        let pf = paladinPathFields(runID: runID, assignmentID: issued.assignmentID)
        guard let token = FleetMissionVehicleToken(storageKey: issued.vehicleTokenKey) else {
            return PaladinEvent(
                level: .error,
                pathID: pf.pathID,
                pathLabel: pf.pathLabel,
                speaker: .paladin,
                message: "Invalid vehicle token for slot \(issued.slotName); command dropped.",
                templateKey: PaladinLogTemplateKey.commandInvalidToken,
                templateParams: ["slot": issued.slotName]
            )
        }
        guard let vehicleID = resolveVehicleID(for: token, fleetLink: fleetLink, sitl: sitl) else {
            return PaladinEvent(
                level: .error,
                pathID: pf.pathID,
                pathLabel: pf.pathLabel,
                speaker: .paladin,
                message: "Vehicle unavailable for slot \(issued.slotName); command dropped.",
                templateKey: PaladinLogTemplateKey.commandVehicleUnavailable,
                templateParams: ["slot": issued.slotName]
            )
        }
        let summary = paladinShortCommandSummary(issued.command)
        let commandID = fleetLink.executeVehicleCommand(
            vehicleID: vehicleID,
            command: issued.command,
            source: issued.source,
            category: issued.category,
            onPaladinCommandOutcome: { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .succeeded:
                    self.appendPaladinFleetAck(
                        runID: runID,
                        assignmentID: issued.assignmentID,
                        level: .info,
                        message: "Fleet acknowledged: \(summary) on \(vehicleID).",
                        templateKey: PaladinLogTemplateKey.fleetAckSuccess,
                        templateParams: ["summary": summary, "vehicleID": vehicleID]
                    )
                case .failed(let reason):
                    self.appendPaladinFleetAck(
                        runID: runID,
                        assignmentID: issued.assignmentID,
                        level: .error,
                        message: "Fleet command failed: \(summary) — \(reason)",
                        templateKey: PaladinLogTemplateKey.fleetAckFailed,
                        templateParams: ["summary": summary, "reason": reason]
                    )
                }
            }
        )
        if commandID != nil {
            return PaladinEvent(
                level: .info,
                pathID: pf.pathID,
                pathLabel: pf.pathLabel,
                speaker: .paladin,
                message: "Command dispatched to \(vehicleID).",
                templateKey: PaladinLogTemplateKey.commandDispatched,
                templateParams: ["vehicleID": vehicleID]
            )
        }
        return PaladinEvent(
            level: .error,
            pathID: pf.pathID,
            pathLabel: pf.pathLabel,
            speaker: .paladin,
            message: "Command not sent to \(vehicleID) (no session, blocked by authority gate, or dispatch error).",
            templateKey: PaladinLogTemplateKey.commandNotSent,
            templateParams: ["vehicleID": vehicleID]
        )
    }

    private func paladinShortCommandSummary(_ command: FleetVehicleCommand) -> String {
        switch command {
        case .arm: return "arm"
        case .disarm: return "disarm"
        case .holdPosition: return "hold"
        case .gotoCoordinate: return "goto"
        case .uploadAndStartMission(let items): return "upload+start mission (\(items.count) item(s))"
        case .returnToLaunch: return "return to launch"
        case .land: return "land"
        case .manualControl(let manual): return "manual \(manual.intent.rawValue)"
        }
    }

    private func appendPaladinFleetAck(
        runID: UUID,
        assignmentID: UUID,
        level: PaladinEventLevel,
        message: String,
        templateKey: String? = nil,
        templateParams: [String: String] = [:]
    ) {
        guard var session = paladinSessionsByRunID[runID] else { return }
        let pf = paladinPathFields(runID: runID, assignmentID: assignmentID)
        session.events.append(
            PaladinEvent(
                level: level,
                pathID: pf.pathID,
                pathLabel: pf.pathLabel,
                speaker: .paladin,
                message: message,
                templateKey: templateKey,
                templateParams: templateParams
            )
        )
        paladinSessionsByRunID[runID] = session
    }

    private func resolveVehicleID(
        for token: FleetMissionVehicleToken,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> String? {
        resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
    }

    // MARK: - Start run preflight (arm probe)

    /// No `FleetVehicleModel` for this stream key (same notion as the Vehicles grid).
    static let armProbeNoVehicleDetail = "No vehicle."

    /// `FleetVehicleModel` exists but lifecycle is not **`.live`** (only `.live` yields green on the fleet card).
    static let armProbeNotConnectedDetail = "Not connected."

    /// Before sending arm: require the same lifecycle gate as the fleet UI (green = `stage == .live`).
    private func armProbeReadinessBlocker(vehicleID: String, fleetLink: FleetLinkService) -> SingleVehicleArmProbeResult? {
        guard let model = fleetLink.vehicleModel(forVehicleID: vehicleID) else {
            return SingleVehicleArmProbeResult(
                passed: false,
                armedDuringProbe: false,
                detail: Self.armProbeNoVehicleDetail,
                remediationAdvice: nil
            )
        }
        guard model.collections.lifecycleStatus.stage == .live else {
            return SingleVehicleArmProbeResult(
                passed: false,
                armedDuringProbe: false,
                detail: Self.armProbeNotConnectedDetail,
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

    /// Single-vehicle arm check (same semantics as one slot in `runPreflightArmProbeForStartRun`).
    func runSingleVehicleArmProbe(
        vehicleID: String,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        leaveArmed: Bool = false
    ) async -> SingleVehicleArmProbeResult {
        if let blocked = armProbeReadinessBlocker(vehicleID: vehicleID, fleetLink: fleetLink) {
            return blocked
        }

        let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
        if hub?.isArmed == true {
            return SingleVehicleArmProbeResult(
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
            source: "vehicles.testArmProbe"
        )
        let isSim = isVehicleSimulationStream(vehicleID: vehicleID, fleetLink: fleetLink, sitl: sitl)

        switch outcome {
        case .succeeded:
            let result = SingleVehicleArmProbeResult(
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
            let advice = ArmFailureAdvisor.advice(
                for: ArmFailureRemediationContext(
                    autopilotStack: hub?.autopilotStack ?? .unknown,
                    rawFailureDetail: reason,
                    hubSnapshot: hub,
                    isSimulation: isSim
                )
            )
            return SingleVehicleArmProbeResult(
                passed: false,
                armedDuringProbe: false,
                detail: preflightArmFailureDetail(hub: hub, reason: reason),
                remediationAdvice: advice
            )
        }
    }

    /// Attempts to **arm** every roster slot that has a fleet token + resolvable vehicle ID. Rows are reported via `rowUpdated` as each step completes.
    /// - Returns: whether every slot passed, and vehicle IDs that **became armed** during this probe (for optional disarm on abandon).
    func runPreflightArmProbeForStartRun(
        run: MissionRun,
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

            if let blocked = armProbeReadinessBlocker(vehicleID: vehicleID, fleetLink: fleetLink) {
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
                source: "missionControl.preflightArmProbe"
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
                let advice = ArmFailureAdvisor.advice(
                    for: ArmFailureRemediationContext(
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
}

// MARK: - Geo helpers (mission narrative)

private enum MissionTelemetryGeo {
    static func bearingDegrees(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let Δλ = (lon2 - lon1) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let θ = atan2(y, x) * 180 / .pi
        return (θ + 360).truncatingRemainder(dividingBy: 360)
    }

    static func angleDifferenceDeg(_ a: Double, _ b: Double) -> Double {
        let d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { return d - 360 }
        if d < -180 { return d + 360 }
        return d
    }

    static func horizontalDistanceM(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let Δφ = (lat2 - lat1) * .pi / 180
        let Δλ = (lon2 - lon1) * .pi / 180
        let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}
