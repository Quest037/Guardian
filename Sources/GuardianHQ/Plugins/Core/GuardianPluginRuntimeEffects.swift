import Foundation

/// Side effects when a plugin is toggled in ``PluginsView`` (templates, assistant registry, etc.).
enum GuardianPluginRuntimeEffects {
    @MainActor
    static func applyDisabled(_ pluginID: GuardianPluginID) {
        if pluginID == .paladin {
            StructuredLogTemplateCatalog.unregisterAllTemplates(forPlugin: pluginID)
            MissionRunAssistantRegistry.shared.unregister(forKey: PaladinMissionAssistant.assistantKey)
            PaladinEngine.shared.missionControlDomainBridge().detachAllAssistants()
        }
    }

    @MainActor
    static func applyEnabled(_ pluginID: GuardianPluginID) {
        if pluginID == .paladin {
            PaladinMissionAssistant.registerProfile()
            PaladinEngine.shared.missionControlDomainBridge().resyncAssistantsForAllRuns()
        }
    }
}
