import Foundation

// MARK: - Window-level operator toast (Mission Control task abort / complete protocol)

/// Ephemeral operator toast when Mission Control records abort or complete wind-down (§3 auto batch or manual triage) — ``ToastCenter`` in ``GuardianHQApp``.
enum GuardianMissionRunSlotEvidenceAutoTriageToastNotification {
    static let name = Notification.Name("guardianhq.missionRun.slotEvidenceAutoTriageToast")

    static let messageKey = "guardianhq.missionRun.slotEvidenceAutoTriageToast.message"
    static let severityRawKey = "guardianhq.missionRun.slotEvidenceAutoTriageToast.severity"

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

enum MissionRunSlotEvidenceAutoTriageOperatorCopy {
    static func toastManualTriage(taskName: String, state: MissionTaskState) -> String {
        switch state {
        case .completed:
            return "Mission Control recorded complete wind-down for \(taskName). Logged on the mission run."
        case .aborted:
            return "Mission Control recorded abort wind-down for \(taskName). Logged on the mission run."
        default:
            return ""
        }
    }

    static func toastConsolidated(abortTaskNames: [String], recoveryTaskNames: [String]) -> String {
        var parts: [String] = []
        if !abortTaskNames.isEmpty {
            parts.append("abort wind-down for \(abortTaskNames.joined(separator: ", "))")
        }
        if !recoveryTaskNames.isEmpty {
            parts.append("complete wind-down for \(recoveryTaskNames.joined(separator: ", "))")
        }
        let body = parts.joined(separator: "; ")
        return "Automatic protocol confirmation from roster slot evidence: \(body). Logged on the mission run."
    }
}
