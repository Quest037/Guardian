import Combine
import Foundation

// MARK: - OperatorPromptCenter

/// Stateful Stage D host: routes via ``OperatorPromptRouter``, mirrors prompts that
/// dispatch to ``OperatorPromptDeliveryTarget/inAppInbox`` into a live inbox list,
/// schedules expiry, and bridges ``OperatorPromptResumptionChannel/awaitAnswer(for:)``.
///
/// Production publishers should use ``OperatorPromptCenter/shared`` and
/// ``awaitAnswer(for:)`` so the universal inbox stays aligned with pending work.
@MainActor
final class OperatorPromptCenter: ObservableObject {

    // MARK: Shared

    static let shared = OperatorPromptCenter(
        router: OperatorPromptRouter.shared,
        resumption: OperatorPromptResumptionChannel.shared
    )

    // MARK: State

    /// Prompts currently mirrored to the in-app inbox (routing included ``OperatorPromptDeliveryTarget/inAppInbox``).
    @Published private(set) var inboxPrompts: [OperatorPromptEvent] = []

    private let router: OperatorPromptRouter
    private let resumption: OperatorPromptResumptionChannel

    // MARK: Init

    init(router: OperatorPromptRouter, resumption: OperatorPromptResumptionChannel) {
        self.router = router
        self.resumption = resumption
    }

    // MARK: Session wiring

    /// Installs this center as the source of ``OperatorPromptRouter/availabilityProbe``
    /// for the router instance this center was constructed with. Safe to call more than once.
    func prepareOperatorPromptRoutingSession() {
        router.availabilityProbe = { [weak self] target in
            guard let self else { return OperatorPromptRouter.defaultAvailabilityProbe(target) }
            return self.evaluateDeliveryAvailability(for: target)
        }
    }

    /// v1 availability: only the universal inbox drawer is a live delivery host.
    /// Contextual panels register in a later pass.
    func evaluateDeliveryAvailability(for target: OperatorPromptDeliveryTarget) -> Bool {
        switch target {
        case .inAppInbox: return true
        default: return false
        }
    }

    // MARK: Publisher API

    /// Routes `event`, mirrors to the inbox list when policy dispatches ``OperatorPromptDeliveryTarget/inAppInbox``,
    /// arms an expiry task, then suspends on ``OperatorPromptResumptionChannel`` until resolution.
    func awaitAnswer(for event: OperatorPromptEvent) async -> OperatorPromptAnswer {
        if event.isExpired() {
            return await resumption.awaitAnswer(for: event)
        }

        let decision = router.route(event)
        let mirrorsInbox = decision.dispatched.contains(.inAppInbox)
        if mirrorsInbox {
            registerInbox(event)
        }

        let expiry = scheduleExpiry(for: event)
        defer {
            expiry.cancel()
            if mirrorsInbox {
                unregisterInbox(promptID: event.id)
            }
        }

        return await resumption.awaitAnswer(for: event)
    }

    /// Applies an operator-chosen (or synthesised) answer. Delivery surfaces call this
    /// instead of touching ``OperatorPromptResumptionChannel`` directly so the center
    /// stays the single write path for inbox-adjacent actions.
    @discardableResult
    func submitAnswer(_ answer: OperatorPromptAnswer) -> Bool {
        resumption.submit(answer)
    }

    @discardableResult
    func resolveExpiry(for event: OperatorPromptEvent) -> Bool {
        resumption.resolveExpiry(for: event)
    }

    // MARK: Inbox mutations

    private func registerInbox(_ event: OperatorPromptEvent) {
        if let idx = inboxPrompts.firstIndex(where: { $0.id == event.id }) {
            inboxPrompts[idx] = event
        } else {
            inboxPrompts.append(event)
        }
    }

    private func unregisterInbox(promptID: UUID) {
        inboxPrompts.removeAll { $0.id == promptID }
    }

    private func scheduleExpiry(for event: OperatorPromptEvent) -> Task<Void, Never> {
        let remaining = event.expiresAt.timeIntervalSinceNow
        if remaining <= 0 {
            return Task { @MainActor [weak self] in
                _ = self?.resumption.resolveExpiry(for: event)
            }
        }
        let cappedSeconds = min(max(remaining, 0.001), 86_400.0)
        let ns = UInt64(cappedSeconds * 1_000_000_000.0)
        return Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            _ = self.resumption.resolveExpiry(for: event)
        }
    }
}
