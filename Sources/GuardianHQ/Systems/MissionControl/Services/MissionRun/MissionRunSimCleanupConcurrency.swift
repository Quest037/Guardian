import Foundation

/// Wave size for run-complete SIM cleanup awaits that can safely overlap **per vehicle** (park recipe, mission clear, battery patch).
///
/// **Override for experiments / CI:** set environment variable ``envKey`` to a decimal integer ≥ 1 (values above ``resolvedWaveCap`` are clamped). Unset or invalid → ``defaultMaxConcurrentPerWave``.
enum MissionRunSimCleanupConcurrency {
    /// `GUARDIAN_MISSION_RUN_SIM_CLEANUP_MAX_CONCURRENT`
    static let envKey = "GUARDIAN_MISSION_RUN_SIM_CLEANUP_MAX_CONCURRENT"

    static let defaultMaxConcurrentPerWave = 20
    /// Hard ceiling for env override (load / escalation safety).
    static let resolvedWaveCap = 256

    /// Resolved wave size for the current process environment.
    static var maxConcurrentPerWave: Int {
        resolveMaxConcurrent(ProcessInfo.processInfo.environment)
    }

    /// Same rules as ``maxConcurrentPerWave`` using an arbitrary environment map (unit tests).
    static func resolveMaxConcurrent(_ environment: [String: String]) -> Int {
        guard let raw = environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let parsed = Int(raw), parsed >= 1
        else {
            return defaultMaxConcurrentPerWave
        }
        return min(parsed, resolvedWaveCap)
    }
}
