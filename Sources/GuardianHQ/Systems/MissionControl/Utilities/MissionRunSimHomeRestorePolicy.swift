import Foundation

/// Gating for optional **SIM home restore** after a qualifying Mission Control run completion (v1).
enum MissionRunSimHomeRestorePolicy {
    static func shouldScheduleAfterMarkCompleted(
        completionKind: MissionRunCompletionKind?,
        settingsEnabled: Bool,
        snapshotsNonEmpty: Bool,
        hasFleetAndSitl: Bool
    ) -> Bool {
        guard completionKind?.qualifiesForSimHomeRestoreAfterSuccessfulMissionRun == true else { return false }
        guard settingsEnabled else { return false }
        guard snapshotsNonEmpty else { return false }
        guard hasFleetAndSitl else { return false }
        return true
    }
}
