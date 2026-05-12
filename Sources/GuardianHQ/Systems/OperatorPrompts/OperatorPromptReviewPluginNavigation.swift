import Foundation

// MARK: - Plugin review navigation (extension bus)

extension Notification.Name {

    /// Posted when the operator asks to review a ``OperatorPromptReviewSurface/pluginSurface`` from the Decisions drawer.
    ///
    /// **userInfo keys:** ``OperatorPromptReviewPluginNavigationUserInfoKey/applicationNamespace`` (String),
    /// ``OperatorPromptReviewPluginNavigationUserInfoKey/parameters`` (`[String: String]`).
    static let operatorPromptReviewPluginNavigation = Notification.Name("guardian.operatorPrompt.reviewPluginNavigation")
}

enum OperatorPromptReviewPluginNavigationUserInfoKey {
    static let applicationNamespace = "applicationNamespace"
    static let parameters = "parameters"
}

enum OperatorPromptReviewPluginNavigation {

    static func post(applicationNamespace: String, parameters: [String: String]) {
        NotificationCenter.default.post(
            name: .operatorPromptReviewPluginNavigation,
            object: nil,
            userInfo: [
                OperatorPromptReviewPluginNavigationUserInfoKey.applicationNamespace: applicationNamespace,
                OperatorPromptReviewPluginNavigationUserInfoKey.parameters: parameters,
            ]
        )
    }
}
