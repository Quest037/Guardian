import Foundation

/// Terrain / layout preset for a training environment world (manifest `sceneType`).
enum TrainingEnvironmentSceneType: String, Codable, CaseIterable, Identifiable, Sendable {
    case flat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flat: return "Flat"
        }
    }

    static func resolved(from raw: String?) -> TrainingEnvironmentSceneType {
        guard let raw, let scene = TrainingEnvironmentSceneType(rawValue: raw) else { return .flat }
        return scene
    }
}
