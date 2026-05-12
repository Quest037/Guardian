import Foundation

// MARK: - OperatorPromptReviewSurfaceResolver

/// Derives **where the operator should review** a prompt in first-party chrome, using the **same** routing policy
/// ordering as ``OperatorPromptRouter`` (via ``ProcessPromptPolicy/routingPolicy(for:)`` + ``ProcessPromptPolicy/bind``).
///
/// Skips broadcast-only targets (inbox, persistent toast, OS notification) and Vehicle Inspector for v1 — those are
/// not first-party “shell sections” in the sidebar sense. Plugins extend the chain via ``OperatorPromptReviewSurfaceContributorRegistry``.
enum OperatorPromptReviewSurfaceResolver {

    /// Returns the first actionable review destination, or a contributor-provided ``OperatorPromptReviewSurface/pluginSurface``.
    static func resolve(for event: OperatorPromptEvent) -> OperatorPromptReviewSurface? {
        if let builtIn = resolveBuiltIn(for: event) { return builtIn }
        return OperatorPromptReviewSurfaceContributorRegistry.shared.contributedSurface(for: event)
    }

    private static func resolveBuiltIn(for event: OperatorPromptEvent) -> OperatorPromptReviewSurface? {
        let policy = ProcessPromptPolicy.routingPolicy(for: event)
        let targets = policy.resolveTargets(for: event)
        for target in targets {
            switch target {
            case .mcrPromptPanel(let runID):
                return .missionControlRun(runID: runID, missionTaskID: event.target.missionTaskID)

            case .liveDrivePromptPanel(let missionRunID, let vehicleID):
                let trimmedVehicle = (vehicleID ?? event.target.affectedVehicleID)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !trimmedVehicle.isEmpty else { continue }
                let run = missionRunID ?? event.target.missionRunID
                return .liveDriveSession(vehicleID: trimmedVehicle, missionRunID: run)

            case .vehicleInspectorWizardPanel, .persistentToast, .userNotification, .inAppInbox:
                continue
            }
        }
        return nil
    }
}
