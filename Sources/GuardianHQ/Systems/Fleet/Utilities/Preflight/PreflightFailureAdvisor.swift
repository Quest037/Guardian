import Foundation

// MARK: - Context & result (extend with new fields as rules need them)

/// Input for pattern matching and operator guidance after an arm command fails.
struct PreflightFailureRemediationContext {
    var autopilotStack: FleetAutopilotStack
    /// Full string from MAVSDK / `augmentCommandFailureDetail` (includes optional STATUSTEXT tail).
    var rawFailureDetail: String
    /// Latest hub snapshot for the vehicle; rules may branch on health flags later.
    var hubSnapshot: FleetHubVehicleTelemetry?
    /// True for in-app SITL (advice can mention sim-specific waits/restarts); false for live / other links.
    var isSimulation: Bool
}

/// Operator-facing guidance for a failed arm. **`patternId`** is stable for tests and future i18n keys.
struct PreflightFailureRemediationAdvice: Equatable {
    let patternId: String
    let summary: String
    let steps: [String]
}

// MARK: - Advisor (ordered rules — first match wins)

/// Shared advisor for **arm denied** outcomes: Mission Control start-run preflight, future **Vehicles** grid “test arm”, Paladin, etc.
/// Add new **`RemediationRule`** entries at the **start** of **`buildRules()`** for higher priority.
enum PreflightFailureAdvisor {

    static func advice(for context: PreflightFailureRemediationContext) -> PreflightFailureRemediationAdvice {
        let haystack = Self.normalizedHaystack(context.rawFailureDetail)
        for rule in Self.buildRules() {
            if let stacks = rule.stacks, !stacks.contains(context.autopilotStack) {
                continue
            }
            if rule.matches(haystack, context) {
                return rule.makeAdvice(context)
            }
        }
        return defaultAdvice(haystack: haystack, context: context)
    }

    /// Lowercased single string for substring checks; keeps matching simple and robust to MAVSDK prefix noise.
    private static func normalizedHaystack(_ detail: String) -> String {
        detail.lowercased()
    }

    // MARK: - Rules table

    private struct RemediationRule {
        let patternId: String
        /// When non-`nil`, rule applies only to these stacks. `nil` means any stack.
        let stacks: Set<FleetAutopilotStack>?
        let matches: (String, PreflightFailureRemediationContext) -> Bool
        let makeAdvice: (PreflightFailureRemediationContext) -> PreflightFailureRemediationAdvice
    }

    /// **Order matters:** earlier rules win. Add new patterns here (or extract to a registry file later).
    private static func buildRules() -> [RemediationRule] {
        [
        RemediationRule(
            patternId: "ardupilot.accels_inconsistent",
            stacks: [.ardupilot, .unknown],
            matches: { haystack, _ in
                haystack.contains("accel") && haystack.contains("inconsistent")
            },
            makeAdvice: { ctx in
                var steps: [String] = [
                    "Leave the vehicle level and still; vibration or movement during IMU warm-up can trigger this.",
                    "On hardware: check IMU mounting, redo accelerometer calibration if the airframe changed, then power-cycle.",
                    "Retry arming after the EKF/GPS status lines in the log show a stable navigation solution.",
                ]
                if ctx.isSimulation {
                    steps.insert(
                        "In SITL: wait until after \"ArduPilot Ready\" and EKF/GPS messages settle (often several seconds); retry arm once.",
                        at: 0
                    )
                }
                return PreflightFailureRemediationAdvice(
                    patternId: "ardupilot.accels_inconsistent",
                    summary: "Accelerometers disagree — autopilot blocked arming.",
                    steps: steps
                )
            }
        ),
        RemediationRule(
            patternId: "px4.heading_estimate_invalid",
            stacks: [.px4, .unknown],
            matches: { haystack, _ in
                (haystack.contains("heading") && haystack.contains("estimate") && haystack.contains("invalid"))
                    || (haystack.contains("preflight") && haystack.contains("heading"))
            },
            makeAdvice: { ctx in
                var steps: [String] = [
                    "Wait for the attitude/heading filter to initialize (clear sky view for mag, minimal motion).",
                    "On hardware: verify magnetometer calibration and interference; recalibrate compass if needed.",
                    "Check that GPS and home position are valid if the stack requires them for heading.",
                ]
                if ctx.isSimulation {
                    steps.insert("In SITL: allow a few seconds after boot for estimators; retry after \"Ready for takeoff\" or equivalent.", at: 0)
                }
                return PreflightFailureRemediationAdvice(
                    patternId: "px4.heading_estimate_invalid",
                    summary: "Heading estimate not valid — PX4 preflight blocked arming.",
                    steps: steps
                )
            }
        ),
        RemediationRule(
            patternId: "common.compass_mag",
            stacks: nil,
            matches: { haystack, _ in
                haystack.contains("compass")
                    || haystack.contains("magnetometer")
                    || haystack.contains("mag bias")
                    || (haystack.contains("mag") && (haystack.contains("cal") || haystack.contains("fail") || haystack.contains("error")))
            },
            makeAdvice: { _ in
                PreflightFailureRemediationAdvice(
                    patternId: "common.compass_mag",
                    summary: "Compass / magnetometer issue reported.",
                    steps: [
                        "Move away from metal, speakers, and strong currents; recalibrate the compass per your stack’s procedure.",
                        "On ArduPilot, check compass priority and that the primary compass is healthy.",
                        "Retry outdoors or in an environment with low magnetic interference.",
                    ]
                )
            }
        ),
        RemediationRule(
            patternId: "common.gps_position",
            stacks: nil,
            matches: { haystack, _ in
                haystack.contains("gps")
                    || haystack.contains("global position")
                    || haystack.contains("need position")
                    || haystack.contains("no fix")
                    || haystack.contains("3d fix")
            },
            makeAdvice: { ctx in
                var steps: [String] = [
                    "Wait for a solid GPS fix (enough satellites / good HDOP) before arming.",
                    "On hardware: check antenna, clear view of sky, and that GPS is enabled in parameters.",
                ]
                if ctx.hubSnapshot?.gpsNumSatellites == nil || (ctx.hubSnapshot?.gpsNumSatellites ?? 0) < 6 {
                    steps.append("Telemetry shows weak or missing GPS satellite count — resolve link or wait for satellites.")
                }
                return PreflightFailureRemediationAdvice(
                    patternId: "common.gps_position",
                    summary: "GPS or position estimate not ready.",
                    steps: steps
                )
            }
        ),
        RemediationRule(
            patternId: "common.rc",
            stacks: nil,
            matches: { haystack, _ in
                haystack.contains("rc not found")
                    || haystack.contains("rc not")
                    || (haystack.contains("prearm") && haystack.contains("rc"))
                    || haystack.contains("radio")
            },
            makeAdvice: { _ in
                PreflightFailureRemediationAdvice(
                    patternId: "common.rc",
                    summary: "RC / radio not ready or not detected.",
                    steps: [
                        "Turn on the handset, bind/reconnect, and verify the autopilot sees RC input.",
                        "If using simulation, enable or map a virtual RC source required by your stack.",
                    ]
                )
            }
        ),
        RemediationRule(
            patternId: "common.geofence",
            stacks: nil,
            matches: { haystack, _ in
                haystack.contains("fence") || haystack.contains("geofence")
            },
            makeAdvice: { _ in
                PreflightFailureRemediationAdvice(
                    patternId: "common.geofence",
                    summary: "Geofence or breach reported.",
                    steps: [
                        "Clear the breach or disable/adjust the fence in parameters if appropriate for your test.",
                        "Ensure home and mission are inside allowed regions.",
                    ]
                )
            }
        ),
        RemediationRule(
            patternId: "common.ekf",
            stacks: nil,
            matches: { haystack, _ in
                haystack.contains("ekf")
            },
            makeAdvice: { _ in
                PreflightFailureRemediationAdvice(
                    patternId: "common.ekf",
                    summary: "EKF / estimator check failed.",
                    steps: [
                        "Allow time after boot for the filter to align; avoid moving the vehicle during initialization.",
                        "Verify IMU and GPS health; on hardware, check for bad vibrations or GPS dropouts.",
                    ]
                )
            }
        ),
        ]
    }

    private static func defaultAdvice(haystack: String, context: PreflightFailureRemediationContext) -> PreflightFailureRemediationAdvice {
        var steps: [String] = [
            "Read the autopilot message in the technical line below — it usually states the failing check.",
            "Open the Vehicles log for this airframe and look for CRITICAL/WARN lines just before the arm attempt.",
            "Resolve pre-arm / health checks on the autopilot (GPS, compass, accelerometers, RC, battery), then retry.",
        ]
        if context.isSimulation {
            steps.insert("In SITL: confirm the sim is fully booted and estimators are ready before arming.", at: 0)
        }
        if haystack.contains("preflight") {
            steps.insert("A \"preflight\" message means the stack’s arming checks failed — use your GCS or parameter docs for that specific check.", at: 1)
        }
        return PreflightFailureRemediationAdvice(
            patternId: "generic.arm_denied",
            summary: "Arming was refused — see technical detail and autopilot logs.",
            steps: steps
        )
    }
}
