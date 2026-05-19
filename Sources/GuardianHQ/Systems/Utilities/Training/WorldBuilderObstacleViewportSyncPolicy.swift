import Foundation

/// Rules for applying gzweb obstacle editor lists back into the Swift manifest.
enum WorldBuilderObstacleViewportSyncPolicy {
    /// Viewport may only update poses for obstacles already in the manifest.
    /// Additions use ``WorldBuilderController/placeObstacleAt(centerXM:centerYM:)``;
    /// removals use ``WorldBuilderController/confirmDeleteObstacle(id:)``.
    static func acceptsViewportObstacleList(
        prior: [TrainingEnvironmentObstacleRecord],
        proposed: [TrainingEnvironmentObstacleRecord]
    ) -> Bool {
        if proposed.count > prior.count { return false }
        return Set(prior.map(\.id)) == Set(proposed.map(\.id))
    }
}
