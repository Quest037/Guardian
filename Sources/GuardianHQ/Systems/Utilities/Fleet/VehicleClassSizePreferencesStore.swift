import Foundation

/// Per-vehicle size tier overrides and per-class defaults (Garage + spawn).
@MainActor
final class VehicleClassSizePreferencesStore: ObservableObject {
  static let shared = VehicleClassSizePreferencesStore()

  @Published private(set) var defaultTierByClass: [FleetVehicleType: VehicleSizeTier] = [:]
  @Published private(set) var tierByVehicleID: [String: VehicleSizeTier] = [:]

  private let defaultsKey = "guardian.vehicleClassSizePreferences.v1"
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  private struct Persisted: Codable {
    var defaultTierByClass: [String: VehicleSizeTier]
    var tierByVehicleID: [String: VehicleSizeTier]
  }

  private init() {
    load()
  }

  func defaultTier(for vehicleClass: FleetVehicleType) -> VehicleSizeTier {
    defaultTierByClass[vehicleClass] ?? VehicleClassSizeCatalogue.defaultTier(for: vehicleClass)
  }

  func resolvedTier(vehicleID: String, vehicleClass: FleetVehicleType) -> VehicleSizeTier {
    if let explicit = tierByVehicleID[vehicleID] {
      return explicit
    }
    return defaultTier(for: vehicleClass)
  }

  func resolvedFootprint(vehicleID: String, vehicleClass: FleetVehicleType) -> VehicleFootprint {
    let tier = resolvedTier(vehicleID: vehicleID, vehicleClass: vehicleClass)
    return VehicleClassSizeCatalogue.footprint(vehicleClass: vehicleClass, tier: tier)
  }

  func setDefaultTier(_ tier: VehicleSizeTier, for vehicleClass: FleetVehicleType) {
    defaultTierByClass[vehicleClass] = tier
    save()
  }

  func setTier(_ tier: VehicleSizeTier, forVehicleID vehicleID: String) {
    tierByVehicleID[vehicleID] = tier
    save()
  }

  func clearVehicleOverride(forVehicleID vehicleID: String) {
    tierByVehicleID.removeValue(forKey: vehicleID)
    save()
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: defaultsKey),
          let persisted = try? decoder.decode(Persisted.self, from: data)
    else { return }
    defaultTierByClass = persisted.defaultTierByClass.compactMapKeys { FleetVehicleType(rawValue: $0) }
    tierByVehicleID = persisted.tierByVehicleID
  }

  private func save() {
    let payload = Persisted(
      defaultTierByClass: Dictionary(uniqueKeysWithValues: defaultTierByClass.map { ($0.key.rawValue, $0.value) }),
      tierByVehicleID: tierByVehicleID
    )
    guard let data = try? encoder.encode(payload) else { return }
    UserDefaults.standard.set(data, forKey: defaultsKey)
  }
}

private extension Dictionary {
  func compactMapKeys<K: Hashable>(_ transform: (Key) -> K?) -> [K: Value] {
    var out: [K: Value] = [:]
    for (key, value) in self {
      if let k = transform(key) {
        out[k] = value
      }
    }
    return out
  }
}
