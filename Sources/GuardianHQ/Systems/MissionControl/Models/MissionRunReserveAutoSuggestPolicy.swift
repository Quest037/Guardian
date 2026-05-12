import Foundation

// MARK: - Reason

/// Why Mission Control may **suggest** a floating-reserve swap (toast only — no automatic roster commit).
enum MissionRunReserveAutoSuggestReason: Equatable, Sendable, CaseIterable {
    /// Hub telemetry has not updated for longer than ``MissionRunReserveAutoSuggestPolicy/defaultLinkStaleThresholdSeconds``.
    case linkStale
    /// A catalogue / vehicle command recently failed for this vehicle (see ``MissionRunReserveAutoSuggestPolicy/recentFleetDispatchFailureTemplateKeys``).
    case recentFleetDispatchFailure
    /// Battery traffic band is ``warn`` or ``critical`` (aligned with roster traffic-light bands).
    case lowBattery
    /// Flight mode string looks like RTL / return-home / RTH (substring heuristic on raw MAVLink mode text).
    case returnHomeMode

    /// Operator-facing toast body (MC-R only).
    var operatorToastBody: String {
        switch self {
        case .linkStale:
            return "Telemetry for this aircraft looks stale. A class-matched reserve is available on this task — use Swap in reserve if you need a replacement."
        case .recentFleetDispatchFailure:
            return "A recent vehicle command did not succeed. A class-matched reserve is available — use Swap in reserve if you want to try another airframe."
        case .lowBattery:
            return "Battery on this roster aircraft is low. A class-matched reserve is available — use Swap in reserve if you want to replace it."
        case .returnHomeMode:
            return "This aircraft is in a return-home style mode. A class-matched reserve is available — use Swap in reserve after you land if you need a fresh airframe on the roster."
        }
    }
}

// MARK: - Gating + signals

/// Inputs for **when** auto-suggest is allowed (mission / task lifecycle).
struct MissionRunReserveAutoSuggestGatingSnapshot: Equatable, Sendable {
    let runStatus: MissionRunStatus
    let sessionPhase: MissionRunSessionPhase
    let taskState: MissionTaskState?
    /// When non-`nil`, the task has in-flight abort/complete wind-down intent — suppress suggests.
    let taskAttemptState: MissionTaskAttemptState?
    let hasClassCompatibleFloatingReserve: Bool
}

/// Telemetry-derived inputs for one roster-bound vehicle.
struct MissionRunReserveAutoSuggestSignalSnapshot: Equatable, Sendable {
    let batteryTraffic: FleetVehicleBatteryTrafficBand
    /// Seconds since last hub update; `nil` when no hub slice exists for this vehicle.
    let telemetryAgeS: TimeInterval?
    /// Raw MAVLink flight mode string from the hub (may include enum prefix).
    let flightModeRaw: String
}

// MARK: - Policy

/// v1 rules for **suggesting** a reserve swap from live MC-R telemetry + run log signals, and shared lifecycle / signal
/// helpers for the **autonomous reserve auto-swap executor** (``MissionRunReserveAutoSwapLiveEvaluator``).
///
/// Gating matches operator intent: no suggests while the run is not in ``MissionRunSessionPhase/executing``,
/// while the focused task is winding down (``MissionTaskState`` / ``MissionTaskAttemptState``), or when
/// no class-compatible floating reserve exists for the vacancy.
enum MissionRunReserveAutoSuggestPolicy: Sendable {

    /// Hub silence threshold before ``MissionRunReserveAutoSuggestReason/linkStale`` fires.
    static let defaultLinkStaleThresholdSeconds: TimeInterval = 45

    /// How far back to scan ``MissionRunEvent`` rows for fleet ack failures tied to this ``vehicleID``.
    static let defaultFleetFailureLookbackSeconds: TimeInterval = 120

    /// Minimum spacing between toasts per **fleet vehicle id** so telemetry flicker does not spam.
    static let defaultToastDebouncePerVehicleSeconds: TimeInterval = 120

    /// `MissionRunEvent.templateKey` values that count as a recent dispatch failure for this feature.
    static let recentFleetDispatchFailureTemplateKeys: Set<String> = [
        MissionRunLogTemplateKey.fleetAckFailed,
        MissionRunLogTemplateKey.commandNotSent,
        MissionRunLogTemplateKey.commandInvalidToken,
        MissionRunLogTemplateKey.commandVehicleUnavailable,
    ]

    // MARK: Gating

    /// Shared lifecycle gate for MC-R **distress-driven** reserve automation (suggest toasts and autonomous swap executor).
    static func gatingAllowsReserveDistressAutomationCore(
        runStatus: MissionRunStatus,
        sessionPhase: MissionRunSessionPhase,
        taskState: MissionTaskState?,
        taskAttemptState: MissionTaskAttemptState?
    ) -> Bool {
        guard sessionPhase == .executing else { return false }
        switch runStatus {
        case .running, .paused:
            break
        default:
            return false
        }
        if taskAttemptState != nil { return false }
        guard let taskState else { return false }
        switch taskState {
        case .executing, .between:
            return true
        default:
            return false
        }
    }

    static func gatingAllowsSuggest(_ gating: MissionRunReserveAutoSuggestGatingSnapshot) -> Bool {
        guard gating.hasClassCompatibleFloatingReserve else { return false }
        return gatingAllowsReserveDistressAutomationCore(
            runStatus: gating.runStatus,
            sessionPhase: gating.sessionPhase,
            taskState: gating.taskState,
            taskAttemptState: gating.taskAttemptState
        )
    }

    // MARK: Signals

    /// `true` when `raw` looks like RTL / return / RTH (best-effort substring match on MAVLink mode text).
    static func flightModeLooksLikeReturnHome(_ raw: String) -> Bool {
        let u = raw.uppercased()
        if u.contains("RTL") { return true }
        if u.contains("RETURN") { return true }
        if u.contains("RTH") { return true }
        if u.contains("SMART_RTL") || u.contains("SMARTRTL") { return true }
        return false
    }

    static func recentFleetDispatchFailure(
        events: [MissionRunEvent],
        vehicleID: String,
        lookback: TimeInterval,
        now: Date
    ) -> Bool {
        let cutoff = now.addingTimeInterval(-lookback)
        for e in events.reversed() where e.at >= cutoff {
            guard let key = e.templateKey, recentFleetDispatchFailureTemplateKeys.contains(key) else { continue }
            let vid = e.templateParams["vehicleID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if vid == vehicleID { return true }
        }
        return false
    }

    /// Distress signals only (no lifecycle / floating-pool gate). Used by the autonomous **auto-swap** executor together with ``gatingAllowsReserveDistressAutomationCore`` and a unique swap candidate.
    static func firstDistressSignalReason(
        signals: MissionRunReserveAutoSuggestSignalSnapshot,
        recentFleetDispatchFailure: Bool,
        linkStaleThreshold: TimeInterval = defaultLinkStaleThresholdSeconds
    ) -> MissionRunReserveAutoSuggestReason? {
        if let age = signals.telemetryAgeS, age.isFinite, age > linkStaleThreshold {
            return .linkStale
        }
        if recentFleetDispatchFailure {
            return .recentFleetDispatchFailure
        }
        switch signals.batteryTraffic {
        case .warn, .critical:
            return .lowBattery
        case .ok, .unknown:
            break
        }
        if flightModeLooksLikeReturnHome(signals.flightModeRaw) {
            return .returnHomeMode
        }
        return nil
    }

    /// First matching reason in priority order, or `nil` when gating fails or no signal fires.
    static func firstSuggestReason(
        gating: MissionRunReserveAutoSuggestGatingSnapshot,
        signals: MissionRunReserveAutoSuggestSignalSnapshot,
        recentFleetDispatchFailure: Bool,
        linkStaleThreshold: TimeInterval = defaultLinkStaleThresholdSeconds
    ) -> MissionRunReserveAutoSuggestReason? {
        guard gatingAllowsSuggest(gating) else { return nil }
        return firstDistressSignalReason(
            signals: signals,
            recentFleetDispatchFailure: recentFleetDispatchFailure,
            linkStaleThreshold: linkStaleThreshold
        )
    }

    /// Whether enough time passed since the last toast for `vehicleID` (inclusive debounce).
    static func debounceAllowsToast(
        lastToastAt: Date?,
        debounce: TimeInterval,
        now: Date
    ) -> Bool {
        guard let lastToastAt else { return true }
        return now.timeIntervalSince(lastToastAt) >= debounce
    }
}
