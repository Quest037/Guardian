import Foundation

extension GuardianLeafletMissionBridgePayload {
    /// Builds the `setMissionData(...)` JavaScript call for ``OSMMapView``.
    nonisolated func javascriptExpression() -> String {
        OSMMapView.javascriptExpression(for: self)
    }
}

extension OSMMapView {
    nonisolated static func javascriptExpression(for payload: GuardianLeafletMissionBridgePayload) -> String {
        let homeJSON: String
        if let home = payload.home {
            homeJSON = "{\"lat\":\(home.coord.lat),\"lon\":\(home.coord.lon)}"
        } else {
            homeJSON = "null"
        }

        let allPathsJSON = payload.allTasksCoords.map { path in
            "[\(path.map { "{\"lat\":\($0.lat),\"lon\":\($0.lon)}" }.joined(separator: ","))]"
        }.joined(separator: ",")
        let taskPathIDsJSON: String
        if payload.taskPathIDs.count == payload.allTasksCoords.count, !payload.allTasksCoords.isEmpty {
            taskPathIDsJSON = "[\(payload.taskPathIDs.map { jsStringLiteral($0.uuidString) }.joined(separator: ","))]"
        } else {
            taskPathIDsJSON = "null"
        }
        let waypointsJSON = payload.selectedTaskWaypoints.enumerated().map { idx, wp in
            let anchorJSON = wp.pathRole == .anchor ? "true" : "false"
            return "{\"idx\":\(idx),\"lat\":\(wp.coord.lat),\"lon\":\(wp.coord.lon),\"anchor\":\(anchorJSON)}"
        }.joined(separator: ",")
        let selectedWaypointIndexJS = payload.selectedWaypointIndex.map(String.init) ?? "null"
        let vehicleMarkersJSON = payload.vehicleMarkers.map { marker in
            let headingJSON: String
            if let h = marker.headingDeg {
                headingJSON = "\"heading\":\(h)"
            } else {
                headingJSON = "\"heading\":null"
            }
            let imageJSON = marker.imageDataURL.map(jsStringLiteral) ?? "null"
            let accessibilityTitleJSON = marker.accessibilityTitle.map(jsStringLiteral) ?? "null"
            let glyphJSON = jsStringLiteral(marker.glyphKind.rawValue)
            return "{\"id\":\(jsStringLiteral(marker.id)),\"lat\":\(marker.lat),\"lon\":\(marker.lon),\"label\":\(jsStringLiteral(marker.label)),\"color\":\(jsStringLiteral(marker.colorHex)),\"glyph\":\(glyphJSON),\"image\":\(imageJSON),\"showLabel\":\(marker.showLabel ? "true" : "false"),\"selected\":\(marker.selected ? "true" : "false"),\"draggable\":\(marker.draggable ? "true" : "false"),\"pendingSimSync\":\(marker.pendingSimSync ? "true" : "false"),\"selectionAttentionPulse\":\(marker.selectionAttentionPulse ? "true" : "false"),\"accessibilityTitle\":\(accessibilityTitleJSON),\(headingJSON)}"
        }.joined(separator: ",")
        let headingPreviewJSON: String
        if let headingPreview = payload.headingPreview {
            headingPreviewJSON = "{\"lat\":\(headingPreview.lat),\"lon\":\(headingPreview.lon),\"heading\":\(headingPreview.heading)}"
        } else {
            headingPreviewJSON = "null"
        }
        let cameraPreviewJSON: String
        if let cameraPreview = payload.cameraPreview {
            cameraPreviewJSON = "{\"lat\":\(cameraPreview.lat),\"lon\":\(cameraPreview.lon),\"bearing\":\(cameraPreview.bearing),\"fovDeg\":\(cameraPreview.fovDeg)}"
        } else {
            cameraPreviewJSON = "null"
        }
        let followedVehicleMarkerIDJSON = payload.followedVehicleMarkerID.map(jsStringLiteral) ?? "null"
        let missionPointsJSON = payload.missionPointMarkers.map { m in
            "{\"id\":\(jsStringLiteral(m.id.uuidString)),\"lat\":\(m.lat),\"lon\":\(m.lon),\"chipCompact\":\(jsStringLiteral(m.mapLabelCompact)),\"chipFull\":\(jsStringLiteral(m.mapLabelFull)),\"kind\":\(jsStringLiteral(m.kindRaw)),\"closed\":\(m.isClosed ? "true" : "false"),\"selected\":\(m.isSelected ? "true" : "false")}"
        }.joined(separator: ",")
        let contextMenuPolicyJSON = """
        {"vehicleActions":[\(payload.contextMenuPolicy.vehicleActions.map { jsStringLiteral($0.rawValue) }.joined(separator: ","))],"waypointActions":[\(payload.contextMenuPolicy.waypointActions.map { jsStringLiteral($0.rawValue) }.joined(separator: ","))],"homeActions":[\(payload.contextMenuPolicy.homeActions.map { jsStringLiteral($0.rawValue) }.joined(separator: ","))],"missionPointActions":[\(payload.contextMenuPolicy.missionPointActions.map { jsStringLiteral($0.rawValue) }.joined(separator: ","))]}
        """
        let mcsPoolHomeArmedJS = payload.mcsReservePoolHomePlacementArmed ? "true" : "false"
        let geofencesJSON = payload.geofenceOverlays.map { g in
            let polyInner = g.polygonLatLons.map { "{\"lat\":\($0.0),\"lon\":\($0.1)}" }.joined(separator: ",")
            let cirLat: String
            if let v = g.circleLat { cirLat = String(v) } else { cirLat = "null" }
            let cirLon: String
            if let v = g.circleLon { cirLon = String(v) } else { cirLon = "null" }
            let cirR: String
            if let v = g.circleRadiusM { cirR = String(v) } else { cirR = "null" }
            let boundary = g.isInclusion ? "inclusion" : "exclusion"
            let shape = g.isPolygon ? "polygon" : "circle"
            let sel = g.isAuthoringMapSelected ? "true" : "false"
            return "{\"id\":\(jsStringLiteral(g.id.uuidString)),\"boundary\":\(jsStringLiteral(boundary)),\"shape\":\(jsStringLiteral(shape)),\"polygon\":[\(polyInner)],\"circleLat\":\(cirLat),\"circleLon\":\(cirLon),\"circleRadiusM\":\(cirR),\"selected\":\(sel)}"
        }.joined(separator: ",")
        let geofenceChromeJSON = payload.geofenceLeafletChrome.jsonObjectFragmentEscapedForJS()
        let geofencePtrSelJS = payload.geofenceMapLayerPointerSelectsFence ? "true" : "false"
        return "setMissionData(\(homeJSON), [\(allPathsJSON)], \(taskPathIDsJSON), [\(waypointsJSON)], \(selectedWaypointIndexJS), [\(vehicleMarkersJSON)], \"\(payload.mapStyle.rawValue)\", \(payload.recenterNonce), \(headingPreviewJSON), \(cameraPreviewJSON), \(followedVehicleMarkerIDJSON), \(contextMenuPolicyJSON), \(payload.preserveView ? "true" : "false"), \(payload.isEditingTask ? "true" : "false"), \(payload.missionPointPlacementArmed ? "true" : "false"), \(mcsPoolHomeArmedJS), [\(missionPointsJSON)], [\(geofencesJSON)], \(geofenceChromeJSON), \(geofencePtrSelJS));"
    }
}
