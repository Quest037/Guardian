import Foundation
import os

// MARK: - Errors subsystem registrations

/// Stage C errors subsystem registration entry point.
///
/// Mirrors ``FleetCalibrationRecipeRegistrations`` — a `@MainActor` enum with a
/// single `registerAll()` static method invoked once by
/// ``FleetRecipesCatalogueBootstrap`` at app start. Idempotency is inherited from the
/// catalogue's "last write wins per name" registration rule and the bootstrap's
/// one-shot latch.
///
/// **Hybrid authoring shape.** Each error-fix recipe is authored as two pieces:
/// 1. A ``FleetRecipeDescriptor`` Swift literal inside `registerAll()` — owns the
///    name, human-facing labels, risk tier, retry policy, parameters, prerequisites,
///    escalation expectations, and optional `cancelRecipe`.
/// 2. A per-recipe JSON file at `ErrorBodies/<recipe.name>.json` — owns the step
///    graph (typically `invokeRecipe` steps composing the matching
///    `recipe.fleet.calibrate.*` children). Loaded via
///    ``FleetRecipeBodyLoader/load(recipeName:inSubdirectory:bundle:)`` using
///    ``bodiesSubdirectoryName`` (`"ErrorBodies"`).
///
/// **v1 body is intentionally empty.** Stage C's first error-fix recipe lands one
/// JSON file under `ErrorBodies/` and one descriptor literal inside `registerAll()`.
///
/// **Layer 0 contributions:** error-fix recipes will lean on existing
/// `command.fleet.vehicle.do.*` core commands plus the `command.fleet.vehicle.get.*`
/// telemetry-get verbs. Any error-fix-specific command (e.g. autopilot-side reboot
/// variants beyond `do.reboot.autopilot`) registers alongside the matching recipe.
@MainActor
enum FleetErrorRecipeRegistrations {

    private static let log = OSLog(
        subsystem: "guardian.fleet.recipesCatalogue",
        category: "errors"
    )

    /// Bundle subdirectory holding this subsystem's recipe body JSON files.
    /// Must match the directory name on disk *and* the `.copy(...)` entry in
    /// `Package.swift` — SPM flattens directory copies to the bundle root, so
    /// each subsystem owns a uniquely-named bodies directory.
    static let bodiesSubdirectoryName = "ErrorBodies"

    /// Idempotent. Registers every error-fix recipe into ``FleetRecipesCatalogue``.
    /// Subsequent calls are no-ops by the catalogue's per-name overwrite rule.
    ///
    /// **Ordering note:** error-fix recipes that compose `recipe.fleet.calibrate.*`
    /// children rely on the calibration subsystem registering first; the
    /// bootstrap guarantees that order (`FleetCalibrationRecipeRegistrations.registerAll()`
    /// runs before this entry point).
    static func registerAll() {
        let beforeCount = FleetRecipesCatalogue.shared.descriptors.count

        registerCalibrationRequiredRecipe()

        let registered = FleetRecipesCatalogue.shared.descriptors.count - beforeCount
        os_log(
            .info,
            log: log,
            "Errors subsystem registered (%{public}d recipes).",
            registered
        )
    }

    // MARK: - Recipes

    /// Composite recovery flow: sequential compass → accelerometer → gyro
    /// calibration sweep followed by an arm-probe verification. The migration
    /// target for "autopilot says calibration required on arm" today; surfaces
    /// child failures by failing the parent so a partial sweep never silently
    /// passes recovery.
    ///
    /// Risk tier `groundOnly` because every child is `groundOnly`. cancelRecipe
    /// is `recipe.fleet.calibrate.cancel` because the recipe spends the bulk of
    /// its time inside a calibration procedure; cancelling mid-flight asks the
    /// autopilot to abort any in-progress cal, which is the right cleanup for
    /// the dominant cancel point.
    private static func registerCalibrationRequiredRecipe() {
        let name = FleetRecipeName.literal("recipe.fleet.errors.fix.calibrationrequired")

        guard let body = loadBody(for: name) else { return }

        FleetRecipesCatalogue.shared.register(FleetRecipeDescriptor(
            name: name,
            humanLabel: "Fix: calibration required",
            humanDescription:
                "Sequential calibration sweep (compass → accelerometer → gyro) followed " +
                "by an arm-probe verification. Used as the recovery flow when the " +
                "autopilot reports calibration-required on arm, or when an operator " +
                "triggers a 'fix calibration' action against a system reporting " +
                "calibrationDeclined. Fails the parent on any child failure — a " +
                "partial calibration sweep leaves the autopilot in an undefined state.",
            riskTier: .groundOnly,
            expectedDuration: 560,
            appliesToSystems: ["compass", "accelerometer", "gyro", "preflight"],
            containsRecipes: [
                .literal("recipe.fleet.calibrate.compass"),
                .literal("recipe.fleet.calibrate.accelerometer"),
                .literal("recipe.fleet.calibrate.gyro"),
                .literal("recipe.fleet.diagnose.armprobe"),
            ],
            body: body,
            cancelRecipe: .literal("recipe.fleet.calibrate.cancel")
        ))
    }

    // MARK: - Body loader

    /// Convenience wrapper: load this recipe's body from the subsystem's bodies
    /// directory, log the failure on miss, return `nil` so the caller skips the
    /// registration cleanly. Mirrors the calibration subsystem's loader shape.
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
