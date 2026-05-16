import Foundation

extension MissionRunEnvironment {
    /// Roster / pool vehicle rows for mission clear, geofence clear, battery, and teleport union (see ``MissionRunSimCleanupParkPolicy`` for ordering).
    fileprivate func runCompleteSimCleanupUnionVehicleRows(
        policyTargets: [(vehicleID: String, assignment: MissionRunAssignment)],
        shouldTeleport: Bool,
        rosterSnapshots: [UUID: FleetSimState],
        poolSnapshots: [UUID: FleetSimState],
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> [(vehicleID: String, assignment: MissionRunAssignment)] {
        var rows = policyTargets
        var seen = Set(policyTargets.map(\.0))
        guard shouldTeleport else { return rows }
        for assignmentID in rosterSnapshots.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let assignment = assignments.first(where: { $0.id == assignmentID }) else { continue }
            guard let vid = resolvedFleetStreamVehicleID(
                assignment: assignment,
                fleetLink: fleetLink,
                sitl: sitl
            ) else { continue }
            guard fleetLink.isGuardianManagedSitlStream(vehicleID: vid) else { continue }
            let stack = fleetLink.vehicleModel(forVehicleID: vid)?.data.telemetry?.autopilotStack
                ?? fleetLink.hubTelemetry(forVehicleID: vid)?.autopilotStack
                ?? .unknown
            guard stack != .unknown else { continue }
            if seen.insert(vid).inserted {
                rows.append((vid, assignment))
            }
        }
        for slotID in poolSnapshots.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let pair = reservePoolSlot(forSlotID: slotID) else { continue }
            let assignment = MissionRunAssignment.syntheticForReservePool(slot: pair.slot)
            guard let vid = resolvedFleetStreamVehicleID(
                assignment: assignment,
                fleetLink: fleetLink,
                sitl: sitl
            ) else { continue }
            guard fleetLink.isGuardianManagedSitlStream(vehicleID: vid) else { continue }
            let stack = fleetLink.vehicleModel(forVehicleID: vid)?.data.telemetry?.autopilotStack
                ?? fleetLink.hubTelemetry(forVehicleID: vid)?.autopilotStack
                ?? .unknown
            guard stack != .unknown else { continue }
            if seen.insert(vid).inserted {
                rows.append((vid, assignment))
            }
        }
        return rows
    }

    /// After ``markCompleted`` notification: **Phase A** — waved MAVSDK ``Action/kill`` (force disarm) on every connected
    /// Guardian-managed SITL (manual stream stop first), **once per physical stream**; then **mission clear**, **geofence clear**,
    /// optional **teleport** (not gated on kill success), and **SIM battery** on the cleanup union in **waves** of up to
    /// ``MissionRunSimCleanupConcurrency/maxConcurrentPerWave`` (default **20**; override with ``MissionRunSimCleanupConcurrency/envKey``).
    ///
    /// A short settle delay runs after the kill wave before mission clear so stacks can finish disarm transitions.
    ///
    /// When there is no mission/geofence/battery/teleport work but Guardian SITL sessions exist, still runs **kill-only** (SIM-only hard stop).
    ///
    /// May also be invoked manually from Mission Control Setup (**Tasks** tab) while simulation is enabled.
    func scheduleMissionRunSimCleanupIfNeeded() {
        guard let fleetLink, let sitl else { return }
        Task { @MainActor in
            await performMissionRunSimCleanupPassIfNeeded(fleetLink: fleetLink, sitl: sitl)
        }
    }

    /// Shared implementation for operator-scheduled cleanup. Run **removal** uses
    /// ``MissionRunEnvironment/hardStopAndRemoveAllRunBoundSitlsForDeletion`` instead (see ``MissionControlStore/deleteRun``).
    func performMissionRunSimCleanupPassIfNeeded(fleetLink: FleetLinkService, sitl: SitlService) async {
        let targets = MissionRunSimCleanupParkPolicy.orderedCleanupParkTargets(
            assignments: assignments,
            reservePoolByTaskID: reservePoolByTaskID,
            fleetLink: fleetLink,
            sitl: sitl
        )

        let rosterSnapshots = rosterSimStartPoseSnapshotByAssignmentID
        let poolSnapshots = reservePoolSimStartPoseSnapshotBySlotID
        let shouldTeleport = MissionRunSimHomeRestorePolicy.shouldScheduleAfterMarkCompleted(
            completionKind: completionKind,
            settingsEnabled: operatorDisplaySettings.resetSimToStartPoseOnSuccessfulComplete,
            snapshotsNonEmpty: !rosterSnapshots.isEmpty || !poolSnapshots.isEmpty,
            hasFleetAndSitl: true
        )

        let cleanupRows = runCompleteSimCleanupUnionVehicleRows(
            policyTargets: targets,
            shouldTeleport: shouldTeleport,
            rosterSnapshots: rosterSnapshots,
            poolSnapshots: poolSnapshots,
            fleetLink: fleetLink,
            sitl: sitl
        )

        let killVehicleIDs = fleetLink.guardianManagedSitlSessionVehicleIDsSorted()
        let downstreamWork = !cleanupRows.isEmpty || shouldTeleport
        let killOnlyPass = !downstreamWork
        if killOnlyPass, killVehicleIDs.isEmpty { return }

        guard !isMissionRunSimCleanupPassRunning else {
            GuardianMissionRunSimCleanupOperatorToastNotification.post(
                message: "SIM cleanup is already running.",
                severity: .info
            )
            return
        }

        setMissionRunSimCleanupPassRunning(true)
        defer { setMissionRunSimCleanupPassRunning(false) }
        let waveLimit = MissionRunSimCleanupConcurrency.maxConcurrentPerWave

        if !killOnlyPass {
            let completionLabel = self.completionKind.map(\.rawValue) ?? "none"
            self.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.lifecycleSimCleanupRunStarted,
                templateParams: [
                    "sitlKill": "\(killVehicleIDs.count)",
                    "teleport": shouldTeleport ? "on" : "off",
                    "union": "\(cleanupRows.count)",
                    "completion": completionLabel,
                ]
            )
        }

        var killSucceeded = 0
        var killFailed = 0
        var killWaveStart = 0
        while killWaveStart < killVehicleIDs.count {
            let killWaveEnd = min(killWaveStart + waveLimit, killVehicleIDs.count)
            let killWave = Array(killVehicleIDs[killWaveStart..<killWaveEnd])
            var killTasks: [Task<FleetLinkService.RunCleanupSimKillOutcome, Never>] = []
            killTasks.reserveCapacity(killWave.count)
            for vehicleID in killWave {
                killTasks.append(Task {
                    await fleetLink.performRunCleanupSimKill(vehicleID: vehicleID)
                })
            }
            for task in killTasks {
                switch await task.value {
                case .skippedNoSession:
                    break
                case .succeeded:
                    killSucceeded += 1
                case .failed:
                    killFailed += 1
                }
            }
            killWaveStart = killWaveEnd
        }

        let killAttempted = killSucceeded + killFailed
        if killAttempted > 0 {
            self.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.guardianSitlKillPassAfterRunCompleted,
                templateParams: ["vehicleCount": "\(killAttempted)"]
            )
        }

        if killAttempted > 0 {
            self.systems.logging.appendLogEvent(
                level: killFailed > 0 ? .warning : .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.lifecycleSimCleanupKillBatch,
                templateParams: [
                    "attempted": "\(killAttempted)",
                    "succeeded": "\(killSucceeded)",
                    "failed": "\(killFailed)",
                ]
            )
        }

        if killOnlyPass {
            return
        }

        try? await Task.sleep(nanoseconds: 300_000_000)

        var missionClearCommands: [MissionRunIssuedCommand] = []
        missionClearCommands.reserveCapacity(cleanupRows.count)
        for (_, assignment) in cleanupRows {
            guard let clearIssued = MissionRunPlannerSubsystem.catalogueMissionClearCommand(
                forAssignment: assignment,
                issuerKey: MissionRunCommandIssuerKey.runCleanupMissionClear
            ) else { continue }
            missionClearCommands.append(clearIssued)
        }
        var missionClearIssued = 0
        var clearWaveStart = 0
        while clearWaveStart < missionClearCommands.count {
            let clearWaveEnd = min(clearWaveStart + waveLimit, missionClearCommands.count)
            let clearWave = Array(missionClearCommands[clearWaveStart..<clearWaveEnd])
            var clearTasks: [Task<Void, Never>] = []
            clearTasks.reserveCapacity(clearWave.count)
            for issued in clearWave {
                let cmd = issued
                clearTasks.append(Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = await self.systems.commands.awaitCatalogueMissionClearDispatchAndAckLogs(
                        issued: cmd,
                        fleetLink: fleetLink,
                        sitl: sitl
                    )
                })
            }
            for task in clearTasks {
                await task.value
            }
            missionClearIssued += clearWave.count
            clearWaveStart = clearWaveEnd
        }

        var geofenceClearCommands: [MissionRunIssuedCommand] = []
        geofenceClearCommands.reserveCapacity(cleanupRows.count)
        for (_, assignment) in cleanupRows {
            guard let geIssued = MissionRunPlannerSubsystem.catalogueGeofenceClearCommand(
                forAssignment: assignment,
                issuerKey: MissionRunCommandIssuerKey.runCleanupGeofenceClear
            ) else { continue }
            geofenceClearCommands.append(geIssued)
        }
        var geofenceClearIssued = 0
        var geofenceWaveStart = 0
        while geofenceWaveStart < geofenceClearCommands.count {
            let geofenceWaveEnd = min(geofenceWaveStart + waveLimit, geofenceClearCommands.count)
            let geofenceWave = Array(geofenceClearCommands[geofenceWaveStart..<geofenceWaveEnd])
            var geofenceTasks: [Task<Void, Never>] = []
            geofenceTasks.reserveCapacity(geofenceWave.count)
            for issued in geofenceWave {
                let cmd = issued
                geofenceTasks.append(Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = await self.systems.commands.awaitCatalogueDispatchAndAckLogs(
                        issued: cmd,
                        fleetLink: fleetLink,
                        sitl: sitl
                    )
                })
            }
            for task in geofenceTasks {
                await task.value
            }
            geofenceClearIssued += geofenceWave.count
            geofenceWaveStart = geofenceWaveEnd
        }

        var rosterTele = (applied: 0, skipped: 0)
        var poolTele = (applied: 0, skipped: 0)
        if shouldTeleport {
            rosterTele = await self.performRosterSimHomeRestoreAfterSuccessfulCompletion(
                snapshots: rosterSnapshots,
                fleetLink: fleetLink,
                sitl: sitl,
                skipVehicleIDs: []
            )
            poolTele = await self.performReservePoolSimHomeRestoreAfterSuccessfulCompletion(
                snapshots: poolSnapshots,
                fleetLink: fleetLink,
                sitl: sitl,
                skipVehicleIDs: []
            )
        }

        var batteryWork: [(vehicleID: String, stack: FleetAutopilotStack)] = []
        batteryWork.reserveCapacity(cleanupRows.count)
        for (vid, _) in cleanupRows {
            let stack = fleetLink.vehicleModel(forVehicleID: vid)?.data.telemetry?.autopilotStack
                ?? fleetLink.hubTelemetry(forVehicleID: vid)?.autopilotStack
                ?? .unknown
            guard stack != .unknown else { continue }
            batteryWork.append((vid, stack))
        }
        var batteryVehicles = 0
        var batteryWaveStart = 0
        while batteryWaveStart < batteryWork.count {
            let batteryWaveEnd = min(batteryWaveStart + waveLimit, batteryWork.count)
            let batteryWave = Array(batteryWork[batteryWaveStart..<batteryWaveEnd])
            var batteryTasks: [Task<Void, Never>] = []
            batteryTasks.reserveCapacity(batteryWave.count)
            for row in batteryWave {
                let vid = row.vehicleID
                let stack = row.stack
                batteryTasks.append(Task { @MainActor in
                    await fleetLink.applySimBatteryFullChargeAfterRunCleanup(
                        vehicleID: vid,
                        autopilotStack: stack,
                        source: "missioncontrol.run_complete_sim_cleanup.battery_full"
                    )
                })
            }
            for task in batteryTasks {
                await task.value
            }
            batteryVehicles += batteryWave.count
            batteryWaveStart = batteryWaveEnd
        }

        let finishedLevel: MissionRunEventLevel = killFailed > 0 ? .warning : .info
        self.systems.logging.appendLogEvent(
            level: finishedLevel,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.lifecycleSimCleanupRunFinished,
            templateParams: [
                "killAttempted": "\(killAttempted)",
                "killFailed": "\(killFailed)",
                "missionClear": "\(missionClearIssued)",
                "geofenceClear": "\(geofenceClearIssued)",
                "rTeleApplied": "\(rosterTele.applied)",
                "rTeleSkipped": "\(rosterTele.skipped)",
                "pTeleApplied": "\(poolTele.applied)",
                "pTeleSkipped": "\(poolTele.skipped)",
                "battery": "\(batteryVehicles)",
            ]
        )

        if let toast = MissionRunSimCleanupOperatorToastCopy.partialFailureMessage(
            simKillFailedCount: killFailed,
            shouldTeleport: shouldTeleport,
            rosterSnapshotCount: rosterSnapshots.count,
            rosterSkipped: rosterTele.skipped,
            poolSnapshotCount: poolSnapshots.count,
            poolSkipped: poolTele.skipped
        ) {
            GuardianMissionRunSimCleanupOperatorToastNotification.post(message: toast, severity: .warning)
        }
    }
}
