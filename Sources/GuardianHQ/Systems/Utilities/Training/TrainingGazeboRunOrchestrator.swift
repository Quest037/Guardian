import Foundation

/// Resolved inputs for a Training / Formation operational Gazebo session (`.run`).
struct TrainingGazeboRunSpawnPlan: Equatable, Sendable {
  let purpose: GazeboSessionPurpose
  let environmentID: String
  let worldPath: String

  init(environment: TrainingEnvironmentPackage) {
    purpose = .run
    environmentID = environment.id
    worldPath = environment.worldFileURL().path
  }
}

enum TrainingGazeboRunOrchestrator {
  static func spawnPlan(for environment: TrainingEnvironmentPackage) -> TrainingGazeboRunSpawnPlan {
    TrainingGazeboRunSpawnPlan(environment: environment)
  }

  static func layout(
    environment: TrainingEnvironmentPackage,
    targetSlot: TrainingTaskPose,
    spawnDefaults: SimSpawnDefaults
  ) -> TrainingTaskLayout {
    let start = TrainingEnvironmentGeodesy.taskPose(
      environmentPose: environment.manifest.defaultSpawn,
      origin: spawnDefaults
    )
    return TrainingTaskLayout(start: start, goal: targetSlot)
  }
}
