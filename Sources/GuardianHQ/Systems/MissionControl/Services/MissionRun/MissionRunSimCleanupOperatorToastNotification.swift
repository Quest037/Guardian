import Foundation

// MARK: - Window-level operator toast (Mission Run SIM cleanup)

/// Ephemeral operator toast for SIM cleanup outcomes (``ToastCenter`` subscribes in ``GuardianHQApp``).
enum GuardianMissionRunSimCleanupOperatorToastNotification {
    /// `userInfo`: ``messageKey`` (`String`), ``severityRawKey`` (`String`, ``GuardianFeedbackSeverity/rawValue``).
    static let name = Notification.Name("guardianhq.missionRun.simCleanupOperatorToast")

    static let messageKey = "guardianhq.missionRun.simCleanupOperatorToast.message"
    static let severityRawKey = "guardianhq.missionRun.simCleanupOperatorToast.severity"

    @MainActor
    static func post(message: String, severity: GuardianFeedbackSeverity) {
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: [
                messageKey: message,
                severityRawKey: severity.rawValue,
            ]
        )
    }
}

enum MissionRunSimCleanupOperatorToastCopy {
    /// Operator-facing summary when SIM kill or gated home-restore skips indicate a partial pass; `nil` when no toast.
    static func partialFailureMessage(
        simKillFailedCount: Int,
        shouldTeleport: Bool,
        rosterSnapshotCount: Int,
        rosterSkipped: Int,
        poolSnapshotCount: Int,
        poolSkipped: Int
    ) -> String? {
        var parts: [String] = []
        if simKillFailedCount > 0 {
            parts.append(
                simKillFailedCount == 1
                    ? "SIM kill did not succeed for one vehicle"
                    : "SIM kill did not succeed for \(simKillFailedCount) vehicles"
            )
        }
        if shouldTeleport {
            if rosterSnapshotCount > 0, rosterSkipped > 0 {
                parts.append(
                    rosterSkipped == 1
                        ? "roster home restore skipped one vehicle"
                        : "roster home restore skipped \(rosterSkipped) vehicles"
                )
            }
            if poolSnapshotCount > 0, poolSkipped > 0 {
                parts.append(
                    poolSkipped == 1
                        ? "reserve pool home restore skipped one vehicle"
                        : "reserve pool home restore skipped \(poolSkipped) vehicles"
                )
            }
        }
        guard !parts.isEmpty else { return nil }
        let body = parts.joined(separator: "; ")
        return "SIM cleanup finished with issues: \(body). Check the mission log for details."
    }
}
