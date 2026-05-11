import Foundation

// MARK: - OperatorPromptRoutingDecision

/// The pure output of an ``OperatorPromptRouter/route(_:)`` call. Describes which
/// delivery targets a given event will actually be dispatched to, which were
/// suppressed (wanted by the policy but rejected by the availability probe),
/// and which one is the operator-facing **primary**.
///
/// This is a value type with no side effects. The ``OperatorPromptCenter``
/// (Stage D follow-up) consumes a decision and performs the dispatching,
/// withdrawal, timeout, and answer-forwarding work.
struct OperatorPromptRoutingDecision: Equatable, Sendable {

    /// The event being routed. Kept on the decision so audit logging and
    /// downstream dispatch don't need to thread it separately.
    let event: OperatorPromptEvent

    /// Primary delivery target — the first policy-resolved target whose
    /// addressing matched the event **and** that the router's availability
    /// probe accepted. `nil` only when no policy-resolved target was
    /// available (rare; the default policy mirrors to ``OperatorPromptDeliveryTarget/inAppInbox``
    /// which is always-available in v1, so this is reachable only when a
    /// policy with `mirrorToInbox = false` runs against a probe that rejects
    /// everything).
    let primary: OperatorPromptDeliveryTarget?

    /// Targets that are available alongside the primary. The center dispatches
    /// to these too so the operator can see the prompt from any of their
    /// current surfaces; the first resolution wins and the center withdraws the
    /// rest.
    let mirrors: [OperatorPromptDeliveryTarget]

    /// Targets the policy wanted but the availability probe rejected — e.g. an
    /// MCR panel entry when no MCR window is mounted. Recorded so the audit
    /// log can answer "why didn't this fire on MCR?" without re-running the
    /// decision.
    let suppressed: [OperatorPromptDeliveryTarget]

    /// All targets the center will actually dispatch to, in preference order:
    /// `[primary] + mirrors` when a primary exists, else just `mirrors`.
    var dispatched: [OperatorPromptDeliveryTarget] {
        if let primary { return [primary] + mirrors }
        return mirrors
    }

    /// `true` when no target was available. Center can use this to escalate
    /// (e.g. fall back to an OS user notification with `mcrCriticalReturn`
    /// style) or to mark the event as "queued — operator returned to in-app
    /// presence required". Equivalent to `primary == nil && mirrors.isEmpty`.
    var isUnroutable: Bool {
        primary == nil && mirrors.isEmpty
    }
}

// MARK: - OperatorPromptRouter

/// Stage D's operator-prompt router. Lives on the main actor because routing
/// decisions are consumed by SwiftUI hosts that live there too.
///
/// ## Responsibilities (v1)
///
/// 1. Resolve the policy for an event's origin (via ``policyProvider``).
/// 2. Resolve the policy's entries against the event's addressing (delegates to
///    ``ProcessPromptPolicy/resolveTargets(for:)``).
/// 3. Classify each resolved target via ``availabilityProbe`` — accepted
///    targets become `primary` + `mirrors`, rejected become `suppressed`.
/// 4. Return a pure ``OperatorPromptRoutingDecision``. The router does **not**
///    dispatch; ``OperatorPromptCenter`` consumes the decision and owns the
///    dispatch / lifecycle / timeout / answer-forwarding work.
///
/// ## Why split router and center?
///
/// The decision is pure data and trivially testable; the center is stateful
/// (host registry, in-flight prompts, timeouts, answer-fan-in). Keeping them
/// separate means policy and routing edits don't need to touch any side-effect
/// machinery, and exhaustive routing tests can run with no UI fixture.
///
/// ## Defaults
///
/// - ``policyProvider`` defaults to ``ProcessPromptPolicy/default(for:)`` —
///   the per-origin defaults documented in `README.md`.
/// - ``availabilityProbe`` defaults to **inbox-only availability**: only
///   ``OperatorPromptDeliveryTarget/inAppInbox`` returns `true`, everything
///   else returns `false`. This is the safe v1 boot fallback — the router
///   functions before the center has registered a single host, and prompts
///   queue to the inbox.
@MainActor
final class OperatorPromptRouter: ObservableObject {

    // MARK: Shared instance

    /// App-wide router. The center owns the host registry and swaps in a real
    /// ``availabilityProbe`` at app start; tests construct their own instance.
    static let shared = OperatorPromptRouter()

    // MARK: Injection points

    /// Returns the policy for a given event origin. Default uses
    /// ``ProcessPromptPolicy/default(for:)``; the center can swap this for
    /// per-process overrides (Stage D follow-up).
    var policyProvider: @MainActor @Sendable (OperatorPromptOrigin) -> ProcessPromptPolicy

    /// Returns `true` when `target` can deliver right now. Encodes both host
    /// registry presence (e.g. is there an MCR panel mounted for this run id?)
    /// and operator-presence heuristics (e.g. OOA notification fires only when
    /// the operator is out of app). The center installs a real implementation
    /// at app start; the default below is the safe v1 fallback.
    var availabilityProbe: @MainActor @Sendable (OperatorPromptDeliveryTarget) -> Bool

    // MARK: Init

    init(
        policyProvider: @escaping @MainActor @Sendable (OperatorPromptOrigin) -> ProcessPromptPolicy = OperatorPromptRouter.defaultPolicyProvider,
        availabilityProbe: @escaping @MainActor @Sendable (OperatorPromptDeliveryTarget) -> Bool = OperatorPromptRouter.defaultAvailabilityProbe
    ) {
        self.policyProvider = policyProvider
        self.availabilityProbe = availabilityProbe
    }

    // MARK: Routing

    /// Compute the routing decision for `event`. Pure — no dispatching, no
    /// side effects, no state mutation. The center calls this and acts on the
    /// returned decision.
    ///
    /// The walk preserves policy order: the first available target is the
    /// primary, subsequent available targets become mirrors, and rejected
    /// targets are collected under `suppressed` for audit.
    func route(_ event: OperatorPromptEvent) -> OperatorPromptRoutingDecision {
        let policy = policyProvider(event.origin)
        let resolved = policy.resolveTargets(for: event)

        var primary: OperatorPromptDeliveryTarget?
        var mirrors: [OperatorPromptDeliveryTarget] = []
        var suppressed: [OperatorPromptDeliveryTarget] = []

        for target in resolved {
            if availabilityProbe(target) {
                if primary == nil {
                    primary = target
                } else {
                    mirrors.append(target)
                }
            } else {
                suppressed.append(target)
            }
        }

        return OperatorPromptRoutingDecision(
            event: event,
            primary: primary,
            mirrors: mirrors,
            suppressed: suppressed
        )
    }

    // MARK: Defaults

    /// Default policy provider — returns ``ProcessPromptPolicy/default(for:)``
    /// for the supplied origin. Stable across runs; the center swaps this in
    /// at startup for parity with future per-process overrides.
    static let defaultPolicyProvider: @MainActor @Sendable (OperatorPromptOrigin) -> ProcessPromptPolicy = { origin in
        ProcessPromptPolicy.default(for: origin)
    }

    /// Default availability probe — only ``OperatorPromptDeliveryTarget/inAppInbox``
    /// is accepted. Every other target returns `false`. Keeps the router safe
    /// to construct before any host has registered: prompts route to the inbox
    /// and queue for the operator's next visit.
    static let defaultAvailabilityProbe: @MainActor @Sendable (OperatorPromptDeliveryTarget) -> Bool = { target in
        target.isUniversalArchive
    }
}
