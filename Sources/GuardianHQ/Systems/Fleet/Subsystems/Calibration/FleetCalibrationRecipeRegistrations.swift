import Foundation
import os

// MARK: - Calibration subsystem registrations

/// Stage C calibration subsystem registration entry point.
///
/// Mirrors ``FleetVehicleCoreCommandRegistrations`` (Layer 0) — a `@MainActor` enum
/// with a single `registerAll()` static method invoked once by
/// ``FleetRecipesCatalogueBootstrap`` at app start. Idempotency is inherited from the
/// catalogue's "last write wins per name" registration rule and the bootstrap's
/// one-shot latch; calling this entry point twice during the same process is harmless.
///
/// **Hybrid authoring shape.** Each calibration recipe is authored as two pieces:
/// 1. A ``FleetRecipeDescriptor`` Swift literal inside `registerAll()` — owns the
///    name, human-facing labels, risk tier, retry policy, parameters, prerequisites,
///    escalation expectations, and optional `cancelRecipe`.
/// 2. A per-recipe JSON file at `CalibrationBodies/<recipe.name>.json` — owns the
///    step graph. Loaded via ``FleetRecipeBodyLoader/load(recipeName:inSubdirectory:bundle:)``
///    using ``bodiesSubdirectoryName`` (`"CalibrationBodies"`) and `Bundle.module`,
///    then attached to the descriptor before registration.
///
/// **v1 body is intentionally empty.** Stage C's per-recipe items each land one
/// JSON file under `CalibrationBodies/` and one descriptor literal inside `registerAll()`.
///
/// **Layer 0 contributions:** the calibration subsystem currently piggy-backs on the
/// existing `command.fleet.vehicle.do.calibrate.*` core commands registered by
/// ``FleetVehicleCoreCommandRegistrations``. If a future calibration recipe needs a
/// command that is genuinely subsystem-scoped (not a generic vehicle action), the
/// matching Layer 0 registration goes alongside the recipe registration here.
@MainActor
enum FleetCalibrationRecipeRegistrations {

    private static let log = OSLog(
        subsystem: "guardian.fleet.recipesCatalogue",
        category: "calibration"
    )

    /// Bundle subdirectory holding this subsystem's recipe body JSON files.
    /// Must match the directory name on disk *and* the `.copy(...)` entry in
    /// `Package.swift` — SPM flattens directory copies to the bundle root, so
    /// each subsystem owns a uniquely-named bodies directory.
    static let bodiesSubdirectoryName = "CalibrationBodies"

    /// Idempotent. Registers every calibration recipe into ``FleetRecipesCatalogue``.
    /// Subsequent calls are no-ops by the catalogue's per-name overwrite rule.
    ///
    /// Registration order matters: cleanup recipes register first because
    /// ``FleetRecipesCatalogue`` rejects a descriptor whose declared `cancelRecipe`
    /// is not yet registered. Inside this method the order is therefore
    /// strictly *cleanup recipes → recipes that reference them*.
    static func registerAll() {
        let beforeCount = FleetRecipesCatalogue.shared.descriptors.count

        registerCancelRecipe()

        // Sensor-procedure cals (autopilot-driven; both stacks unless noted).
        registerCompassRecipe()
        registerAccelerometerRecipe()
        registerGyroRecipe()
        registerBaroRecipe()
        registerLevelRecipe()
        registerCompassMotorRecipe()
        registerBaroTemperatureRecipe()
        registerAirspeedRecipe()
        registerEscRecipe()
        registerRcRecipe()
        registerRcTrimRecipe()
        registerGimbalRecipe()

        // Discoverability shells for cals whose per-stack support is not
        // implemented in v1; running on a current stack returns a precise
        // "not supported in this app version" failure.
        registerRangefinderRecipe()
        registerFlowRecipe()
        registerVisionRecipe()

        // Param-driven cals. Bodies forward descriptor parameters into Layer 0
        // command parameters through FleetRecipeParameterValue.reference.
        registerCompassDeclinationRecipe()
        registerBatteryVoltageRecipe()
        registerBatteryCurrentRecipe()
        registerBatteryCapacityRecipe()
        registerServoRecipe()
        registerGimbalNeutralRecipe()

        // Diagnose recipes. Stage E's wizard migrates today's preflight overlay
        // onto `recipe.fleet.diagnose.armprobe`; the matching `recipe.fleet
        // .diagnose.cancel` is the cleanup the armprobe declares so cancel
        // mid-probe still disarms the vehicle. The cancel recipe must register
        // first because the catalogue refuses descriptors whose `cancelRecipe`
        // is not yet registered.
        registerArmProbeCancelRecipe()
        registerArmProbeRecipe()

        let registered = FleetRecipesCatalogue.shared.descriptors.count - beforeCount
        os_log(
            .info,
            log: log,
            "Calibration subsystem registered (%{public}d recipes).",
            registered
        )
    }

    // MARK: - Recipes

    /// Best-effort cleanup recipe used as the `cancelRecipe` for every interactive
    /// calibration recipe. Atomic by design (no `containsRecipes`, no own
    /// `cancelRecipe`) so the catalogue accepts it as a valid cleanup target.
    private static func registerCancelRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.cancel")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Cancel calibration",
            humanDescription:
                "Best-effort cleanup that asks the autopilot to abort any in-progress " +
                "calibration procedure. Used as the cancelRecipe for interactive " +
                "calibration recipes so cancelling mid-flight leaves the autopilot in " +
                "a clean (no-calibration-running) state.",
            riskTier: .safeInLiveMission,
            expectedDuration: 2,
            body: body
        ))
    }

    /// Interactive magnetometer calibration. Operator rotates the vehicle through
    /// three orthogonal axes while the autopilot collects samples and computes
    /// hard- and soft-iron offsets. Risk-tier `groundOnly` because the procedure
    /// renders the heading reference unstable while running.
    private static func registerCompassRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.compass")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Compass calibration",
            humanDescription:
                "Interactive magnetometer calibration. The operator rotates the vehicle " +
                "through three orthogonal axes while the autopilot collects samples and " +
                "computes hard- and soft-iron offsets. Requires the vehicle on the " +
                "ground and clear of large ferrous objects.",
            riskTier: .groundOnly,
            expectedDuration: 120,
            appliesToSystems: ["compass"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Six-position accelerometer calibration. Operator orients the airframe through
    /// each face while the autopilot collects samples and computes per-axis bias and
    /// scale. Risk-tier `groundOnly` because the procedure invalidates the attitude
    /// estimate while running.
    private static func registerAccelerometerRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.accelerometer")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Accelerometer calibration",
            humanDescription:
                "Six-position accelerometer calibration. The operator orients the airframe " +
                "through each face (level, on side, on other side, nose up, nose down, on back) " +
                "while the autopilot collects samples and computes per-axis bias and scale. " +
                "Requires the vehicle on the ground and on a stable, level reference for the " +
                "first orientation.",
            riskTier: .groundOnly,
            expectedDuration: 180,
            appliesToSystems: ["accelerometer"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Gyroscope null-rate calibration. Operator sets the vehicle on a stable surface
    /// and does not touch it while the autopilot zeroes the angular-rate bias. Risk
    /// tier `groundOnly` — running mid-mission would zero the rate reference and
    /// destabilise attitude control.
    private static func registerGyroRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.gyro")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Gyro calibration",
            humanDescription:
                "Gyroscope null-rate calibration. The operator sets the vehicle on a " +
                "stable surface and does not touch it while the autopilot zeroes the " +
                "angular-rate bias. Fast procedure (typically 10-30s); the only operator " +
                "action that can recover a failure is to hold the vehicle still.",
            riskTier: .groundOnly,
            expectedDuration: 15,
            appliesToSystems: ["gyro"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Barometer ground-pressure reset. Vehicle must be on the ground and still while
    /// the autopilot zeroes the baro reference at current altitude. Risk tier
    /// `groundOnly` — running mid-mission would invalidate every subsequent altitude
    /// report.
    private static func registerBaroRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.baro")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Barometer calibration",
            humanDescription:
                "Barometer ground-pressure reset. The operator sets the vehicle on the " +
                "ground and does not touch it while the autopilot zeroes the baro " +
                "reference at the current altitude. Fast procedure (typically <5s); " +
                "operator-recoverable failures are about motion / vibration during " +
                "sampling.",
            riskTier: .groundOnly,
            expectedDuration: 5,
            appliesToSystems: ["barometer"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// AHRS level / horizon reference capture. Operator places the vehicle on a
    /// stable, level surface; the autopilot snapshots the current attitude as the
    /// zero reference for the artificial horizon and self-level modes. Risk tier
    /// `groundOnly` — overwriting the horizon reference mid-mission would destabilise
    /// attitude control.
    private static func registerLevelRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.level")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Level calibration",
            humanDescription:
                "AHRS level / horizon reference capture. The operator places the vehicle " +
                "on a stable, level surface; the autopilot captures the current attitude " +
                "as the zero reference so the artificial horizon and self-level modes are " +
                "accurate. Both recoverable failure kinds resolve to the same operator " +
                "action — get the vehicle flatter and steadier.",
            riskTier: .groundOnly,
            expectedDuration: 20,
            appliesToSystems: ["level"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Compass-motor interference characterisation. ArduPilot-only — operator
    /// restrains the airframe while the autopilot sweeps throttle and samples
    /// magnetic deflection. PX4 path returns `notImplemented` and surfaces a clean
    /// "not supported on this stack" failure via the body's matcher.
    private static func registerCompassMotorRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.compass.motor")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Compass-motor interference calibration",
            humanDescription:
                "ArduPilot-only compass-motor interference characterisation. The " +
                "operator physically restrains the airframe while the autopilot " +
                "sweeps throttle and measures magnetic deflection per throttle / " +
                "current step; the resulting compensation table de-biases the " +
                "compass against motor-induced fields. PX4 has no equivalent " +
                "procedure.",
            riskTier: .groundOnly,
            expectedDuration: 180,
            appliesToSystems: ["compass"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Barometer temperature compensation. ArduPilot-only cold-start procedure
    /// (10-15 minutes of warm-up sampling). PX4 path returns `notImplemented`.
    private static func registerBaroTemperatureRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.baro.temperature")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Barometer temperature calibration",
            humanDescription:
                "ArduPilot-only cold-start barometer temperature-compensation " +
                "calibration. The vehicle sits powered and unmoving while the " +
                "autopilot samples the baro across its warm-up temperature range " +
                "and fits the compensation curve. Long procedure — typically " +
                "10-15 minutes.",
            riskTier: .groundOnly,
            expectedDuration: 600,
            appliesToSystems: ["barometer"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Airspeed sensor zero / auto-calibration. Both stacks; PX4 invokes the
    /// procedure directly, ArduPilot enables auto-cal on the next flight via
    /// `ARSPD_AUTOCAL`.
    private static func registerAirspeedRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.airspeed")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Airspeed calibration",
            humanDescription:
                "Airspeed sensor zero / auto-calibration. The operator shields the " +
                "pitot tube from wind and the autopilot zeroes the differential " +
                "pressure reading. PX4 runs the procedure inline; ArduPilot arms " +
                "the auto-calibrate flag for the next flight.",
            riskTier: .groundOnly,
            expectedDuration: 10,
            appliesToSystems: ["airspeed"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// ESC throttle-endpoint calibration. **Dangerous** — motors arm and spin at
    /// the endpoints; props must be removed and the airframe restrained. Operator
    /// gates this through the Vehicle Inspector / wizard UI; the recipe runner
    /// itself does not insert an extra pre-confirmation step in v1.
    private static func registerEscRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.esc")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "ESC throttle calibration",
            humanDescription:
                "DANGEROUS: Electronic Speed Controller throttle-endpoint " +
                "calibration. Motors arm and run at the procedure's throttle " +
                "endpoints — propellers MUST be removed and the airframe MUST be " +
                "physically restrained. Operator unplugs the battery to start, " +
                "invokes the cal, then reconnects so ESCs can learn the autopilot's " +
                "high/low PWM endpoints, then disconnects again to commit.",
            riskTier: .groundOnly,
            expectedDuration: 90,
            appliesToSystems: ["esc"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Interactive RC channel min / max / centre calibration.
    private static func registerRcRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.rc")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "RC calibration",
            humanDescription:
                "Interactive RC channel min / max / centre calibration. The operator " +
                "powers on the transmitter, binds the receiver, and exercises every " +
                "stick / switch through its full physical range so the autopilot can " +
                "learn the PWM endpoints per channel.",
            riskTier: .groundOnly,
            expectedDuration: 90,
            appliesToSystems: ["rc"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// RC stick-centre trim capture. Faster sibling of full RC calibration; no
    /// min / max sweep.
    private static func registerRcTrimRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.rc.trim")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "RC trim calibration",
            humanDescription:
                "RC stick-centre trim capture. The operator centres every stick on " +
                "the transmitter and the autopilot snapshots the resulting PWM " +
                "values as the new trim baseline. Faster sibling of the full RC " +
                "calibration; no min / max sweep.",
            riskTier: .groundOnly,
            expectedDuration: 15,
            appliesToSystems: ["rc"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Gimbal accelerometer calibration. PX4-only via MAVSDK; ArduPilot path
    /// returns `notImplemented` (param-driven `gimbal.neutral` lives separately).
    private static func registerGimbalRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.gimbal")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Gimbal accelerometer calibration",
            humanDescription:
                "PX4-only gimbal accelerometer calibration via the MAVSDK Calibration " +
                "plugin. The gimbal must be detected on the bus and able to report " +
                "its accelerometer for the autopilot to characterise its mounting. " +
                "ArduPilot has no equivalent MAVSDK call — use the separate " +
                "param-driven `recipe.fleet.calibrate.gimbal.neutral` workflow.",
            riskTier: .groundOnly,
            expectedDuration: 30,
            appliesToSystems: ["gimbal"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Rangefinder calibration — discoverability shell. Both stacks return
    /// `notImplemented` in v1; AP `RNGFND_*` and PX4 driver families don't
    /// overlap cleanly enough to ship a portable recipe.
    private static func registerRangefinderRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.rangefinder")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Rangefinder calibration",
            humanDescription:
                "Rangefinder / lidar calibration. Not implemented in this app " +
                "version — AP `RNGFND_*` and PX4 per-driver parameter families are " +
                "disjoint enough that a portable cal recipe requires a per-stack, " +
                "per-driver authoring pass. Registered so the Vehicle Inspector " +
                "lists it and any invocation gets a precise failure message.",
            riskTier: .groundOnly,
            appliesToSystems: ["rangefinder"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Optical-flow calibration — discoverability shell. Both stacks return
    /// `notImplemented` in v1.
    private static func registerFlowRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.flow")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Optical-flow calibration",
            humanDescription:
                "Optical-flow sensor calibration. Not implemented in this app " +
                "version — AP `FLOW_*` and PX4 `SENS_FLOW_*` / `EKF2_OF_*` overlap " +
                "only on mounting-position params; per-axis scalers, yaw orientation, " +
                "sensor type, and fusion delay are stack-specific. Registered for " +
                "discoverability.",
            riskTier: .groundOnly,
            appliesToSystems: ["flow"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Vision-pose calibration — discoverability shell. Both stacks return
    /// `notImplemented` in v1.
    private static func registerVisionRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.vision")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Vision-pose calibration",
            humanDescription:
                "Vision-pose source calibration. Not implemented in this app " +
                "version — AP `VISO_*` and PX4 `EKF2_EV_*` parameter families " +
                "differ enough (sensor type, delay, noise) that a portable cal " +
                "recipe requires a per-stack authoring pass. Registered for " +
                "discoverability.",
            riskTier: .groundOnly,
            appliesToSystems: ["vision"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Set magnetic declination in degrees. Stack converters handle native units
    /// and read-back validation.
    private static func registerCompassDeclinationRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.compass.declination")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Compass declination calibration",
            humanDescription:
                "Write the magnetic declination in degrees. The ArduPilot converter " +
                "handles radians, PX4 receives degrees directly, and both paths verify " +
                "the write by reading the parameter back.",
            parameters: [
                FleetRecipeParameterDeclaration(name: "degrees", type: .double, required: true, humanLabel: "Declination (deg)"),
            ],
            riskTier: .groundOnly,
            expectedDuration: 5,
            appliesToSystems: ["compass"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Battery voltage scale write, computed by the operator / wizard from
    /// measured-vs-reported pack voltage.
    private static func registerBatteryVoltageRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.battery.voltage")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Battery voltage calibration",
            humanDescription:
                "Write the battery voltage scale factor computed from measured-vs-" +
                "reported pack voltage. Stack converters map to the native autopilot " +
                "parameter and validate the write by read-back.",
            parameters: [
                FleetRecipeParameterDeclaration(name: "scale", type: .double, required: true, humanLabel: "Voltage scale"),
            ],
            riskTier: .groundOnly,
            expectedDuration: 5,
            appliesToSystems: ["battery"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Battery current scale write, computed by the operator / wizard from
    /// measured-vs-reported current.
    private static func registerBatteryCurrentRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.battery.current")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Battery current calibration",
            humanDescription:
                "Write the battery current scale factor computed from measured-vs-" +
                "reported current. Stack converters map to the native autopilot " +
                "parameter and validate the write by read-back.",
            parameters: [
                FleetRecipeParameterDeclaration(name: "scale", type: .double, required: true, humanLabel: "Current scale"),
            ],
            riskTier: .groundOnly,
            expectedDuration: 5,
            appliesToSystems: ["battery"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Battery capacity write in mAh.
    private static func registerBatteryCapacityRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.battery.capacity")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Battery capacity calibration",
            humanDescription:
                "Write the battery pack capacity in mAh. Stack converters map to " +
                "the native autopilot parameter and validate the write by read-back.",
            parameters: [
                FleetRecipeParameterDeclaration(name: "mAh", type: .integer, required: true, humanLabel: "Capacity (mAh)"),
            ],
            riskTier: .groundOnly,
            expectedDuration: 5,
            appliesToSystems: ["battery"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Servo PWM endpoint calibration for one channel.
    private static func registerServoRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.servo")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Servo endpoint calibration",
            humanDescription:
                "Write min / max / trim PWM endpoints for one servo channel. " +
                "Stack converters expand the command into the native parameter " +
                "writes and validate each write by read-back.",
            parameters: [
                FleetRecipeParameterDeclaration(name: "channel", type: .integer, required: true, humanLabel: "Channel (1-16)"),
                FleetRecipeParameterDeclaration(name: "minPwm", type: .integer, required: true, humanLabel: "Min PWM (us)"),
                FleetRecipeParameterDeclaration(name: "maxPwm", type: .integer, required: true, humanLabel: "Max PWM (us)"),
                FleetRecipeParameterDeclaration(name: "trimPwm", type: .integer, required: true, humanLabel: "Trim PWM (us)"),
            ],
            riskTier: .groundOnly,
            expectedDuration: 10,
            appliesToSystems: ["servo"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    /// Gimbal neutral roll / pitch / yaw offset write.
    private static func registerGimbalNeutralRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.calibrate.gimbal.neutral")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Gimbal neutral calibration",
            humanDescription:
                "Write gimbal neutral roll / pitch / yaw offsets in degrees. " +
                "Stack converters expand the command into native parameter writes " +
                "and validate each write by read-back.",
            parameters: [
                FleetRecipeParameterDeclaration(name: "rollDeg", type: .double, required: true, humanLabel: "Roll neutral (deg)"),
                FleetRecipeParameterDeclaration(name: "pitchDeg", type: .double, required: true, humanLabel: "Pitch neutral (deg)"),
                FleetRecipeParameterDeclaration(name: "yawDeg", type: .double, required: true, humanLabel: "Yaw neutral (deg)"),
            ],
            riskTier: .groundOnly,
            expectedDuration: 10,
            appliesToSystems: ["gimbal"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    // MARK: - Diagnose recipes

    /// Cleanup recipe for the arm probe — atomic best-effort disarm. Declared as
    /// the `cancelRecipe` of `recipe.fleet.diagnose.armprobe` so a cancel that
    /// arrives after arm succeeded but before the recipe's own disarm step had
    /// a chance to run still leaves the vehicle disarmed. Atomic (no
    /// `containsRecipes`, no own `cancelRecipe`) so the catalogue accepts it as
    /// a valid cleanup target.
    private static func registerArmProbeCancelRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.diagnose.cancel")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Cancel arm probe",
            humanDescription:
                "Best-effort disarm used as the cancelRecipe for the arm probe. " +
                "Runs when the operator cancels mid-probe (after a successful arm " +
                "but before the probe's own disarm step has had a chance to run) " +
                "so cancel never leaves a vehicle armed on the pad.",
            riskTier: .safeInLiveMission,
            expectedDuration: 2,
            body: body
        ))
    }

    /// Arm probe — attempts to arm the vehicle and immediately disarms. The
    /// migration target for today's preflight overlay (Stage E swaps the UI;
    /// Stage C just authors the recipe). Risk tier `groundOnly`; Stage B2's
    /// `allowDuringLiveMission` override remains the supported escape hatch for
    /// the "reserve drone deployment / drone-back-online" workflows the user
    /// flagged for live-mission preflight.
    private static func registerArmProbeRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.diagnose.armprobe")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Arm probe",
            humanDescription:
                "Attempts to arm the vehicle and immediately disarms; surfaces the " +
                "common autopilot refusal reasons (GPS lock, calibration state, mode, " +
                "battery, autopilot busy, link health) as classified failures via the " +
                "matcher list. Stage E's wizard migrates today's preflight overlay onto " +
                "this recipe — the underlying probe is the same arm-then-disarm " +
                "sequence today's PreflightProbeArm runs.",
            riskTier: .groundOnly,
            expectedDuration: 8,
            appliesToSystems: ["arm", "preflight"],
            body: body,
            cancelRecipe: .literal("recipe.fleet.diagnose.cancel")
        ))
    }

    // MARK: - Body loader

    /// Convenience wrapper: load this recipe's body from the subsystem's bodies
    /// directory, log the failure on miss, return `nil` so the caller skips the
    /// registration cleanly.
    private static func loadBody(for name: FleetRecipeName) -> FleetRecipeBody? {
        let outcome = FleetRecipeBodyLoader.load(
            recipeName: name,
            inSubdirectory: bodiesSubdirectoryName,
            bundle: .module
        )
        switch outcome {
        case .success(let body):
            return body
        case .failure(let error):
            os_log(
                .fault,
                log: log,
                "Skipping registration of %{public}@: %{public}@",
                name.rawValue,
                error.description
            )
            return nil
        }
    }
}
