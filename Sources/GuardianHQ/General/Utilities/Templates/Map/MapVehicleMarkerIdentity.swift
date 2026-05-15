import Foundation

/// Stable ``MapVehicleMarker/id`` values for Leaflet marker reconciliation (``vehicleMarkerById`` in ``OSMMapView``).
///
/// **Contract**
/// - **Mission roster slot:** ``missionRunAssignment(_:)`` — ``MissionRunAssignment/id`` for the bound slot row.
///   Stable across hub motion and reserve swap until the assignment row is replaced.
/// - **Floating reserve pool berth:** ``floatingReservePool(taskID:slotID:)`` — encoded via ``MissionControlReservePoolMapMarkerID``
///   (`frp|<taskUUID>|<slotUUID>`). Tap handlers decode berth context from this id.
/// - **Live Drive freestyle:** ``fleetHubVehicle(_:)`` — fleet hub stream vehicle id when not in a mission overlay.
/// - **Settings SIM spawn editor:** ``simSpawnDraft`` — static draft marker on the spawn map (not hub-driven).
///
/// Do **not** use fleet tokens, SITL instance ids, or bridge stream handles as marker ids — they change on swap/rebind
/// and force full layer tear-down in JS.
enum MapVehicleMarkerIdentity {
    static func missionRunAssignment(_ assignmentID: UUID) -> String {
        assignmentID.uuidString
    }

    static func floatingReservePool(taskID: UUID, slotID: UUID) -> String {
        MissionControlReservePoolMapMarkerID.encode(taskID: taskID, slotID: slotID)
    }

    static func fleetHubVehicle(_ vehicleID: String) -> String {
        vehicleID
    }

    static let simSpawnDraft = "sim-spawn-default"
}
