import Foundation
import os

/// One-shot registration of built-in plugins into ``GuardianPluginRegistry``.
enum GuardianPluginBootstrap {
    private static let didRegister = OSAllocatedUnfairLock(initialState: false)
    private static let log = OSLog(subsystem: "guardian.plugins", category: "bootstrap")

    /// Canonical Paladin manifest (``registerPaladin()``). Paladin does **not** register plugin-owned
    /// fleet catalogue rows: it drives Mission Control / LiveDrive / Vehicle Inspector flows using **core**
    /// commands and recipes (`pluginID == nil`). Fleet publish/invoke claim arrays stay empty unless that
    /// policy changes. Tests may temporarily replace this manifest and restore via this factory.
    static func builtInPaladinManifest() -> GuardianPluginManifest {
        GuardianPluginManifest(
            pluginID: .paladin,
            displayName: "Paladin",
            shortDescription: "Mission Control assistant: execution handoff, prompts, and Paladin-authored log lines."
        )
    }

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
        ingestBuiltIn(builtInPaladinManifest(), sidebarItems: [])
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
        ingestBuiltIn(manifest, sidebarItems: [sidebar])
    }

    @MainActor
    private static func ingestBuiltIn(_ manifest: GuardianPluginManifest, sidebarItems: [GuardianPluginSidebarItem]) {
        if let err = manifest.namespaceClaimValidationError() {
            os_log(
                .fault,
                log: log,
                "Refusing built-in plugin registration %{public}@: %{public}@",
                manifest.pluginID.rawValue,
                err
            )
            assertionFailure("Invalid built-in GuardianPluginManifest for \(manifest.pluginID): \(err)")
            return
        }
        GuardianPluginRegistry.shared.ingestBuiltInRegistration(manifest: manifest, sidebarItems: sidebarItems)
    }
}
