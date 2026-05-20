import Foundation

/// Resolved start pose for one Training lab roster row (SITL + optional Gazebo proxy).
struct TrainingLabMapSessionVehicleStart: Equatable, Sendable {
    let entryID: UUID
    let vehicleID: String
    let mavlinkSystemID: Int
    let taskPose: TrainingTaskPose
    let environmentPose: TrainingEnvironmentPose
    let vehicleClass: FleetVehicleType
    let vehicleSizeTier: VehicleSizeTier
    /// Index in ``TrainingLabMapSessionContext/squads`` for ``TrainingLabSquadFormationPalette`` tint.
    let squadIndex: Int
}

/// Inputs for ``TrainingLabMapSessionLifecycle`` (run **buildMap** / **resetMap**).
@MainActor
struct TrainingLabMapSessionContext {
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let gazebo: GazeboService?
    /// Operator sim defaults (battery seed, etc.).
    let spawnDefaults: SimSpawnDefaults
    /// Map-local WGS84 origin for ENU ↔ lat/lon (see ``TrainingEnvironmentGeodesy/mapSessionOrigin``).
    let mapGeodeticOrigin: SimSpawnDefaults
    let simulationPlatform: SimulationPlatform
    let activeGazeboWorldID: UUID?
    let environment: TrainingEnvironmentPackage?
    let squads: [TrainingLabSquad]
    let learningSquadID: UUID?
    /// When the learning squad is a single vehicle, prefer task layout start over manifest spawn.
    let learningSquadSingleVehicleStart: TrainingTaskPose?
    /// Optional sink for Training **Run** / Logs rail diagnostics (`[Map]` prefix applied by caller).
    var log: TrainingLabMapSessionDiagnostics.LogHandler?
}

/// Training lab map session: park/disarm sims, teleport to starts, add/remove Gazebo vehicle proxies.
enum TrainingLabMapSessionLifecycle {
    private static let applySource = "training.lab.map_session"
    private static let squadPrimaryStaggerM = 12.0

    static func mapGeodeticOrigin(
        environment: TrainingEnvironmentPackage,
        spawnDefaults: SimSpawnDefaults
    ) -> SimSpawnDefaults {
        TrainingEnvironmentGeodesy.mapSessionOrigin(
            manifest: environment.manifest,
            fallback: spawnDefaults
        )
    }

    /// Start-slot ENU pose for a roster row before its SITL exists (spawn alignment).
    @MainActor
    static func startEnvironmentPoseForPendingEntry(
        squad: TrainingLabSquad,
        squadIndex: Int,
        entryIndex: Int,
        environment: TrainingEnvironmentPackage,
        mapGeodeticOrigin: SimSpawnDefaults,
        learningSquadID: UUID?,
        learningSquadSingleVehicleStart: TrainingTaskPose?
    ) -> TrainingEnvironmentPose {
        let zones = WorldBuilderZoneManifestSupport.zones(from: environment.manifest)
        let useFormationSlots = zones.start.placed
        let isLearningSquad = learningSquadID == squad.id

        if useFormationSlots {
            let anchor = squad.startZoneAnchor ?? .seeded(in: zones.start)
            let layout = TrainingLabFormationSlotGeometry.groupLayout(
                squad: squad,
                squadIndex: squadIndex,
                phase: .start,
                anchor: anchor
            )
            guard entryIndex < layout.slots.count else {
                return manifestFallbackStart(environment: environment, squadIndex: squadIndex)
            }
            let slot = layout.slots[entryIndex]
            return TrainingEnvironmentPose(
                xM: slot.centerXM,
                yM: slot.centerYM,
                zM: WorldBuilderZoneBoundsCheck.mapBaseTopZM,
                yawDeg: slot.headingDeg
            )
        }

        if entryIndex == 0 {
            var primaryEnv = staggeredPrimaryEnvironmentPose(
                manifest: environment.manifest,
                squadIndex: squadIndex
            )
            if !useFormationSlots,
               squad.isSingleVehicle,
               isLearningSquad,
               let override = learningSquadSingleVehicleStart {
                return TrainingEnvironmentGeodesy.environmentPose(
                    taskPose: override,
                    origin: mapGeodeticOrigin
                )
            }
            return primaryEnv
        }

        let primaryEnv = staggeredPrimaryEnvironmentPose(
            manifest: environment.manifest,
            squadIndex: squadIndex
        )
        let primaryTask = TrainingEnvironmentGeodesy.taskPose(
            environmentPose: primaryEnv,
            origin: mapGeodeticOrigin
        )
        let formation = squad.formationPolicy.startFormation
        let formationSpacing = squad.formationPolicy.startSpacing
        let convoySpacing = MissionSquadConvoySpacingPolicy.resolvedSpacing(
            taskPattern: .convoy,
            primaryGranularClass: squad.primary.vehicleClass.fleetVehicleType,
            spacing: formationSpacing,
            formation: formation
        )
        let wingIndex = entryIndex - 1
        let pad = Utilities.mission.squadFormation.desiredPadSlot(
            formation: formation,
            primaryLatitudeDeg: primaryTask.latitudeDeg,
            primaryLongitudeDeg: primaryTask.longitudeDeg,
            primaryHeadingDeg: primaryTask.headingDeg,
            wingmanOrdinal: wingIndex,
            spacing: convoySpacing
        )
        return TrainingEnvironmentGeodesy.environmentPose(
            taskPose: TrainingTaskPose(
                latitudeDeg: pad.lat,
                longitudeDeg: pad.lon,
                headingDeg: primaryTask.headingDeg,
                absoluteAltitudeM: primaryTask.absoluteAltitudeM
            ),
            origin: mapGeodeticOrigin
        )
    }

    private static func manifestFallbackStart(
        environment: TrainingEnvironmentPackage,
        squadIndex: Int
    ) -> TrainingEnvironmentPose {
        staggeredPrimaryEnvironmentPose(manifest: environment.manifest, squadIndex: squadIndex)
    }

    @MainActor
    static func resolveStartPoses(
        squads: [TrainingLabSquad],
        environment: TrainingEnvironmentPackage,
        mapGeodeticOrigin: SimSpawnDefaults,
        sitlInstances: [SitlRunningInstance],
        learningSquadID: UUID?,
        learningSquadSingleVehicleStart: TrainingTaskPose?
    ) -> [TrainingLabMapSessionVehicleStart] {
        let zones = WorldBuilderZoneManifestSupport.zones(from: environment.manifest)
        let useFormationSlots = zones.start.placed
        var out: [TrainingLabMapSessionVehicleStart] = []
        for (squadIndex, squad) in squads.enumerated() {
            let isLearningSquad = learningSquadID == squad.id
                || (learningSquadID == nil && squadIndex == 0)

            if useFormationSlots {
                let anchor = squad.startZoneAnchor ?? .seeded(in: zones.start)
                let layout = TrainingLabFormationSlotGeometry.groupLayout(
                    squad: squad,
                    squadIndex: squadIndex,
                    phase: .start,
                    anchor: anchor
                )
                for (index, entry) in squad.allEntries.enumerated() {
                    guard index < layout.slots.count,
                          let slotState = entry.slotState,
                          let vehicleID = slotState.vehicleID,
                          let mavlinkSystemID = mavlinkSystemID(instances: sitlInstances, slot: slotState)
                    else { continue }
                    let slot = layout.slots[index]
                    let envPose = TrainingEnvironmentPose(
                        xM: slot.centerXM,
                        yM: slot.centerYM,
                        zM: WorldBuilderZoneBoundsCheck.mapBaseTopZM,
                        yawDeg: slot.headingDeg
                    )
                    let taskPose = TrainingEnvironmentGeodesy.taskPose(
                        environmentPose: envPose,
                        origin: mapGeodeticOrigin
                    )
                    out.append(
                        TrainingLabMapSessionVehicleStart(
                            entryID: entry.id,
                            vehicleID: vehicleID,
                            mavlinkSystemID: mavlinkSystemID,
                            taskPose: taskPose,
                            environmentPose: envPose,
                            vehicleClass: entry.vehicleClass.fleetVehicleType,
                            vehicleSizeTier: entry.vehicleSizeTier,
                            squadIndex: squadIndex
                        )
                    )
                }
                continue
            }

            let primaryEnv = staggeredPrimaryEnvironmentPose(
                manifest: environment.manifest,
                squadIndex: squadIndex
            )
            var primaryTask = TrainingEnvironmentGeodesy.taskPose(
                environmentPose: primaryEnv,
                origin: mapGeodeticOrigin
            )
            if !useFormationSlots,
               squad.isSingleVehicle,
               isLearningSquad,
               let override = learningSquadSingleVehicleStart {
                primaryTask = override
            }

            if let slot = squad.primary.slotState,
               let vehicleID = slot.vehicleID,
               let mavlinkSystemID = mavlinkSystemID(instances: sitlInstances, slot: slot) {
                out.append(
                    TrainingLabMapSessionVehicleStart(
                        entryID: squad.primary.id,
                        vehicleID: vehicleID,
                        mavlinkSystemID: mavlinkSystemID,
                        taskPose: primaryTask,
                        environmentPose: TrainingEnvironmentGeodesy.environmentPose(
                            taskPose: primaryTask,
                            origin: mapGeodeticOrigin
                        ),
                        vehicleClass: squad.primary.vehicleClass.fleetVehicleType,
                        vehicleSizeTier: squad.primary.vehicleSizeTier,
                        squadIndex: squadIndex
                    )
                )
            }

            let formation = squad.formationPolicy.startFormation
            let formationSpacing = squad.formationPolicy.startSpacing
            let convoySpacing = MissionSquadConvoySpacingPolicy.resolvedSpacing(
                taskPattern: .convoy,
                primaryGranularClass: squad.primary.vehicleClass.fleetVehicleType,
                spacing: formationSpacing,
                formation: formation
            )
            for (wingIndex, wingman) in squad.wingmen.enumerated() {
                guard let slot = wingman.slotState,
                      let vehicleID = slot.vehicleID,
                      let mavlinkSystemID = mavlinkSystemID(instances: sitlInstances, slot: slot)
                else { continue }
                let pad = Utilities.mission.squadFormation.desiredPadSlot(
                    formation: formation,
                    primaryLatitudeDeg: primaryTask.latitudeDeg,
                    primaryLongitudeDeg: primaryTask.longitudeDeg,
                    primaryHeadingDeg: primaryTask.headingDeg,
                    wingmanOrdinal: wingIndex,
                    spacing: convoySpacing
                )
                let wingTask = TrainingTaskPose(
                    latitudeDeg: pad.lat,
                    longitudeDeg: pad.lon,
                    headingDeg: primaryTask.headingDeg,
                    absoluteAltitudeM: primaryTask.absoluteAltitudeM
                )
                out.append(
                    TrainingLabMapSessionVehicleStart(
                        entryID: wingman.id,
                        vehicleID: vehicleID,
                        mavlinkSystemID: mavlinkSystemID,
                        taskPose: wingTask,
                        environmentPose: TrainingEnvironmentGeodesy.environmentPose(
                            taskPose: wingTask,
                            origin: mapGeodeticOrigin
                        ),
                        vehicleClass: wingman.vehicleClass.fleetVehicleType,
                        vehicleSizeTier: wingman.vehicleSizeTier,
                        squadIndex: squadIndex
                    )
                )
            }
        }
        return out
    }

    @MainActor
    static func resetMap(context: TrainingLabMapSessionContext) async {
        log(context, "resetMap begin — \(TrainingLabMapSessionDiagnostics.contextSummary(context))")
        let vehicles = linkedVehicles(context: context, log: context.log)
        guard !vehicles.isEmpty else {
            log(context, "resetMap: no linked vehicles — removing any Gazebo proxies.")
            await removeAllGazeboProxies(context: context, log: context.log)
            return
        }
        log(context, "resetMap: \(vehicles.count) linked vehicle(s).")

        for row in vehicles {
            await quiesceVehicle(row.vehicleID, fleetLink: context.fleetLink)
        }
        for row in vehicles {
            await applyStartPose(row, context: context)
        }
        await removeAllGazeboProxies(context: context, log: context.log)
        log(context, "resetMap complete.")
    }

    @MainActor
    static func buildMap(context: TrainingLabMapSessionContext) async {
        log(context, "buildMap begin — \(TrainingLabMapSessionDiagnostics.contextSummary(context))")
        let vehicles = linkedVehicles(context: context, log: context.log)
        guard !vehicles.isEmpty else {
            log(
                context,
                "buildMap aborted: no linked vehicles (check squads have sims with vehicleID + sitl session)."
            )
            diagnoseUnlinkedRoster(context: context)
            return
        }
        log(context, "buildMap: resolved \(vehicles.count) vehicle start pose(s).")

        for row in vehicles {
            await applyStartPose(row, context: context)
        }
        await removeAllGazeboProxies(context: context, log: context.log)
        await spawnGazeboProxies(vehicles: vehicles, context: context)
        log(context, "buildMap complete.")
    }

    @MainActor
    private static func diagnoseUnlinkedRoster(context: TrainingLabMapSessionContext) {
        let zones = context.environment.map {
            WorldBuilderZoneManifestSupport.zones(from: $0.manifest)
        }
        for (squadIndex, squad) in context.squads.enumerated() {
            for (entryIndex, entry) in squad.allEntries.enumerated() {
                let label = entryIndex == 0 && squad.primary.id == entry.id ? "primary" : "wingman"
                guard let slot = entry.slotState else {
                    log(context, "  squad[\(squadIndex)] \(label): no slotState.")
                    continue
                }
                guard let vehicleID = slot.vehicleID else {
                    log(context, "  squad[\(squadIndex)] \(label): slot has no vehicleID (link pending?).")
                    continue
                }
                guard slot.sitlSessionID != nil else {
                    log(context, "  squad[\(squadIndex)] \(label) \(vehicleID): no sitlSessionID.")
                    continue
                }
                let sysid = mavlinkSystemID(instances: context.sitl.instances, slot: slot)
                if sysid == nil {
                    log(context, "  squad[\(squadIndex)] \(label) \(vehicleID): sitl session not in SitlService.instances.")
                    continue
                }
                if zones?.start.placed != true {
                    log(context, "  squad[\(squadIndex)] \(label) \(vehicleID): start zone not placed on map.")
                }
            }
        }
    }

    @MainActor
    private static func log(_ context: TrainingLabMapSessionContext, _ message: String) {
        TrainingLabMapSessionDiagnostics.log(context.log, message)
    }

    /// Teleport one linked roster row to its resolved start slot (SITL only — no Gazebo proxy).
    @MainActor
    static func positionVehicleAtStart(entryID: UUID, context: TrainingLabMapSessionContext) async {
        guard let environment = context.environment else { return }
        let vehicles = resolveStartPoses(
            squads: context.squads,
            environment: environment,
            mapGeodeticOrigin: context.mapGeodeticOrigin,
            sitlInstances: context.sitl.instances,
            learningSquadID: context.learningSquadID,
            learningSquadSingleVehicleStart: context.learningSquadSingleVehicleStart
        )
        guard let row = vehicles.first(where: { $0.entryID == entryID }) else { return }
        await applyStartPose(row, context: context)
    }

    /// Environment pose for a roster row's start slot (Gazebo proxy / placement hints).
    @MainActor
    static func startEnvironmentPose(
        entryID: UUID,
        context: TrainingLabMapSessionContext
    ) -> TrainingEnvironmentPose? {
        guard let environment = context.environment else { return nil }
        let vehicles = resolveStartPoses(
            squads: context.squads,
            environment: environment,
            mapGeodeticOrigin: context.mapGeodeticOrigin,
            sitlInstances: context.sitl.instances,
            learningSquadID: context.learningSquadID,
            learningSquadSingleVehicleStart: context.learningSquadSingleVehicleStart
        )
        return vehicles.first(where: { $0.entryID == entryID })?.environmentPose
    }

    // MARK: - Private

    private static func staggeredPrimaryEnvironmentPose(
        manifest: TrainingEnvironmentManifest,
        squadIndex: Int
    ) -> TrainingEnvironmentPose {
        guard squadIndex > 0 else { return manifest.defaultSpawn }
        var pose = manifest.defaultSpawn
        let staggerM = Double(squadIndex) * squadPrimaryStaggerM
        let yawRad = pose.yawDeg * .pi / 180
        pose.xM -= sin(yawRad) * staggerM
        pose.yM -= cos(yawRad) * staggerM
        return pose
    }

    private static func mavlinkSystemID(
        instances: [SitlRunningInstance],
        slot: FormationsPlaygroundSlotState
    ) -> Int? {
        instances.first(where: { $0.id == slot.sitlSessionID })?.mavlinkSystemID
    }

    @MainActor
    private static func linkedVehicles(
        context: TrainingLabMapSessionContext,
        log: TrainingLabMapSessionDiagnostics.LogHandler? = nil
    ) -> [TrainingLabMapSessionVehicleStart] {
        guard let environment = context.environment else {
            TrainingLabMapSessionDiagnostics.log(log, "linkedVehicles: no environment package.")
            return []
        }
        return resolveStartPoses(
            squads: context.squads,
            environment: environment,
            mapGeodeticOrigin: context.mapGeodeticOrigin,
            sitlInstances: context.sitl.instances,
            learningSquadID: context.learningSquadID,
            learningSquadSingleVehicleStart: context.learningSquadSingleVehicleStart
        )
    }

    @MainActor
    private static func quiesceVehicle(_ vehicleID: String, fleetLink: FleetLinkService) async {
        guard fleetLink.isGuardianManagedSitlStream(vehicleID: vehicleID) else { return }
        await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)
        await fleetLink.stopFormationFollowStream(vehicleID: vehicleID)
        await fleetLink.awaitLiveDriveSurfaceParkHoldAndDisarm(vehicleID: vehicleID)
    }

    @MainActor
    private static func applyStartPose(
        _ row: TrainingLabMapSessionVehicleStart,
        context: TrainingLabMapSessionContext
    ) async {
        guard context.fleetLink.isGuardianManagedSitlStream(vehicleID: row.vehicleID) else {
            log(
                context,
                "SITL pose skipped \(row.vehicleID) sysid=\(row.mavlinkSystemID): not a Guardian-managed sim stream."
            )
            return
        }
        log(
            context,
            "SITL pose \(row.vehicleID) sysid=\(row.mavlinkSystemID) — \(TrainingLabMapSessionDiagnostics.formatPose(row.environmentPose)); \(TrainingLabMapSessionDiagnostics.formatTaskPose(row.taskPose))"
        )
        context.fleetLink.clearPendingSpawnSimState(forVehicleID: row.vehicleID)
        let hub = context.fleetLink.hubTelemetry(forVehicleID: row.vehicleID)
        let stack = hub?.autopilotStack != .unknown
            ? hub!.autopilotStack
            : FleetAutopilotStack(simulationPlatform: context.simulationPlatform)
        let state = FleetSimState(
            latitudeDeg: row.taskPose.latitudeDeg,
            longitudeDeg: row.taskPose.longitudeDeg,
            absoluteAltitudeM: row.taskPose.absoluteAltitudeM,
            yawDeg: Float(row.taskPose.headingDeg)
        )
        await context.fleetLink.applySimState(
            vehicleID: row.vehicleID,
            state: state,
            autopilotStack: stack,
            source: applySource
        )
    }

    @MainActor
    private static func spawnGazeboProxies(
        vehicles: [TrainingLabMapSessionVehicleStart],
        context: TrainingLabMapSessionContext
    ) async {
        guard let gazebo = context.gazebo else {
            log(context, "Gazebo proxy spawn skipped: GazeboService not attached to Training lab.")
            return
        }
        guard let worldID = context.activeGazeboWorldID else {
            log(context, "Gazebo proxy spawn skipped: activeGazeboWorldID is nil (map world not bound).")
            return
        }
        guard gazebo.isWorldAlive(id: worldID) else {
            log(
                context,
                "Gazebo proxy spawn skipped: world \(worldID.uuidString.prefix(8))… is not alive. \(gazebo.lastError ?? "No error text.")"
            )
            return
        }
        log(context, "Gazebo proxy spawn: world \(worldID.uuidString.prefix(8))…, \(vehicles.count) vehicle(s).")
        var okCount = 0
        for row in vehicles {
            let squadColorHex = TrainingLabSquadFormationPalette.colorHex(squadIndex: row.squadIndex)
            let params = GazeboVehicleSpawnParams(
                vehicleClass: row.vehicleClass,
                vehicleSizeTier: row.vehicleSizeTier,
                pose: row.environmentPose,
                squadColorHex: squadColorHex
            )
            let ok = await gazebo.spawnVehicleProxy(
                worldID: worldID,
                mavlinkSystemID: row.mavlinkSystemID,
                params: params
            )
            if ok {
                okCount += 1
                log(
                    context,
                    "Gazebo proxy OK sysid=\(row.mavlinkSystemID) \(row.vehicleClass.classCode) squadTint=\(squadColorHex) — \(TrainingLabMapSessionDiagnostics.formatPose(row.environmentPose))"
                )
            } else {
                log(
                    context,
                    "Gazebo proxy FAILED sysid=\(row.mavlinkSystemID) — \(gazebo.lastError ?? "unknown error")"
                )
            }
        }
        log(context, "Gazebo proxy spawn finished: \(okCount)/\(vehicles.count) succeeded.")
    }

    @MainActor
    private static func removeAllGazeboProxies(
        context: TrainingLabMapSessionContext,
        log: TrainingLabMapSessionDiagnostics.LogHandler? = nil
    ) async {
        guard let gazebo = context.gazebo else { return }
        var removed = 0
        for squad in context.squads {
            for entry in squad.allEntries {
                guard let sessionID = entry.slotState?.sitlSessionID,
                      let inst = context.sitl.instances.first(where: { $0.id == sessionID })
                else { continue }
                await gazebo.removeVehicleProxy(mavlinkSystemID: inst.mavlinkSystemID)
                removed += 1
            }
        }
        if removed > 0 {
            TrainingLabMapSessionDiagnostics.log(log, "Removed \(removed) Gazebo vehicle proxy(ies).")
        }
    }
}
