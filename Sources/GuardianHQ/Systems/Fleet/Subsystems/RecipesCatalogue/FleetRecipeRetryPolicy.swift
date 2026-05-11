import Foundation

// MARK: - Retry policy

/// Per-step retry policy for a recipe.
///
/// The Layer 0 catalogue is single-shot. Retry is a **Layer 1** concern that the
/// recipe runner consumes: when a step's response matches one of the retryable
/// triggers, the runner waits ``delaySeconds`` and re-invokes the underlying
/// command, up to ``maxAttempts`` additional attempts. The initial attempt does
/// **not** count toward ``maxAttempts``.
///
/// Two locked v1 decisions live here:
///
/// 1. **Catalogue default** (``catalogueDefault``): `1 retry, fixed 250 ms delay,
///    only on { timeout, .noSession, .autopilotBusy }`. Authoritative when neither
///    a step nor a recipe declares its own policy.
/// 2. **Hard caps** enforced at recipe registration / DSL parse time
///    (``maxAttemptsCap``, ``maxDelaySecondsCap``, ``maxWorstCaseAdditionalSecondsCap``).
///    A descriptor whose retry policy exceeds the caps is rejected by the registry
///    unless its descriptor opts out via `relaxRetryCaps = true` (the "I know what
///    I'm doing, log it but allow it" escape hatch).
struct FleetRecipeRetryPolicy: Equatable, Hashable, Sendable {

    // MARK: Constants (caps)

    /// Maximum additional retries allowed beyond the initial attempt.
    /// Catalogue default authors should rarely need more than 1; cap is intentionally
    /// stingy to surface authoring mistakes early.
    static let maxAttemptsCap: Int = 5

    /// Maximum delay between retries.
    static let maxDelaySecondsCap: TimeInterval = 5

    /// Maximum total wall-clock spent purely on retry-backoff across a single step
    /// (≈ `maxAttempts × delaySeconds`). Independent of the step's command timeout.
    static let maxWorstCaseAdditionalSecondsCap: TimeInterval = 15

    // MARK: Configuration

    /// Additional retries beyond the initial attempt. `0` disables retries.
    let maxAttempts: Int

    /// Fixed delay between retries, in seconds. v1 only supports fixed delay; an
    /// exponential variant can land later behind the same field if/when needed.
    let delaySeconds: TimeInterval

    /// Closed set of ``FleetCommandErrorKind`` cases whose `.error(kind:)` outcome
    /// triggers a retry.
    let retryableErrorKinds: Set<FleetCommandErrorKind>

    /// When `true`, a top-level `.timeout` outcome also triggers a retry. Modelled
    /// separately from ``retryableErrorKinds`` because timeout is its own outcome
    /// case in ``FleetCommandResponse/Outcome``, not a `FleetCommandErrorKind`.
    let retryOnTimeout: Bool

    init(
        maxAttempts: Int,
        delaySeconds: TimeInterval,
        retryableErrorKinds: Set<FleetCommandErrorKind>,
        retryOnTimeout: Bool
    ) {
        self.maxAttempts = maxAttempts
        self.delaySeconds = delaySeconds
        self.retryableErrorKinds = retryableErrorKinds
        self.retryOnTimeout = retryOnTimeout
    }

    // MARK: Locked defaults

    /// **v1 catalogue default — locked.**
    ///
    /// `1 retry, fixed 250 ms delay, only on transient kinds`.
    /// Used by the runner when a step omits its own policy and the recipe declares
    /// no recipe-level default.
    ///
    /// Rationale (see `CommandsRecipesToDo.md` open-questions resolution): retries
    /// are a transient-flake tool, not a flaky-transport tool. Authority and
    /// validation failures are deterministic — retrying them just wastes the
    /// recipe budget. Fixed delay (rather than exponential) keeps unit tests
    /// deterministic and is sufficient for a single-drone single-link transport.
    static let catalogueDefault: FleetRecipeRetryPolicy = FleetRecipeRetryPolicy(
        maxAttempts: 1,
        delaySeconds: 0.25,
        retryableErrorKinds: [.noSession, .autopilotBusy],
        retryOnTimeout: true
    )

    /// Explicit "do not retry". Recipes / steps that should fail-fast on the first
    /// response declare this so the absence of retries is intentional rather than
    /// inherited from the catalogue default.
    static let disabled: FleetRecipeRetryPolicy = FleetRecipeRetryPolicy(
        maxAttempts: 0,
        delaySeconds: 0,
        retryableErrorKinds: [],
        retryOnTimeout: false
    )

    // MARK: Match

    /// Whether the supplied response would trigger a retry under this policy. Pure
    /// function over the policy and the response; the runner consults this to
    /// decide whether to schedule another attempt.
    func shouldRetry(_ response: FleetCommandResponse) -> Bool {
        switch response.outcome {
        case .succeeded, .cancelled:
            return false
        case .timeout:
            return retryOnTimeout
        case .error(let kind):
            return retryableErrorKinds.contains(kind)
        }
    }

    // MARK: Cap validation

    /// One cap violation produced by ``violations(for:)``. Equatable for tests,
    /// `CustomStringConvertible` for log lines.
    struct CapViolation: Equatable, Hashable, Sendable, CustomStringConvertible {
        let kind: Kind
        let actual: Double
        let cap: Double

        enum Kind: String, Equatable, Hashable, Sendable {
            case maxAttempts
            case delaySeconds
            case worstCaseAdditionalSeconds
            case negativeMaxAttempts
            case negativeDelay
        }

        var description: String {
            switch kind {
            case .maxAttempts:
                return "maxAttempts \(Int(actual)) exceeds cap \(Int(cap))"
            case .delaySeconds:
                return "delaySeconds \(actual)s exceeds cap \(cap)s"
            case .worstCaseAdditionalSeconds:
                return "worst-case additional time \(actual)s exceeds cap \(cap)s"
            case .negativeMaxAttempts:
                return "maxAttempts \(Int(actual)) is negative"
            case .negativeDelay:
                return "delaySeconds \(actual) is negative"
            }
        }
    }

    /// Every cap violation in the supplied policy. Empty means within bounds.
    static func violations(for policy: FleetRecipeRetryPolicy) -> [CapViolation] {
        var out: [CapViolation] = []
        if policy.maxAttempts < 0 {
            out.append(CapViolation(
                kind: .negativeMaxAttempts,
                actual: Double(policy.maxAttempts),
                cap: 0
            ))
        }
        if policy.delaySeconds < 0 {
            out.append(CapViolation(
                kind: .negativeDelay,
                actual: policy.delaySeconds,
                cap: 0
            ))
        }
        if policy.maxAttempts > maxAttemptsCap {
            out.append(CapViolation(
                kind: .maxAttempts,
                actual: Double(policy.maxAttempts),
                cap: Double(maxAttemptsCap)
            ))
        }
        if policy.delaySeconds > maxDelaySecondsCap {
            out.append(CapViolation(
                kind: .delaySeconds,
                actual: policy.delaySeconds,
                cap: maxDelaySecondsCap
            ))
        }
        let worstCase = Double(max(0, policy.maxAttempts)) * max(0, policy.delaySeconds)
        if worstCase > maxWorstCaseAdditionalSecondsCap {
            out.append(CapViolation(
                kind: .worstCaseAdditionalSeconds,
                actual: worstCase,
                cap: maxWorstCaseAdditionalSecondsCap
            ))
        }
        return out
    }
}

// MARK: - Codable

extension FleetRecipeRetryPolicy: Codable {
    private enum CodingKeys: String, CodingKey {
        case maxAttempts
        case delaySeconds
        case retryableErrorKinds
        case retryOnTimeout
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let maxAttempts = try c.decode(Int.self, forKey: .maxAttempts)
        let delaySeconds = try c.decode(TimeInterval.self, forKey: .delaySeconds)
        let kinds = try c.decode([FleetCommandErrorKind].self, forKey: .retryableErrorKinds)
        let onTimeout = try c.decode(Bool.self, forKey: .retryOnTimeout)
        self.init(
            maxAttempts: maxAttempts,
            delaySeconds: delaySeconds,
            retryableErrorKinds: Set(kinds),
            retryOnTimeout: onTimeout
        )
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(maxAttempts, forKey: .maxAttempts)
        try c.encode(delaySeconds, forKey: .delaySeconds)
        // Deterministic encoding order so DSL diffs stay readable.
        try c.encode(retryableErrorKinds.sorted(by: { $0.rawValue < $1.rawValue }), forKey: .retryableErrorKinds)
        try c.encode(retryOnTimeout, forKey: .retryOnTimeout)
    }
}
