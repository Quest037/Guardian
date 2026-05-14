import Foundation

/// MAVLink constants and helpers for mapping ``MissionGeofence`` **authoring** altitude references
/// to ``MAV_FRAME`` / vertex `z` when building or replaying raw `MAV_MISSION_TYPE_FENCE` items **outside**
/// Guardian’s fleet `geofencePolygonsJSON` wire (that JSON carries horizontal geometry only).
///
/// **MAVSDK Geofence plugin:** The bundled server’s Geofence upload path still assembles fence mission items with
/// `MAV_FRAME_GLOBAL_INT` and **z = 0** on every vertex (see upstream `geofence_impl.cpp` `assemble_items`).
/// PX4 persists MISSION_ITEM `z` into `mission_fence_point.alt` when fence items are received via the mission
/// protocol; ArduPilot’s fence mission item encoder sets polygon vertex **z = 0** and does not use vertex z for
/// polygon inclusion.
enum MissionGeofenceFenceMavlinkAltitude: Sendable {
    /// `MAV_FRAME_GLOBAL_INT` — global lat/lon, altitude AMSL (metres).
    static let mavFrameGlobalInt: UInt32 = 5
    /// `MAV_FRAME_GLOBAL_TERRAIN_ALT_INT` — global lat/lon, altitude **above terrain** (metres).
    static let mavFrameGlobalTerrainAltInt: UInt32 = 10
    /// `MAV_FRAME_GLOBAL_RELATIVE_ALT_INT` — global lat/lon, altitude relative to **home** (metres).
    static let mavFrameGlobalRelativeAltInt: UInt32 = 11

    /// MAVLink `MAV_FRAME` value for fence ``MISSION_ITEM_INT`` / ``MissionRaw.MissionItem`` `frame` when
    /// interpreting ``MissionGeofenceAltitudeReference`` for PX4-style global frames.
    static func mavlinkFrameUInt32(for reference: MissionGeofenceAltitudeReference) -> UInt32 {
        switch reference {
        case .relativeHome:
            return mavFrameGlobalRelativeAltInt
        case .agl:
            return mavFrameGlobalTerrainAltInt
        case .msl:
            return mavFrameGlobalInt
        }
    }

    /// Recommended `z` (param7 / ``MissionRaw.MissionItem`` `z`) for each polygon vertex when replaying fence
    /// items as `MAV_CMD_NAV_FENCE_POLYGON_VERTEX_*`: use the **upper** bound of the envelope so relative/MSL
    /// ceilings match operator intent; the lower bound is ``MissionGeofence/minAltitudeMeters`` on the fence model.
    static func recommendedVertexAltitudeZMeters(for fence: MissionGeofence) -> Double {
        max(fence.minAltitudeMeters, fence.maxAltitudeMeters)
    }
}
