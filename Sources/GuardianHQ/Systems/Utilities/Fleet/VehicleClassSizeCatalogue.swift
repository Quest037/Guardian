import Foundation

/// Midpoint footprints from `Resources/vehicle_size_matrix.md` (regenerate via `scripts/generate_vehicle_class_size_catalogue.py`).
enum VehicleClassSizeCatalogue {
  struct Entry: Equatable, Sendable {
    let vehicleClass: FleetVehicleType
    let tier: VehicleSizeTier
    let widthCm: Int
    let lengthCm: Int
    let heightCm: Int

    var footprint: VehicleFootprint {
      VehicleFootprint(widthCm: widthCm, lengthCm: lengthCm, heightCm: heightCm)
    }
  }

  private static let entriesByKey: [String: Entry] = {
    Dictionary(
      uniqueKeysWithValues: VehicleClassSizeCatalogueGenerated.entries.map {
        (key(vehicleClass: $0.vehicleClass, tier: $0.tier), $0)
      }
    )
  }()

  private static let conservativeFallback = VehicleFootprint(widthCm: 200, lengthCm: 300, heightCm: 120)

  static var matrixSHA256Prefix: String { VehicleClassSizeCatalogueGenerated.matrixSHA256Prefix }

  static func defaultTier(for vehicleClass: FleetVehicleType) -> VehicleSizeTier { .medium }

  static func footprint(vehicleClass: FleetVehicleType, tier: VehicleSizeTier) -> VehicleFootprint {
    if let entry = entriesByKey[key(vehicleClass: vehicleClass, tier: tier)] {
      return entry.footprint
    }
    if vehicleClass == .unknown {
      return conservativeFallback
    }
    return footprint(vehicleClass: vehicleClass, tier: .medium)
  }

  static func footprintMetres(
    vehicleClass: FleetVehicleType,
    tier: VehicleSizeTier
  ) -> (widthM: Double, lengthM: Double, heightM: Double) {
    footprint(vehicleClass: vehicleClass, tier: tier).metres()
  }

  static func tiers(for vehicleClass: FleetVehicleType) -> [VehicleSizeTier] {
    VehicleSizeTier.allCases
  }

  private static func key(vehicleClass: FleetVehicleType, tier: VehicleSizeTier) -> String {
    "\(vehicleClass.rawValue)|\(tier.rawValue)"
  }
}
