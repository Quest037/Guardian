import Foundation

// MARK: - OperatorPromptReviewSurface

/// **Where to review** an ``OperatorPromptEvent`` in product chrome (Mission Control, Live Drive, …).
///
/// Routing policies (``ProcessPromptPolicy``) already declare preferred contextual surfaces; this type is the
/// **navigation** analogue so the Decisions drawer can send the operator to the same place without duplicating policy tables.
///
/// ## Extension model
///
/// - **Built-in** cases cover first-party destinations the shell knows how to open.
/// - ``pluginSurface`` carries a **reverse-DNS namespace** (e.g. `com.guardianhq.plugin.example.workspace`) and opaque parameters.
///   Plugins register a ``OperatorPromptReviewSurfaceContributorRegistry`` closure that maps events to this case, and observe
///   ``Notification.Name/operatorPromptReviewPluginNavigation`` to perform navigation when the operator taps **Review** in the drawer.
enum OperatorPromptReviewSurface: Equatable, Hashable, Sendable {

    /// Open **Mission Control** and drill into the live / setup run for `runID`. Optional `missionTaskID` is reserved for future scroll-to-task behaviour.
    case missionControlRun(runID: UUID, missionTaskID: UUID?)

    /// Open **Live Drive** and select `vehicleID` in the picker. `missionRunID` is optional context when the session is tied to a run.
    case liveDriveSession(vehicleID: String, missionRunID: UUID?)

    /// Plugin-owned destination — core shell only posts ``Notification.Name/operatorPromptReviewPluginNavigation``.
    case pluginSurface(applicationNamespace: String, parameters: [String: String])
}

extension OperatorPromptReviewSurface {

    /// Primary button label for the Decisions drawer.
    var reviewNavigationButtonTitle: String {
        switch self {
        case .missionControlRun:
            return "Review in Mission Control"
        case .liveDriveSession:
            return "Review in Live Drive"
        case .pluginSurface(let namespace, _):
            return "Review in \(shortPluginLabel(from: namespace))"
        }
    }

    var reviewNavigationAccessibilityHint: String {
        switch self {
        case .missionControlRun:
            return "Switches to Mission Control and opens this mission run."
        case .liveDriveSession:
            return "Switches to Live Drive and selects the vehicle for this prompt."
        case .pluginSurface:
            return "Sends a navigation request to the owning extension."
        }
    }

    private func shortPluginLabel(from namespace: String) -> String {
        if let r = namespace.split(separator: ".").last, !r.isEmpty { return String(r) }
        return namespace
    }
}
