import Foundation

/// Stable `MapVehicleMarker.id` values for MC-R **floating reserve pool** aircraft (not roster ``MissionRunAssignment`` ids).
enum MissionControlReservePoolMapMarkerID {
    static let prefix = "frp"

    /// Encodes task + pool slot so the live map tap handler can open the correct **task triage** sheet.
    static func encode(taskID: UUID, slotID: UUID) -> String {
        "\(prefix)|\(taskID.uuidString)|\(slotID.uuidString)"
    }

    /// Returns the **task** id when ``markerID`` is a floating-reserve marker; otherwise `nil`.
    static func decodeTaskID(_ markerID: String) -> UUID? {
        let parts = markerID.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == prefix else { return nil }
        return UUID(uuidString: parts[1])
    }
}
