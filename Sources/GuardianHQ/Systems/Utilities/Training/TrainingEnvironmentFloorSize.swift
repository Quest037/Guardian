
import Foundation

/// Square training floor area preset (side² = footprint in m²).
enum TrainingEnvironmentFloorSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case micro
    case mini
    case small
    case medium
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .micro: return "Micro (100 m × 100 m)"
        case .mini: return "Mini (500 m × 500 m)"
        case .small: return "Small (1 km²)"
        case .medium: return "Medium (2 km²)"
        case .large: return "Large (4 km²)"
        }
    }

    /// Square floor side length in metres (`side` × `side` = footprint).
    var floorSideM: Double {
        switch self {
        case .micro: return 100
        case .mini: return 500
        case .small: return 1000
        case .medium: return 1000 * sqrt(2)
        case .large: return 2000
        }
    }

    /// Closest allowed orbit radius (metres from target) for embedded gzweb maps (`OrbitControls.minDistance`).
    var orbitMinDistanceM: Double {
        switch self {
        case .micro: return 25
        default: return 50
        }
    }

    /// Max start/end zone radius (m) for this floor preset (`WorldBuilderZoneState.minRadiusM` … this value).
    var maxZoneRadiusM: Double {
        switch self {
        case .micro: return 25
        default: return WorldBuilderZoneState.maxRadiusM
        }
    }

    static func resolved(from raw: String?) -> TrainingEnvironmentFloorSize {
        guard let raw, let size = TrainingEnvironmentFloorSize(rawValue: raw) else { return .small }
        return size
    }
}
