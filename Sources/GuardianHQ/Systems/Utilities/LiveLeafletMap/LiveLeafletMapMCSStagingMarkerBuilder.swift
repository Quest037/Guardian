import Foundation

/// MCS roster staging map markers (roster SITL/live + floating reserve pool) with SIM-drag overlays. Markers use SVG glyphs; ``imageCache`` is reserved for optional thumbnail data URLs.
@MainActor
enum LiveLeafletMapMCSStagingMarkerBuilder {

    static func build(
        inputs: LiveLeafletMapMCSStagingMarkerBuildInputs,
        imageCache: LiveLeafletMapMarkerCache = Utilities.liveLeafletMap.markerImageCache
    ) -> LiveLeafletMapMarkerBuildResult {
        var markers: [MapVehicleMarker] = []
        markers.reserveCapacity(inputs.assignments.count + 8)

        for assignment in inputs.assignments {
            if let marker = buildRosterMarker(assignment: assignment, inputs: inputs, imageCache: imageCache) {
                markers.append(marker)
            }
        }

        for task in inputs.mission.routeMacro.tasks where task.enabled {
            let tid = task.id
            let pool = inputs.reservePoolsByTaskID[tid] ?? MissionRunReservePool()
            for slot in pool.entries {
                if let marker = buildPoolMarker(
                    taskID: tid,
                    taskName: task.name,
                    slot: slot,
                    inputs: inputs,
                    imageCache: imageCache
                ) {
                    markers.append(marker)
                }
            }
        }

        let digest = LiveLeafletMapMCSStagingMarkerMotionDigest.make(from: markers)
        return LiveLeafletMapMarkerBuildResult(
            markers: markers,
            motionDigest: digest,
            motionSamples: []
        )
    }

    // MARK: - Private

    private static func buildRosterMarker(
        assignment: MissionRunAssignment,
        inputs: LiveLeafletMapMCSStagingMarkerBuildInputs,
        imageCache: LiveLeafletMapMarkerCache
    ) -> MapVehicleMarker? {
        guard let tokenKey = assignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: tokenKey)
        else { return nil }

        let selected = assignment.id == inputs.selectedAssignmentID
        let label = assignment.slotName
        let glyphKind = GuardianMapVehicleGlyphKind.forRosterAssignment(assignment, mission: inputs.mission)

        switch token {
        case .sitl(let uuid):
            guard let inst = inputs.sitl.instances.first(where: { $0.id == uuid }) else { return nil }
            let vehicleID = inputs.fleetLink.vehicleID(forSystemID: inst.mavlinkSystemID)
                ?? inst.guardianVehicleStreamKey
            let colorHex = inputs.fleetLink.mapColorHex(forVehicleID: vehicleID)
            if let optimistic = inputs.rosterSimDragByAssignmentID[assignment.id] {
                let heading: Double? = {
                    guard let hub = inputs.fleetLink.hubTelemetry(forVehicleID: vehicleID) else { return nil }
                    return hub.headingDeg ?? hub.yawDeg
                }()
                let hubCoord = hubCoordinate(forAssignment: assignment, inputs: inputs)
                return MapVehicleMarker(
                    id: MapVehicleMarkerIdentity.missionRunAssignment(assignment.id),
                    lat: optimistic.coordinate.lat,
                    lon: optimistic.coordinate.lon,
                    label: "\(label) (SIM)",
                    colorHex: colorHex,
                    glyphKind: glyphKind,
                    imageDataURL: nil,
                    selected: selected,
                    draggable: selected,
                    headingDeg: heading,
                    pendingSimSync: pendingSimSync(optimistic: optimistic, hubCoordinate: hubCoord, now: inputs.now)
                )
            }
            guard let hub = inputs.fleetLink.hubTelemetry(forVehicleID: vehicleID),
                  let lat = hub.latitudeDeg,
                  let lon = hub.longitudeDeg
            else { return nil }
            let heading = hub.headingDeg ?? hub.yawDeg
            return MapVehicleMarker(
                id: MapVehicleMarkerIdentity.missionRunAssignment(assignment.id),
                lat: lat,
                lon: lon,
                label: "\(label) (SIM)",
                colorHex: colorHex,
                glyphKind: glyphKind,
                imageDataURL: nil,
                selected: selected,
                draggable: selected,
                headingDeg: heading
            )
        case .live:
            guard let vehicleID = resolvedFleetStreamVehicleID(
                assignment: assignment,
                fleetLink: inputs.fleetLink,
                sitl: inputs.sitl
            ),
                  let hub = inputs.fleetLink.hubTelemetry(forVehicleID: vehicleID),
                  let lat = hub.latitudeDeg,
                  let lon = hub.longitudeDeg
            else { return nil }
            let heading = hub.headingDeg ?? hub.yawDeg
            return MapVehicleMarker(
                id: MapVehicleMarkerIdentity.missionRunAssignment(assignment.id),
                lat: lat,
                lon: lon,
                label: "\(label) (Live)",
                colorHex: inputs.fleetLink.mapColorHex(forVehicleID: vehicleID),
                glyphKind: glyphKind,
                imageDataURL: nil,
                selected: selected,
                draggable: false,
                headingDeg: heading
            )
        }
    }

    private static func buildPoolMarker(
        taskID: UUID,
        taskName: String,
        slot: MissionRunReservePoolSlot,
        inputs: LiveLeafletMapMCSStagingMarkerBuildInputs,
        imageCache: LiveLeafletMapMarkerCache
    ) -> MapVehicleMarker? {
        guard slot.hasFleetOrLegacyBinding,
              let rawTok = slot.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTok.isEmpty
        else { return nil }

        let markerID = MapVehicleMarkerIdentity.floatingReservePool(taskID: taskID, slotID: slot.id)
        let syn = syntheticAssignment(from: slot)
        guard let vehicleID = resolvedFleetStreamVehicleID(
            assignment: syn,
            fleetLink: inputs.fleetLink,
            sitl: inputs.sitl
        ),
              let hub = inputs.fleetLink.hubTelemetry(forVehicleID: vehicleID),
              let hubLat = hub.latitudeDeg,
              let hubLon = hub.longitudeDeg
        else { return nil }

        let eligible = MCSReservePoolHomeStagingMapEligibility.isEligibleSitlReservePoolSlot(
            slot: slot,
            sitl: inputs.sitl,
            fleetLink: inputs.fleetLink
        )
        let selected = inputs.selectedReservePoolTaskID == taskID && inputs.selectedReservePoolSlotID == slot.id
        let colorHex = inputs.fleetLink.mapColorHex(forVehicleID: vehicleID)
        let heading = hub.headingDeg ?? hub.yawDeg
        let poolGlyphType = inputs.fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType ?? .unknown
        let poolA11y = MissionRunReserveSwapAccessibilityCopy.floatingPoolMapMarker(
            taskName: taskName,
            berthLabel: slot.label,
            swapPickActiveOnTask: false,
            markerIsEligiblePickTarget: false,
            browsingThisBerthOnTask: false
        )

        let lat: Double
        let lon: Double
        let pendingSimSync: Bool
        if let optimistic = inputs.poolSimDragByMarkerID[markerID] {
            lat = optimistic.coordinate.lat
            lon = optimistic.coordinate.lon
            let hubCoord = RouteCoordinate(lat: hubLat, lon: hubLon)
            pendingSimSync = Self.pendingSimSync(
                optimistic: optimistic,
                hubCoordinate: hubCoord,
                now: inputs.now
            )
        } else {
            lat = hubLat
            lon = hubLon
            pendingSimSync = false
        }

        return MapVehicleMarker(
            id: markerID,
            lat: lat,
            lon: lon,
            label: "\(slot.label) · pool",
            colorHex: colorHex,
            glyphKind: GuardianMapVehicleGlyphKind.forFleetVehicleType(poolGlyphType),
            imageDataURL: nil,
            selected: selected,
            draggable: selected && eligible,
            headingDeg: heading,
            pendingSimSync: pendingSimSync,
            accessibilityTitle: poolA11y
        )
    }

    private static func hubCoordinate(
        forAssignment assignment: MissionRunAssignment,
        inputs: LiveLeafletMapMCSStagingMarkerBuildInputs
    ) -> RouteCoordinate? {
        guard let tokenKey = assignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: tokenKey),
              case .sitl(let sitlInstanceID) = token,
              let inst = inputs.sitl.instances.first(where: { $0.id == sitlInstanceID })
        else { return nil }
        let vehicleID = inputs.fleetLink.vehicleID(forSystemID: inst.mavlinkSystemID)
            ?? inst.guardianVehicleStreamKey
        guard let hub = inputs.fleetLink.hubTelemetry(forVehicleID: vehicleID),
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else { return nil }
        return RouteCoordinate(lat: lat, lon: lon)
    }

    private static func pendingSimSync(
        optimistic: MissionRunStagingSimDragOverlay,
        hubCoordinate: RouteCoordinate?,
        now: Date
    ) -> Bool {
        let hubOk = hubCoordinate.map {
            MissionControlSetupSimDragOverlayPolicy.hubMatches(
                pendingCoordinate: optimistic.coordinate,
                hubCoordinate: $0
            )
        } ?? false
        let sustained = MissionControlSetupSimDragOverlayPolicy.isSustainedHubAgreement(
            hubAgreesSince: optimistic.hubAgreesSince,
            now: now
        )
        return !hubOk || !sustained
    }

    private static func syntheticAssignment(from slot: MissionRunReservePoolSlot) -> MissionRunAssignment {
        MissionRunAssignment(
            id: slot.id,
            rosterDeviceId: slot.id,
            slotName: slot.label,
            attachedDevice: slot.attachedDevice,
            attachedFleetVehicleToken: slot.attachedFleetVehicleToken
        )
    }
}
