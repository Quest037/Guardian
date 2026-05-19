import Foundation

/// Terrain height under the map-base-square (ENU metres). Flat worlds return floor top z = 0.
enum TrainingEnvironmentTerrainHeightQuery {
    static func heightM(xM: Double, yM: Double, sceneType: TrainingEnvironmentSceneType) -> Double {
        switch sceneType {
        case .flat:
            _ = (xM, yM)
            return 0
        }
    }
}
