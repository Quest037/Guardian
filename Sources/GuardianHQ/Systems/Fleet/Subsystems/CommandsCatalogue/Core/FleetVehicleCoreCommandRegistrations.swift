import Foundation

// MARK: - Built-in command name literals

/// Stable, internal-only literals for every core `command.fleet.vehicle.*` command.
///
/// These are the names registration code refers to, the names stack converters branch
/// on, and the names recipes (Stage B) will reference by raw string. Any rename here
/// is a coordinated change: catalogue registration + stack converters + recipe
/// catalogues all need to update together.
extension FleetCommandName {

    // MARK: do — nav atomics

    static let fleetVehicleDoArm =
        FleetCommandName.literal("command.fleet.vehicle.do.arm")
    static let fleetVehicleDoDisarm =
        FleetCommandName.literal("command.fleet.vehicle.do.disarm")
    static let fleetVehicleDoMode =
        FleetCommandName.literal("command.fleet.vehicle.do.mode")
    static let fleetVehicleDoLoiter =
        FleetCommandName.literal("command.fleet.vehicle.do.loiter")
    static let fleetVehicleDoPark =
        FleetCommandName.literal("command.fleet.vehicle.do.park")
    static let fleetVehicleDoLand =
        FleetCommandName.literal("command.fleet.vehicle.do.land")
    static let fleetVehicleDoSurface =
        FleetCommandName.literal("command.fleet.vehicle.do.surface")
    static let fleetVehicleDoReturnHome =
        FleetCommandName.literal("command.fleet.vehicle.do.return.home")
    static let fleetVehicleDoMoveAltitude =
        FleetCommandName.literal("command.fleet.vehicle.do.move.altitude")
    static let fleetVehicleDoMoveHeading =
        FleetCommandName.literal("command.fleet.vehicle.do.move.heading")
    static let fleetVehicleDoMovePoint =
        FleetCommandName.literal("command.fleet.vehicle.do.move.point")

    // MARK: do — mission verbs (upload / start / pause / clear / jumpTo / download …)

    /// Atomic upload of a mission plan. Sibling mission verbs (`do.mission.start`,
    /// `do.mission.pause`, `do.mission.clear`, `do.mission.jumpTo`, `do.mission.download`)
    /// share the MAVSDK `Mission` plugin surface via
    /// ``FleetCommandStackConverterShared/translateFleetVehicleMissionIfNeeded(commandName:parameters:)``.
    static let fleetVehicleDoMissionUpload =
        FleetCommandName.literal("command.fleet.vehicle.do.mission.upload")
    static let fleetVehicleDoMissionClear =
        FleetCommandName.literal("command.fleet.vehicle.do.mission.clear")
    static let fleetVehicleDoMissionStart =
        FleetCommandName.literal("command.fleet.vehicle.do.mission.start")
    static let fleetVehicleDoMissionPause =
        FleetCommandName.literal("command.fleet.vehicle.do.mission.pause")
    static let fleetVehicleDoMissionJumpTo =
        FleetCommandName.literal("command.fleet.vehicle.do.mission.jump.to")
    static let fleetVehicleDoMissionDownload =
        FleetCommandName.literal("command.fleet.vehicle.do.mission.download")
    static let fleetVehicleDoMissionUploadWithProgress =
        FleetCommandName.literal("command.fleet.vehicle.do.mission.upload.with.progress")
    static let fleetVehicleDoMissionDownloadWithProgress =
        FleetCommandName.literal("command.fleet.vehicle.do.mission.download.with.progress")
    static let fleetVehicleDoMissionRtlAfterSet =
        FleetCommandName.literal("command.fleet.vehicle.do.mission.rtl.after.set")
    static let fleetVehicleDoMissionUploadStart =
        FleetCommandName.literal("command.fleet.vehicle.do.mission.upload.start")

    static let fleetVehicleGetMissionFinished =
        FleetCommandName.literal("command.fleet.vehicle.get.mission.finished")
    static let fleetVehicleGetMissionRtlAfter =
        FleetCommandName.literal("command.fleet.vehicle.get.mission.rtl.after")

    static let fleetVehicleCancelMissionUpload =
        FleetCommandName.literal("command.fleet.vehicle.cancel.mission.upload")
    static let fleetVehicleCancelMissionDownload =
        FleetCommandName.literal("command.fleet.vehicle.cancel.mission.download")

    // MARK: do — calibration atomics

    // Sensor cals (autopilot-driven 6-position / spin-rest / pressure-zero procedures)
    static let fleetVehicleDoCalibrateCompass =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass")
    static let fleetVehicleDoCalibrateCompassMotor =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass.motor")
    static let fleetVehicleDoCalibrateCompassDeclination =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.compass.declination")
    static let fleetVehicleDoCalibrateAccelerometer =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.accelerometer")
    static let fleetVehicleDoCalibrateGyro =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.gyro")
    static let fleetVehicleDoCalibrateBaro =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.baro")
    static let fleetVehicleDoCalibrateBaroTemperature =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.baro.temperature")
    static let fleetVehicleDoCalibrateLevel =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.level")
    static let fleetVehicleDoCalibrateAirspeed =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.airspeed")

    // Power / battery monitor cals (param-driven; operator computes scale or capacity)
    static let fleetVehicleDoCalibrateBatteryVoltage =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.battery.voltage")
    static let fleetVehicleDoCalibrateBatteryCurrent =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.battery.current")
    static let fleetVehicleDoCalibrateBatteryCapacity =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.battery.capacity")

    // Actuators / RC cals
    static let fleetVehicleDoCalibrateEsc =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.esc")
    static let fleetVehicleDoCalibrateRc =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.rc")
    static let fleetVehicleDoCalibrateRcTrim =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.rc.trim")
    static let fleetVehicleDoCalibrateServo =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.servo")

    // Auxiliary sensor cals (param-driven; ride on RNGFND* / FLOW* / VISN* families)
    static let fleetVehicleDoCalibrateRangefinder =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.rangefinder")
    static let fleetVehicleDoCalibrateFlow =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.flow")
    static let fleetVehicleDoCalibrateVision =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.vision")

    // Mount / gimbal cals
    static let fleetVehicleDoCalibrateGimbal =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.gimbal")
    static let fleetVehicleDoCalibrateGimbalNeutral =
        FleetCommandName.literal("command.fleet.vehicle.do.calibrate.gimbal.neutral")

    // MARK: do — autopilot lifecycle (reboot, …)

    /// Reboots the autopilot via `MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN`. Used as the
    /// universal "clear all transient state" action because MAVLink / MAVSDK do not
    /// expose a generic "clear errors" command — STATUSTEXT messages are one-way and
    /// health flags clear themselves when the underlying condition resolves.
    static let fleetVehicleDoRebootAutopilot =
        FleetCommandName.literal("command.fleet.vehicle.do.reboot.autopilot")

    // MARK: get — telemetry one-shot reads

    static let fleetVehicleGetTelemetryBattery =
        FleetCommandName.literal("command.fleet.vehicle.get.telemetry.battery")
    static let fleetVehicleGetTelemetryCompass =
        FleetCommandName.literal("command.fleet.vehicle.get.telemetry.compass")
    static let fleetVehicleGetTelemetryGps =
        FleetCommandName.literal("command.fleet.vehicle.get.telemetry.gps")
    static let fleetVehicleGetTelemetryEstimator =
        FleetCommandName.literal("command.fleet.vehicle.get.telemetry.estimator")
    static let fleetVehicleGetTelemetryFlight =
        FleetCommandName.literal("command.fleet.vehicle.get.telemetry.flight")
    static let fleetVehicleGetTelemetryRc =
        FleetCommandName.literal("command.fleet.vehicle.get.telemetry.rc")
    static let fleetVehicleGetTelemetryLink =
        FleetCommandName.literal("command.fleet.vehicle.get.telemetry.link")
    static let fleetVehicleGetTelemetryMode =
        FleetCommandName.literal("command.fleet.vehicle.get.telemetry.mode")

    // MARK: cancel — stop long-runners

    static let fleetVehicleCancelCalibration =
        FleetCommandName.literal("command.fleet.vehicle.cancel.calibration")
    static let fleetVehicleCancelMission =
        FleetCommandName.literal("command.fleet.vehicle.cancel.mission")
}

// MARK: - Mode parameter allowed-values (stack-agnostic)

/// Allowed `mode` parameter values for `command.fleet.vehicle.do.mode`. Backed by
/// ``FleetVehicleMode`` so the catalogue's allow-list and the runtime command type
/// cannot drift. Per-stack dispatch happens in
/// ``FleetLinkService/completionForSetMode(mode:vehicleID:session:)``.
enum FleetVehicleCoreCommandModeValue {
    static var allowedSet: Set<String> {
        Set(FleetVehicleMode.allCases.map(\.rawValue))
    }
}

// MARK: - Allowed datums for move.altitude

enum FleetVehicleCoreCommandAltitudeDatum: String, CaseIterable {
    case asl
    case msl
    case agl

    static var allowedSet: Set<String> {
        Set(allCases.map(\.rawValue))
    }
}

// MARK: - Allowed point kinds for move.point

/// Stack-agnostic point selectors for `command.fleet.vehicle.do.move.point`.
///
/// * `currentLatLon` — re-target the vehicle's current latitude / longitude. Useful for
///   "stay here at altitude X heading Y" stop-the-bleeding moves; lat/lon come from
///   hub telemetry inside the converter.
/// * `home` / `rally` — symbolic points sourced from the autopilot. Catalogue-side
///   readback is **not** wired in v1; the converters surface `.notImplemented` so
///   recipes can branch.
/// * `explicit` — caller supplies `latitudeDeg` / `longitudeDeg` directly. This is the
///   path MRE uses today via `FleetVehicleCommand.gotoCoordinate(...)`.
enum FleetVehicleCoreCommandPointKind: String, CaseIterable {
    case currentLatLon
    case home
    case rally
    case explicit

    static var allowedSet: Set<String> {
        Set(allCases.map(\.rawValue))
    }
}

// MARK: - Allowed orientations for do.calibrate.rangefinder

/// Stack-agnostic orientation tokens for `command.fleet.vehicle.do.calibrate.rangefinder`.
/// Maps to ArduPilot's `MAV_SENSOR_ORIENTATION` family (`RNGFND1_ORIENT`) and PX4's
/// `SENS_*_ROT` parameter families inside the per-stack converter.
enum FleetVehicleCoreCommandRangefinderOrientation: String, CaseIterable {
    case down
    case forward
    case backward
    case up
    case left
    case right

    static var allowedSet: Set<String> {
        Set(allCases.map(\.rawValue))
    }
}

// MARK: - Registration entry point

/// Registers every core `command.fleet.vehicle.*` descriptor at boot. Idempotent; safe
/// to call from any thread because the catalogue is `@MainActor`.
enum FleetVehicleCoreCommandRegistrations {

    @MainActor
    static func registerAll() {
        registerNavCommands()
        registerMissionCatalogueCommands()
        registerCalibrationCommands()
        registerLifecycleCommands()
        registerTelemetryGetCommands()
        registerCancelCommands()
    }

    // MARK: do — nav atomics

    @MainActor
    private static func registerNavCommands() {

        // do.arm — request the autopilot to arm motors.
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoArm,
            humanLabel: "Arm",
            humanDescription: "Request the autopilot to arm motors. Idempotent — already-armed vehicles surface `alreadyArmed` rather than failing.",
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .alreadyArmed, .armRejectedByAutopilot, .calibrationDeclined, .modeNotSupported, .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .groundOnly
        ))

        // do.disarm — request the autopilot to disarm motors.
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoDisarm,
            humanLabel: "Disarm",
            humanDescription: "Request the autopilot to disarm motors. Idempotent — already-disarmed vehicles surface `alreadyDisarmed` rather than failing.",
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .alreadyDisarmed, .modeNotSupported, .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        // do.mode — set autopilot mode.
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMode,
            humanLabel: "Set mode",
            humanDescription: "Set the autopilot's flight / drive mode. Allowed values are stack-agnostic; per-stack converters translate to the concrete autopilot mode.",
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "mode",
                    type: .string,
                    required: true,
                    allowedStringValues: FleetVehicleCoreCommandModeValue.allowedSet,
                    humanLabel: "Mode"
                )
            ],
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .modeNotSupported, .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        // do.loiter — hold position / loiter where supported.
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoLoiter,
            humanLabel: "Loiter",
            humanDescription: "Hold position or attitude where the airframe / autopilot supports a loiter mode.",
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .modeNotSupported, .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .safeInLiveMission
        ))

        // do.park — class-aware land/surface, disarm, hold (single orchestrated vehicle command).
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoPark,
            humanLabel: "Park",
            humanDescription:
                "Bring the vehicle to a safe parked state: first best-effort `Mission.pauseMission()` so onboard mission execution stops where supported, then class-specific steps — " +
                "UAV and unknown-class targets land if airborne, then disarm and enter hold/loiter; " +
                "UGV/USV hold to stop motion, disarm, then `Action.hold()` again for a clear parked mode (PX4 **UGV-W**: first stop uses raw `SET_MODE` hold / AUTO_LOITER like catalogue `do.mode` hold, then disarm, then a final `Action.hold()`); " +
                "UUV surfaces if below the surface threshold (ArduSub `mode surface`), then disarm and hold. " +
                "Implemented as one `FleetVehicleCommand.park` pipeline in FleetLink — not a multi-step catalogue composite.",
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .modeNotSupported, .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        // do.land — command the autopilot to land now.
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoLand,
            humanLabel: "Land",
            humanDescription: "Command the autopilot to land at the current position (where supported).",
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .modeNotSupported, .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        // do.surface — UUV surface action.
        //
        // Wired on ArduPilot for UUV class only: dispatches `mode surface` via the
        // MAVSDK Shell plugin, which ArduSub firmware honours (mode number 9). PX4 has
        // no UUV stack and surfaces `.notImplemented`. Non-UUV ArduPilot airframes
        // (Plane / Copter / Rover) also surface `.notImplemented` because their
        // firmware does not know the `surface` mode token. Recipes that target
        // mixed-class fleets should branch on `.notImplemented` rather than assume
        // the autopilot will silently no-op.
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoSurface,
            humanLabel: "Surface",
            humanDescription: "Command an underwater vehicle to surface. Wired for ArduSub (UUV class) via `mode surface`. PX4 and non-UUV ArduPilot airframes surface `.notImplemented`.",
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .modeNotSupported, .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        // do.return.home — return-to-launch.
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoReturnHome,
            humanLabel: "Return home",
            humanDescription: "Navigate back toward home / launch using the autopilot's RTL action.",
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .modeNotSupported, .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        // do.move.altitude — move to a target altitude (parameterised).
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMoveAltitude,
            humanLabel: "Move to altitude",
            humanDescription: "Move the vehicle to a specific altitude relative to the chosen datum. Stack converters map to autopilot-specific climb / descend semantics.",
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "meters", type: .double, required: true, humanLabel: "Altitude (m)"
                ),
                FleetCommandParameterDeclaration(
                    name: "datum",
                    type: .string,
                    required: true,
                    allowedStringValues: FleetVehicleCoreCommandAltitudeDatum.allowedSet,
                    humanLabel: "Datum"
                )
            ],
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .modeNotSupported, .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        // do.move.heading — translate horizontally on a heading by a distance.
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMoveHeading,
            humanLabel: "Move on heading",
            humanDescription: "Translate the vehicle horizontally on the supplied bearing by the supplied distance.",
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "distanceM", type: .double, required: true, humanLabel: "Distance (m)"
                ),
                FleetCommandParameterDeclaration(
                    name: "headingDegrees", type: .double, required: true, humanLabel: "Heading (deg)"
                )
            ],
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .modeNotSupported, .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        // do.move.point — move to a point.
        //
        // Today's wired path is `pointKind = explicit | currentLatLon`, which dispatches to
        // `FleetVehicleCommand.gotoCoordinate(coord, relativeAltitudeM:, yawDeg:)` inside the
        // stack converter. `home` and `rally` need autopilot-side readback (no hub field
        // exposes them yet) and surface `.notImplemented`.
        //
        // Parameter shape:
        // * `pointKind` (required, allow-listed)
        // * `latitudeDeg` / `longitudeDeg` (required only when `pointKind = explicit`,
        //   enforced cross-field by the converter — the schema marks them optional so
        //   `currentLatLon` invocations don't need to pass dummy values)
        // * `relativeAltitudeM` (required — every move targets a height)
        // * `yawDeg` (optional — defaults to 0 when omitted)
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMovePoint,
            humanLabel: "Move to point",
            humanDescription: "Move the vehicle to a point. Use `pointKind=explicit` with latitudeDeg / longitudeDeg for waypoint moves, or `pointKind=currentLatLon` to re-target the vehicle's current position at a new altitude / yaw. `home` and `rally` are stack-resolved and not yet wired.",
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "pointKind",
                    type: .string,
                    required: true,
                    allowedStringValues: FleetVehicleCoreCommandPointKind.allowedSet,
                    humanLabel: "Point kind"
                ),
                FleetCommandParameterDeclaration(
                    name: "latitudeDeg",
                    type: .double,
                    required: false,
                    humanLabel: "Latitude (deg)"
                ),
                FleetCommandParameterDeclaration(
                    name: "longitudeDeg",
                    type: .double,
                    required: false,
                    humanLabel: "Longitude (deg)"
                ),
                FleetCommandParameterDeclaration(
                    name: "relativeAltitudeM",
                    type: .double,
                    required: true,
                    humanLabel: "Altitude above takeoff (m)"
                ),
                FleetCommandParameterDeclaration(
                    name: "yawDeg",
                    type: .double,
                    required: false,
                    humanLabel: "Yaw (deg)"
                )
            ],
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .modeNotSupported, .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        // do.mission.upload — upload a Mission plan to the autopilot (atomic upload only).
        //
        // Mission items are passed through as a JSON string under `missionItemsJSON`
        // because the catalogue's parameter schema only supports scalar values. The
        // shared converter helper decodes the JSON into `[Mavsdk.Mission.MissionItem]`
        // and the stack converters produce `[.uploadMission(items:)]`.
        //
        // Scope: this command is the **upload step only** (mirrors MAVSDK
        // `Mission.uploadMission` + `setCurrentMissionItem(0)`). The composite
        // `do.mission.upload.start` chains upload, `do.arm`, then `do.mission.start`
        // (see registration below).
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMissionUpload,
            humanLabel: "Upload mission",
            humanDescription: "Upload a list of mission items to the autopilot's Mission plugin and reset the current item to the first waypoint. Atomic upload only — does not arm or start the mission.",
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "missionItemsJSON",
                    type: .string,
                    required: true,
                    humanLabel: "Mission items (JSON array)"
                )
            ],
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))
    }

    // MARK: do / get / cancel — mission plugin (MAVSDK Mission)

    @MainActor
    private static func registerMissionCatalogueCommands() {

        let missionDoKinds = FleetCommandDeclaredResponseKinds.standardDo.adding(.autopilotBusy)
        let missionGetKinds = FleetCommandDeclaredResponseKinds.standardGet

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMissionClear,
            humanLabel: "Clear mission",
            humanDescription: "Clear the mission plan stored on the autopilot (`Mission.clearMission`).",
            declaredResponseKinds: missionDoKinds,
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMissionStart,
            humanLabel: "Start mission",
            humanDescription: "Start mission execution (`Mission.startMission`). Vehicle must already be in a mission-capable mode where the stack supports it.",
            declaredResponseKinds: missionDoKinds,
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMissionPause,
            humanLabel: "Pause mission",
            humanDescription: "Pause mission execution (`Mission.pauseMission`).",
            declaredResponseKinds: missionDoKinds,
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMissionJumpTo,
            humanLabel: "Jump to mission item",
            humanDescription: "Set the current mission item index (`Mission.setCurrentMissionItem`). Supply integer `index` (preferred) or `missionItemIndex`.",
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "index",
                    type: .integer,
                    required: true,
                    humanLabel: "Mission item index"
                )
            ],
            declaredResponseKinds: missionDoKinds,
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMissionDownload,
            humanLabel: "Download mission",
            humanDescription: "Download the mission plan from the autopilot (`Mission.downloadMission`). On success the response payload is a JSON array string in the same shape as `do.mission.upload`'s `missionItemsJSON` parameter.",
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDoMissionDownload,
            retryHints: .conservative,
            riskTier: .safeInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMissionUploadWithProgress,
            humanLabel: "Upload mission (with progress)",
            humanDescription: "Catalogue placeholder for MAVSDK `uploadMissionWithProgress` (Observable). Not wired in Guardian v1 — invoke returns `.notImplemented` until streaming Layer 0 support lands.",
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "missionItemsJSON",
                    type: .string,
                    required: true,
                    humanLabel: "Mission items (JSON array)"
                )
            ],
            declaredResponseKinds: missionDoKinds,
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMissionDownloadWithProgress,
            humanLabel: "Download mission (with progress)",
            humanDescription: "Catalogue placeholder for MAVSDK `downloadMissionWithProgress` (Observable). Not wired in Guardian v1 — invoke returns `.notImplemented` until streaming Layer 0 support lands.",
            declaredResponseKinds: missionDoKinds,
            retryHints: .conservative,
            riskTier: .safeInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleGetMissionFinished,
            humanLabel: "Mission finished?",
            humanDescription: "Read whether the mission has finished (`Mission.isMissionFinished`). Success payload is a boolean.",
            declaredResponseKinds: missionGetKinds,
            retryHints: .none,
            riskTier: .safeInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleGetMissionRtlAfter,
            humanLabel: "RTL after mission?",
            humanDescription: "Read whether the vehicle will RTL after the mission completes (`Mission.getReturnToLaunchAfterMission`). Success payload is a boolean.",
            declaredResponseKinds: missionGetKinds,
            retryHints: .none,
            riskTier: .safeInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMissionRtlAfterSet,
            humanLabel: "Set RTL after mission",
            humanDescription: "Enable or disable return-to-launch after the mission completes (`Mission.setReturnToLaunchAfterMission`).",
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "enable",
                    type: .bool,
                    required: true,
                    humanLabel: "Enable RTL after mission"
                )
            ],
            declaredResponseKinds: missionDoKinds,
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        let cancelKinds = FleetCommandDeclaredResponseKinds.standardCancel.adding(.autopilotBusy)

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleCancelMissionUpload,
            humanLabel: "Cancel mission upload",
            humanDescription: "Cancel an in-flight mission upload (`Mission.cancelMissionUpload`).",
            declaredResponseKinds: cancelKinds,
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleCancelMissionDownload,
            humanLabel: "Cancel mission download",
            humanDescription: "Cancel an in-flight mission download (`Mission.cancelMissionDownload`).",
            declaredResponseKinds: cancelKinds,
            retryHints: .conservative,
            riskTier: .safeInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoMissionUploadStart,
            humanLabel: "Upload, arm, then start mission",
            humanDescription: "Composite: uploads `missionItemsJSON`, arms (`do.arm`), then starts mission execution (`do.mission.start`). Same parameters as upload — extra keys are ignored by the arm step.",
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "missionItemsJSON",
                    type: .string,
                    required: true,
                    humanLabel: "Mission items (JSON array)"
                )
            ],
            declaredResponseKinds: missionDoKinds,
            retryHints: .conservative,
            riskTier: .confirmInLiveMission,
            containsCommands: [.fleetVehicleDoMissionUpload, .fleetVehicleDoArm, .fleetVehicleDoMissionStart]
        ))
    }

    // MARK: do — calibration atomics
    //
    // Calibration commands fall into three transport flavours, all `groundOnly`:
    //
    // * **Autopilot-driven sensor procedures** (gyro, accel, mag, level, gimbal-accel):
    //   run on the flight controller and emit a progress stream where the stack exposes
    //   one. PX4 bridges the MAVSDK `Calibration` plugin via `FleetVehicleCommand
    //   .calibrateMavsdk(_:)`; raw MAVLink-only procedures use
    //   `.mavlinkCommandLong(...)` with `MAV_CMD_PREFLIGHT_CALIBRATION` or the mag-cal
    //   command-long siblings.
    //
    // * **Stack-native sensor procedures exposed only as MAVLink command-long**
    //   (baro, ESC, RC, RC trim, compass-motor, some airspeed paths): dispatch through
    //   the raw `COMMAND_LONG` transport. Recipes still own progress, timeout, and
    //   operator-prompt policy above this Layer 0 atom.
    //
    // * **Param-driven cals** (compass declination, battery voltage / current /
    //   capacity, servo endpoints, gimbal neutral, rangefinder / flow / vision setup,
    //   ArduPilot airspeed auto-cal): expand to one or more `setParameterFloat /
    //   setParameterInt` writes through the MAVSDK Param plugin. The recipe layer does
    //   the read-modify-write where the new value depends on the existing one (e.g.
    //   battery voltage scale). The catalogue command is the atomic write itself; the
    //   operator wizard / plugin computes the input value.

    @MainActor
    private static func registerCalibrationCommands() {

        let sensorKinds = FleetCommandDeclaredResponseKinds.standardDo.adding(
            .calibrationDeclined, .calibrationDidNotConverge, .modeNotSupported, .autopilotBusy
        )
        let paramKinds = FleetCommandDeclaredResponseKinds.standardDo.adding(
            .parameterRejected, .parameterReadBackMismatch, .autopilotBusy
        )

        // MARK: sensor procedures (autopilot-driven, stream-of-progress)

        register(
            name: .fleetVehicleDoCalibrateGyro,
            label: "Calibrate gyro",
            description: "Run the autopilot's gyroscope null-rate calibration. Vehicle must be still on a level surface.",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateAccelerometer,
            label: "Calibrate accelerometer",
            description: "Run the autopilot's six-position accelerometer calibration. Operator orients the airframe through each face.",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateLevel,
            label: "Calibrate level",
            description: "Capture the airframe's level reference for the AHRS / horizon. Vehicle must be still on a level surface.",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateCompass,
            label: "Calibrate compass",
            description: "Run the autopilot's interactive magnetometer calibration (rotation through three orthogonal axes).",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateCompassMotor,
            label: "Calibrate compass-motor interference",
            description: "ArduPilot-only: characterise compass deflection vs throttle / current to compensate for motor magnetic interference.",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateBaro,
            label: "Calibrate barometer",
            description: "Reset the autopilot's ground-pressure reference (zero baro at current altitude). Vehicle must be on the ground.",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateBaroTemperature,
            label: "Calibrate barometer temperature",
            description: "ArduPilot-only: cold-start barometer temperature compensation calibration.",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateAirspeed,
            label: "Calibrate airspeed",
            description: "Zero / auto-calibrate the airspeed sensor for fixed-wing platforms. PX4 invokes the autopilot procedure; ArduPilot enables auto-cal during the next flight via `ARSPD_AUTOCAL`.",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateEsc,
            label: "Calibrate ESCs",
            description: "Run the autopilot's ESC throttle endpoint calibration (multirotor). Battery must be unplugged at the start of the procedure.",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateRc,
            label: "Calibrate RC",
            description: "Interactive RC channel min / max / centre calibration. Operator moves all sticks and switches through their full range.",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateRcTrim,
            label: "Calibrate RC trim",
            description: "Capture RC stick centre trims without re-running full min / max calibration.",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateGimbal,
            label: "Calibrate gimbal accelerometer",
            description: "PX4-only: run the gimbal accelerometer calibration via the MAVSDK Calibration plugin.",
            kinds: sensorKinds
        )
        register(
            name: .fleetVehicleDoCalibrateFlow,
            label: "Calibrate optical flow",
            description: "Initialise / scale optical-flow sensor parameters. Stack-specific param family (`FLOW_*` on ArduPilot, `EKF2_OF_*` on PX4).",
            kinds: paramKinds
        )
        register(
            name: .fleetVehicleDoCalibrateVision,
            label: "Calibrate vision pose",
            description: "Reset the vision pose origin / fusion offset. Stack-specific param family.",
            kinds: paramKinds
        )

        // MARK: param-driven cals (single PARAM_SET round-trip per write)

        register(
            name: .fleetVehicleDoCalibrateCompassDeclination,
            label: "Set compass declination",
            description: "Write the magnetic declination (degrees) to the autopilot's compass parameter. Stack converter handles unit conversion (radians on ArduPilot, degrees on PX4).",
            kinds: paramKinds,
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "degrees",
                    type: .double,
                    required: true,
                    humanLabel: "Declination (deg)"
                )
            ]
        )
        register(
            name: .fleetVehicleDoCalibrateBatteryVoltage,
            label: "Calibrate battery voltage",
            description: "Write the autopilot's battery voltage scale parameter (`BATT_VOLT_MULT` on ArduPilot, `BAT_V_DIV` on PX4). Operator / wizard computes the multiplier from measured-vs-reported voltage.",
            kinds: paramKinds,
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "scale",
                    type: .double,
                    required: true,
                    humanLabel: "Voltage scale"
                )
            ]
        )
        register(
            name: .fleetVehicleDoCalibrateBatteryCurrent,
            label: "Calibrate battery current",
            description: "Write the autopilot's battery current scale parameter (`BATT_AMP_PERVLT` on ArduPilot, `BAT_A_PER_V` on PX4). Operator / wizard computes the multiplier from measured-vs-reported current.",
            kinds: paramKinds,
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "scale",
                    type: .double,
                    required: true,
                    humanLabel: "Current scale"
                )
            ]
        )
        register(
            name: .fleetVehicleDoCalibrateBatteryCapacity,
            label: "Set battery capacity",
            description: "Write the autopilot's battery pack capacity in mAh (`BATT_CAPACITY` on ArduPilot, `BAT1_CAPACITY` on PX4).",
            kinds: paramKinds,
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "mAh",
                    type: .integer,
                    required: true,
                    humanLabel: "Capacity (mAh)"
                )
            ]
        )
        register(
            name: .fleetVehicleDoCalibrateServo,
            label: "Calibrate servo endpoints",
            description: "Write min / max / trim PWM endpoints for one servo channel. Expands to three sequential `PARAM_SET` writes.",
            kinds: paramKinds,
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "channel",
                    type: .integer,
                    required: true,
                    humanLabel: "Channel (1-16)"
                ),
                FleetCommandParameterDeclaration(
                    name: "minPwm",
                    type: .integer,
                    required: true,
                    humanLabel: "Min PWM (us)"
                ),
                FleetCommandParameterDeclaration(
                    name: "maxPwm",
                    type: .integer,
                    required: true,
                    humanLabel: "Max PWM (us)"
                ),
                FleetCommandParameterDeclaration(
                    name: "trimPwm",
                    type: .integer,
                    required: true,
                    humanLabel: "Trim PWM (us)"
                )
            ]
        )
        register(
            name: .fleetVehicleDoCalibrateGimbalNeutral,
            label: "Set gimbal neutral angles",
            description: "Write the gimbal mount's neutral roll / pitch / yaw offsets. Expands to three sequential `PARAM_SET` writes.",
            kinds: paramKinds,
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "rollDeg",
                    type: .double,
                    required: true,
                    humanLabel: "Roll neutral (deg)"
                ),
                FleetCommandParameterDeclaration(
                    name: "pitchDeg",
                    type: .double,
                    required: true,
                    humanLabel: "Pitch neutral (deg)"
                ),
                FleetCommandParameterDeclaration(
                    name: "yawDeg",
                    type: .double,
                    required: true,
                    humanLabel: "Yaw neutral (deg)"
                )
            ]
        )
        register(
            name: .fleetVehicleDoCalibrateRangefinder,
            label: "Calibrate rangefinder",
            description: "Configure rangefinder min / max range, ground clearance, and orientation. Stack converter expands to the appropriate `RNGFND_*` family writes.",
            kinds: paramKinds,
            parameters: [
                FleetCommandParameterDeclaration(
                    name: "minM",
                    type: .double,
                    required: true,
                    humanLabel: "Min range (m)"
                ),
                FleetCommandParameterDeclaration(
                    name: "maxM",
                    type: .double,
                    required: true,
                    humanLabel: "Max range (m)"
                ),
                FleetCommandParameterDeclaration(
                    name: "groundClearanceM",
                    type: .double,
                    required: true,
                    humanLabel: "Ground clearance (m)"
                ),
                FleetCommandParameterDeclaration(
                    name: "orientation",
                    type: .string,
                    required: true,
                    allowedStringValues: FleetVehicleCoreCommandRangefinderOrientation.allowedSet,
                    humanLabel: "Orientation"
                )
            ]
        )
    }

    /// Internal helper to keep the calibration registration table tidy. Honours the
    /// `groundOnly` policy: every calibration is gated to ground state at the
    /// risk-tier check inside `FleetCommandsCatalogue.invoke()`.
    @MainActor
    private static func register(
        name: FleetCommandName,
        label: String,
        description: String,
        kinds: FleetCommandDeclaredResponseKinds,
        parameters: [FleetCommandParameterDeclaration] = [],
        riskTier: FleetCommandRiskTier = .groundOnly,
        retryHints: FleetCommandRetryHints = .none
    ) {
        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: name,
            humanLabel: label,
            humanDescription: description,
            parameters: parameters,
            declaredResponseKinds: kinds,
            retryHints: retryHints,
            riskTier: riskTier
        ))
    }

    // MARK: do — autopilot lifecycle (reboot, …)
    //
    // The Layer 0 catalogue does **not** register `do.error.clear.all` /
    // `do.error.clear.message` — neither MAVLink nor MAVSDK exposes a generic
    // "clear errors" command, and STATUSTEXT messages are one-way (no autopilot-side
    // acknowledgement). Error resolution is therefore per-error / per-stack:
    //
    // * **Sticky / latched faults** — clear by re-running the relevant
    //   `do.calibrate.*` command, by writing the responsible failsafe parameter (e.g.
    //   `FS_BATT_ENABLE=0` on ArduPilot via `setParameterFloat`), or by `do.disarm`
    //   then `do.arm` once the underlying condition resolves.
    // * **Transient health-flag failures** — clear themselves when the underlying
    //   condition resolves (GPS lock, calibration pass, mode-supported, …); recipes
    //   poll via `get.telemetry.*`.
    // * **All transient autopilot state at once** — `do.reboot.autopilot` (this
    //   command), the heavy hammer.
    //
    // The `errorClearRefused` ``FleetCommandErrorKind`` stays in the taxonomy so
    // future per-failsafe / per-fault clear atoms (when they land) can speak it.

    @MainActor
    private static func registerLifecycleCommands() {

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleDoRebootAutopilot,
            humanLabel: "Reboot autopilot",
            humanDescription: "Reboots the autopilot to clear all transient state (sticky pre-arm faults, latched failsafes, hung calibrations). Closest universal \"reset\" since MAVLink has no generic clear-errors command. Ground-only.",
            declaredResponseKinds: FleetCommandDeclaredResponseKinds.standardDo.adding(
                .autopilotBusy
            ),
            retryHints: .conservative,
            riskTier: .groundOnly
        ))
    }

    // MARK: get — telemetry one-shot reads

    @MainActor
    private static func registerTelemetryGetCommands() {

        let getKinds = FleetCommandDeclaredResponseKinds.standardGet

        let reads: [(FleetCommandName, String, String)] = [
            (.fleetVehicleGetTelemetryBattery,
             "Get battery",
             "Read latest cached battery voltage / current / remaining percent / time-remaining."),
            (.fleetVehicleGetTelemetryCompass,
             "Get compass",
             "Read latest cached heading and per-flag magnetometer health."),
            (.fleetVehicleGetTelemetryGps,
             "Get GPS",
             "Read latest cached GPS fix type, satellite count, lat / lon / altitude."),
            (.fleetVehicleGetTelemetryEstimator,
             "Get estimator",
             "Read the EKF / estimator health flags."),
            (.fleetVehicleGetTelemetryFlight,
             "Get flight state",
             "Read armed / in-air / mode-text and per-flag flight-state health."),
            (.fleetVehicleGetTelemetryRc,
             "Get RC",
             "Read latest cached RC presence / availability snapshot."),
            (.fleetVehicleGetTelemetryLink,
             "Get link",
             "Read latest cached MAVLink stream / link-quality snapshot."),
            (.fleetVehicleGetTelemetryMode,
             "Get mode",
             "Read the autopilot's current mode text.")
        ]

        for (name, label, description) in reads {
            FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
                name: name,
                humanLabel: label,
                humanDescription: description,
                declaredResponseKinds: getKinds,
                retryHints: .none,
                riskTier: .safeInLiveMission
            ))
        }
    }

    // MARK: cancel — stop long-runners

    @MainActor
    private static func registerCancelCommands() {

        let cancelKinds = FleetCommandDeclaredResponseKinds.standardCancel.adding(
            .autopilotBusy
        )

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleCancelCalibration,
            humanLabel: "Cancel calibration",
            humanDescription: "Abort an in-progress calibration procedure on the autopilot.",
            declaredResponseKinds: cancelKinds,
            retryHints: .conservative,
            riskTier: .safeInLiveMission
        ))

        FleetCommandsCatalogue.shared.register(FleetCommandDescriptor(
            name: .fleetVehicleCancelMission,
            humanLabel: "Cancel mission",
            humanDescription: "Abort an in-progress mission upload / start, where the autopilot supports it.",
            declaredResponseKinds: cancelKinds,
            retryHints: .conservative,
            riskTier: .confirmInLiveMission
        ))
    }
}
