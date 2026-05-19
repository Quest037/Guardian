import Foundation

/// Default Gazebo proxy colours by macro vehicle class (v1 boxes; custom meshes use the same tint).
enum GazeboUniversalClassVisualStyle {
  struct RGBA: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    var diffuseTriple: String {
      String(format: "%.3f %.3f %.3f", r, g, b)
    }
  }

  static func rgba(for universalClass: UniversalVehicleClass) -> RGBA {
    switch universalClass {
    case .uav:
      return RGBA(r: 1.0, g: 0.92, b: 0.15, a: 1.0)
    case .ugv:
      return RGBA(r: 0.20, g: 0.45, b: 1.0, a: 1.0)
    case .usv:
      return RGBA(r: 0.95, g: 0.18, b: 0.18, a: 1.0)
    case .uuv:
      return RGBA(r: 1.0, g: 0.45, b: 0.72, a: 1.0)
    case .unknown:
      return RGBA(r: 0.55, g: 0.55, b: 0.55, a: 1.0)
    }
  }
}
