import Foundation

/// PX4 adapter for the universal command catalogue.
///
/// Mirrors ``FleetCommandStackConverterArduPilot`` for nav atomics (PX4 and AP share
/// the same `FleetVehicleCommand` enum and MAVSDK Action plumbing today), including
/// ``FleetCommandName/fleetVehicleDoPark`` → ``FleetVehicleCommand/park``. PX4-specific
/// overrides live in ``normaliseOutcome(_:commandName:elapsed:)`` where the autopilot
/// error phrasing diverges (PX4 surfaces `MAV_RESULT_DENIED`, `MAV_RESULT_FAILED`,
/// `MAV_RESULT_TEMPORARILY_REJECTED` from MAVSDK; ArduPilot tends to add `PreArm:`
/// STATUSTEXT lines).
///
/// **Move / upload coverage in v1:**
/// - `do.move.altitude` — wired via the shared converter. Computes the target absolute
///   altitude from `datum` (`asl` / `msl` → AMSL; `agl` → ground AMSL derived from
///   hub `absoluteAltM − relativeAltM`) and dispatches one
///   `FleetVehicleCommand.gotoCoordinate(...)` with the equivalent delta. Yaw is
///   preserved at the vehicle's current heading.
/// - `do.move.heading` — wired via the shared converter. Offsets the current lat/lon
///   by `distanceM` along `headingDegrees` using the spherical great-circle formula
///   and dispatches one `FleetVehicleCommand.gotoCoordinate(...)` with
///   `relativeAltitudeM = 0` and `yawDeg = headingDegrees`.
/// - `do.move.point` — wired for `pointKind = explicit | currentLatLon` via
///   `FleetVehicleCommand.gotoCoordinate(...)`. `home` / `rally` surface
///   `.notImplemented` (no autopilot-side readback exposed yet).
/// - `do.mission.*` / `get.mission.*` / `cancel.mission.*` — wired via
///   ``FleetCommandStackConverterShared/translateFleetVehicleMissionIfNeeded(commandName:parameters:)``
///   into MAVSDK `Mission` plugin calls on ``FleetVehicleCommand``.
///
/// **Calibration coverage in v1:**
/// - `do.calibrate.gyro / .accelerometer / .compass / .level / .gimbal` — wired through
///   the MAVSDK Calibration plugin via `FleetVehicleCommand.calibrateMavsdk(_:)`.
/// - `cancel.calibration` — wired to `Drone.calibration.cancel()` via
///   `FleetVehicleCommand.cancelCalibration`.
/// - `do.calibrate.compass.declination`, `do.calibrate.battery.{voltage,current,capacity}`,
///   `do.calibrate.gimbal.neutral` — wired as PX4-flavoured `PARAM_SET` writes through
///   `FleetVehicleCommand.setParameterFloat / .setParameterInt`.
/// - `do.calibrate.{baro, airspeed, esc, rc, rc.trim}` — wired through raw MAVLink
///   `COMMAND_LONG` / `MAV_CMD_PREFLIGHT_CALIBRATION`.
/// - `do.calibrate.servo` — wired (PX4 main PWM bank only) as three `PARAM_SET`
///   writes against `PWM_MAIN_MIN<n>` / `PWM_MAIN_MAX<n>` / `PWM_MAIN_DIS<n>`.
///   The catalogue's `trimPwm` parameter maps onto `PWM_MAIN_DIS<n>` because PX4
///   has no per-channel "trim" param; channel must be 1...16 (main bank). AUX
///   PWM (`PWM_AUX_*`) and CAN-actuator buses are deliberately out of scope —
///   recipes targeting AUX should write the AUX family directly via a future
///   `command.fleet.vehicle.do.param.set` atom.
/// - `do.calibrate.{baro.temperature, compass.motor, rangefinder, flow, vision}` —
///   intentionally `.notImplemented` in v1. PX4 either does not expose the
///   procedure (no `baro.temperature` / `compass.motor`) or lacks a stack-wide
///   parameter contract that overlaps cleanly with ArduPilot (`rangefinder` is
///   driver-fragmented across `SENS_EN_*` flags; `flow` and `vision` only overlap
///   with AP on mounting-position params). The descriptors stay registered as
///   permanent surfaces so the response taxonomy is uniform, but recipe authors
///   should not enroll them as calibration entry-points until a per-stack
///   param-set recipe lands.
///
/// **Lifecycle:**
/// - `do.reboot.autopilot` — wired via `FleetVehicleCommand.rebootAutopilot` (MAVSDK
///   `Action.reboot()` → `MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN`). Closest universal
///   "clear all transient state" since MAVLink has no generic clear-errors atom;
///   `errorClearRefused` stays in the response taxonomy for future per-failsafe /
///   per-fault clear atoms.
struct FleetCommandStackConverterPX4: FleetCommandStackConverter {

    let stack: FleetAutopilotStack = .px4

    // MARK: - Translation

    func translate(
        commandName: FleetCommandName,
        parameters: FleetCommandParameters,
        context: FleetCommandStackConverterContext
    ) -> FleetCommandStackTranslation {

        switch commandName {

        // MARK: do — nav atomics

        case .fleetVehicleDoArm:
            return .vehicleCommands([.arm])
        case .fleetVehicleDoDisarm:
            return .vehicleCommands([.disarm])
        case .fleetVehicleDoLand:
            return .vehicleCommands([.land])
        case .fleetVehicleDoReturnHome:
            return .vehicleCommands([.returnToLaunch])
        case .fleetVehicleDoLoiter:
            return .vehicleCommands([.holdPosition])
        case .fleetVehicleDoPark:
            return .vehicleCommands([.park])

        case .fleetVehicleDoMode:
            guard let raw = parameters.string(named: "mode") else {
                return .notImplemented(detail: "do.mode requires a `mode` parameter.")
            }
            if let cmds = FleetCommandStackConverterShared.vehicleCommands(forModeValue: raw) {
                return .vehicleCommands(cmds)
            }
            return .notImplemented(detail: "do.mode value '\(raw)' is not a recognised FleetVehicleMode token.")

        // MARK: do — moves

        case .fleetVehicleDoMoveAltitude:
            return FleetCommandStackConverterShared.translateMoveAltitude(
                parameters: parameters,
                context: context
            )
        case .fleetVehicleDoMoveHeading:
            return FleetCommandStackConverterShared.translateMoveHeading(
                parameters: parameters,
                context: context
            )
        case .fleetVehicleDoMovePoint:
            return FleetCommandStackConverterShared.translateMovePoint(
                parameters: parameters,
                context: context
            )

        // MARK: do — mission verbs
        //
        // Resolved in `default` via
        // ``FleetCommandStackConverterShared/translateFleetVehicleMissionIfNeeded``.

        // MARK: do — calibration: autopilot-driven sensor procedures (MAVSDK Calibration plugin)
        //
        // PX4 exposes these five over the MAVSDK Calibration plugin's progress streams.
        // FleetLinkService bridges the stream onto a Completable so the standard dispatch
        // path returns a single terminal outcome (success / failure). The recipe layer
        // sees `.success` or `.error(.calibrationDeclined / .calibrationDidNotConverge)`.
        case .fleetVehicleDoCalibrateGyro:
            return .vehicleCommands([.calibrateMavsdk(.gyro)])
        case .fleetVehicleDoCalibrateAccelerometer:
            return .vehicleCommands([.calibrateMavsdk(.accelerometer)])
        case .fleetVehicleDoCalibrateCompass:
            return .vehicleCommands([.calibrateMavsdk(.magnetometer)])
        case .fleetVehicleDoCalibrateLevel:
            return .vehicleCommands([.calibrateMavsdk(.levelHorizon)])
        case .fleetVehicleDoCalibrateGimbal:
            return .vehicleCommands([.calibrateMavsdk(.gimbalAccelerometer)])

        // MARK: do — calibration: raw MAVLink command-long procedures
        //
        // PX4's barometer / ESC / RC / RC-trim / airspeed calibrations are not exposed
        // by MAVSDK Swift, but are available through MAV_CMD_PREFLIGHT_CALIBRATION.
        case .fleetVehicleDoCalibrateBaro:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "PX4 barometer calibration", param3: 1))])
        case .fleetVehicleDoCalibrateBaroTemperature:
            return .notImplemented(detail: "PX4 has no barometer temperature calibration (ArduPilot-only).")
        case .fleetVehicleDoCalibrateAirspeed:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "PX4 airspeed calibration", param6: 1))])
        case .fleetVehicleDoCalibrateEsc:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "PX4 ESC calibration", param7: 1))])
        case .fleetVehicleDoCalibrateRc:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "PX4 RC calibration", param4: 1))])
        case .fleetVehicleDoCalibrateRcTrim:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "PX4 RC trim calibration", param4: 2))])
        case .fleetVehicleDoCalibrateCompassMotor:
            return .notImplemented(detail: "PX4 has no compass-motor interference calibration (ArduPilot-only firmware feature).")

        // MARK: do — calibration: param-driven (single PARAM_SET round-trip)
        //
        // Operator (or wizard / plugin) computes the new value; the catalogue command is
        // the atomic write. PX4 uses a different parameter family from ArduPilot for
        // every entry below — the AP converter has the parallel mapping.
        case .fleetVehicleDoCalibrateCompassDeclination:
            guard let degrees = parameters.double(named: "degrees") else {
                return .notImplemented(detail: "do.calibrate.compass.declination requires a `degrees` parameter.")
            }
            return .vehicleCommands([
                .setParameterFloat(name: "ATT_MAG_DECL", value: degrees)
            ])

        case .fleetVehicleDoCalibrateBatteryVoltage:
            guard let scale = parameters.double(named: "scale") else {
                return .notImplemented(detail: "do.calibrate.battery.voltage requires a `scale` parameter.")
            }
            return .vehicleCommands([
                .setParameterFloat(name: "BAT_V_DIV", value: scale)
            ])

        case .fleetVehicleDoCalibrateBatteryCurrent:
            guard let scale = parameters.double(named: "scale") else {
                return .notImplemented(detail: "do.calibrate.battery.current requires a `scale` parameter.")
            }
            return .vehicleCommands([
                .setParameterFloat(name: "BAT_A_PER_V", value: scale)
            ])

        case .fleetVehicleDoCalibrateBatteryCapacity:
            guard let mAh = parameters.integer(named: "mAh") else {
                return .notImplemented(detail: "do.calibrate.battery.capacity requires an integer `mAh` parameter.")
            }
            return .vehicleCommands([
                .setParameterInt(name: "BAT1_CAPACITY", value: Int32(clamping: mAh))
            ])

        case .fleetVehicleDoCalibrateGimbalNeutral:
            guard
                let roll = parameters.double(named: "rollDeg"),
                let pitch = parameters.double(named: "pitchDeg"),
                let yaw = parameters.double(named: "yawDeg")
            else {
                return .notImplemented(detail: "do.calibrate.gimbal.neutral requires rollDeg / pitchDeg / yawDeg parameters.")
            }
            return .vehicleCommands([
                .setParameterFloat(name: "MNT_OFF_ROLL", value: roll),
                .setParameterFloat(name: "MNT_OFF_PITCH", value: pitch),
                .setParameterFloat(name: "MNT_OFF_YAW", value: yaw)
            ])

        case .fleetVehicleDoCalibrateServo:
            // PX4 main PWM bank only (v1). The mainline PWM endpoints are
            // `PWM_MAIN_MIN<n>` / `PWM_MAIN_MAX<n>` / `PWM_MAIN_DIS<n>`. PX4 has no
            // per-channel "trim" parameter (the catalogue's `trimPwm` was modelled on
            // ArduPilot's `SERVO<n>_TRIM`), so we map `trimPwm` onto `PWM_MAIN_DIS<n>`
            // — the value the autopilot emits while disarmed, which doubles as the
            // safe / neutral PWM for the channel on every PX4-supported mixer today.
            //
            // AUX outputs (`PWM_AUX_*`) and CAN-actuator buses are out of scope here;
            // recipes targeting AUX should write the AUX family directly via
            // `command.fleet.vehicle.do.param.set` once that atom lands.
            guard
                let channel = parameters.integer(named: "channel"),
                let minPwm = parameters.integer(named: "minPwm"),
                let maxPwm = parameters.integer(named: "maxPwm"),
                let trimPwm = parameters.integer(named: "trimPwm")
            else {
                return .notImplemented(detail: "do.calibrate.servo requires channel / minPwm / maxPwm / trimPwm parameters.")
            }
            guard (1...16).contains(channel) else {
                return .notImplemented(detail: "PX4 do.calibrate.servo channel must be 1...16 (main PWM bank); got \(channel).")
            }
            let suffix = "\(channel)"
            return .vehicleCommands([
                .setParameterInt(name: "PWM_MAIN_MIN" + suffix, value: Int32(clamping: minPwm)),
                .setParameterInt(name: "PWM_MAIN_MAX" + suffix, value: Int32(clamping: maxPwm)),
                .setParameterInt(name: "PWM_MAIN_DIS" + suffix, value: Int32(clamping: trimPwm))
            ])

        case .fleetVehicleDoCalibrateRangefinder:
            // Deliberately not wired in v1. PX4 has no stack-wide `RNGFND_*` family
            // equivalent to ArduPilot's. Each rangefinder driver (LL40LS, MB12XX,
            // TFmini, MAVLink-rangefinder, …) is gated by its own `SENS_EN_<driver>`
            // flag and exposes a separate, sparse parameter set; ground-clearance /
            // orientation knobs are mostly burnt into the EKF (`EKF2_RNG_*`) rather
            // than per-driver params. Recipes that genuinely need PX4 rangefinder
            // setup should write the driver's parameters directly via
            // `command.fleet.vehicle.do.param.set` once that atom lands; the generic
            // surface stays `.notImplemented` rather than gambling on which driver
            // happens to be active.
            return .notImplemented(detail: "PX4 do.calibrate.rangefinder is intentionally not wired: PX4 lacks a stack-wide rangefinder param family; per-driver `SENS_EN_*` / `EKF2_RNG_*` writes are recipe-author work today, not a generic atom.")

        case .fleetVehicleDoCalibrateFlow:
            // Deliberately not wired in v1. PX4's optical-flow surface (`SENS_FLOW_*`
            // for the sensor and `EKF2_OF_*` for fusion) only overlaps with ArduPilot
            // on **mounting position** (`EKF2_OF_POS_X/Y/Z` ↔ AP `FLOW_POS_*`). The
            // catalogue descriptor declares no parameters today, and we explicitly
            // refuse to invent a partial param set that only writes position — flow
            // calibration that ignores scalers and yaw orientation would be worse
            // than no calibration. Recipes that need this should target
            // `command.fleet.vehicle.do.param.set` per-stack until a verified
            // cross-stack parameter contract is designed.
            return .notImplemented(detail: "PX4 do.calibrate.flow is intentionally not wired: PX4 (`SENS_FLOW_*` / `EKF2_OF_*`) and ArduPilot (`FLOW_*`) only overlap on mounting-position params; v1 declines to ship a half-wired surface.")

        case .fleetVehicleDoCalibrateVision:
            // Deliberately not wired in v1. PX4 fuses external vision through the
            // `EKF2_EV_*` family (DELAY, POS_X/Y/Z, NOISE, GATE, …); ArduPilot uses
            // `VISO_*`. The two only overlap cleanly on mounting position; pose
            // alignment, fusion noise and delay are stack-specific. Same reasoning
            // as `do.calibrate.flow` — refuse a partial atom.
            return .notImplemented(detail: "PX4 do.calibrate.vision is intentionally not wired: PX4 (`EKF2_EV_*`) and ArduPilot (`VISO_*`) only overlap on mounting-position params; v1 declines to ship a half-wired surface.")

        // MARK: do — autopilot lifecycle (reboot, …)

        case .fleetVehicleDoRebootAutopilot:
            return .vehicleCommands([.rebootAutopilot])

        // MARK: do — surface (UUV)

        case .fleetVehicleDoSurface:
            // PX4 mainline has no UUV stack and no SURFACE mode equivalent. Recipes
            // targeting underwater ops should branch on `.notImplemented` and either
            // refuse the command or fall back to `do.move.altitude` toward a positive
            // AGL target plus an operator escalation.
            return .notImplemented(detail: "PX4 has no UUV stack — do.surface is not supported. Use do.move.altitude toward a positive AGL target if a UAV / USV needs to climb.")

        // MARK: get — telemetry one-shot reads

        case .fleetVehicleGetTelemetryBattery,
             .fleetVehicleGetTelemetryCompass,
             .fleetVehicleGetTelemetryGps,
             .fleetVehicleGetTelemetryEstimator,
             .fleetVehicleGetTelemetryFlight,
             .fleetVehicleGetTelemetryRc,
             .fleetVehicleGetTelemetryLink,
             .fleetVehicleGetTelemetryMode:
            if let immediate = FleetCommandStackConverterShared.translateGetTelemetry(
                commandName: commandName,
                hub: context.hubTelemetry
            ) {
                return immediate
            }
            return .notImplemented(detail: "PX4 \(commandName.rawValue) telemetry mapping missing.")

        // MARK: cancel
        //
        // Cancelling the in-flight calibration aborts whichever MAVSDK Calibration
        // observable is currently subscribed; the running invocation sees its onError
        // and surfaces a `.cancelled`-shaped failure (string-classified by the shared
        // outcome normaliser in the absence of a typed cancel signal).
        case .fleetVehicleCancelCalibration:
            return .vehicleCommands([.cancelCalibration])
        case .fleetVehicleCancelMission:
            return .notImplemented(
                detail: "Generic `cancel.mission` is not wired — prefer `cancel.mission.upload` or `cancel.mission.download` for MAVSDK `Mission.cancelMissionUpload` / `cancelMissionDownload`."
            )

        default:
            if let mission = FleetCommandStackConverterShared.translateFleetVehicleMissionIfNeeded(
                commandName: commandName,
                parameters: parameters
            ) {
                return mission
            }
            return .notImplemented(detail: "PX4 has no translation registered for \(commandName.rawValue).")
        }
    }

    // MARK: - Outcome normalisation

    func normaliseOutcome(
        _ outcome: FleetCommandAsyncOutcome,
        commandName: FleetCommandName,
        elapsed: TimeInterval
    ) -> FleetCommandResponse {

        if case .failed(let raw) = outcome {
            let lower = raw.lowercased()

            // PX4 commonly surfaces `MAV_RESULT_TEMPORARILY_REJECTED` while in air or
            // during a still-running calibration. Map that to .autopilotBusy so recipes
            // can choose to retry-with-backoff.
            if lower.contains("temporarily_rejected") || lower.contains("temporarily rejected") {
                return .error(.autopilotBusy, detail: raw, elapsed: elapsed)
            }

            // PX4 surfaces explicit DENIED for things like arming with bad calibration.
            if lower.contains("mav_result_denied") {
                if commandName == .fleetVehicleDoArm {
                    // Without a STATUSTEXT we cannot distinguish calibrationDeclined
                    // from a generic rejection — recipes should treat .armRejectedByAutopilot
                    // as covering both and probe further with calibration recipes.
                    return .error(.armRejectedByAutopilot, detail: raw, elapsed: elapsed)
                }
                return .error(.dispatchFailed, detail: raw, elapsed: elapsed)
            }

            // PX4 sometimes returns the raw MAV_CMD result token; map the common ones.
            if lower.contains("mav_result_unsupported") {
                return .error(.notImplemented, detail: raw, elapsed: elapsed)
            }
        }
        return FleetCommandStackConverterShared.normaliseOutcome(outcome, commandName: commandName, elapsed: elapsed)
    }
}
