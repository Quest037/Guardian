import Foundation

/// Physical bounding box in centimetres — width × length × height (matrix axis semantics).
struct VehicleFootprint: Equatable, Codable, Sendable {
  var widthCm: Int
  var lengthCm: Int
  var heightCm: Int

  /// Longest horizontal axis in cm (spacing / clearance heuristics).
  var maxHorizontalAxisCm: Int {
    max(widthCm, lengthCm)
  }

  var dimensionsLabelCm: String {
    "\(widthCm) × \(lengthCm) × \(heightCm) cm"
  }

  func metres() -> (widthM: Double, lengthM: Double, heightM: Double) {
    (
      widthM: Double(widthCm) / 100.0,
      lengthM: Double(lengthCm) / 100.0,
      heightM: Double(heightCm) / 100.0
    )
  }
}
