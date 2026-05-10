import Foundation

/// Shared limits and conversions for mission delays (task start, regularity gap, MC run overrides, postpone steps).
/// Waypoint dwell times use the same ``DelayUnit`` but keep their own numeric field caps in the route editor.
enum MissionDelayPolicy {
    /// Maximum duration for a single authored or per-run override delay (48 h).
    static let maxAuthoringDelaySeconds: TimeInterval = 48 * 3600

    /// Default upper bound for a single Mission Control **Alter** step — Sooner / Later (Settings › Missions).
    static let defaultOperatorPostponeStepCapSeconds: Int = 3600

    /// Converts authored postpone amount to an integer second step (clamped to ``capSeconds``).
    static func clampedPostponeStepSeconds(value: Double, unit: DelayUnit, capSeconds: Int) -> Int {
        let raw = Int(totalSeconds(value: value, unit: unit).rounded())
        return clampPostponeStepSeconds(raw, capSeconds: capSeconds)
    }

    static func totalSeconds(value: Double, unit: DelayUnit) -> TimeInterval {
        let v = max(0, value)
        switch unit {
        case .secs: return v
        case .mins: return v * 60
        case .hrs: return v * 3600
        }
    }

    static func clampTotalSeconds(
        _ seconds: TimeInterval,
        minimumTotalSeconds: TimeInterval,
        maximumTotalSeconds: TimeInterval? = nil
    ) -> TimeInterval {
        let upper = maximumTotalSeconds.map { min(maxAuthoringDelaySeconds, $0) } ?? maxAuthoringDelaySeconds
        return min(upper, max(minimumTotalSeconds, seconds))
    }

    /// Upper bound for the numeric field at a given unit so total seconds never exceeds ``maxAuthoringDelaySeconds``.
    static func maxDisplayValue(for unit: DelayUnit) -> Double {
        switch unit {
        case .secs: return maxAuthoringDelaySeconds
        case .mins: return maxAuthoringDelaySeconds / 60
        case .hrs: return maxAuthoringDelaySeconds / 3600
        }
    }

    /// Upper display bound when total delay must not exceed ``capTotalSeconds`` (e.g. operator postpone cap).
    static func maxDisplayValue(for unit: DelayUnit, cappedAtTotalSeconds capTotalSeconds: TimeInterval) -> Double {
        let upper = min(maxAuthoringDelaySeconds, max(1, capTotalSeconds))
        switch unit {
        case .secs: return upper
        case .mins: return upper / 60
        case .hrs: return upper / 3600
        }
    }

    static func clampDisplayValue(
        _ value: Double,
        unit: DelayUnit,
        minimumTotalSeconds: TimeInterval,
        maximumTotalSeconds: TimeInterval? = nil
    ) -> Double {
        let secs = clampTotalSeconds(
            totalSeconds(value: value, unit: unit),
            minimumTotalSeconds: minimumTotalSeconds,
            maximumTotalSeconds: maximumTotalSeconds
        )
        switch unit {
        case .secs: return secs
        case .mins: return secs / 60
        case .hrs: return secs / 3600
        }
    }

    static func normalizedTaskStart(value: Double, unit: DelayUnit) -> (Double, DelayUnit) {
        let v = clampDisplayValue(value, unit: unit, minimumTotalSeconds: 0)
        return (v, unit)
    }

    static func normalizedRegularityGap(value: Double, unit: DelayUnit) -> (Double, DelayUnit) {
        let v = clampDisplayValue(value, unit: unit, minimumTotalSeconds: 1)
        return (v, unit)
    }

    /// Human-readable duration for logs and inline labels (e.g. `2h 5m`, `90s`).
    static func humanReadableDuration(seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return m == 1 ? "1 min" : "\(m) min" }
        let h = m / 60
        let rm = m % 60
        if rm == 0 { return h == 1 ? "1 hr" : "\(h) hr" }
        return "\(h)h \(rm)m"
    }

    static func clampPostponeStepSeconds(_ raw: Int, capSeconds: Int) -> Int {
        let r = max(1, raw)
        let cap = max(1, min(Int(maxAuthoringDelaySeconds), capSeconds))
        return min(cap, r)
    }
}

extension DelayUnit {
    /// Menu labels aligned with waypoint delay picker style (`secs` / `mins` / `hrs` raw values).
    var missionDelayMenuLabel: String { rawValue }
}
