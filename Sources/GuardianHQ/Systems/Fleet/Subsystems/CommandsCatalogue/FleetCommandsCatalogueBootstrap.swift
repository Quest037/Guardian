import Foundation
import os

/// One-shot registration of built-in core descriptors and stack converters into
/// ``FleetCommandsCatalogue``.
///
/// Pattern mirrors ``GuardianPluginBootstrap``: idempotent, lock-guarded, safe from
/// any call site during app startup. Plugin contributions (Stage F) will register
/// alongside core through their own bootstrap once manifest namespace claims land.
enum FleetCommandsCatalogueBootstrap {

    private static let didRegister = OSAllocatedUnfairLock(initialState: false)

    /// Idempotent. Subsequent calls are no-ops.
    @MainActor
    static func ensureRegistered() {
        let shouldRun = Self.didRegister.withLock { flag -> Bool in
            if flag { return false }
            flag = true
            return true
        }
        guard shouldRun else { return }

        // Order matters only insofar as composite descriptors (v1: none) require their
        // children to be registered first. We register stack converters last so any
        // descriptor-validation log lines surface before stack-side wiring.
        FleetVehicleCoreCommandRegistrations.registerAll()

        FleetCommandsCatalogue.shared.registerStackConverter(FleetCommandStackConverterArduPilot())
        FleetCommandsCatalogue.shared.registerStackConverter(FleetCommandStackConverterPX4())
        FleetCommandsCatalogue.shared.registerStackConverter(FleetCommandStackConverterUnknown())
    }
}
