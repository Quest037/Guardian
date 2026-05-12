import Foundation

// MARK: - OperatorPromptReviewSurfaceContributorRegistry

/// **Extension point:** plugins (or future first-party subsystems) map ``OperatorPromptEvent`` payloads to
/// ``OperatorPromptReviewSurface/pluginSurface`` without Mission Control hard-coding plugin names.
///
/// Registration is idempotent per `contributorID` for a single process — re-registering replaces the prior closure.
/// Contributors run **after** built-in policy-ordered resolution fails to produce an MCR / Live Drive surface.
final class OperatorPromptReviewSurfaceContributorRegistry: @unchecked Sendable {

    static let shared = OperatorPromptReviewSurfaceContributorRegistry()

    private let lock = NSLock()
    private var rows: [(contributorID: String, resolve: @Sendable (OperatorPromptEvent) -> OperatorPromptReviewSurface?)] = []

    private init() {}

    /// Registers or replaces a contributor. Call from plugin bootstrap on the main thread.
    func registerContributor(
        id contributorID: String,
        resolve: @escaping @Sendable (OperatorPromptEvent) -> OperatorPromptReviewSurface?
    ) {
        lock.lock()
        if let idx = rows.firstIndex(where: { $0.contributorID == contributorID }) {
            rows[idx] = (contributorID, resolve)
        } else {
            rows.append((contributorID, resolve))
        }
        lock.unlock()
    }

    func unregisterContributor(id contributorID: String) {
        lock.lock()
        rows.removeAll { $0.contributorID == contributorID }
        lock.unlock()
    }

    /// First non-`nil` surface wins, in registration order.
    func contributedSurface(for event: OperatorPromptEvent) -> OperatorPromptReviewSurface? {
        lock.lock()
        let snapshot = rows
        lock.unlock()
        for row in snapshot {
            if let s = row.resolve(event) { return s }
        }
        return nil
    }
}
