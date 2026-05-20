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
}

/// Inputs for ``TrainingLabMapSessionLifecycle`` (run **buildMap** / **resetMap**).
@MainActor
struct TrainingLabMapSessionContext {
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let gazebo: GazeboService?
    let spawnDefaults: SimSpawnDefaults
    let simulationPlatform: SimulationPlatform
    let activeGazeboWorldID: UUID?
    let environment: TrainingEnvironmentPackage?
    let squads: [TrainingLabSquad]
    let learningSquadID: UUID?
    /// When the learning squad is a single vehicle, prefer task layout start over manifest spawn.
    let learningSquadSingleVehicleStart: TrainingTaskPose?
}

/// Training lab map session: park/disarm sims, teleport to starts, add/remove Gazebo vehicle proxies.
enum TrainingLabMapSessionLifecycle {
    private static let applySource = "training.lab.map_session"
    private static let squadPrimaryStaggerM = 12.0

    @MainActor
    static func resolveStartPoses(
        squads: [TrainingLabSquad],
        environment: TrainingEnvironmentPackage,
        spawnDefaults: SimSpawnDefaults,
        sitlInstances: [SitlRunningInstance],
        learningSquadID: UUID?,
        learningSquadSingleVehicleStart: TrainingTaskPose?
    ) -> [TrainingLabMapSessionVehicleStart] {
        let zones = WorldBuilderZoneManifestSupport.zones(from: environment.manifest)
        var out: [TrainingLabMapSessionVehicleStart] = []
        for (squadIndex, squad) in squads.enumerated() {
            let isLearningSquad = learningSquadID == squad.id
                || (learningSquadID == nil && squadIndex == 0)

            if zones.start.placed {
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
                    var envPose = TrainingEnvironmentPose(
                        xM: slot.centerXM,
                        yM: slot.centerYM,
                        zM: WorldBuilderZoneBoundsCheck.mapBaseTopZM,
                        yawDeg: slot.headingDeg
                    )
                    var taskPose = TrainingEnvironmentGeodesy.taskPose(
                        environmentPose: envPose,
                        origin: spawnDefaults
                    )
                    if squad.isSingleVehicle, isLearningSquad, index == 0, let override = learningSquadSingleVehicleStart {
                        taskPose = override
                        envPose = TrainingEnvironmentGeodesy.environmentPose(
                            taskPose: override,
                            origin: spawnDefaults
                        )
                    }
                    out.append(
                        TrainingLabMapSessionVehicleStart(
                            entryID: entry.id,
                            vehicleID: vehicleID,
                            mavlinkSystemID: mavlinkSystemID,
                            taskPose: taskPose,
                            environmentPose: envPose,
                            vehicleClass: entry.vehicleClass.fleetVehicleType,
                            vehicleSizeTier: entry.vehicleSizeTier
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
                origin: spawnDefaults
            )
            if squad.isSingleVehicle, isLearningSquad, let override = learningSquadSingleVehicleStart {
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
                            origin: spawnDefaults
                        ),
                        vehicleClass: squad.primary.vehicleClass.fleetVehicleType,
                        vehicleSizeTier: squad.primary.vehicleSizeTier
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
                            origin: spawnDefaults
                        ),
                        vehicleClass: wingman.vehicleClass.fleetVehicleType,
                        vehicleSizeTier: wingman.vehicleSizeTier
                    )
                )
            }
        }
        return out
    }

    @MainActor
    static func resetMap(context: TrainingLabMapSessionContext) async {
        let vehicles = linkedVehicles(context: context)
        guard !vehicles.isEmpty else {
            await removeAllGazeboProxies(context: context)
            return
        }

        for row in vehicles {
            await quiesceVehicle(row.vehicleID, fleetLink: context.fleetLink)
        }
        for row in vehicles {
            await applyStartPose(row, context: context)
        }
        await removeAllGazeboProxies(context: context)
    }

    @MainActor
    static func buildMap(context: TrainingLabMapSessionContext) async {
        let vehicles = linkedVehicles(context: context)
        guard !vehicles.isEmpty else { return }

        for row in vehicles {
            await applyStartPose(row, context: context)
        }
        await spawnGazeboProxies(vehicles: vehicles, context: context)
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
    private static func linkedVehicles(context: TrainingLabMapSessionContext) -> [TrainingLabMapSessionVehicleStart] {
        guard let environment = context.environment else { return [] }
        return resolveStartPoses(
            squads: context.squads,
            environment: environment,
            spawnDefaults: context.spawnDefaults,
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
        guard context.fleetLink.isGuardianManagedSitlStream(vehicleID: row.vehicleID) else { return }
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
        guard let gazebo = context.gazebo, let worldID = context.activeGazeboWorldID else { return }
        for row in vehicles {
            let params = GazeboVehicleSpawnParams(
                vehicleClass: row.vehicleClass,
                vehicleSizeTier: row.vehicleSizeTier,
                pose: row.environmentPose
            )
            _ = await gazebo.spawnVehicleProxy(
                worldID: worldID,
                mavlinkSystemID: row.mavlinkSystemID,
                params: params
            )
        }
    }

    @MainActor
    private static func removeAllGazeboProxies(context: TrainingLabMapSessionContext) async {
        guard let gazebo = context.gazebo else { return }
        for squad in context.squads {
            for entry in squad.allEntries {
                guard let sessionID = entry.slotState?.sitlSessionID,
                      let inst = context.sitl.instances.first(where: { $0.id == sessionID })
                else { continue }
                await gazebo.removeVehicleProxy(mavlinkSystemID: inst.mavlinkSystemID)
            }
        }
    }
}
