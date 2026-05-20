import Foundation

/// Operator-facing Nav2 warm-start status is owned by ``FleetNav2StackRunner`` (Swift).
/// The bridge may still poll for readiness when ``GUARDIAN_NAV2_LAUNCH_DISABLED=1``, but stdout
/// must not overwrite Swift status (otherwise a failed launch stays stuck on "starting").
enum FleetNav2TrainingStackStatusPolicy {
    static let applyBridgeStdoutStatusToUI = false
}
