import Foundation

/// Rolling counters for Leaflet ``setMissionData`` bridge traffic (debug builds only).
///
/// Enable console summaries with environment variable ``loggingEnabledEnvKey`` (`1`).
struct GuardianLeafletMissionBridgeProfileAccumulator: Equatable, Sendable {
    var updateNSViewCalls: Int = 0
    var payloadUnchangedSkips: Int = 0
    var scriptsBuilt: Int = 0
    var scriptsEnqueued: Int = 0
    var coalescerDuplicateSkips: Int = 0
    var javascriptEvals: Int = 0
    var totalBuiltBytes: Int = 0
    var totalEnqueuedBytes: Int = 0
    var totalEvalBytes: Int = 0
    var lastBuiltBytes: Int = 0
    var lastVehicleMarkerCount: Int = 0

    mutating func recordUpdateNSView(vehicleMarkerCount: Int) {
        updateNSViewCalls += 1
        lastVehicleMarkerCount = vehicleMarkerCount
    }

    mutating func recordPayloadUnchangedSkip() {
        payloadUnchangedSkips += 1
    }

    mutating func recordScriptBuilt(byteCount: Int, vehicleMarkerCount: Int) {
        scriptsBuilt += 1
        totalBuiltBytes += byteCount
        lastBuiltBytes = byteCount
        lastVehicleMarkerCount = vehicleMarkerCount
    }

    mutating func recordScriptEnqueued(byteCount: Int) {
        scriptsEnqueued += 1
        totalEnqueuedBytes += byteCount
    }

    mutating func recordCoalescerDuplicateSkip() {
        coalescerDuplicateSkips += 1
    }

    mutating func recordJavaScriptEval(byteCount: Int) {
        javascriptEvals += 1
        totalEvalBytes += byteCount
    }

    /// One-line summary for Instruments / Console verification after coalescing + Equatable diff.
    func summaryLine() -> String {
        let builtKB = String(format: "%.1f", Double(totalBuiltBytes) / 1024.0)
        let evalKB = String(format: "%.1f", Double(totalEvalBytes) / 1024.0)
        let lastKB = String(format: "%.1f", Double(lastBuiltBytes) / 1024.0)
        return """
        updateNSView=\(updateNSViewCalls) payloadSkip=\(payloadUnchangedSkips) built=\(scriptsBuilt) \
        enqueued=\(scriptsEnqueued) coalesceSkip=\(coalescerDuplicateSkips) evals=\(javascriptEvals) \
        builtKB=\(builtKB) evalKB=\(evalKB) lastKB=\(lastKB) vehicles=\(lastVehicleMarkerCount)
        """
    }
}

#if DEBUG
@MainActor
enum GuardianLeafletMissionBridgeProfiler {
    static let loggingEnabledEnvKey = "GUARDIAN_MAP_BRIDGE_PROFILE"
    private static let summaryInterval: TimeInterval = 5.0

    private static var accumulator = GuardianLeafletMissionBridgeProfileAccumulator()
    private static var lastSummaryTime = CFAbsoluteTimeGetCurrent()

    static var isLoggingEnabled: Bool {
        ProcessInfo.processInfo.environment[loggingEnabledEnvKey] == "1"
    }

    static func snapshotForTesting() -> GuardianLeafletMissionBridgeProfileAccumulator {
        accumulator
    }

    static func resetForTesting() {
        accumulator = GuardianLeafletMissionBridgeProfileAccumulator()
        lastSummaryTime = CFAbsoluteTimeGetCurrent()
    }

    static func recordUpdateNSView(vehicleMarkerCount: Int) {
        accumulator.recordUpdateNSView(vehicleMarkerCount: vehicleMarkerCount)
        maybeEmitSummary()
    }

    static func recordPayloadUnchangedSkip() {
        accumulator.recordPayloadUnchangedSkip()
        maybeEmitSummary()
    }

    static func recordScriptBuilt(byteCount: Int, vehicleMarkerCount: Int) {
        accumulator.recordScriptBuilt(byteCount: byteCount, vehicleMarkerCount: vehicleMarkerCount)
        maybeEmitSummary()
    }

    static func recordScriptEnqueued(byteCount: Int) {
        accumulator.recordScriptEnqueued(byteCount: byteCount)
        maybeEmitSummary()
    }

    static func recordCoalescerDuplicateSkip() {
        accumulator.recordCoalescerDuplicateSkip()
        maybeEmitSummary()
    }

    static func recordJavaScriptEval(byteCount: Int) {
        accumulator.recordJavaScriptEval(byteCount: byteCount)
        maybeEmitSummary()
    }

    private static func maybeEmitSummary() {
        guard isLoggingEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSummaryTime >= summaryInterval else { return }
        lastSummaryTime = now
        print("[GuardianHQ][MapBridge][Profile] \(accumulator.summaryLine())")
    }
}
#else
@MainActor
enum GuardianLeafletMissionBridgeProfiler {
    static let loggingEnabledEnvKey = "GUARDIAN_MAP_BRIDGE_PROFILE"

    static var isLoggingEnabled: Bool { false }

    static func recordUpdateNSView(vehicleMarkerCount: Int) {}
    static func recordPayloadUnchangedSkip() {}
    static func recordScriptBuilt(byteCount: Int, vehicleMarkerCount: Int) {}
    static func recordScriptEnqueued(byteCount: Int) {}
    static func recordCoalescerDuplicateSkip() {}
    static func recordJavaScriptEval(byteCount: Int) {}
}
#endif
