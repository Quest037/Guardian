import Foundation

/// Caps concurrent Gazebo worlds on one machine (Training + Formation).
enum GazeboConcurrency {
    static let envKey = "GUARDIAN_GAZEBO_MAX_CONCURRENT_WORLDS"

    static let defaultMaxConcurrentWorlds = 2
    static let resolvedCap = 16

    static var maxConcurrentWorlds: Int {
        resolveMaxConcurrent(ProcessInfo.processInfo.environment)
    }

    static func resolveMaxConcurrent(_ environment: [String: String]) -> Int {
        guard let raw = environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let parsed = Int(raw), parsed >= 1
        else {
            return defaultMaxConcurrentWorlds
        }
        return min(parsed, resolvedCap)
    }
}
