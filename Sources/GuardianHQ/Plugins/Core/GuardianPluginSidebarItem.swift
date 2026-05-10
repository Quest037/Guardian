import Foundation

/// User-visible sidebar row contributed by a plugin.
struct GuardianPluginSidebarItem: Identifiable, Equatable, Sendable {
    let id: String
    let pluginID: GuardianPluginID
    let placement: GuardianPluginSidebarPlacement
    let title: String
    let systemImage: String
    let tapAction: GuardianPluginSidebarTapAction
}

enum GuardianPluginSidebarTapAction: Equatable, Sendable {
    case openAppSection(AppSection)
}
