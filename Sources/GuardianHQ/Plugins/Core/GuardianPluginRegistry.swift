import Combine
import Foundation

/// App-wide registry for built-in plugins: metadata, optional sidebar rows, and preference wiring.
///
/// Registration runs once at launch via ``GuardianPluginBootstrap/ensureRegistered()``. Templates
/// and assistants must register only through APIs that require a validated ``GuardianPluginID``.
@MainActor
final class GuardianPluginRegistry: ObservableObject {
    static let shared = GuardianPluginRegistry()

    @Published private(set) var manifests: [GuardianPluginManifest] = []
    @Published private(set) var sidebarContributions: [GuardianPluginSidebarItem] = []

    private weak var preferences: PluginPreferencesStore?
    private var preferencesCancellable: AnyCancellable?

    private init() {}

    func bindPreferences(_ store: PluginPreferencesStore) {
        guard preferences !== store else { return }
        preferencesCancellable?.cancel()
        preferences = store
        preferencesCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func isPluginEnabled(_ pluginID: GuardianPluginID) -> Bool {
        preferences?.isEnabled(pluginID) ?? true
    }

    func manifestsOrdered() -> [GuardianPluginManifest] {
        manifests.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func sidebarItems(for placement: GuardianPluginSidebarPlacement) -> [GuardianPluginSidebarItem] {
        sidebarContributions
            .filter { $0.placement == placement && isPluginEnabled($0.pluginID) }
    }

    /// Called only from ``GuardianPluginBootstrap`` (single pass).
    func ingestBuiltInRegistration(manifest: GuardianPluginManifest, sidebarItems: [GuardianPluginSidebarItem]) {
        manifests.removeAll { $0.pluginID == manifest.pluginID }
        manifests.append(manifest)
        sidebarContributions.removeAll { $0.pluginID == manifest.pluginID }
        sidebarContributions.append(contentsOf: sidebarItems)
        objectWillChange.send()
    }
}
