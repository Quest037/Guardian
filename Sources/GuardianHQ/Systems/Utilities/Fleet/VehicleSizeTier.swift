import Foundation

/// Fixed size band vocabulary from `Resources/vehicle_size_matrix.md` (seven steps per granular class).
enum VehicleSizeTier: String, Equatable, Codable, CaseIterable, Sendable {
  case micro
  case mini
  case small
  case medium
  case large
  case xlarge
  case xxlarge

  /// Operator-facing label (Theme catalogue strings).
  var displayName: String {
    switch self {
    case .micro: return "Micro"
    case .mini: return "Mini"
    case .small: return "Small"
    case .medium: return "Medium"
    case .large: return "Large"
    case .xlarge: return "XLarge"
    case .xxlarge: return "XXLarge"
    }
  }
}
