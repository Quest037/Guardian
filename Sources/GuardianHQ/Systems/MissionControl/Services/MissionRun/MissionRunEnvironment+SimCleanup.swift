import Foundation

extension MissionRunEnvironment {
    /// Park targets plus roster / pool snapshot rows (when teleport will run) so **mission clear** and **battery reset** cover the same SITLs as ``applySimState`` home restore.
    fileprivate func runCompleteSimCleanupUnionVehicleRows(
        parkTargets: [(vehicleID: String, assignment: MissionRunAssignment)],
        shouldTeleport: Bool,
        rosterSnapshots: [UUID: FleetSimState],
        poolSnapshots: [UUID: FleetSimState],
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> [(vehicleID: String, assignment: MissionRunAssignment)] {
        var rows = parkTargets
        var seen = Set(parkTargets.map(\.0))
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

    /// After ``markCompleted`` notification: **Phase A motion damp** (best-effort manual stream stop, mission pause, offboard stop)
    /// on every connected Guardian-managed SITL **before** the park recipe; then **park**, **mission clear**, and **SIM battery** steps on the cleanup union
    /// in **waves** of up to ``MissionRunSimCleanupConcurrency/maxConcurrentPerWave`` concurrent awaits per wave (default **20**; override with
    /// ``MissionRunSimCleanupConcurrency/envKey``). Park has no ``MissionRunCompletionKind`` gate.
    /// Optional roster then pool **teleport** when policy allows. Emits **started** and **finished**
    /// summary log lines for the full cleanup pass (motion-only runs log ``MissionRunLogTemplateKey/guardianSitlMotionStopPassAfterRunCompleted`` only).
    ///
    /// When there are no park targets and teleport is off, still schedules a **motion-only** pass if any Guardian SITL session exists.
    ///
    /// May also be invoked manually from Mission Control Setup (**Tasks** tab) while simulation is enabled.
    func scheduleMissionRunSimCleanupIfNeeded() {
        guard let fleetLink, let sitl else { return }

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
            parkTargets: targets,
            shouldTeleport: shouldTeleport,
            rosterSnapshots: rosterSnapshots,
            poolSnapshots: poolSnapshots,
            fleetLink: fleetLink,
            sitl: sitl
        )

        let motionVehicleIDs = fleetLink.guardianManagedSitlSessionVehicleIDsSorted()
        let motionOnlyCleanup = targets.isEmpty && !shouldTeleport
        if motionOnlyCleanup, motionVehicleIDs.isEmpty { return }

        guard !isMissionRunSimCleanupPassRunning else {
            GuardianMissionRunSimCleanupOperatorToastNotification.post(
                message: "SIM cleanup is already running.",
                severity: .info
            )
            return
        }

        setMissionRunSimCleanupPassRunning(true)
        Task { @MainActor in
            defer { setMissionRunSimCleanupPassRunning(false) }
            let motionIDsForPass = fleetLink.guardianManagedSitlSessionVehicleIDsSorted()
            let motionCount = await fleetLink.awaitGuardianSitlMotionStopAfterMissionRunCompleted(vehicleIDs: motionIDsForPass)
            if motionCount > 0 {
                self.systems.logging.appendLogEvent(
                    level: .info,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.guardianSitlMotionStopPassAfterRunCompleted,
                    templateParams: ["vehicleCount": "\(motionCount)"]
                )
            }

            if motionOnlyCleanup {
                return
            }

            let completionLabel = self.completionKind.map(\.rawValue) ?? "none"
            self.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.lifecycleSimCleanupRunStarted,
                templateParams: [
                    "park": "\(targets.count)",
                    "teleport": shouldTeleport ? "on" : "off",
                    "union": "\(cleanupRows.count)",
                    "completion": completionLabel,
                ]
            )

            let waveLimit = MissionRunSimCleanupConcurrency.maxConcurrentPerWave
            var parkFailedVehicleIDs = Set<String>()
            var parkItems: [(vehicleID: String, issued: MissionRunIssuedCommand)] = []
            parkItems.reserveCapacity(targets.count)
            for (vehicleID, assignment) in targets {
                guard let tokenKey = assignment.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !tokenKey.isEmpty
                else { continue }

                let issued = MissionRunIssuedCommand(
                    assignmentID: assignment.id,
                    slotName: assignment.slotName,
                    vehicleTokenKey: tokenKey,
                    dispatch: .recipe(
                        name: FleetMissionRecipeRegistrations.vehicleDoParkRecipeName,
                        parameters: .empty
                    ),
                    issuer: .missionControl,
                    issuerKey: MissionRunCommandIssuerKey.runCleanupPark
                )
                parkItems.append((vehicleID, issued))
            }
            var parkWaveStart = 0
            while parkWaveStart < parkItems.count {
                let parkWaveEnd = min(parkWaveStart + waveLimit, parkItems.count)
                let parkWave = Array(parkItems[parkWaveStart..<parkWaveEnd])
                var parkTasks: [Task<(String, Bool), Never>] = []
                parkTasks.reserveCapacity(parkWave.count)
                for item in parkWave {
                    let vehicleID = item.vehicleID
                    let issued = item.issued
                    parkTasks.append(Task { @MainActor [weak self] in
                        guard let self else { return (vehicleID, false) }
                        let ok = await self.systems.commands.awaitRecipeDispatchAppendingDispatchedThenAckLogs(
                            issued: issued,
                            fleetLink: fleetLink,
                            sitl: sitl
                        )
                        return (vehicleID, ok)
                    })
                }
                for task in parkTasks {
                    let (vid, ok) = await task.value
                    if !ok { parkFailedVehicleIDs.insert(vid) }
                }
                parkWaveStart = parkWaveEnd
            }

            if !targets.isEmpty {
                let failed = parkFailedVehicleIDs.count
                let ok = targets.count - failed
                self.systems.logging.appendLogEvent(
                    level: failed > 0 ? .warning : .info,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.lifecycleSimCleanupParkBatch,
                    templateParams: [
                        "attempted": "\(targets.count)",
                        "succeeded": "\(ok)",
                        "failed": "\(failed)",
                    ]
                )
            }

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

            var rosterTele = (applied: 0, skipped: 0)
            var poolTele = (applied: 0, skipped: 0)
            if shouldTeleport {
                rosterTele = await self.performRosterSimHomeRestoreAfterSuccessfulCompletion(
                    snapshots: rosterSnapshots,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    skipVehicleIDs: parkFailedVehicleIDs
                )
                poolTele = await self.performReservePoolSimHomeRestoreAfterSuccessfulCompletion(
                    snapshots: poolSnapshots,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    skipVehicleIDs: parkFailedVehicleIDs
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

            let parkFailedCount = parkFailedVehicleIDs.count
            let parkAttempted = targets.count
            let finishedLevel: MissionRunEventLevel = parkFailedCount > 0 ? .warning : .info
            self.systems.logging.appendLogEvent(
                level: finishedLevel,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.lifecycleSimCleanupRunFinished,
                templateParams: [
                    "parkAttempted": "\(parkAttempted)",
                    "parkFailed": "\(parkFailedCount)",
                    "missionClear": "\(missionClearIssued)",
                    "rTeleApplied": "\(rosterTele.applied)",
                    "rTeleSkipped": "\(rosterTele.skipped)",
                    "pTeleApplied": "\(poolTele.applied)",
                    "pTeleSkipped": "\(poolTele.skipped)",
                    "battery": "\(batteryVehicles)",
                ]
            )

            if let toast = MissionRunSimCleanupOperatorToastCopy.partialFailureMessage(
                parkFailedCount: parkFailedCount,
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
}
