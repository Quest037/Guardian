import Foundation

/// §3 **pull** evidence: infer ``MissionRunAssignmentSlotState/policySucceeded`` from hub when push callbacks are missing.
///
/// v1 is intentionally narrow — **disarmed + low ground speed + not in-air** as a post–wind-down “settled” proxy.
/// See README **Slot policy success criteria catalogue** → pull rows.
///
/// **SITL vs live:** thresholds apply to **any** ``FleetHubVehicleTelemetry`` (Guardian SITL hubs and live MAVLink
/// bridges). There is **no** parallel slot-state enum or sim-only branch; if real hardware ever needs looser or
/// tighter timing, introduce **one** optional env override here (debounce / max-age / speed) — not a second state machine.
enum MissionRunPolicySlotPullConformance {

    /// Minimum seconds between **successful** pull promotions for one ``MissionRunAssignment/id`` (debounce).
    static let successDebounceSeconds: TimeInterval = 2.5

    /// Ignore hub snapshots older than this (stale link / tab backgrounding).
    static let hubMaxAgeSeconds: TimeInterval = 20

    /// Treat horizontal ground speed below this (m/s) as “stationary” for park / disarm settlement.
    static let maxHorizontalSpeedMS: Double = 1.5

    /// Hub-only heuristic: vehicle appears **settled** after a policy wind-down when push did not yet mark the slot.
    static func hubSuggestsPolicyWindDownSettled(_ hub: FleetHubVehicleTelemetry, now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(hub.lastUpdate) <= hubMaxAgeSeconds else { return false }
        guard !hub.isArmed else { return false }
        if hub.inAir == true { return false }
        if let spd = hub.horizontalGroundSpeedMS, spd >= maxHorizontalSpeedMS { return false }
        return true
    }
}
