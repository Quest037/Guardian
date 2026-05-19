import Foundation

/// Cross-process catalogue updates (Training auto-export → Mission operator toast).
enum GuardianBrainCatalogueChangeNotification {
    static let name = Notification.Name("guardianhq.brainCatalogue.changed")

    static let displayNameKey = "guardianhq.brainCatalogue.changed.displayName"
    static let brainVersionKey = "guardianhq.brainCatalogue.changed.brainVersion"
    static let brainVersionLabelKey = "guardianhq.brainCatalogue.changed.brainVersionLabel"

    @MainActor
    static func post(displayName: String, brainVersion: GuardianBrainVersion) {
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: [
                displayNameKey: displayName,
                brainVersionKey: brainVersion.semverString,
                brainVersionLabelKey: brainVersion.displayLabel,
            ]
        )
    }
}
