import Combine
import Foundation

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

    init(userDefaults: UserDefaults = .standard) {
        if let loaded = Self.load(from: userDefaults) {
            defaultSimulationPlatform = loaded.defaultSimulationPlatform
        } else {
            defaultSimulationPlatform = .ardupilot
        }
    }

    private func save(userDefaults: UserDefaults = .standard) {
        let snapshot = Snapshot(defaultSimulationPlatform: defaultSimulationPlatform)
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
    }
}
