import Foundation

/// Payload discriminator for Paladin notifications in `userInfo["guardian.kind"]`.
enum PaladinUserNotificationKind: String, Sendable {
    case planCompiled = "paladin.plan_compiled"
    case executionStarted = "paladin.execution_started"
    case runCompleted = "paladin.run_completed"
}

/// Paladin-specific notification helpers plugged into the global app notification service.
extension UserNotificationService {
    func notifyPaladinPlanCompiled(runID: UUID, missionName: String) {
        deliver(
            kind: PaladinUserNotificationKind.planCompiled.rawValue,
            title: "Paladin",
            subtitle: missionName,
            body: "Mission plan compiled and ready.",
            runID: runID
        )
    }

    func notifyPaladinExecutionStarted(runID: UUID, missionName: String) {
        deliver(
            kind: PaladinUserNotificationKind.executionStarted.rawValue,
            title: "Paladin",
            subtitle: missionName,
            body: "Execution started.",
            runID: runID
        )
    }

    func notifyPaladinRunCompleted(runID: UUID, missionName: String, summary: String) {
        let maxLen = 320
        let trimmed = summary.count > maxLen ? String(summary.prefix(maxLen)) + "…" : summary
        deliver(
            kind: PaladinUserNotificationKind.runCompleted.rawValue,
            title: "Paladin",
            subtitle: missionName,
            body: trimmed,
            runID: runID
        )
    }
}
