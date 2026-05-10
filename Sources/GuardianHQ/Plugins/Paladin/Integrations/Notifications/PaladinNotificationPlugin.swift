import Foundation

/// Payload discriminator for Paladin notifications in `userInfo["guardian.kind"]`.
enum PaladinUserNotificationKind: String, Sendable {
    case executionStarted = "paladin.execution_started"
}

/// Paladin-specific notification helpers plugged into the global app notification service.
extension UserNotificationService {
    func notifyPaladinExecutionStarted(runID: UUID, missionName: String) {
        deliver(
            kind: PaladinUserNotificationKind.executionStarted.rawValue,
            title: "Paladin",
            subtitle: missionName,
            body: "Execution started.",
            runID: runID
        )
    }
}
