import Foundation

/// When Training / Formations sim cards should offer **Retry** (reconnect + preflight).
enum GuardianSimulatorSlotRecoveryPolicy {
    static func shouldOfferRetry(slot: FormationsPlaygroundSlotState) -> Bool {
        slot.vehicleID != nil && slot.preflightPassed != true
    }

    /// Linked telemetry but auto preflight failed — offer a dedicated preflight retry control.
    static func shouldOfferPreflightRetry(slot: FormationsPlaygroundSlotState) -> Bool {
        slot.vehicleID != nil && slot.linkReady && slot.preflightPassed == false
    }

    static func retryButtonTitle(linkReady: Bool, phase: TrainingPanelPhase?) -> String {
        if linkReady { return "Retry preflight" }
        if phase == .connecting { return "Retry link" }
        return "Retry"
    }

    static func formationRetryButtonTitle(linkReady: Bool, isConnecting: Bool) -> String {
        if linkReady { return "Retry preflight" }
        if isConnecting { return "Retry link" }
        return "Retry"
    }
}
