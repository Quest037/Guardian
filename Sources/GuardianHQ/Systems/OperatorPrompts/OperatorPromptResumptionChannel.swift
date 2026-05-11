import Combine
import Foundation

// MARK: - OperatorPromptResumptionChannel

/// The resumption-channel of Stage D. Carries operator answers back from the
/// delivery surfaces to the publisher (`FleetRecipeRunner` escalation handler,
/// MRE engagement planner, freeform plugin/banner). Pure transport — no host
/// knowledge, no routing decisions, no dispatch.
///
/// ## Architecture
///
/// Publisher → emits ``OperatorPromptEvent`` → `OperatorPromptCenter` (next
/// item) routes via ``OperatorPromptRouter`` → dispatches to live hosts → hosts
/// call ``submit(_:)`` here when the operator picks an option → channel resumes
/// the publisher's suspended continuation.
///
/// The publisher API is a single async call:
///
/// ```swift
/// let answer = await OperatorPromptResumptionChannel.shared.awaitAnswer(for: event)
/// ```
///
/// `answer.verb` is the closed transport (``FleetRecipeResumptionVerb``) every
/// process consumes; `answer.selectedOptionID` gives publisher-side branching;
/// `answer.remember` feeds the `OperatorDecisionCache` (Stage D follow-up).
///
/// ## Cancellation
///
/// `awaitAnswer(for:)` respects Swift Task cancellation. When the publisher's
/// task is cancelled while awaiting an answer, the channel resolves the pending
/// event with a synthesised timeout-style answer (`verb = .abort` when allowed,
/// else the first ``OperatorPromptEvent/allowedVerbs`` entry) and cleans up.
/// This keeps the publisher's `await` from leaking and lets cancellation
/// propagate end-to-end without the publisher needing custom logic.
///
/// ## Audit stream
///
/// ``allAnswers`` is a Combine publisher that emits every resolved answer.
/// The Stage D inbox / audit-log surfaces subscribe to it; the channel itself
/// does not retain history (the inbox owns persistence).
@MainActor
final class OperatorPromptResumptionChannel: ObservableObject {

    // MARK: Shared instance

    /// App-wide channel. Tests construct their own instance to keep continuation
    /// state isolated.
    static let shared = OperatorPromptResumptionChannel()

    // MARK: State

    /// Pending publisher continuations keyed by event id. Touched only from
    /// the main actor; the channel's `@MainActor` annotation ensures all
    /// mutations are serialised through the main queue.
    private var pending: [UUID: CheckedContinuation<OperatorPromptAnswer, Never>] = [:]

    /// Audit-stream subject. Every resolved answer (operator, cache, timeout,
    /// cancellation) flows through here in publish order.
    private let auditSubject = PassthroughSubject<OperatorPromptAnswer, Never>()

    /// Resolved-answer stream for the inbox / audit-log subscribers. Drops no
    /// values; back-pressure is the subscriber's concern.
    var allAnswers: AnyPublisher<OperatorPromptAnswer, Never> {
        auditSubject.eraseToAnyPublisher()
    }

    /// Convenience: how many events are currently awaiting an answer. Exposed
    /// for diagnostics and tests.
    var pendingCount: Int { pending.count }

    init() {}

    // MARK: Publisher API

    /// Suspend until `event` is resolved. The returned answer's `verb` is
    /// guaranteed to be a member of `event.allowedVerbs` when produced by a
    /// well-behaved host; the channel itself does not enforce membership (the
    /// recipe runner already validates resumption verbs and rejects disallowed
    /// ones with attribution).
    ///
    /// When `event` is already expired at call time, returns a synthesised
    /// timeout answer immediately without ever publishing a continuation.
    /// When the calling Task is cancelled before an answer arrives, returns
    /// the same synthesised timeout answer and cleans up.
    func awaitAnswer(for event: OperatorPromptEvent) async -> OperatorPromptAnswer {
        if event.isExpired() {
            let answer = event.synthesisedTimeoutAnswer()
            auditSubject.send(answer)
            return answer
        }

        return await withTaskCancellationHandler { [weak self] in
            await withCheckedContinuation { (continuation: CheckedContinuation<OperatorPromptAnswer, Never>) in
                guard let self else {
                    continuation.resume(returning: event.synthesisedTimeoutAnswer())
                    return
                }
                if let existing = self.pending[event.id] {
                    // Duplicate await for the same event id. Resolve the
                    // existing waiter with the timeout answer first so it
                    // unblocks, then install the new continuation. This is
                    // exceptional (a single publisher should not await twice
                    // for the same event); the audit stream records the
                    // synthesised resolution.
                    let timeoutAnswer = event.synthesisedTimeoutAnswer()
                    existing.resume(returning: timeoutAnswer)
                    self.auditSubject.send(timeoutAnswer)
                }
                self.pending[event.id] = continuation
            }
        } onCancel: { [weak self] in
            // `onCancel` runs on the cancelling task's executor, not on the
            // main actor. Hop back to drain the pending entry safely.
            Task { @MainActor [weak self] in
                self?.handleCancellation(for: event)
            }
        }
    }

    // MARK: Host / center / cache API

    /// Submit an answer for a pending event. Returns `true` when the answer
    /// was applied to a waiting publisher; `false` when no waiter was found
    /// (the event resolved already via a race, or was never registered).
    ///
    /// The audit-stream emits the answer on every successful application —
    /// the inbox and audit-log consumers see exactly the answers that
    /// publishers received.
    @discardableResult
    func submit(_ answer: OperatorPromptAnswer) -> Bool {
        guard let continuation = pending.removeValue(forKey: answer.promptID) else {
            return false
        }
        continuation.resume(returning: answer)
        auditSubject.send(answer)
        return true
    }

    /// Synthesise the timeout answer for `event` and submit it. Convenience
    /// for the center's expiry timer; equivalent to
    /// `submit(event.synthesisedTimeoutAnswer())`.
    @discardableResult
    func resolveExpiry(for event: OperatorPromptEvent) -> Bool {
        submit(event.synthesisedTimeoutAnswer())
    }

    // MARK: Test hooks

    /// Drop every pending continuation and resume each with a synthesised
    /// abort answer. Test-only — the production path never invokes this.
    @MainActor
    func _testOnlyDrain() {
        let snapshot = pending
        pending.removeAll()
        for (_, continuation) in snapshot {
            // No event context here; synthesise a minimal abort answer so the
            // waiter unblocks. Tests that need richer semantics submit a real
            // answer instead.
            let synthesised = OperatorPromptAnswer(
                promptID: UUID(),
                selectedOptionID: OperatorPromptOption.timeoutOptionID,
                verb: .abort,
                remember: false,
                resolution: .timeoutAborted
            )
            continuation.resume(returning: synthesised)
        }
    }

    // MARK: Private

    private func handleCancellation(for event: OperatorPromptEvent) {
        guard let continuation = pending.removeValue(forKey: event.id) else { return }
        let answer = event.synthesisedTimeoutAnswer()
        continuation.resume(returning: answer)
        auditSubject.send(answer)
    }
}

// MARK: - Timeout-answer synthesis

extension OperatorPromptEvent {

    /// Synthesise the answer the resumption channel uses on timeout, task
    /// cancellation, or any other publisher-side terminal condition that did
    /// not produce an operator choice.
    ///
    /// - `verb` is `.abort` when `.abort` is in ``allowedVerbs``, otherwise the
    ///   first entry in ``allowedVerbs`` (the publisher always declares at
    ///   least one allowed verb). When ``allowedVerbs`` is empty — which Stage
    ///   B's escalation contract rules out but the prompt event type does not
    ///   itself enforce — the fallback is `.abort` so the runner can still
    ///   close out the run with a closed verb.
    /// - `selectedOptionID` is ``OperatorPromptOption/timeoutOptionID``
    ///   (`"verb.timeout"`) so consumers can distinguish synthesised resolutions
    ///   from operator-chosen ones.
    /// - `remember` is always `false` — a timeout-resolution is never written
    ///   to the decision cache.
    /// - `resolution` is ``OperatorPromptResolutionSource/timeoutAborted``.
    func synthesisedTimeoutAnswer(at when: Date = Date()) -> OperatorPromptAnswer {
        let verb: FleetRecipeResumptionVerb
        if allowedVerbs.contains(.abort) {
            verb = .abort
        } else if let first = allowedVerbs.first {
            verb = first
        } else {
            verb = .abort
        }
        return OperatorPromptAnswer(
            promptID: id,
            selectedOptionID: OperatorPromptOption.timeoutOptionID,
            verb: verb,
            remember: false,
            resolution: .timeoutAborted,
            answeredAt: when
        )
    }
}
