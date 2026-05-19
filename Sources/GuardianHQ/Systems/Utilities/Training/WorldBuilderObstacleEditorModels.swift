import Foundation

/// Obstacle editor snapshot pushed to the gzweb viewport.
struct WorldBuilderObstaclesEditorSnapshot: Codable, Equatable, Sendable {
    var editorActive: Bool
    var selectedID: String?
    var placementActive: Bool
    var draft: TrainingEnvironmentObstacleRecord
    var obstacles: [TrainingEnvironmentObstacleRecord]
    var mapHalfExtentM: Double
    /// Obstacle being removed from Gazebo — viewport fades it and blocks selection until done.
    var deletingID: String?

    static func make(
        editorActive: Bool,
        selectedID: String?,
        placementActive: Bool,
        draft: TrainingEnvironmentObstacleRecord,
        obstacles: [TrainingEnvironmentObstacleRecord],
        mapHalfExtentM: Double,
        deletingID: String? = nil
    ) -> WorldBuilderObstaclesEditorSnapshot {
        WorldBuilderObstaclesEditorSnapshot(
            editorActive: editorActive,
            selectedID: selectedID,
            placementActive: placementActive,
            draft: draft,
            obstacles: obstacles,
            mapHalfExtentM: mapHalfExtentM,
            deletingID: deletingID
        )
    }
}
