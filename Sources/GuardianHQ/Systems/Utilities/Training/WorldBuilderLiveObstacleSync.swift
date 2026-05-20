import Foundation

/// Maps live Gazebo model names to manifest obstacle ids for World Builder sim sync.
enum WorldBuilderLiveObstacleSync {
    static func obstacleIDsInSim(
        manifest: [TrainingEnvironmentObstacleRecord],
        liveModelNames: [String]
    ) -> Set<String> {
        Set(
            manifest.compactMap { record in
                let present = liveModelNames.contains {
                    TrainingEnvironmentObstacleNaming.matchesModelName($0, obstacleID: record.id)
                }
                return present ? record.id : nil
            }
        )
    }

    static func gazeboModelName(
        for obstacleID: String,
        in liveModelNames: [String]
    ) -> String? {
        liveModelNames.first {
            TrainingEnvironmentObstacleNaming.matchesModelName($0, obstacleID: obstacleID)
        }
    }
}
