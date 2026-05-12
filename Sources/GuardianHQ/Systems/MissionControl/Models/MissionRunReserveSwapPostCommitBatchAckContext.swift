import Foundation

// MARK: - Post-commit reserve swap batch (fleet ack correlation)

/// Carried on ``MissionRunQueuedCommandBatch/reserveSwapPostCommitAckContext`` so the executor can emit
/// ``MissionRunReserveSwapPipelinePhase`` pass/fail lines **after** fleet acks and surface operator toasts on failure.
struct MissionRunReserveSwapPostCommitBatchAckContext: Equatable, Sendable {
    let correlation: MissionRunReserveRecipeRunnerCorrelation
    let triggerSource: String
}

// MARK: - Window-level operator toast (Mission Control has no `ToastCenter` handle here)

enum GuardianReserveSwapPostCommitOperatorToastNotification {
    /// `userInfo`: ``messageKey`` (`String`), ``severityRawKey`` (`String`, ``GuardianFeedbackSeverity/rawValue``).
    static let name = Notification.Name("guardianhq.reserveSwap.postCommitOperatorToast")

    static let messageKey = "guardianhq.reserveSwap.postCommitOperatorToast.message"
    static let severityRawKey = "guardianhq.reserveSwap.postCommitOperatorToast.severity"
}

// MARK: - Phase inference (post-commit batch rows)

enum MissionRunReserveSwapPostCommitPipelinePhaseResolver: Sendable {
    /// Maps a queued post-commit command to the swap pipeline phase used for ``MissionRunReserveSwapPhaseLogTemplateKey``.
    static func phase(
        for issued: MissionRunIssuedCommand,
        correlation: MissionRunReserveRecipeRunnerCorrelation
    ) -> MissionRunReserveSwapPipelinePhase {
        if case .catalogue(let name, _) = issued.dispatch, name == .fleetVehicleDoMissionClear {
            return .displacedMissionClear
        }
        if case .recipe(let name, _) = issued.dispatch,
           issued.assignmentID == correlation.vacancyAssignmentID {
            let raw = name.rawValue
            if raw == "recipe.fleet.do.mission.upload.start" || raw == "recipe.fleet.do.mission.upload.start.item" {
                return .missionUpload
            }
        }
        return .displacedFleetWindDown
    }
}
