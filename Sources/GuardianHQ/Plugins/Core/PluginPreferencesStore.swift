import Combine
import Foundation

/// Persisted enable/disable flags for ``GuardianPluginID`` entries.
@MainActor
final class PluginPreferencesStore: ObservableObject {
    private static let userDefaultsKey = "GuardianHQ.disabledPluginIDs"

    @Published private(set) var disabledPluginIDs: Set<String> = []

    init() {
        load()
    }

    func isEnabled(_ pluginID: GuardianPluginID) -> Bool {
        !disabledPluginIDs.contains(pluginID.rawValue)
    }

    func setEnabled(_ pluginID: GuardianPluginID, enabled: Bool) {
        if enabled {
            disabledPluginIDs.remove(pluginID.rawValue)
        } else {
            disabledPluginIDs.insert(pluginID.rawValue)
        }
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data)
        {
            disabledPluginIDs = Set(decoded)
        } else {
            disabledPluginIDs = []
        }
    }

    private func save() {
        let array = Array(disabledPluginIDs)
        if let data = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
