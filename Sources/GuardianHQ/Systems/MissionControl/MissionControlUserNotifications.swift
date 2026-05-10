import Foundation

/// Payload discriminators for Mission Control notifications in `userInfo["guardian.kind"]`.
enum MissionControlUserNotificationKind: String, Sendable {
    case planCompiled = "missionControl.plan_compiled"
    case runCompleted = "missionControl.run_completed"
}

extension UserNotificationService {
    func notifyMissionControlPlanCompiled(runID: UUID, missionName: String) {
        deliver(
            kind: MissionControlUserNotificationKind.planCompiled.rawValue,
            title: "Mission Control",
            subtitle: missionName,
            body: "Mission plan compiled and ready.",
            runID: runID
        )
    }

    func notifyMissionControlRunCompleted(runID: UUID, missionName: String, summary: String) {
        let maxLen = 320
        let trimmed = summary.count > maxLen ? String(summary.prefix(maxLen)) + "…" : summary
        deliver(
            kind: MissionControlUserNotificationKind.runCompleted.rawValue,
            title: "Mission Control",
            subtitle: missionName,
            body: trimmed,
            runID: runID
        )
    }
}
