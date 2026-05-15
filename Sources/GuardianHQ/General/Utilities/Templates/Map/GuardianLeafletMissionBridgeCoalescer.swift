import Foundation

/// Debounces ``OSMMapView`` `setMissionData` bridge scripts so twin ``GuardianMapModel`` publishes
/// and rapid hub-driven ``updateNSView`` passes collapse into one ``WKWebView/evaluateJavaScript`` per window.
@MainActor
final class GuardianLeafletMissionBridgeCoalescer {
    /// ~one 60 Hz frame; see ``LiveLeafletMapToDo.md`` Phase A coalesce item.
    static let defaultCoalesceInterval: TimeInterval = 1.0 / 60.0

    let coalesceInterval: TimeInterval
    private(set) var latestScript: String?
    private(set) var lastAppliedScript: String?
    private var workItem: DispatchWorkItem?

    init(coalesceInterval: TimeInterval = GuardianLeafletMissionBridgeCoalescer.defaultCoalesceInterval) {
        self.coalesceInterval = coalesceInterval
    }

    func enqueue(script: String, onFlush: @escaping (String) -> Void) {
        latestScript = script
        workItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performFlush(onFlush: onFlush)
        }
        workItem = work
        if coalesceInterval <= 0 {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + coalesceInterval, execute: work)
        }
    }

    func noteWebViewReloaded() {
        lastAppliedScript = nil
    }

    /// After a direct ``evaluateJavaScript`` (e.g. first load flush) so duplicate coalesced payloads are skipped.
    func noteScriptApplied(_ script: String) {
        lastAppliedScript = script
    }

    /// Unit tests: apply the latest pending script without waiting for the debounce window.
    func flushPendingForTesting(onFlush: (String) -> Void) {
        workItem?.cancel()
        workItem = nil
        performFlush(onFlush: onFlush)
    }

    private func performFlush(onFlush: (String) -> Void) {
        guard let script = latestScript else { return }
        guard script != lastAppliedScript else {
            GuardianLeafletMissionBridgeProfiler.recordCoalescerDuplicateSkip()
            return
        }
        lastAppliedScript = script
        onFlush(script)
    }
}
