import Foundation

/// Coalesces hub-driven ``GuardianMapModel`` marker-only applies at the SwiftUI layer (latest closure wins per window).
@MainActor
final class LiveLeafletMapHubMarkerApplyThrottle: ObservableObject {
    private let minInterval: TimeInterval
    private var lastApplyTime: CFAbsoluteTime = 0
    private var pendingTask: Task<Void, Never>?
    private var pendingApply: (() -> Void)?

    init(maxHz: Double = LiveLeafletMapHubMarkerApplyThrottlePolicy.resolvedMaxHz) {
        minInterval = maxHz > 0 ? 1.0 / maxHz : 0
    }

    /// Coalesce hub-motion applies; the **latest** ``apply`` runs at flush time.
    func requestCoalesced(_ apply: @escaping () -> Void) {
        LiveLeafletMapMarkerPipelineProfiler.recordThrottleCoalescedRequest()
        guard minInterval > 0 else {
            apply()
            lastApplyTime = CFAbsoluteTimeGetCurrent()
            return
        }
        pendingApply = apply
        let elapsed = CFAbsoluteTimeGetCurrent() - lastApplyTime
        if elapsed >= minInterval {
            flushPending()
            return
        }
        scheduleFlush(after: minInterval - elapsed)
    }

    /// Selection / operator actions — bypass coalescing.
    func flushImmediately(_ apply: @escaping () -> Void) {
        LiveLeafletMapMarkerPipelineProfiler.recordThrottleImmediateFlush()
        pendingTask?.cancel()
        pendingTask = nil
        pendingApply = nil
        apply()
        lastApplyTime = CFAbsoluteTimeGetCurrent()
    }

    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingApply = nil
    }

    private func scheduleFlush(after delay: TimeInterval) {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.flushPending()
        }
    }

    private func flushPending() {
        pendingTask?.cancel()
        pendingTask = nil
        guard let apply = pendingApply else { return }
        pendingApply = nil
        apply()
        lastApplyTime = CFAbsoluteTimeGetCurrent()
    }
}
