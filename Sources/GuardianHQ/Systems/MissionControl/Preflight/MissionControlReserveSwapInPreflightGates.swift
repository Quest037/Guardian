import Foundation

/// Hub snapshot checks for **MC-R floating reserve swap-in** before the arm-probe recipe runs.
///
/// These gates are **telemetry-only** (no ``FleetRecipeRunner`` / catalogue dispatch) so they do not
/// consume recipe audit lines or duplicate start-run catalogue steps. The arm probe keeps its own
/// ``preflightAuditSource`` (e.g. `missionControl.preflightProbe.reserveSwapIn`).
enum MissionControlReserveSwapInPreflightGates {

    /// Freshness: hub ``FleetHubVehicleTelemetry/lastUpdate`` must be within this window (live hardware).
    static let maxHubAgeSecondsLive: TimeInterval = 12

    /// SITL / simulation bridges can emit less frequently; use a looser bound so swap-in is usable in dev.
    static let maxHubAgeSecondsSimulation: TimeInterval = 45

    /// Evaluates swap-in snapshot gates. Returns a failed ``SingleVehiclePreflightProbeResult`` when a gate trips; `nil` when the caller should proceed to the arm recipe.
    static func evaluate(
        hub: FleetHubVehicleTelemetry?,
        now: Date = Date(),
        isSimulation: Bool
    ) -> SingleVehiclePreflightProbeResult? {
        guard let hub else {
            return fail(
                detail: "Swap-in check failed: no hub telemetry snapshot yet for this vehicle.",
                advice: PreflightFailureRemediationAdvice(
                    patternId: "reserveSwapIn.telemetry_missing",
                    summary: "Fleet hub has not published a telemetry snapshot for this stream.",
                    steps: [
                        "Confirm the live bridge or SITL session is running and linked to this vehicle.",
                        "Wait for position, battery, or health lines to appear on the fleet card, then retry.",
                    ]
                )
            )
        }

        let maxAge = isSimulation ? maxHubAgeSecondsSimulation : maxHubAgeSecondsLive
        let age = now.timeIntervalSince(hub.lastUpdate)
        if age.isFinite, age > maxAge {
            return fail(
                detail: String(
                    format: "Swap-in check failed: telemetry is stale (last hub update %.0fs ago, limit %.0fs).",
                    age,
                    maxAge
                ),
                advice: PreflightFailureRemediationAdvice(
                    patternId: "reserveSwapIn.telemetry_stale",
                    summary: "The hub snapshot is too old to trust for swap-in gates.",
                    steps: [
                        "Check link health, bridge logs, and that the vehicle is still publishing MAVLink.",
                        "If the feed recovers, retry without leaving the swap picker.",
                    ]
                )
            )
        }

        if !hub.isArmed, hub.inAir == true {
            return fail(
                detail: "Swap-in check failed: vehicle reports in-air while disarmed — resolve flight state before swapping.",
                advice: PreflightFailureRemediationAdvice(
                    patternId: "reserveSwapIn.in_air_inconsistent",
                    summary: "Telemetry shows an airborne state that is unsafe for a ground reserve swap.",
                    steps: [
                        "Verify the stream matches the intended reserve aircraft.",
                        "Land or disarm cleanly, wait for landed-state telemetry to settle, then retry.",
                    ]
                )
            )
        }

        if hub.healthArmable == false {
            return fail(
                detail: "Swap-in check failed: autopilot reports not armable (`health.armable` false).",
                advice: PreflightFailureRemediationAdvice(
                    patternId: "reserveSwapIn.health_not_armable",
                    summary: "The flight stack is blocking arm readiness before any arm command is sent.",
                    steps: [
                        "Review recent status text and health flags in Vehicle Inspector.",
                        "Clear GPS/EKF/compass/sensor blockers reported by the stack, then retry.",
                    ]
                )
            )
        }

        if hub.healthGlobalPositionOk == false {
            return fail(
                detail: "Swap-in check failed: global position health is not OK.",
                advice: PreflightFailureRemediationAdvice(
                    patternId: "reserveSwapIn.health_global_position",
                    summary: "Global position is not healthy enough for a reserve swap-in gate.",
                    steps: [
                        "Wait for GPS / global position to initialize with a solid fix.",
                        "Move to clear sky view, check antenna, then retry the swap-in check.",
                    ]
                )
            )
        }

        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: nil, now: now)
        if op.gps.fixShort == "—" {
            return fail(
                detail: "Swap-in check failed: no usable GPS fix reported for this stream.",
                advice: PreflightFailureRemediationAdvice(
                    patternId: "reserveSwapIn.gps_no_fix",
                    summary: "GPS fix is missing or explicitly no-fix.",
                    steps: [
                        "Wait for a 2D/3D (or RTK) fix with enough satellites before swapping this reserve in.",
                        "Check antenna, interference, and that GPS is enabled for this autopilot.",
                    ]
                )
            )
        }

        switch op.battery.trafficBand {
        case .critical:
            return fail(
                detail: "Swap-in check failed: battery is in the critical band (under 10% reported).",
                advice: PreflightFailureRemediationAdvice(
                    patternId: "reserveSwapIn.battery_critical",
                    summary: "Battery remaining is critically low for mission work.",
                    steps: [
                        "Charge or replace the battery before bringing this aircraft onto an active task.",
                        "Verify remaining-percent telemetry matches the airframe if the reading looks wrong.",
                    ]
                )
            )
        case .unknown, .warn, .ok:
            break
        }

        let mode = hub.flightMode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !mode.isEmpty, mode != "—" {
            let blockedSubstrings = ["TERMINAT", "FAILSAFE", "EMERGENCY", "CRASH"]
            if blockedSubstrings.contains(where: { mode.contains($0) }) {
                return fail(
                    detail: "Swap-in check failed: flight mode \"\(hub.flightMode)\" is not acceptable for reserve swap-in.",
                    advice: PreflightFailureRemediationAdvice(
                        patternId: "reserveSwapIn.flight_mode_blocked",
                        summary: "The reported flight mode looks like a failsafe or termination state.",
                        steps: [
                            "Recover to a normal disarmed mode on the ground before retrying.",
                            "If this is a false label on the stream, verify the correct vehicle is selected.",
                        ]
                    )
                )
            }
        }

        return nil
    }

    private static func fail(
        detail: String,
        advice: PreflightFailureRemediationAdvice
    ) -> SingleVehiclePreflightProbeResult {
        SingleVehiclePreflightProbeResult(
            passed: false,
            armedDuringProbe: false,
            detail: detail,
            remediationAdvice: advice
        )
    }
}
