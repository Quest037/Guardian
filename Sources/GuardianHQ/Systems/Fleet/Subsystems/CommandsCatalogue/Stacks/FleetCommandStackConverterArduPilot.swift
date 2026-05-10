import Foundation

/// ArduPilot adapter for the universal command catalogue.
///
/// Translates `command.fleet.vehicle.*` invocations into `FleetVehicleCommand` cases
/// (or immediate responses for telemetry reads), and normalises raw
/// `FleetCommandAsyncOutcome` values into the typed
/// ``FleetCommandResponse`` taxonomy.
///
/// **Coverage in v1:**
/// - `do.arm`, `do.disarm`, `do.land`, `do.return.home`, `do.loiter` — wired to the
///   existing `FleetVehicleCommand` cases through `FleetLinkService.executeVehicleCommand`.
/// - `do.mode` — wired for `hold | manual | rtl | landMode | brake`; other modes
///   surface `.error(.notImplemented)`.
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
/// - `do.mission.upload` — wired via `FleetVehicleCommand.uploadMission(items:)` after
///   decoding the `missionItemsJSON` parameter. Sibling `do.mission.*` verbs (start,
///   pause, clear, jumpTo, download, …) are tracked in `TODO.md` and land incrementally.
/// - **Calibration:**
///   - Sensor procedures (`do.calibrate.{gyro, accelerometer, compass, compass.motor,
///     baro, baro.temperature, level, esc, rc, rc.trim}`) — wired through raw MAVLink
///     `COMMAND_LONG` (`MAV_CMD_PREFLIGHT_CALIBRATION`, plus
///     `MAV_CMD_DO_START_MAG_CAL` for interactive mag cal).
///   - Param-driven cals (`do.calibrate.compass.declination`, `do.calibrate.battery.*`,
///     `do.calibrate.airspeed`, `do.calibrate.servo`, `do.calibrate.gimbal.neutral`,
///     `do.calibrate.rangefinder`) — wired as ArduPilot-flavoured `PARAM_SET` writes
///     through `FleetVehicleCommand.setParameterFloat / .setParameterInt`.
///   - `do.calibrate.gimbal` — `.notImplemented` (PX4-only MAVSDK call).
///   - `do.calibrate.{flow, vision}` — intentionally `.notImplemented` in v1.
///     AP `FLOW_*` / `VISO_*` and PX4 (`SENS_FLOW_*` / `EKF2_OF_*` / `EKF2_EV_*`)
///     only overlap cleanly on mounting-position params; per-axis scalers, yaw
///     orientation, sensor type, fusion delay and noise are stack-specific.
///     Shipping a partial atom (position-only) would silently leave the rest
///     mis-calibrated, so the descriptors stay registered for response-taxonomy
///     uniformity but recipe authors should not enroll them as calibration
///     entry-points until a per-stack param-set recipe lands.
/// - `do.reboot.autopilot` — wired via `FleetVehicleCommand.rebootAutopilot`
///   (MAVSDK `Action.reboot()` → `MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN`). Used as the
///   universal "clear all transient state" hammer because MAVLink has no generic
///   clear-errors atom; `errorClearRefused` stays in the response taxonomy for
///   future per-failsafe / per-fault clear atoms.
/// - `do.surface` — wired for ArduSub (UUV class) by dispatching
///   `FleetVehicleCommand.setMode(.surface)` (`mode surface` over the MAVSDK Shell
///   plugin → ArduSub mode 9). Non-UUV ArduPilot airframes surface `.notImplemented`
///   with the offending vehicle class in the detail.
/// - `get.telemetry.*` — wired via shared helpers reading `FleetHubVehicleTelemetry`.
/// - `cancel.calibration` — wired to `MAV_CMD_DO_CANCEL_MAG_CAL` for interactive mag
///   calibration cancellation.
/// - `cancel.mission` — `.notImplemented`.
///
/// Unwired translations log via `OSLog` so it's clear when a recipe encountered a
/// `.notImplemented` because of stack scope versus genuine bug.
struct FleetCommandStackConverterArduPilot: FleetCommandStackConverter {

    let stack: FleetAutopilotStack = .ardupilot

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

        case .fleetVehicleDoMissionUpload:
            return FleetCommandStackConverterShared.translateMissionUpload(parameters: parameters)

        // MARK: do — calibration: autopilot-driven sensor procedures
        //
        // ArduPilot drives these sensor procedures through MAVLink command-long rather
        // than MAVSDK's PX4-flavoured Calibration plugin RPCs.
        case .fleetVehicleDoCalibrateGyro:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "ArduPilot gyro calibration", param1: 1))])
        case .fleetVehicleDoCalibrateAccelerometer:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "ArduPilot accelerometer calibration", param5: 1))])
        case .fleetVehicleDoCalibrateLevel:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "ArduPilot level calibration", param5: 2))])
        case .fleetVehicleDoCalibrateCompass:
            return .vehicleCommands([.mavlinkCommandLong(.startMagCalibration(humanLabel: "ArduPilot magnetometer calibration"))])
        case .fleetVehicleDoCalibrateCompassMotor:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "ArduPilot compass-motor calibration", param6: 1))])
        case .fleetVehicleDoCalibrateBaro:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "ArduPilot barometer calibration", param3: 1))])
        case .fleetVehicleDoCalibrateBaroTemperature:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "ArduPilot barometer temperature calibration", param7: 3))])
        case .fleetVehicleDoCalibrateEsc:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "ArduPilot ESC calibration", param7: 1))])
        case .fleetVehicleDoCalibrateRc:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "ArduPilot RC calibration", param4: 1))])
        case .fleetVehicleDoCalibrateRcTrim:
            return .vehicleCommands([.mavlinkCommandLong(.preflightCalibration(humanLabel: "ArduPilot RC trim calibration", param4: 2))])
        case .fleetVehicleDoCalibrateGimbal:
            return .notImplemented(detail: "ArduPilot has no `gimbal accelerometer` calibration (PX4-only MAVSDK procedure). AP gimbals are configured via `MNT*_*` parameter writes — see do.calibrate.gimbal.neutral.")

        // MARK: do — calibration: param-driven (single PARAM_SET round-trip)
        //
        // Operator (or wizard / plugin) computes the new value; the catalogue command is
        // the atomic write. ArduPilot uses different parameter families from PX4 for
        // every entry below — the PX4 converter has the parallel mapping.
        case .fleetVehicleDoCalibrateCompassDeclination:
            guard let degrees = parameters.double(named: "degrees") else {
                return .notImplemented(detail: "do.calibrate.compass.declination requires a `degrees` parameter.")
            }
            // ArduPilot's COMPASS_DEC parameter is in **radians**; the catalogue takes
            // degrees so callers don't have to know the stack-native unit.
            let radians = degrees * (.pi / 180.0)
            return .vehicleCommands([
                .setParameterFloat(name: "COMPASS_DEC", value: radians)
            ])

        case .fleetVehicleDoCalibrateBatteryVoltage:
            guard let scale = parameters.double(named: "scale") else {
                return .notImplemented(detail: "do.calibrate.battery.voltage requires a `scale` parameter.")
            }
            return .vehicleCommands([
                .setParameterFloat(name: "BATT_VOLT_MULT", value: scale)
            ])

        case .fleetVehicleDoCalibrateBatteryCurrent:
            guard let scale = parameters.double(named: "scale") else {
                return .notImplemented(detail: "do.calibrate.battery.current requires a `scale` parameter.")
            }
            return .vehicleCommands([
                .setParameterFloat(name: "BATT_AMP_PERVLT", value: scale)
            ])

        case .fleetVehicleDoCalibrateBatteryCapacity:
            guard let mAh = parameters.integer(named: "mAh") else {
                return .notImplemented(detail: "do.calibrate.battery.capacity requires an integer `mAh` parameter.")
            }
            return .vehicleCommands([
                .setParameterInt(name: "BATT_CAPACITY", value: Int32(clamping: mAh))
            ])

        case .fleetVehicleDoCalibrateAirspeed:
            // ArduPilot's airspeed cal is the in-flight auto-cal: set ARSPD_AUTOCAL=1
            // and the autopilot will refine the ratio during the next flight. Operator
            // is expected to land, persist, and disable autocal afterwards.
            return .vehicleCommands([
                .setParameterInt(name: "ARSPD_AUTOCAL", value: 1)
            ])

        case .fleetVehicleDoCalibrateGimbalNeutral:
            guard
                let roll = parameters.double(named: "rollDeg"),
                let pitch = parameters.double(named: "pitchDeg"),
                let yaw = parameters.double(named: "yawDeg")
            else {
                return .notImplemented(detail: "do.calibrate.gimbal.neutral requires rollDeg / pitchDeg / yawDeg parameters.")
            }
            // ArduPilot 4.x: MNT1_NEUTRAL_X / Y / Z (degrees). Older ArduPilot used
            // MNT_NEUTRAL_*; we standardise on MNT1_ here. Recipe authors targeting
            // legacy AP can fall back to an explicit setParameterFloat write.
            return .vehicleCommands([
                .setParameterFloat(name: "MNT1_NEUTRAL_X", value: roll),
                .setParameterFloat(name: "MNT1_NEUTRAL_Y", value: pitch),
                .setParameterFloat(name: "MNT1_NEUTRAL_Z", value: yaw)
            ])

        case .fleetVehicleDoCalibrateServo:
            guard
                let channel = parameters.integer(named: "channel"),
                let minPwm = parameters.integer(named: "minPwm"),
                let maxPwm = parameters.integer(named: "maxPwm"),
                let trimPwm = parameters.integer(named: "trimPwm")
            else {
                return .notImplemented(detail: "do.calibrate.servo requires channel / minPwm / maxPwm / trimPwm parameters.")
            }
            let prefix = "SERVO\(channel)_"
            return .vehicleCommands([
                .setParameterInt(name: prefix + "MIN", value: Int32(clamping: minPwm)),
                .setParameterInt(name: prefix + "MAX", value: Int32(clamping: maxPwm)),
                .setParameterInt(name: prefix + "TRIM", value: Int32(clamping: trimPwm))
            ])

        case .fleetVehicleDoCalibrateRangefinder:
            guard
                let minM = parameters.double(named: "minM"),
                let maxM = parameters.double(named: "maxM"),
                let groundClearanceM = parameters.double(named: "groundClearanceM"),
                let orientationRaw = parameters.string(named: "orientation"),
                let orientation = FleetVehicleCoreCommandRangefinderOrientation(rawValue: orientationRaw)
            else {
                return .notImplemented(detail: "do.calibrate.rangefinder requires minM / maxM / groundClearanceM / orientation parameters.")
            }
            // ArduPilot RNGFND1_* ranges are in **centimetres**; convert from the
            // catalogue's stack-agnostic metres input.
            let minCm = Int32(clamping: Int((minM * 100).rounded()))
            let maxCm = Int32(clamping: Int((maxM * 100).rounded()))
            let gndCm = Int32(clamping: Int((groundClearanceM * 100).rounded()))
            let orientCode = mapRangefinderOrientationToArduPilot(orientation)
            return .vehicleCommands([
                .setParameterInt(name: "RNGFND1_MIN_CM", value: minCm),
                .setParameterInt(name: "RNGFND1_MAX_CM", value: maxCm),
                .setParameterInt(name: "RNGFND1_GNDCLEAR", value: gndCm),
                .setParameterInt(name: "RNGFND1_ORIENT", value: orientCode)
            ])

        case .fleetVehicleDoCalibrateFlow:
            // Deliberately not wired in v1. ArduPilot's flow surface (`FLOW_TYPE`,
            // `FLOW_FXSCALER` / `FYSCALER`, `FLOW_ORIENT_YAW`, `FLOW_POS_X/Y/Z`,
            // `FLOW_ADDR`) only overlaps cleanly with PX4 on **mounting position**
            // (`FLOW_POS_X/Y/Z` ↔ `EKF2_OF_POS_*`). Per-axis scalers and the yaw
            // orientation are AP-specific; PX4 has no `FXSCALER` / `FYSCALER` and
            // expresses orientation as the discrete `SENS_FLOW_ROT` enum. Shipping a
            // catalogue surface that only writes position would silently leave scaler
            // and yaw mis-calibrated — worse than no calibration — so v1 declines.
            // Recipes that genuinely need flow calibration should target
            // `command.fleet.vehicle.do.param.set` per-stack until a verified
            // cross-stack parameter contract is designed.
            return .notImplemented(detail: "ArduPilot do.calibrate.flow is intentionally not wired: AP `FLOW_*` and PX4 (`SENS_FLOW_*` / `EKF2_OF_*`) only overlap on mounting-position params; v1 declines to ship a half-wired surface.")

        case .fleetVehicleDoCalibrateVision:
            // Deliberately not wired in v1. ArduPilot's vision surface (`VISO_TYPE`,
            // `VISO_POS_X/Y/Z`, `VISO_YAW`, `VISO_DELAY_MS`) and PX4's (`EKF2_EV_*`)
            // only overlap cleanly on mounting position. Sensor type / pose alignment
            // / fusion delay & noise are stack-specific. Same reasoning as
            // `do.calibrate.flow` — refuse a partial atom.
            return .notImplemented(detail: "ArduPilot do.calibrate.vision is intentionally not wired: AP `VISO_*` and PX4 `EKF2_EV_*` only overlap on mounting-position params; v1 declines to ship a half-wired surface.")

        // MARK: do — autopilot lifecycle (reboot, …)

        case .fleetVehicleDoRebootAutopilot:
            return .vehicleCommands([.rebootAutopilot])

        // MARK: do — surface (UUV / ArduSub)
        //
        // ArduSub exposes a dedicated `SURFACE` flight mode (mode number 9 — see
        // ArduSub `mode.h::Mode::Number::SURFACE`). We dispatch via the existing
        // `do.mode mode=surface` plumbing: `FleetVehicleCommand.setMode(.surface)`
        // routes to `Drone.shell.send("mode surface")` for ArduPilot, which Sub
        // firmware accepts. Non-Sub ArduPilot firmware (Plane / Copter / Rover) does
        // not know the `surface` mode token and will reject the shell command —
        // we short-circuit here based on `vehicleType` so non-UUV airframes get a
        // clean `.notImplemented` (with an explicit reason) instead of an obscure
        // STATUSTEXT error from the autopilot.
        case .fleetVehicleDoSurface:
            if context.vehicleType.universalClass == .uuv {
                return .vehicleCommands([.setMode(.surface)])
            }
            return .notImplemented(
                detail: "do.surface is ArduSub-only; vehicle class is \(context.vehicleType.rawValue)."
            )

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
            return .notImplemented(detail: "ArduPilot \(commandName.rawValue) telemetry mapping missing.")

        // MARK: cancel — long runners

        case .fleetVehicleCancelCalibration:
            return .vehicleCommands([.mavlinkCommandLong(.cancelMagCalibration(humanLabel: "ArduPilot cancel magnetometer calibration"))])
        case .fleetVehicleCancelMission:
            return .notImplemented(detail: "ArduPilot \(commandName.rawValue) not yet wired (cancel pipeline deferred).")

        // MARK: Default

        default:
            return .notImplemented(detail: "ArduPilot has no translation registered for \(commandName.rawValue).")
        }
    }

    // MARK: - Outcome normalisation

    func normaliseOutcome(
        _ outcome: FleetCommandAsyncOutcome,
        commandName: FleetCommandName,
        elapsed: TimeInterval
    ) -> FleetCommandResponse {

        // ArduPilot-flavoured shortcut: `PreArm: <reason>` STATUSTEXT lines often appear
        // appended to MAVSDK Action.arm() failures via PreflightFailureAdvisor /
        // augmentCommandFailureDetail. Catch these explicitly so recipes get a
        // calibrationDeclined kind when the autopilot blocks arming on calibration.
        if case .failed(let raw) = outcome {
            let lower = raw.lowercased()
            if lower.contains("prearm") && lower.contains("compass") {
                return .error(.calibrationDeclined, detail: raw, elapsed: elapsed)
            }
            if lower.contains("prearm") && (lower.contains("accel") || lower.contains("gyro") || lower.contains("ins")) {
                return .error(.calibrationDeclined, detail: raw, elapsed: elapsed)
            }
            if lower.contains("prearm") && lower.contains("baro") {
                return .error(.calibrationDeclined, detail: raw, elapsed: elapsed)
            }
        }
        return FleetCommandStackConverterShared.normaliseOutcome(outcome, commandName: commandName, elapsed: elapsed)
    }

    // MARK: - Helpers

    /// Maps the catalogue's stack-agnostic orientation token to ArduPilot's
    /// `MAV_SENSOR_ORIENTATION` integer used by `RNGFND1_ORIENT`.
    /// Source: ArduPilot RangeFinder driver / MAVLink common.xml.
    private func mapRangefinderOrientationToArduPilot(
        _ orientation: FleetVehicleCoreCommandRangefinderOrientation
    ) -> Int32 {
        switch orientation {
        case .forward:  return 0   // MAV_SENSOR_ROTATION_NONE
        case .right:    return 2   // MAV_SENSOR_ROTATION_YAW_90
        case .backward: return 4   // MAV_SENSOR_ROTATION_YAW_180
        case .left:     return 6   // MAV_SENSOR_ROTATION_YAW_270
        case .up:       return 24  // MAV_SENSOR_ROTATION_PITCH_90
        case .down:     return 25  // MAV_SENSOR_ROTATION_PITCH_270
        }
    }
}
