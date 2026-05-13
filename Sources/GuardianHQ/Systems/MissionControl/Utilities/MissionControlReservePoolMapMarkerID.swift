import Foundation

/// Stable `MapVehicleMarker.id` values for MC-R **floating reserve pool** aircraft (not roster ``MissionRunAssignment`` ids).
enum MissionControlReservePoolMapMarkerID {
    static let prefix = "frp"

    /// Encodes task + pool slot so the live map tap handler can open the correct **reserve pool berth** triage.
    static func encode(taskID: UUID, slotID: UUID) -> String {
        "\(prefix)|\(taskID.uuidString)|\(slotID.uuidString)"
    }

    /// Returns **task** and **pool berth** ids when ``markerID`` is a floating-reserve marker; otherwise `nil`.
    static func decodeBerth(_ markerID: String) -> (taskID: UUID, slotID: UUID)? {
        let parts = markerID.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == prefix,
              let taskID = UUID(uuidString: parts[1]),
              let slotID = UUID(uuidString: parts[2])
        else { return nil }
        return (taskID, slotID)
    }

    /// Returns the **task** id when ``markerID`` is a floating-reserve marker; otherwise `nil`.
    static func decodeTaskID(_ markerID: String) -> UUID? {
        decodeBerth(markerID)?.taskID
    }
}
