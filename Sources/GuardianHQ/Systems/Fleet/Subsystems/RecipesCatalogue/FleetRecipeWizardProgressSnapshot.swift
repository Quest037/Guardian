import Foundation

/// Live progress surface for Stage E Vehicle Inspector wizard chrome (and future hosts).
///
/// Published by ``FleetRecipeRunner`` while a recipe body is executing for a vehicle.
/// ``stepOrdinal`` / ``stepTotal`` are **authoring-order** indices (``FleetRecipeBody/steps``),
/// not necessarily the number of physical dispatches (retries / branches can change pacing).
struct FleetRecipeWizardProgressSnapshot: Equatable, Sendable {

    /// Always the **top-level** run id (``FleetRecipeRunner`` per-vehicle slot), even while a nested
    /// ``invokeRecipe`` body is dispatching — matches ``FleetRecipeRunner/cancel(runID:)`` / the
    /// Vehicle Inspector procedure banner.
    let runID: FleetRecipeRunID

    /// Descriptor human label for the recipe whose body is currently executing (may be a nested
    /// child while a parent run is active on the same vehicle).
    let recipeHumanTitle: String

    /// 1-based dispatch index for this run (completed audit entries + the dispatch about to start).
    /// Retries and branches can make this exceed the authored step count; ``stepTotal`` is clamped
    /// so the operator never sees “5 of 3”.
    let stepOrdinal: Int

    /// Display upper bound: at least the authored step count and at least ``stepOrdinal``.
    let stepTotal: Int

    /// Step ID currently being dispatched or about to be dispatched.
    let currentStepID: FleetRecipeStepID

    /// One-line summary (e.g. command name or nested procedure title).
    let activityLine: String
}
