import Combine
import Foundation

enum LogRetentionProfile: String, Codable, CaseIterable, Identifiable {
    case short
    case `default`
    case long

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short: return "Short"
        case .default: return "Default"
        case .long: return "Long"
        }
    }
}

/// Persisted app-wide preferences (General settings).
@MainActor
final class GeneralSettingsStore: ObservableObject {
    private static let defaultsKey = "guardian.generalSettings.v1"

    /// Default stack for **in-app SITL** when the user does not pick ArduPilot vs PX4 per spawn.
    @Published var defaultSimulationPlatform: SimulationPlatform {
        didSet {
            guard defaultSimulationPlatform != oldValue else { return }
            save()
        }
    }

    /// Default basemap for mission route editing and Mission Control live overview (toggle still available in-app).
    @Published var defaultMapTileStyle: MapTileStyle {
        didSet {
            guard defaultMapTileStyle != oldValue else { return }
            save()
        }
    }

    /// Log retention for visible in-app logs.
    @Published var logRetentionProfile: LogRetentionProfile {
        didSet {
            guard logRetentionProfile != oldValue else { return }
            save()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        if let loaded = Self.load(from: userDefaults) {
            defaultSimulationPlatform = loaded.defaultSimulationPlatform
            defaultMapTileStyle = loaded.defaultMapTileStyle ?? .standard
            logRetentionProfile = loaded.logRetentionProfile ?? .default
        } else {
            defaultSimulationPlatform = .ardupilot
            defaultMapTileStyle = .standard
            logRetentionProfile = .default
        }
    }

    private func save(userDefaults: UserDefaults = .standard) {
        let snapshot = Snapshot(
            defaultSimulationPlatform: defaultSimulationPlatform,
            defaultMapTileStyle: defaultMapTileStyle,
            logRetentionProfile: logRetentionProfile
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func load(from userDefaults: UserDefaults) -> Snapshot? {
        guard let data = userDefaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private struct Snapshot: Codable {
        var defaultSimulationPlatform: SimulationPlatform
        /// Omitted in older saves; treated as `.standard`.
        var defaultMapTileStyle: MapTileStyle?
        /// Omitted in older saves; treated as `.default`.
        var logRetentionProfile: LogRetentionProfile?
    }
}
