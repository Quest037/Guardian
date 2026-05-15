import Foundation

/// Shared builder: hub-linked roster + floating reserve pool → ``MapVehicleMarker`` + motion digest.
@MainActor
enum LiveLeafletMapMarkerBuilder {

    /// Builds live map vehicle markers and a motion-only digest. Live roster / pool markers use SVG glyphs (``GuardianMapVehicleGlyphKind``); ``imageCache`` is reserved for callers that still attach ``MapVehicleMarker/imageDataURL``.
    /// Digest uses quantized hub coordinates only.
    static func build(
        inputs: LiveLeafletMapMarkerBuildInputs,
        imageCache: LiveLeafletMapMarkerCache = Utilities.liveLeafletMap.markerImageCache,
        rosterAccessibilityTitle: ((MissionRunAssignment, Mission) -> String?)? = nil
    ) -> LiveLeafletMapMarkerBuildResult {
        var motionSamples: [LiveLeafletMapMarkerMotionSample] = []
        var markers: [MapVehicleMarker] = []

        let rosterRows = inputs.filteredRosterAssignments
        for assignment in rosterRows {
            guard let built = buildRosterMarker(
                assignment: assignment,
                inputs: inputs,
                imageCache: imageCache,
                rosterAccessibilityTitle: rosterAccessibilityTitle
            ) else { continue }
            markers.append(built.marker)
            motionSamples.append(built.motion)
        }

        for tid in inputs.floatingReservePoolScope.taskIDs {
            let pool = inputs.reservePoolsByTaskID[tid] ?? MissionRunReservePool()
            for slot in pool.entries {
                guard let built = buildPoolMarker(
                    taskID: tid,
                    slot: slot,
                    inputs: inputs,
                    imageCache: imageCache
                ) else { continue }
                markers.append(built.marker)
                motionSamples.append(built.motion)
            }
        }

        let digest = LiveLeafletMapMarkerMotionDigest.make(from: motionSamples)
        return LiveLeafletMapMarkerBuildResult(
            markers: markers,
            motionDigest: digest,
            motionSamples: motionSamples
        )
    }

    // MARK: - Private

    private struct BuiltMarker {
        var marker: MapVehicleMarker
        var motion: LiveLeafletMapMarkerMotionSample
    }

    private static func buildRosterMarker(
        assignment: MissionRunAssignment,
        inputs: LiveLeafletMapMarkerBuildInputs,
        imageCache: LiveLeafletMapMarkerCache,
        rosterAccessibilityTitle: ((MissionRunAssignment, Mission) -> String?)?
    ) -> BuiltMarker? {
        guard assignment.attachedFleetVehicleToken != nil,
              let vehicleID = resolvedFleetStreamVehicleID(
                  assignment: assignment,
                  fleetLink: inputs.fleetLink,
                  sitl: inputs.sitl
              ),
              let hub = inputs.fleetLink.hubTelemetry(forVehicleID: vehicleID),
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else { return nil }

        let markerID = MapVehicleMarkerIdentity.missionRunAssignment(assignment.id)
        let heading = hub.headingDeg ?? hub.yawDeg
        let colorHex = inputs.fleetLink.mapColorHex(forVehicleID: vehicleID)
        let highlightID = inputs.presentation.highlightedFleetVehicleID
        let isHighlighted = highlightID.map { vehicleID == $0 } ?? false
        let selected = inputs.presentation.selectedAssignmentID == assignment.id || isHighlighted
        let a11y = rosterAccessibilityTitle?(assignment, inputs.mission)

        let marker = MapVehicleMarker(
            id: markerID,
            lat: lat,
            lon: lon,
            label: assignment.slotName,
            colorHex: colorHex,
            glyphKind: GuardianMapVehicleGlyphKind.forRosterAssignment(assignment, mission: inputs.mission),
            imageDataURL: nil,
            showLabel: isHighlighted && inputs.presentation.highlightShowsLabel,
            selected: selected,
            draggable: false,
            headingDeg: heading,
            accessibilityTitle: a11y
        )
        return BuiltMarker(
            marker: marker,
            motion: LiveLeafletMapMarkerMotionSample(id: markerID, lat: lat, lon: lon, headingDeg: heading)
        )
    }

    private static func buildPoolMarker(
        taskID: UUID,
        slot: MissionRunReservePoolSlot,
        inputs: LiveLeafletMapMarkerBuildInputs,
        imageCache: LiveLeafletMapMarkerCache
    ) -> BuiltMarker? {
        guard slot.hasFleetOrLegacyBinding,
              let rawTok = slot.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTok.isEmpty
        else { return nil }

        let syn = syntheticReservePoolAssignment(from: slot)
        guard let vehicleID = resolvedFleetStreamVehicleID(
            assignment: syn,
            fleetLink: inputs.fleetLink,
            sitl: inputs.sitl
        ),
              let hub = inputs.fleetLink.hubTelemetry(forVehicleID: vehicleID),
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else { return nil }

        let markerID = MapVehicleMarkerIdentity.floatingReservePool(taskID: taskID, slotID: slot.id)
        let heading = hub.headingDeg ?? hub.yawDeg
        let colorHex = inputs.fleetLink.mapColorHex(forVehicleID: vehicleID)
        let pres = inputs.reservePoolPresentation
        let swapPickOnTask = pres.reserveSwapPick?.taskID == taskID
        let markerEligible = pres.reserveSwapPick.map { pick in
            pick.taskID == taskID && pres.eligiblePoolSlotIDsForSwapPick.contains(slot.id)
        } ?? false
        let browsingBerth = pres.browsingPoolBerth.map { $0.taskID == taskID && $0.slotID == slot.id } ?? false
        let selected = markerEligible || browsingBerth
        let taskName = inputs.mission.routeMacro.tasks.first { $0.id == taskID }?.name ?? "Task"
        let poolA11y = MissionRunReserveSwapAccessibilityCopy.floatingPoolMapMarker(
            taskName: taskName,
            berthLabel: slot.label,
            swapPickActiveOnTask: swapPickOnTask,
            markerIsEligiblePickTarget: markerEligible,
            browsingThisBerthOnTask: browsingBerth
        )

        let boundType = inputs.fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType ?? .unknown
        let marker = MapVehicleMarker(
            id: markerID,
            lat: lat,
            lon: lon,
            label: "\(slot.label) · pool",
            colorHex: colorHex,
            glyphKind: GuardianMapVehicleGlyphKind.forFleetVehicleType(boundType),
            imageDataURL: nil,
            showLabel: false,
            selected: selected,
            draggable: false,
            selectionAttentionPulse: selected,
            headingDeg: heading,
            accessibilityTitle: poolA11y
        )
        return BuiltMarker(
            marker: marker,
            motion: LiveLeafletMapMarkerMotionSample(id: markerID, lat: lat, lon: lon, headingDeg: heading)
        )
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
}
