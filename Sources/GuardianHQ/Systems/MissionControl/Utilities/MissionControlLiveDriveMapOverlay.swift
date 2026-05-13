import AppKit
import Foundation

/// Builds MC‑R-style live map payloads for **Live Drive** when the selected vehicle is on a live mission roster.
@MainActor
enum MissionControlLiveDriveMapOverlay {

    static func assignmentMatchesLiveFocus(
        _ assignment: MissionRunAssignment,
        mission: Mission,
        focusedTaskID: UUID?
    ) -> Bool {
        guard let focus = focusedTaskID else { return true }
        if assignment.taskId == focus { return true }
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        if enabled.count == 1, enabled.first?.id == focus {
            return assignment.taskId == nil || assignment.taskId == focus
        }
        return false
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
            mcsReservePoolHomePlacementArmed: false
        )
    }

    static func rosterMapMarkerImageDataURL(
        assignment: MissionRunAssignment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> String? {
        let basenames: [String] = {
            if let sim = simulationImageBasenamesForAssignment(assignment, sitl: sitl), !sim.isEmpty {
                return sim
            }
            let device = mission.rosterDevices.first { $0.id == assignment.rosterDeviceId }
            let rosterDeviceClass = device?.vehicleClass ?? .unknown
            if let vid = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
               let model = fleetLink.vehicleModel(forVehicleID: vid) {
                return model.data.vehicleType.defaultSimulationDeviceImageBasenames
            }
            return rosterDeviceClass.defaultSimulationDeviceImageBasenames
        }()
        guard let image = SimulationDeviceBundleImage.nsImage(firstMatching: basenames),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }

    private static func syntheticReservePoolAssignment(from slot: MissionRunReservePoolSlot) -> MissionRunAssignment {
        MissionRunAssignment(
            id: slot.id,
            rosterDeviceId: slot.id,
            slotName: slot.label,
            attachedDevice: slot.attachedDevice,
            attachedFleetVehicleToken: slot.attachedFleetVehicleToken
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
        let roster = run.assignments
            .filter { assignmentMatchesLiveFocus($0, mission: mission, focusedTaskID: focusedTaskID) }
            .compactMap { assignment -> MapVehicleMarker? in
                guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
                      let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                      let lat = hub.latitudeDeg,
                      let lon = hub.longitudeDeg,
                      assignment.attachedFleetVehicleToken != nil
                else { return nil }
                let colorHex = fleetLink.mapColorHex(forVehicleID: vehicleID)
                let heading = hub.headingDeg ?? hub.yawDeg
                let isLdTarget = vehicleID == ldStreamVehicleID
                return MapVehicleMarker(
                    id: assignment.id.uuidString,
                    lat: lat,
                    lon: lon,
                    label: assignment.slotName,
                    colorHex: colorHex,
                    imageDataURL: rosterMapMarkerImageDataURL(
                        assignment: assignment,
                        mission: mission,
                        fleetLink: fleetLink,
                        sitl: sitl
                    ),
                    showLabel: isLdTarget,
                    selected: isLdTarget,
                    draggable: false,
                    headingDeg: heading,
                    accessibilityTitle: nil
                )
            }

        let taskIDs: [UUID] = {
            if let f = focusedTaskID { return [f] }
            return mission.routeMacro.tasks.filter(\.enabled).map(\.id)
        }()

        var pool: [MapVehicleMarker] = []
        for tid in taskIDs {
            let slots = run.reservePool(forTaskID: tid).entries
            for slot in slots {
                guard slot.hasFleetOrLegacyBinding,
                      let rawTok = slot.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !rawTok.isEmpty
                else { continue }
                let syn = syntheticReservePoolAssignment(from: slot)
                guard let vehicleID = resolvedFleetStreamVehicleID(assignment: syn, fleetLink: fleetLink, sitl: sitl),
                      let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                      let lat = hub.latitudeDeg,
                      let lon = hub.longitudeDeg
                else { continue }
                let colorHex = fleetLink.mapColorHex(forVehicleID: vehicleID)
                let heading = hub.headingDeg ?? hub.yawDeg
                pool.append(
                    MapVehicleMarker(
                        id: MissionControlReservePoolMapMarkerID.encode(taskID: tid, slotID: slot.id),
                        lat: lat,
                        lon: lon,
                        label: "\(slot.label) · pool",
                        colorHex: colorHex,
                        imageDataURL: rosterMapMarkerImageDataURL(
                            assignment: syn,
                            mission: mission,
                            fleetLink: fleetLink,
                            sitl: sitl
                        ),
                        showLabel: false,
                        selected: false,
                        draggable: false,
                        headingDeg: heading,
                        accessibilityTitle: nil
                    )
                )
            }
        }

        return roster + pool
    }
}
