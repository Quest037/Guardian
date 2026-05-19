import Foundation

/// Gazebo / World Builder box dimensions derived from the class size catalogue (metres).
struct VehicleGazeboFootprint: Equatable, Sendable {
  var widthM: Double
  var lengthM: Double
  var heightM: Double

  init(footprint: VehicleFootprint) {
    let m = footprint.metres()
    widthM = m.widthM
    lengthM = m.lengthM
    heightM = m.heightM
  }

  static func resolve(vehicleClass: FleetVehicleType, tier: VehicleSizeTier) -> VehicleGazeboFootprint {
    VehicleGazeboFootprint(
      footprint: VehicleClassSizeCatalogue.footprint(vehicleClass: vehicleClass, tier: tier)
    )
  }

  @MainActor
  static func resolve(vehicleID: String, vehicleClass: FleetVehicleType) -> VehicleGazeboFootprint {
    let footprint = VehicleClassSizePreferencesStore.shared.resolvedFootprint(
      vehicleID: vehicleID,
      vehicleClass: vehicleClass
    )
    return VehicleGazeboFootprint(footprint: footprint)
  }
}
