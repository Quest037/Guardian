import Foundation

// MARK: - Recipe outcome

/// Final outcome reported by ``FleetRecipeRunner/run(...)``. **Binary by locked
/// decision** (succeeded or failed) — `.cancelled` and timeout / budget-breach
/// scenarios are surfaced as `failed` variants with attribution in ``detail``.
///
/// The runner does **not** report partial-success outcomes — if a step matcher
/// returns `.fail`, the entire run is failed. `escalate` is also not a third
/// outcome at this layer; it suspends the runner until a resumption verb resolves
/// the escalation back into one of the two outcomes below.
enum FleetRecipeOutcome: Equatable, Sendable {

    /// Recipe completed successfully — either by walking off the end of the body
    /// or by an explicit `.succeed` control outcome. `payload` is the last
    /// dispatched response's payload (empty for pure `.do.*` recipes).
    case succeeded(detail: String?, payload: FleetCommandResponsePayload, trace: FleetRecipeAuditTrace)

    /// Recipe failed. `failingCommandPath` is the path through the body to the
    /// offending step. `lastResponse` is the last response observed by the
    /// runner (`nil` only when the run never reached a dispatch, e.g. parameter
    /// validation refused the run at entry). `detail` carries the human-facing
    /// failure reason (`"recipe budget exceeded"`, `"operator aborted"`, etc.).
    case failed(
        failingCommandPath: [FleetRecipeStepID],
        lastResponse: FleetCommandResponse?,
        detail: String?,
        trace: FleetRecipeAuditTrace
    )

    // MARK: Accessors

    /// `true` for `.succeeded(...)`.
    var isSuccess: Bool {
        if case .succeeded = self { return true }
        return false
    }

    /// Audit trace for the run, regardless of outcome.
    var trace: FleetRecipeAuditTrace {
        switch self {
        case .succeeded(_, _, let trace): return trace
        case .failed(_, _, _, let trace): return trace
        }
    }

    /// Convenience: human-readable single-line summary of the outcome.
    var loggable: String {
        switch self {
        case .succeeded(let detail, _, _):
            return "succeeded\(detail.map { " (\($0))" } ?? "")"
        case .failed(let path, let lastResponse, let detail, _):
            let pathPart = path.map(\.rawValue).joined(separator: " -> ")
            let outcomePart: String
            switch lastResponse?.outcome {
            case .none: outcomePart = "no dispatch"
            case .succeeded?: outcomePart = "lastResponse succeeded"
            case .error(let kind)?: outcomePart = "lastResponse error.\(kind.rawValue)"
            case .cancelled?: outcomePart = "lastResponse cancelled"
            case .timeout?: outcomePart = "lastResponse timeout"
            }
            return "failed at [\(pathPart)] (\(outcomePart))\(detail.map { ": \($0)" } ?? "")"
        }
    }
}
