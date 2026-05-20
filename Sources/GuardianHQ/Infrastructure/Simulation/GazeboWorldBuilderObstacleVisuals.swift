import Foundation

extension GazeboService {
    /// Inserts one static obstacle into a running World Builder preview/build world.
    @discardableResult
    func spawnWorldBuilderObstacle(
        worldID: UUID,
        record: TrainingEnvironmentObstacleRecord,
        meshDirectory: URL
    ) async throws -> String {
        guard let row = worlds.first(where: { $0.id == worldID && $0.isAlive }) else {
            throw GazeboEntityFactoryError.serviceFailed("Gazebo world is not running.")
        }
        let written = try TrainingEnvironmentObstacleSDF.writeTemporaryModel(
            record: record,
            meshDirectory: meshDirectory
        )
        let pose = WorldBuilderObstacleManifestSupport.entityFactoryPose(for: record)
        let heightM = WorldBuilderObstacleManifestSupport.orientedExtents(record: record).dz
        try await GazeboEntityFactoryClient.createModel(
            worldName: row.gazeboSDFWorldName,
            instanceIndex: row.instanceIndex,
            sdfURL: written.sdfURL,
            modelName: written.modelName,
            pose: pose,
            footprintHeightM: heightM
        )
        // Harmonic queues creates; a short gap avoids dropped follow-up spawns on the same service.
        try? await Task.sleep(nanoseconds: 250_000_000)
        fleetLink?.appendSimulationLog("Gazebo: placed obstacle \(written.modelName).")
        return written.modelName
    }

    @discardableResult
    func removeWorldBuilderObstacle(
        worldID: UUID,
        gazeboModelName: String,
        obstacleID: String? = nil,
        knownLiveModelNames: [String]? = nil
    ) async -> Bool {
        guard let row = worlds.first(where: { $0.id == worldID && $0.isAlive }) else { return false }
        let removed = await GazeboEntityFactoryClient.removeModel(
            worldName: row.gazeboSDFWorldName,
            instanceIndex: row.instanceIndex,
            gazeboModelName: gazeboModelName,
            obstacleID: obstacleID,
            knownLiveModelNames: knownLiveModelNames
        )
        if removed {
            fleetLink?.appendSimulationLog("Gazebo: removed obstacle \(gazeboModelName).")
        } else {
            fleetLink?.appendSimulationLog(
                "Gazebo: could not remove obstacle \(gazeboModelName) from world \(row.gazeboSDFWorldName)."
            )
        }
        return removed
    }

    @discardableResult
    func repositionWorldBuilderObstacle(
        worldID: UUID,
        record: TrainingEnvironmentObstacleRecord,
        gazeboModelName: String
    ) async -> Bool {
        guard let row = worlds.first(where: { $0.id == worldID && $0.isAlive }) else { return false }
        let pose = WorldBuilderObstacleManifestSupport.entityFactoryPose(for: record)
        let heightM = WorldBuilderObstacleManifestSupport.orientedExtents(record: record).dz
        let moved = await GazeboEntityFactoryClient.setModelPose(
            worldName: row.gazeboSDFWorldName,
            instanceIndex: row.instanceIndex,
            modelName: gazeboModelName,
            pose: pose,
            footprintHeightM: heightM
        )
        if moved {
            fleetLink?.appendSimulationLog("Gazebo: moved obstacle \(gazeboModelName).")
        }
        return moved
    }

    /// Lists sim models once, removes every `guardian_obstacle_*` model (manifest + phantoms), for obstacle repair.
    func stripAllGuardianObstacleModelsFromLiveSim(
        worldID: UUID,
        manifest: [TrainingEnvironmentObstacleRecord]
    ) async -> (removedCount: Int, orphanCount: Int) {
        guard let row = worlds.first(where: { $0.id == worldID && $0.isAlive }) else {
            return (0, 0)
        }
        let liveNames = await GazeboEntityFactoryClient.listWorldModelNames(instanceIndex: row.instanceIndex)
        let guardianNames = liveNames.filter { $0.hasPrefix(TrainingEnvironmentObstacleNaming.modelPrefix) }
        var removedCount = 0
        var orphanCount = 0
        for name in guardianNames {
            let isOrphan = !manifest.contains {
                TrainingEnvironmentObstacleNaming.matchesModelName(name, obstacleID: $0.id)
            }
            if isOrphan { orphanCount += 1 }
            if await GazeboEntityFactoryClient.removeModelOnce(
                worldName: row.gazeboSDFWorldName,
                instanceIndex: row.instanceIndex,
                modelName: name
            ) {
                removedCount += 1
                fleetLink?.appendSimulationLog("Gazebo: removed obstacle \(name).")
            }
        }
        return (removedCount, orphanCount)
    }
}
