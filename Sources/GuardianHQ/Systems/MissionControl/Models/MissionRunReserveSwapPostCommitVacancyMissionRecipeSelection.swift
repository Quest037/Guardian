import Foundation

// MARK: - Post–reserve-swap vacancy mission recipe (resume vs fresh start)

/// Chooses between ``FleetMissionRecipeRegistrations/doMissionUploadStartRecipeName`` and
/// ``FleetMissionRecipeRegistrations/doMissionUploadStartItemRecipeName`` for **vacancy** mission
/// upload+arm+start after swap-in, using the **displaced** stream’s last hub mission progress
/// (``FleetHubVehicleTelemetry/missionProgressCurrent`` — same notion as MAVSDK mission progress).
enum MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection: Sendable {

    /// When `nil`, MRE uses ``recipe.fleet.do.mission.upload.start`` (upload resets current item to 0 then arm+start).
    /// When non-`nil`, MRE uses ``recipe.fleet.do.mission.upload.start.item`` with that **0-based** index after upload.
    ///
    /// - **Not started / unknown:** `current == nil` or `current <= 0` → `nil` (standard recipe).
    /// - **Resume:** `current > 0` → clamp into `0 ..< total` when `total` is known and positive; otherwise use `Int(current)`.
    static func handoffMissionStartItemIndex(
        hubMissionProgressCurrent: Int32?,
        hubMissionProgressTotal: Int32?
    ) -> Int? {
        guard let cur = hubMissionProgressCurrent else { return nil }
        if cur <= 0 { return nil }
        let idx = Int(cur)
        guard let tot = hubMissionProgressTotal, tot >= 1 else {
            return idx
        }
        let maxIndex = Int(tot) - 1
        if maxIndex < 0 { return idx }
        return min(idx, maxIndex)
    }
}
