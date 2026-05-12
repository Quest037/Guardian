import Foundation

// MARK: - Swap-time checklist (live reserve swap-in)

/// Locked **v1** policy for what to verify on a reserve **before** a live swap-in pipeline
/// mutates roster / pool (executor wiring remains in ``MissionRosterReservesToDo.md``).
///
/// **Arm vs arm probe:** the catalogue **arm probe** recipes orchestrate arm/disarm to
/// prove the path; there is no separate standalone “arm only” recipe row in this checklist.
enum MissionRunReserveSwapTimeChecklist {

    /// Catalogue recipes that implement the **arm-path smoke test** (same family as Mission
    /// Control **start-run** preflight). Runtime must pick **exactly one** variant using the
    /// same policy as ``MissionControlStore`` arm-probe wiring — never run both in one gate.
    static func armProbeRecipeChoices() -> [FleetRecipeName] {
        [
            .literal("recipe.fleet.diagnose.armprobe"),
            .literal("recipe.fleet.diagnose.armprobe.hold"),
        ]
    }

    /// Optional **IMU / compass / RC trim** calibration recipes after phase-1 arm probe
    /// passes. **v1 stack policy:** identical ordered list for ArduPilot, PX4, and unknown
    /// stacks (catalogue bodies differ internally by command stack).
    static func optionalPostArmCalibrationRecipes(stack: FleetAutopilotStack) -> [FleetRecipeName] {
        switch stack {
        case .ardupilot, .px4, .unknown:
            return [
                .literal("recipe.fleet.calibrate.compass"),
                .literal("recipe.fleet.calibrate.accelerometer"),
                .literal("recipe.fleet.calibrate.rc.trim"),
            ]
        }
    }

    /// Telemetry / advisory signals to review **alongside** recipes (no dedicated
    /// `recipe.*` swap gate in v1 — reuse live calibration rows and preflight classifiers).
    enum NonRecipeGate: CaseIterable, Equatable, Sendable {
        /// RC link / hub health (e.g. ``FleetVehicleCalibrationModel`` RC item).
        case rcLink
        /// Geofence / fence breach signals (e.g. ``PreflightFailureAdvisor`` `common.geofence`).
        case geofenceOrFence
    }

    /// **v1:** same non-recipe review set for every ``FleetAutopilotStack`` case.
    static func nonRecipeGates(stack: FleetAutopilotStack) -> [NonRecipeGate] {
        switch stack {
        case .ardupilot, .px4, .unknown:
            return NonRecipeGate.allCases
        }
    }
}
