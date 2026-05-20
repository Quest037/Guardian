import Foundation

/// Inputs for inserting a vehicle proxy model into a running Gazebo world.
struct GazeboVehicleSpawnParams: Equatable, Sendable {
  var vehicleClass: FleetVehicleType
  var vehicleSizeTier: VehicleSizeTier
  /// Optional custom mesh URI/path (v10). When nil or unreadable, a sized box is used.
  var customMeshURI: String?
  var pose: TrainingEnvironmentPose
  /// When set, proxy box/mesh tint uses squad palette (``TrainingLabSquadFormationPalette``) instead of macro class colour.
  var squadColorHex: String?

  @MainActor
  init(
    vehicleClass: FleetVehicleType,
    vehicleID: String,
    pose: TrainingEnvironmentPose,
    customMeshURI: String? = nil,
    squadColorHex: String? = nil
  ) {
    self.vehicleClass = vehicleClass
    self.vehicleSizeTier = VehicleClassSizePreferencesStore.shared.resolvedTier(
      vehicleID: vehicleID,
      vehicleClass: vehicleClass
    )
    self.customMeshURI = customMeshURI
    self.pose = pose
    self.squadColorHex = squadColorHex
  }

  init(
    vehicleClass: FleetVehicleType,
    vehicleSizeTier: VehicleSizeTier,
    pose: TrainingEnvironmentPose,
    customMeshURI: String? = nil,
    squadColorHex: String? = nil
  ) {
    self.vehicleClass = vehicleClass
    self.vehicleSizeTier = vehicleSizeTier
    self.customMeshURI = customMeshURI
    self.pose = pose
    self.squadColorHex = squadColorHex
  }
}

/// Ties a built-in SITL spawn to an active Gazebo `.run` world and ENU pose.
struct GazeboVehiclePlacement: Equatable, Sendable {
  var worldID: UUID
  var pose: TrainingEnvironmentPose
  var customMeshURI: String?

  init(worldID: UUID, pose: TrainingEnvironmentPose, customMeshURI: String? = nil) {
    self.worldID = worldID
    self.pose = pose
    self.customMeshURI = customMeshURI
  }
}
