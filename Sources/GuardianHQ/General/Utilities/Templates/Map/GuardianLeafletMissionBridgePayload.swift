import Foundation

/// Equatable snapshot of every argument passed to Leaflet ``setMissionData`` from ``OSMMapView``.
///
/// ``OSMMapView/Coordinator`` compares consecutive payloads and **skips** JSON encoding + bridge enqueue when
/// ``Equatable`` reports no change (including ``vehicleMarkers`` — same pattern as ``GuardianRouteMapGeometry`` on
/// ``GuardianMapModel``).
struct GuardianLeafletMissionBridgePayload: Equatable {
    var home: RouteHome?
    var allTasksCoords: [[RouteCoordinate]]
    var taskPathIDs: [UUID]
    var selectedTaskWaypoints: [RouteWaypoint]
    var selectedWaypointIndex: Int?
    var vehicleMarkers: [MapVehicleMarker]
    var mapStyle: MapTileStyle
    var recenterNonce: Int
    var headingPreview: HeadingPreview?
    var cameraPreview: CameraPreview?
    var followedVehicleMarkerID: String?
    var contextMenuPolicy: GuardianMapContextMenuPolicy
    var preserveView: Bool
    var isEditingTask: Bool
    var missionPointMarkers: [GuardianMissionPointMapMarker]
    var missionPointPlacementArmed: Bool
    var mcsReservePoolHomePlacementArmed: Bool
    var geofenceOverlays: [GuardianGeofenceMapOverlay]
    var geofenceLeafletChrome: GuardianGeofenceLeafletChrome
    var geofenceMapLayerPointerSelectsFence: Bool
    var formationSlotGroupMapEdit: GuardianFormationSlotGroupMapEdit? = nil
    var debugOverlayPolylines: [[RouteCoordinate]] = []
}

extension GuardianMapContextMenuPolicy: Equatable {
    public static func == (lhs: GuardianMapContextMenuPolicy, rhs: GuardianMapContextMenuPolicy) -> Bool {
        lhs.vehicleActions == rhs.vehicleActions
            && lhs.waypointActions == rhs.waypointActions
            && lhs.homeActions == rhs.homeActions
            && lhs.missionPointActions == rhs.missionPointActions
    }
}
