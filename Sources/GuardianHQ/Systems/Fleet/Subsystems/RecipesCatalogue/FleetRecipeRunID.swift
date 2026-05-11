import Foundation

// MARK: - Run ID

/// Opaque per-run identifier produced by ``FleetRecipeRunner`` for every started
/// recipe execution. Stable for the lifetime of a single run and carried by every
/// escalation event, audit entry, and cancel request so downstream consumers can
/// correlate them without leaking runner internals.
///
/// `Hashable` so handlers can index events by run; `Sendable` so it can cross actor
/// boundaries when Stage D's prompt router lands.
struct FleetRecipeRunID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init() {
        self.rawValue = UUID()
    }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    var description: String { rawValue.uuidString }
}
