import Foundation

// MARK: - Stack-agnostic response taxonomy

/// Closed taxonomy of stack-agnostic outcome kinds. **Stack converters MUST translate
/// every raw outcome into one of these kinds** so Layer 1 recipes can branch reliably
/// without parsing free-form strings.
///
/// New cases are deliberate Layer 0 changes — adding one means every recipe that
/// branches on `error.<kind>` may need to consider the new outcome, and every stack
/// converter must declare whether/when it produces it.
///
/// `unknown` is the safety net for genuinely opaque autopilot outcomes. Recipes that
/// branch on it should treat it as an unrecoverable failure and escalate.
enum FleetCommandErrorKind: String, Equatable, Hashable, Sendable, Codable, CaseIterable {

    // MARK: Routing / preflight failures (catalogue-level)

    /// No descriptor registered for the requested name.
    case unknownCommand
    /// No `FleetVehicleModel` for the target vehicle ID.
    case noVehicle
    /// `FleetVehicleModel` exists but lifecycle is not `.live`.
    case notConnected
    /// MAVSDK session unavailable (e.g. SITL not running, link down).
    case noSession
    /// Authority gate / live-mission gate / live-drive gate refused the dispatch.
    case authorityGated
    /// Stack converter for the vehicle's autopilot stack does not implement this command.
    case notImplemented
    /// Catalogue dispatch itself failed (parameter validation, internal plumbing).
    case dispatchFailed

    // MARK: Vehicle-side outcomes (translated from autopilot)

    /// Autopilot reports the vehicle is already armed (arm command was a no-op).
    case alreadyArmed
    /// Autopilot reports the vehicle is already disarmed (disarm command was a no-op).
    case alreadyDisarmed
    /// Autopilot refused to arm — generic catch-all when no more specific kind applies.
    case armRejectedByAutopilot
    /// Autopilot refused to start a calibration procedure (already running, mode wrong, etc.).
    case calibrationDeclined
    /// Calibration was started and acknowledged but did not converge / failed mid-procedure.
    case calibrationDidNotConverge
    /// Parameter set/get refused by autopilot (wrong type, out of range, locked).
    case parameterRejected
    /// `PARAM_SET` succeeded over the wire but a follow-up `PARAM_REQUEST_READ`
    /// returned a value that does not match the requested value. Surfaces the
    /// common silent-clamp / silent-quantize / locked-parameter cases that a
    /// bare `MAV_RESULT_ACCEPTED` ack cannot detect. Recipes that branch on
    /// this should treat it as a calibration failure and either escalate or
    /// retry with a clamped value.
    case parameterReadBackMismatch
    /// Autopilot does not support the requested mode for this airframe / state.
    case modeNotSupported
    /// Autopilot has no known fault to clear, or refused to clear it.
    case errorClearRefused
    /// Autopilot reports it is busy with a higher-priority operation.
    case autopilotBusy

    // MARK: Catch-all

    /// The stack converter could not classify the raw outcome. Recipes should treat
    /// this as an unrecoverable failure and escalate.
    case unknown
}

/// Optional structured payload, used primarily by `command.get.*` reads.
///
/// Kept deliberately small: any new payload shape forces a corresponding recipe-side
/// matcher, so we add cases only when a real consumer needs them.
enum FleetCommandResponsePayload: Equatable, Sendable {
    case empty
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case stringList([String])
    /// String→String key/value pairs for compact telemetry snapshots. Order is not
    /// guaranteed to be stable across reads.
    case keyValues([String: String])

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }
}

// MARK: - Response

/// Normalised, typed response from a registered command invocation.
///
/// Every Layer 1 recipe step receives one of these. Branching matches against the
/// `outcome` (and, for `.error`, the inner ``FleetCommandErrorKind``).
struct FleetCommandResponse: Equatable, Sendable {

    /// Top-level outcome.
    enum Outcome: Equatable, Sendable {
        /// The command completed and produced its intended effect.
        case succeeded
        /// The command failed in a way the converter could classify.
        case error(kind: FleetCommandErrorKind)
        /// The command was cancelled before completing (operator or runner cancel).
        case cancelled
        /// The command did not produce an outcome within the runner's budget.
        case timeout
    }

    /// What happened.
    let outcome: Outcome

    /// Free-form human-readable detail (logs, UI subtitles). Never used for branching.
    let detail: String?

    /// Structured payload, usually empty for `do.*` and `cancel.*` commands and
    /// populated for `get.*` commands.
    let payload: FleetCommandResponsePayload

    /// Wall-clock time the command spent in flight. `nil` when the dispatcher could not
    /// measure it (immediate gate failures, e.g. `.unknownCommand`).
    let elapsed: TimeInterval?

    // MARK: Convenience

    static func success(
        detail: String? = nil,
        payload: FleetCommandResponsePayload = .empty,
        elapsed: TimeInterval? = nil
    ) -> FleetCommandResponse {
        FleetCommandResponse(outcome: .succeeded, detail: detail, payload: payload, elapsed: elapsed)
    }

    static func error(
        _ kind: FleetCommandErrorKind,
        detail: String? = nil,
        payload: FleetCommandResponsePayload = .empty,
        elapsed: TimeInterval? = nil
    ) -> FleetCommandResponse {
        FleetCommandResponse(outcome: .error(kind: kind), detail: detail, payload: payload, elapsed: elapsed)
    }

    static func cancelled(
        detail: String? = nil,
        elapsed: TimeInterval? = nil
    ) -> FleetCommandResponse {
        FleetCommandResponse(outcome: .cancelled, detail: detail, payload: .empty, elapsed: elapsed)
    }

    static func timeout(
        detail: String? = nil,
        elapsed: TimeInterval? = nil
    ) -> FleetCommandResponse {
        FleetCommandResponse(outcome: .timeout, detail: detail, payload: .empty, elapsed: elapsed)
    }

    // MARK: Accessors

    /// `true` when the response represents a successful completion.
    var isSuccess: Bool {
        if case .succeeded = outcome { return true }
        return false
    }

    /// Underlying error kind, when ``outcome`` is `.error`.
    var errorKind: FleetCommandErrorKind? {
        if case .error(let kind) = outcome { return kind }
        return nil
    }
}
