import Foundation
import os

/// One-shot registration of built-in plugins into ``GuardianPluginRegistry``.
enum GuardianPluginBootstrap {
    private static let didRegister = OSAllocatedUnfairLock(initialState: false)

    /// Idempotent: safe from any call site during app startup.
    @MainActor
    static func ensureRegistered() {
        let shouldRun = Self.didRegister.withLock { flag -> Bool in
            if flag { return false }
            flag = true
            return true
        }
        guard shouldRun else { return }
        registerPaladin()
        registerTheme()
        PaladinMissionAssistant.registerProfile()
    }

    @MainActor
    private static func registerPaladin() {
        let manifest = GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Mission Control assistant: execution handoff, prompts, and Paladin-authored log lines."
        )
        GuardianPluginRegistry.shared.ingestBuiltInRegistration(manifest: manifest, sidebarItems: [])
    }

    @MainActor
    private static func registerTheme() {
        let manifest = GuardianPluginManifest(
            pluginID: .theme,
            displayName: "Theme",
            shortDescription: "Visual catalog of cards, buttons, and layout defaults for consistent UI."
        )
        let sidebar = GuardianPluginSidebarItem(
            id: "guardian.plugin.theme.sidebar.panel",
            pluginID: .theme,
            placement: .secondary,
            title: "Theme",
            systemImage: "paintpalette.fill",
            tapAction: .openAppSection(.theme)
        )
        GuardianPluginRegistry.shared.ingestBuiltInRegistration(manifest: manifest, sidebarItems: [sidebar])
    }
}
