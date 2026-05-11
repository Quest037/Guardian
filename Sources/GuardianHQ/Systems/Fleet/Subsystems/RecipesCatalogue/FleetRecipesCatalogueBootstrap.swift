import Foundation
import os

/// One-shot registration of built-in recipe descriptors into ``FleetRecipesCatalogue``.
///
/// Pattern mirrors ``FleetCommandsCatalogueBootstrap`` and ``GuardianPluginBootstrap``:
/// idempotent, lock-guarded, safe from any call site during app startup. Plugin
/// contributions (Stage F) will register alongside core through their own bootstrap
/// once manifest namespace claims land.
///
/// **Subsystem entry points** are invoked here, in the order Stage C documents:
/// 1. ``FleetCalibrationRecipeRegistrations/registerAll()``
/// 2. ``FleetErrorRecipeRegistrations/registerAll()``
///
/// Both entry points are idempotent on their own and ship zero recipes today (Stage C
/// authoring is content-only — no further bootstrap edits expected). The bootstrap
/// continues to short-circuit on its own latch so calling `ensureRegistered()` twice
/// in the same process is still cheap.
enum FleetRecipesCatalogueBootstrap {

    private static let didRegister = OSAllocatedUnfairLock(initialState: false)

    private static let log = OSLog(
        subsystem: "guardian.fleet.recipesCatalogue",
        category: "bootstrap"
    )

    /// Idempotent. Subsequent calls are no-ops.
    @MainActor
    static func ensureRegistered() {
        let shouldRun = Self.didRegister.withLock { flag -> Bool in
            if flag { return false }
            flag = true
            return true
        }
        guard shouldRun else { return }

        FleetCalibrationRecipeRegistrations.registerAll()
        FleetErrorRecipeRegistrations.registerAll()

        // Telemetry directory references recipes by name; validate after every
        // subsystem has registered so an authoring typo (citation added without
        // the matching registration landing) surfaces as a fault at app start
        // rather than at menu-render time in Stage E. A miss is a soft failure
        // — the Vehicle Inspector skips the missing menu entry — so we log
        // rather than crash.
        let misses = FleetTelemetryFieldCatalog
            .validateRecipeReferences(against: FleetRecipesCatalogue.shared)
        for miss in misses {
            os_log(
                .fault,
                log: log,
                "Telemetry directory: %{public}@",
                miss.description
            )
        }

        os_log(
            .info,
            log: log,
            "FleetRecipesCatalogue bootstrap completed (%{public}d recipes registered, %{public}d directory misses).",
            FleetRecipesCatalogue.shared.descriptors.count,
            misses.count
        )
    }

    /// Test-only reset of the idempotency latch. Pairs with
    /// ``FleetRecipesCatalogue/_testOnlyReset()`` so each test can run against a
    /// known-empty registry.
    static func _testOnlyResetIdempotencyFlag() {
        Self.didRegister.withLock { $0 = false }
    }
}
