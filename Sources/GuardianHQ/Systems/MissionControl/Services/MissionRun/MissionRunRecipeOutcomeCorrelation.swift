import Foundation

/// Guards MRE recipe **fleet ack** handling against the wrong ``FleetRecipeOutcome`` (``FleetRecipeRunner`` already
/// enforces one top-level run per ``vehicleID``; this catches impossible cross-wiring or future regressions).
enum MissionRunRecipeOutcomeCorrelation {

    /// `true` when the audit trace matches the issued **recipe** dispatch and the resolved fleet stream id.
    nonisolated static func outcomeTraceMatchesIssuedRecipeDispatch(
        issued: MissionRunIssuedCommand,
        outcome: FleetRecipeOutcome,
        resolvedFleetVehicleID: String
    ) -> Bool {
        guard outcome.trace.vehicleID == resolvedFleetVehicleID else { return false }
        guard case .recipe(let name, _) = issued.dispatch else { return false }
        return outcome.trace.recipe == name
    }
}
