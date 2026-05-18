import Foundation

/// UDP port release timing after built-in SITL stops (random-port mode).
enum GuardianSitlPortReleaseSettle {
    static let portReleaseSettleTimeoutEnvKey = "GUARDIAN_SITL_PORT_RELEASE_SETTLE_TIMEOUT"
    static let bulkSpawnInterSpawnMsEnvKey = "GUARDIAN_SITL_BULK_SPAWN_INTER_SPAWN_MS"

    static func portReleaseSettleTimeout(defaultSeconds: TimeInterval = 2.5) -> TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment[portReleaseSettleTimeoutEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let value = TimeInterval(raw),
              value >= 0
        else { return defaultSeconds }
        return value
    }

    /// Pause between sequential MCS bulk spawns so each MAVSDK `udpin` listener can bind (random ports).
    static func bulkSpawnInterSpawnPauseNanoseconds(defaultMilliseconds: Int = 150) -> UInt64 {
        let ms: Int
        if let raw = ProcessInfo.processInfo.environment[bulkSpawnInterSpawnMsEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let parsed = Int(raw) {
            ms = parsed
        } else {
            ms = defaultMilliseconds
        }
        return UInt64(max(0, ms)) * 1_000_000
    }

    static var shouldPauseBetweenBulkSpawns: Bool {
        !SitlLaunchRecipe.usesLegacySitlPorts()
    }
}
