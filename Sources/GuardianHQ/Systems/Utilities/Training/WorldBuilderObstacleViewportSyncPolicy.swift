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

    /// Applies gzweb pose edits only — dimensions and kind stay on the manifest (viewport meshes may be scaled in Three.js).
    static func mergingPoseUpdates(
        prior: [TrainingEnvironmentObstacleRecord],
        proposed: [TrainingEnvironmentObstacleRecord]
    ) -> [TrainingEnvironmentObstacleRecord] {
        let proposedByID = Dictionary(uniqueKeysWithValues: proposed.map { ($0.id, $0) })
        return prior.map { existing in
            guard let incoming = proposedByID[existing.id] else { return existing }
            var merged = existing
            merged.centerXM = incoming.centerXM
            merged.centerYM = incoming.centerYM
            merged.centerZM = incoming.centerZM
            merged.yawDeg = incoming.yawDeg
            merged.usesAutoZ = incoming.usesAutoZ
            return merged
        }
    }
}
