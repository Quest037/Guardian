import Foundation

/// How obstacles are embedded when writing `world.sdf`.
enum TrainingEnvironmentWorldCompositionMode: Sendable {
    /// World Builder session: floor only; obstacles are live-spawned from `manifest.json`.
    case builderSession
    /// Training / Formation `.run`: floor plus one baked static obstacle model.
    case trainingRun
}

/// Writes `world.sdf` for a training environment manifest (floor + static obstacles).
enum TrainingEnvironmentWorldComposer {
    static func writeWorld(
        manifest: TrainingEnvironmentManifest,
        to worldURL: URL,
        mode: TrainingEnvironmentWorldCompositionMode = .trainingRun
    ) throws {
        let floor = TrainingEnvironmentFloorSize.resolved(from: manifest.floorSize)
        let scene = TrainingEnvironmentSceneType.resolved(from: manifest.sceneType)
        var prepared = manifest.obstacles
        let floorHalfM = floor.floorSideM / 2
        for index in prepared.indices {
            WorldBuilderObstacleManifestSupport.normalizeDimensions(&prepared[index])
            WorldBuilderObstacleManifestSupport.reclampAutoZ(
                &prepared[index],
                floorHalfM: floorHalfM,
                sceneType: scene
            )
            WorldBuilderObstacleManifestSupport.clampToFloor(&prepared[index], floorHalfM: floorHalfM)
        }
        switch scene {
        case .flat:
            let meshDirectory = worldURL.deletingLastPathComponent()
                .appendingPathComponent("obstacle_meshes", isDirectory: true)
            let obstacleXML: String
            switch mode {
            case .builderSession:
                obstacleXML = ""
            case .trainingRun:
                if prepared.isEmpty {
                    try? TrainingEnvironmentObstacleBaking.pruneLegacyAuthoringMeshes(in: meshDirectory)
                    obstacleXML = ""
                } else {
                    try TrainingEnvironmentObstacleBaking.pruneLegacyAuthoringMeshes(in: meshDirectory)
                    obstacleXML = try TrainingEnvironmentObstacleBaking.bakedModelXML(
                        records: prepared,
                        meshDirectory: meshDirectory
                    )
                }
            }
            try TrainingEnvironmentWorldSDF.writeOpenFieldWorld(
                to: worldURL,
                floorSideM: floor.floorSideM,
                additionalModelsXML: obstacleXML
            )
        }
    }
}
