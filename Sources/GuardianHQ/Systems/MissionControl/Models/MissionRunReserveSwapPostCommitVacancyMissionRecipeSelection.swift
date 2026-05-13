import Foundation

// MARK: - Post–reserve-swap vacancy mission recipe (resume vs fresh start)

/// Chooses between ``FleetMissionRecipeRegistrations/doMissionUploadStartRecipeName`` and
/// ``FleetMissionRecipeRegistrations/doMissionUploadStartItemRecipeName`` for **vacancy** mission
/// upload+arm+start after swap-in, using the **displaced** stream’s last hub mission progress
/// (``FleetHubVehicleTelemetry/missionProgressCurrent`` / ``missionProgressTotal`` — same stream as MAVSDK mission progress).
enum MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection: Sendable {

    /// When `nil`, MRE uses ``recipe.fleet.do.mission.upload.start`` (upload resets current item to 0 then arm+start).
    /// When non-`nil`, MRE uses ``recipe.fleet.do.mission.upload.start.item`` with that **0-based** index after upload
    /// (``command.fleet.vehicle.do.mission.jump.to`` / ``missionSetCurrentItem``).
    ///
    /// - **Not started / unknown:** `current == nil` or `current <= 0` → `nil` (standard recipe).
    /// - **Resume:** `current > 0` → map `current` to the jump index with **`Int(current) - 1`** (hub progress reads one
    ///   step ahead of the index that matches the compiled upload envelope in the field), then clamp into
    ///   `0 ... total - 1` when `total` is known and positive.
    static func handoffMissionStartItemIndex(
        hubMissionProgressCurrent: Int32?,
        hubMissionProgressTotal: Int32?
    ) -> Int? {
        guard let cur = hubMissionProgressCurrent else { return nil }
        if cur <= 0 { return nil }
        let idx0 = Int(cur) - 1
        if idx0 < 0 { return nil }
        guard let tot = hubMissionProgressTotal, tot >= 1 else {
            return idx0
        }
        let maxIndex = Int(tot) - 1
        if maxIndex < 0 { return idx0 }
        return min(idx0, maxIndex)
    }
}
