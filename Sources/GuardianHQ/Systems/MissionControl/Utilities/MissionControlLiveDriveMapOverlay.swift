import Foundation

/// Builds MC‑R-style live map payloads for **Live Drive** when the selected vehicle is on a live mission roster.
@MainActor
enum MissionControlLiveDriveMapOverlay {

    static func assignmentMatchesLiveFocus(
        _ assignment: MissionRunAssignment,
        mission: Mission,
        focusedTaskID: UUID?
    ) -> Bool {
        LiveLeafletMapMarkerFocus.assignmentMatchesTaskFocus(
            assignment,
            mission: mission,
            taskFocusID: focusedTaskID
        )
    }

    static func taskPathPayload(mission: Mission, focusedTaskID: UUID?) -> (coords: [[RouteCoordinate]], ids: [UUID]) {
        if let tid = focusedTaskID,
           let task = mission.routeMacro.tasks.first(where: { $0.id == tid }) {
            return ([task.waypoints.map(\.coord)], [tid])
        }
        let tasks = mission.routeMacro.tasks
        return (tasks.map { $0.waypoints.map(\.coord) }, tasks.map(\.id))
    }

    static func guardianMissionPointMarkers(
        runtimePoints: [MissionPoint],
        focusedTaskID: UUID?,
        selectedMissionPointID: UUID?
    ) -> [GuardianMissionPointMapMarker] {
        MissionPoint.filteredForMissionControlLiveMap(runtimePoints, focusedTaskID: focusedTaskID).map { mp in
            GuardianMissionPointMapMarker(
                id: mp.id,
                lat: mp.coordinate.lat,
                lon: mp.coordinate.lon,
                mapLabelCompact: mp.mapGlyphDigit,
                mapLabelFull: mp.mapChipLabel,
                kindRaw: mp.kind.rawValue,
                isClosed: mp.isClosed,
                isSelected: selectedMissionPointID == mp.id
            )
        }
    }

    static func routeGeometry(
        mission: Mission,
        run: MissionRunEnvironment,
        focusedTaskID: UUID?,
        selectedMissionPointID: UUID?
    ) -> GuardianRouteMapGeometry {
        let pathPayload = taskPathPayload(mission: mission, focusedTaskID: focusedTaskID)
        return GuardianRouteMapGeometry(
            home: mission.routeMacro.home,
            allTasksCoords: pathPayload.coords,
            taskPathIDs: pathPayload.ids,
            selectedTaskWaypoints: [],
            selectedWaypointIndex: nil,
            headingPreview: nil,
            cameraPreview: nil,
            preserveView: true,
            isEditingTask: false,
            missionPointMarkers: guardianMissionPointMarkers(
                runtimePoints: run.runtimeMissionPoints,
                focusedTaskID: focusedTaskID,
                selectedMissionPointID: selectedMissionPointID
            ),
            missionPointPlacementArmed: false,
            mcsReservePoolHomePlacementArmed: false,
            geofenceOverlays: mission.geofenceGuardianMapOverlaysForMissionControl(
                operatorSettings: run.operatorDisplaySettings,
                mapFocusedTaskID: focusedTaskID,
                respectMapTaskIsolation: true,
                run: run
            ),
            geofenceMapLayerPointerSelectsFence: false
        )
    }

    static func rosterMapMarkerImageDataURL(
        assignment: MissionRunAssignment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        imageCache: LiveLeafletMapMarkerCache = Utilities.liveLeafletMap.markerImageCache
    ) -> String? {
        imageCache.imageDataURL(
            assignment: assignment,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    static func vehicleMarkers(
        run: MissionRunEnvironment,
        mission: Mission,
        focusedTaskID: UUID?,
        ldStreamVehicleID: String,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> [MapVehicleMarker] {
        buildLiveMap(
            run: run,
            mission: mission,
            focusedTaskID: focusedTaskID,
            ldStreamVehicleID: ldStreamVehicleID,
            fleetLink: fleetLink,
            sitl: sitl
        ).markers
    }

    static func buildLiveMap(
        run: MissionRunEnvironment,
        mission: Mission,
        focusedTaskID: UUID?,
        ldStreamVehicleID: String,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> LiveLeafletMapMarkerBuildResult {
        let inputs = LiveLeafletMapMarkerBuildInputs.liveDriveMissionOverlay(
            run: run,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            focusedTaskID: focusedTaskID,
            ldStreamVehicleID: ldStreamVehicleID
        )
        return Utilities.liveLeafletMap.buildMapVehicleMarkersLive(inputs: inputs)
    }
}
