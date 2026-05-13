import Foundation

extension FleetRecipeOutcome {
    /// Whether Mission Run should log this **failed** recipe outcome with the geofence-specific
    /// fleet template instead of the generic ``MissionRunLogTemplateKey/fleetAckFailed``.
    ///
    /// Covers standalone geofence recipes, catalogue geofence steps, and composite
    /// `do.mission.upload` stacks where the first failing child was geofence (detail is prefixed
    /// in ``FleetCommandsCatalogue/dispatchSequentially``).
    func isMissionRunGeofenceFleetFailureForDistinctExecutorLogs(recipeName: FleetRecipeName) -> Bool {
        guard !isSuccess else { return false }
        guard case .failed(let path, let lastResponse, _, let trace) = self else { return false }
        if recipeName.rawValue == "recipe.fleet.do.geofence.upload"
            || recipeName.rawValue == "recipe.fleet.do.geofence.clear" {
            return true
        }
        if path.contains(where: { $0.rawValue == "uploadGeofence" }) { return true }
        if let last = trace.entries.last {
            switch last.kind {
            case .command(let cmdName)
                where cmdName.rawValue == "command.fleet.vehicle.do.geofence.upload"
                || cmdName.rawValue == "command.fleet.vehicle.do.geofence.clear":
                return true
            default:
                break
            }
        }
        let lower = (lastResponse?.detail ?? "").lowercased()
        if lower.hasPrefix("upload geofence") || lower.hasPrefix("clear geofence") {
            return true
        }
        return false
    }
}
