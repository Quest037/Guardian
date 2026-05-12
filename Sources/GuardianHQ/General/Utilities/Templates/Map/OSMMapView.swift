import AppKit
import Foundation
import SwiftUI
import WebKit

/// SwiftUI sizes the **root** ``NSView`` of an ``NSViewRepresentable``; hosting ``WKWebView`` as a direct
/// root can leave its layout/hit rect out of sync with that proposal on dense ``GeometryReader`` stacks
/// (e.g. Mission Control live console). Pinning the web view to ``bounds`` in ``layout()`` matches AppKit
/// hit testing to what SwiftUI painted.
final class GuardianLeafletMapHostingView: NSView {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        addSubview(webView)
    }

    required init?(coder: NSCoder) {
        fatalError("GuardianLeafletMapHostingView is not instantiated from a nib")
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }
}

enum MapTileStyle: String, CaseIterable, Identifiable, Codable {
    case standard
    case satellite
    var id: String { rawValue }
}

struct HeadingPreview: Equatable {
    var lat: Double
    var lon: Double
    var heading: Double
}

struct CameraPreview: Equatable {
    var lat: Double
    var lon: Double
    var bearing: Double
    var fovDeg: Double
}

struct MapVehicleMarker: Equatable {
    var id: String
    var lat: Double
    var lon: Double
    var label: String
    var colorHex: String
    /// Optional embedded thumbnail (data URL) rendered inside the circular marker.
    var imageDataURL: String? = nil
    /// Whether to render the marker label as a tooltip.
    var showLabel: Bool = true
    var selected: Bool
    var draggable: Bool
    /// When set, a small heading wedge is drawn at this marker (degrees clockwise from north).
    var headingDeg: Double? = nil
    /// Roster / staging: show a sync spinner while SIM pose is applied and telemetry is catching up.
    var pendingSimSync: Bool = false
}

struct OSMMapView: NSViewRepresentable {
    var home: RouteHome?
    var allTasksCoords: [[RouteCoordinate]]
    var taskPathIDs: [UUID]
    var selectedTaskWaypoints: [RouteWaypoint]
    var selectedWaypointIndex: Int?
    var vehicleMarkers: [MapVehicleMarker]
    var mapStyle: MapTileStyle
    var recenterNonce: Int
    var viewportNudge: GuardianMapViewportNudge?
    var headingPreview: HeadingPreview?
    var cameraPreview: CameraPreview?
    var followedVehicleMarkerID: String?
    var preserveView: Bool
    var isEditingTask: Bool
    var missionPointMarkers: [GuardianMissionPointMapMarker] = []
    var missionPointPlacementArmed: Bool = false
    var contextMenuPolicy: GuardianMapContextMenuPolicy
    var onMapClick: (Double, Double) -> Void
    var onVehicleMarkerMoved: (String, Double, Double) -> Void
    var onContextAction: (GuardianMapContextActionEvent) -> Void
    var onWaypointClick: (Int) -> Void
    var onWaypointMoved: (Int, Double, Double) -> Void
    var onWaypointDelete: (Int) -> Void
    var onTaskMapInsert: (Int, Double, Double) -> Void
    var onMissionPointClick: (UUID) -> Void = { _ in }
    var onMissionPointMoved: (UUID, Double, Double) -> Void = { _, _, _ in }
    var onMissionPointDoubleClick: (UUID) -> Void = { _ in }
    var onVehicleTap: (GuardianMapVehiclePointerEvent) -> Void = { _ in }
    var onVehicleDoubleTap: (GuardianMapVehiclePointerEvent) -> Void = { _ in }
    var onTaskPathTap: (GuardianMapTaskPathPointerEvent) -> Void = { _ in }
    var onTaskPathDoubleTap: (GuardianMapTaskPathPointerEvent) -> Void = { _ in }
    var onHomeTap: (GuardianMapHomePointerEvent) -> Void = { _ in }
    var onHomeDoubleTap: (GuardianMapHomePointerEvent) -> Void = { _ in }
    var onViewportCenterChanged: (Double, Double) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMapClick: onMapClick,
            onVehicleMarkerMoved: onVehicleMarkerMoved,
            onContextAction: onContextAction,
            onWaypointClick: onWaypointClick,
            onWaypointMoved: onWaypointMoved,
            onWaypointDelete: onWaypointDelete,
            onTaskMapInsert: onTaskMapInsert,
            onMissionPointClick: onMissionPointClick,
            onMissionPointMoved: onMissionPointMoved,
            onMissionPointDoubleClick: onMissionPointDoubleClick,
            onVehicleTap: onVehicleTap,
            onVehicleDoubleTap: onVehicleDoubleTap,
            onTaskPathTap: onTaskPathTap,
            onTaskPathDoubleTap: onTaskPathDoubleTap,
            onHomeTap: onHomeTap,
            onHomeDoubleTap: onHomeDoubleTap,
            onViewportCenterChanged: onViewportCenterChanged
        )
    }

    func makeNSView(context: Context) -> GuardianLeafletMapHostingView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "mapClick")
        controller.add(context.coordinator, name: "vehicleMove")
        controller.add(context.coordinator, name: "vehicleClick")
        controller.add(context.coordinator, name: "vehicleDoubleClick")
        controller.add(context.coordinator, name: "waypointClick")
        controller.add(context.coordinator, name: "waypointMove")
        controller.add(context.coordinator, name: "waypointDelete")
        controller.add(context.coordinator, name: "routeInsert")
        controller.add(context.coordinator, name: "markerContextAction")
        controller.add(context.coordinator, name: "missionPointClick")
        controller.add(context.coordinator, name: "missionPointDoubleClick")
        controller.add(context.coordinator, name: "missionPointMove")
        controller.add(context.coordinator, name: "taskPathClick")
        controller.add(context.coordinator, name: "taskPathDoubleClick")
        controller.add(context.coordinator, name: "homeClick")
        controller.add(context.coordinator, name: "homeDoubleClick")
        controller.add(context.coordinator, name: "mapViewportCenter")

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        // Sandboxed macOS apps: default persistent store + nil baseURL can trigger noisy WebContent / pasteboard XPC failures.
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.setValue(false, forKey: "drawsBackground")
        let mapPageBase = URL(string: "about:blank")!
        webView.loadHTMLString(Self.html, baseURL: mapPageBase)
        return GuardianLeafletMapHostingView(webView: webView)
    }

    func updateNSView(_ hostingView: GuardianLeafletMapHostingView, context: Context) {
        let webView = hostingView.webView
        let c = context.coordinator
        c.webView = webView
        c.onMapClick = onMapClick
        c.onVehicleMarkerMoved = onVehicleMarkerMoved
        c.onContextAction = onContextAction
        c.onWaypointClick = onWaypointClick
        c.onWaypointMoved = onWaypointMoved
        c.onWaypointDelete = onWaypointDelete
        c.onTaskMapInsert = onTaskMapInsert
        c.onMissionPointClick = onMissionPointClick
        c.onMissionPointMoved = onMissionPointMoved
        c.onMissionPointDoubleClick = onMissionPointDoubleClick
        c.onViewportCenterChanged = onViewportCenterChanged
        c.onVehicleTap = onVehicleTap
        c.onVehicleDoubleTap = onVehicleDoubleTap
        c.onTaskPathTap = onTaskPathTap
        c.onTaskPathDoubleTap = onTaskPathDoubleTap
        c.onHomeTap = onHomeTap
        c.onHomeDoubleTap = onHomeDoubleTap
        let homeJSON: String
        if let home {
            homeJSON = "{\"lat\":\(home.coord.lat),\"lon\":\(home.coord.lon)}"
        } else {
            homeJSON = "null"
        }

        let allPathsJSON = allTasksCoords.map { path in
            "[\(path.map { "{\"lat\":\($0.lat),\"lon\":\($0.lon)}" }.joined(separator: ","))]"
        }.joined(separator: ",")
        let taskPathIDsJSON: String
        if taskPathIDs.count == allTasksCoords.count, !allTasksCoords.isEmpty {
            taskPathIDsJSON = "[\(taskPathIDs.map { Self.jsStringLiteral($0.uuidString) }.joined(separator: ","))]"
        } else {
            taskPathIDsJSON = "null"
        }
        let waypointsJSON = selectedTaskWaypoints.enumerated().map { idx, wp in
            let anchorJSON = wp.pathRole == .anchor ? "true" : "false"
            return "{\"idx\":\(idx),\"lat\":\(wp.coord.lat),\"lon\":\(wp.coord.lon),\"anchor\":\(anchorJSON)}"
        }.joined(separator: ",")
        let selectedWaypointIndexJS = selectedWaypointIndex.map(String.init) ?? "null"
        let vehicleMarkersJSON = vehicleMarkers.map { marker in
            let headingJSON: String
            if let h = marker.headingDeg {
                headingJSON = "\"heading\":\(h)"
            } else {
                headingJSON = "\"heading\":null"
            }
            let imageJSON = marker.imageDataURL.map(Self.jsStringLiteral) ?? "null"
            return "{\"id\":\(Self.jsStringLiteral(marker.id)),\"lat\":\(marker.lat),\"lon\":\(marker.lon),\"label\":\(Self.jsStringLiteral(marker.label)),\"color\":\(Self.jsStringLiteral(marker.colorHex)),\"image\":\(imageJSON),\"showLabel\":\(marker.showLabel ? "true" : "false"),\"selected\":\(marker.selected ? "true" : "false"),\"draggable\":\(marker.draggable ? "true" : "false"),\"pendingSimSync\":\(marker.pendingSimSync ? "true" : "false"),\(headingJSON)}"
        }.joined(separator: ",")
        let headingPreviewJSON: String
        if let headingPreview {
            headingPreviewJSON = "{\"lat\":\(headingPreview.lat),\"lon\":\(headingPreview.lon),\"heading\":\(headingPreview.heading)}"
        } else {
            headingPreviewJSON = "null"
        }
        let cameraPreviewJSON: String
        if let cameraPreview {
            cameraPreviewJSON = "{\"lat\":\(cameraPreview.lat),\"lon\":\(cameraPreview.lon),\"bearing\":\(cameraPreview.bearing),\"fovDeg\":\(cameraPreview.fovDeg)}"
        } else {
            cameraPreviewJSON = "null"
        }
        let followedVehicleMarkerIDJSON = followedVehicleMarkerID.map(Self.jsStringLiteral) ?? "null"
        let missionPointsJSON = missionPointMarkers.map { m in
            "{\"id\":\(Self.jsStringLiteral(m.id.uuidString)),\"lat\":\(m.lat),\"lon\":\(m.lon),\"chipCompact\":\(Self.jsStringLiteral(m.mapLabelCompact)),\"chipFull\":\(Self.jsStringLiteral(m.mapLabelFull)),\"kind\":\(Self.jsStringLiteral(m.kindRaw)),\"closed\":\(m.isClosed ? "true" : "false"),\"selected\":\(m.isSelected ? "true" : "false")}"
        }.joined(separator: ",")
        let contextMenuPolicyJSON = """
        {"vehicleActions":[\(contextMenuPolicy.vehicleActions.map { Self.jsStringLiteral($0.rawValue) }.joined(separator: ","))],"waypointActions":[\(contextMenuPolicy.waypointActions.map { Self.jsStringLiteral($0.rawValue) }.joined(separator: ","))],"homeActions":[\(contextMenuPolicy.homeActions.map { Self.jsStringLiteral($0.rawValue) }.joined(separator: ","))],"missionPointActions":[\(contextMenuPolicy.missionPointActions.map { Self.jsStringLiteral($0.rawValue) }.joined(separator: ","))]}
        """
        let js = "setMissionData(\(homeJSON), [\(allPathsJSON)], \(taskPathIDsJSON), [\(waypointsJSON)], \(selectedWaypointIndexJS), [\(vehicleMarkersJSON)], \"\(mapStyle.rawValue)\", \(recenterNonce), \(headingPreviewJSON), \(cameraPreviewJSON), \(followedVehicleMarkerIDJSON), \(contextMenuPolicyJSON), \(preserveView ? "true" : "false"), \(isEditingTask ? "true" : "false"), \(missionPointPlacementArmed ? "true" : "false"), [\(missionPointsJSON)]);"
        context.coordinator.queueMissionUpdate(script: js)
        context.coordinator.applyViewportNudge(viewportNudge, webView: webView)
    }

    /// Leaflet bridge for ``GuardianMapViewportNudge`` (numeric literals only).
    static func javascriptExpression(for nudge: GuardianMapViewportNudge) -> String {
        switch nudge.kind {
        case let .panRetainZoom(lat, lon):
            return "guardianPanToRetainZoom(\(lat),\(lon));"
        case let .fitBounds(points):
            let inner = points.map { "[\($0.0),\($0.1)]" }.joined(separator: ",")
            return "guardianFitBoundsForPoints([\(inner)]);"
        }
    }
}

extension OSMMapView {
    /// Decodes numeric values from ``WKScriptMessage`` bodies (often ``NSNumber``, not native `Double` / `Int`).
    enum WKScriptPayloadBridge {
        static func double(_ any: Any?) -> Double? {
            switch any {
            case let d as Double: return d
            case let f as Float: return Double(f)
            case let n as NSNumber: return n.doubleValue
            case let i as Int: return Double(i)
            default: return nil
            }
        }

        static func int(_ any: Any?) -> Int? {
            switch any {
            case let i as Int: return i
            case let n as NSNumber: return n.intValue
            default: return nil
            }
        }

        /// WebKit often bridges JSON string values as `String`, but nested dictionaries can surface
        /// `NSString` / tagged values that fail a plain `as? String` cast.
        static func optionalString(_ any: Any?) -> String? {
            switch any {
            case nil, is NSNull:
                return nil
            case let s as String:
                return s
            default:
                if let s = any as? NSString {
                    return s as String
                }
                return nil
            }
        }
    }
}

private extension OSMMapView {
    static func jsStringLiteral(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        return "\"\(escaped)\""
    }
}

extension OSMMapView {
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var pendingScript: String?
        private var didFinishInitialLoad = false
        /// Latest mission script from ``updateNSView`` (may arrive in a burst when several
        /// ``GuardianMapModel`` fields publish in the same tick).
        private var latestMissionScript: String?
        private var coalescedMissionWorkItem: DispatchWorkItem?
        /// Last script we successfully pushed to JS (skip duplicate evals).
        private var lastAppliedMissionScript: String?
        private var pendingViewportNudge: GuardianMapViewportNudge?
        private var lastAppliedViewportNudgeSequence: UInt64?
        /// After a layer-specific bridge message (vehicle, mission point, task path, …), Leaflet can still
        /// deliver a **map** `click` in the same gesture on some stacks. That posts `mapClick` → Swift clears
        /// MC-R focus/selection (same failure mode as task-path triage before `L.DomEvent.stop` on polylines).
        /// Ignore background `mapClick` for a few ms after any of those messages so marker/path taps “stick”.
        private var suppressBackgroundMapClickUntil: CFAbsoluteTime = 0

        /// Refreshed from ``OSMMapView/updateNSView`` every pass so WKWebView callbacks always hit the **current** SwiftUI closures (``State`` / ``Binding`` / parent actions). Do not leave these frozen from ``init`` only — stale handlers break mission-point drag, waypoint edits, and map taps after the first frame.
        var onMapClick: (Double, Double) -> Void
        var onVehicleMarkerMoved: (String, Double, Double) -> Void
        var onContextAction: (GuardianMapContextActionEvent) -> Void
        var onWaypointClick: (Int) -> Void
        var onWaypointMoved: (Int, Double, Double) -> Void
        var onWaypointDelete: (Int) -> Void
        var onTaskMapInsert: (Int, Double, Double) -> Void
        var onMissionPointClick: (UUID) -> Void
        var onMissionPointMoved: (UUID, Double, Double) -> Void
        var onViewportCenterChanged: (Double, Double) -> Void
        var onMissionPointDoubleClick: (UUID) -> Void
        var onVehicleTap: (GuardianMapVehiclePointerEvent) -> Void
        var onVehicleDoubleTap: (GuardianMapVehiclePointerEvent) -> Void
        var onTaskPathTap: (GuardianMapTaskPathPointerEvent) -> Void
        var onTaskPathDoubleTap: (GuardianMapTaskPathPointerEvent) -> Void
        var onHomeTap: (GuardianMapHomePointerEvent) -> Void
        var onHomeDoubleTap: (GuardianMapHomePointerEvent) -> Void

        init(
            onMapClick: @escaping (Double, Double) -> Void,
            onVehicleMarkerMoved: @escaping (String, Double, Double) -> Void,
            onContextAction: @escaping (GuardianMapContextActionEvent) -> Void,
            onWaypointClick: @escaping (Int) -> Void,
            onWaypointMoved: @escaping (Int, Double, Double) -> Void,
            onWaypointDelete: @escaping (Int) -> Void,
            onTaskMapInsert: @escaping (Int, Double, Double) -> Void,
            onMissionPointClick: @escaping (UUID) -> Void,
            onMissionPointMoved: @escaping (UUID, Double, Double) -> Void,
            onMissionPointDoubleClick: @escaping (UUID) -> Void,
            onVehicleTap: @escaping (GuardianMapVehiclePointerEvent) -> Void,
            onVehicleDoubleTap: @escaping (GuardianMapVehiclePointerEvent) -> Void,
            onTaskPathTap: @escaping (GuardianMapTaskPathPointerEvent) -> Void,
            onTaskPathDoubleTap: @escaping (GuardianMapTaskPathPointerEvent) -> Void,
            onHomeTap: @escaping (GuardianMapHomePointerEvent) -> Void,
            onHomeDoubleTap: @escaping (GuardianMapHomePointerEvent) -> Void,
            onViewportCenterChanged: @escaping (Double, Double) -> Void
        ) {
            self.onMapClick = onMapClick
            self.onVehicleMarkerMoved = onVehicleMarkerMoved
            self.onContextAction = onContextAction
            self.onWaypointClick = onWaypointClick
            self.onWaypointMoved = onWaypointMoved
            self.onWaypointDelete = onWaypointDelete
            self.onTaskMapInsert = onTaskMapInsert
            self.onMissionPointClick = onMissionPointClick
            self.onMissionPointMoved = onMissionPointMoved
            self.onMissionPointDoubleClick = onMissionPointDoubleClick
            self.onVehicleTap = onVehicleTap
            self.onVehicleDoubleTap = onVehicleDoubleTap
            self.onTaskPathTap = onTaskPathTap
            self.onTaskPathDoubleTap = onTaskPathDoubleTap
            self.onHomeTap = onHomeTap
            self.onHomeDoubleTap = onHomeDoubleTap
            self.onViewportCenterChanged = onViewportCenterChanged
        }

        private func noteLayerPointerDeliveredToSwift() {
            suppressBackgroundMapClickUntil = CFAbsoluteTimeGetCurrent() + 0.08
        }

        /// Coalesces rapid ``updateNSView`` calls and skips identical mission payloads so the
        /// WKWebView bridge does not tear down/rebuild every Leaflet layer dozens of times per frame.
        func queueMissionUpdate(script: String) {
            latestMissionScript = script
            coalescedMissionWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.flushMissionScriptToWebViewIfNeeded()
            }
            coalescedMissionWorkItem = work
            DispatchQueue.main.async(execute: work)
        }

        private func flushMissionScriptToWebViewIfNeeded() {
            guard let script = latestMissionScript else { return }
            if script == lastAppliedMissionScript { return }
            guard didFinishInitialLoad, let webView else {
                pendingScript = script
                return
            }
            lastAppliedMissionScript = script
            pendingScript = nil
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func applyViewportNudge(_ nudge: GuardianMapViewportNudge?, webView: WKWebView) {
            guard let nudge else { return }
            if nudge.sequence == lastAppliedViewportNudgeSequence { return }
            guard didFinishInitialLoad else {
                pendingViewportNudge = nudge
                return
            }
            lastAppliedViewportNudgeSequence = nudge.sequence
            pendingViewportNudge = nil
            webView.evaluateJavaScript(OSMMapView.javascriptExpression(for: nudge), completionHandler: nil)
        }

        private func flushPendingViewportNudgeIfLoaded(webView: WKWebView) {
            guard let nudge = pendingViewportNudge else { return }
            pendingViewportNudge = nil
            if nudge.sequence == lastAppliedViewportNudgeSequence { return }
            lastAppliedViewportNudgeSequence = nudge.sequence
            webView.evaluateJavaScript(OSMMapView.javascriptExpression(for: nudge), completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishInitialLoad = true
            lastAppliedMissionScript = nil
            let script = latestMissionScript ?? pendingScript
            if let script {
                lastAppliedMissionScript = script
                pendingScript = nil
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
            flushPendingViewportNudgeIfLoaded(webView: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            DispatchQueue.main.async { [weak self] in
                self?.handleScriptMessage(message)
            }
        }

        private func handleScriptMessage(_ message: WKScriptMessage) {
            if message.name == "mapClick",
               let payload = message.body as? [String: Any],
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                if CFAbsoluteTimeGetCurrent() < suppressBackgroundMapClickUntil {
                    return
                }
                onMapClick(lat, lon)
                return
            }

            if message.name == "waypointClick",
               let payload = message.body as? [String: Any],
               let idx = OSMMapView.WKScriptPayloadBridge.int(payload["idx"]) {
                noteLayerPointerDeliveredToSwift()
                onWaypointClick(idx)
                return
            }

            if message.name == "waypointMove",
               let payload = message.body as? [String: Any],
               let idx = OSMMapView.WKScriptPayloadBridge.int(payload["idx"]),
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                onWaypointMoved(idx, lat, lon)
            }

            if message.name == "waypointDelete",
               let payload = message.body as? [String: Any],
               let idx = OSMMapView.WKScriptPayloadBridge.int(payload["idx"]) {
                onWaypointDelete(idx)
            }

            if message.name == "routeInsert",
               let payload = message.body as? [String: Any],
               let idx = OSMMapView.WKScriptPayloadBridge.int(payload["idx"]),
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                noteLayerPointerDeliveredToSwift()
                onTaskMapInsert(idx, lat, lon)
                return
            }

            if message.name == "vehicleMove",
               let payload = message.body as? [String: Any],
               let id = OSMMapView.WKScriptPayloadBridge.optionalString(payload["id"]),
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                onVehicleMarkerMoved(id, lat, lon)
            }

            if message.name == "vehicleClick",
               let payload = message.body as? [String: Any],
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                let id = OSMMapView.WKScriptPayloadBridge.optionalString(payload["id"])
                noteLayerPointerDeliveredToSwift()
                onVehicleTap(GuardianMapVehiclePointerEvent(markerID: id, lat: lat, lon: lon))
                return
            }

            if message.name == "vehicleDoubleClick",
               let payload = message.body as? [String: Any],
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                let id = OSMMapView.WKScriptPayloadBridge.optionalString(payload["id"])
                noteLayerPointerDeliveredToSwift()
                onVehicleDoubleTap(GuardianMapVehiclePointerEvent(markerID: id, lat: lat, lon: lon))
                return
            }

            if message.name == "markerContextAction",
               let payload = message.body as? [String: Any],
               let actionRaw = payload["action"] as? String,
               let markerTypeRaw = payload["markerType"] as? String,
               let action = GuardianMapContextAction(rawValue: actionRaw),
               let markerType = GuardianMapMarkerType(rawValue: markerTypeRaw),
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                onContextAction(
                    GuardianMapContextActionEvent(
                        action: action,
                        markerType: markerType,
                        markerID: payload["markerID"] as? String,
                        lat: lat,
                        lon: lon
                    )
                )
            }

            if message.name == "missionPointClick" {
                #if DEBUG
                print(
                    "[GuardianHQ][MapBridge] missionPointClick received bodyType=\(String(describing: type(of: message.body)))"
                )
                #endif
                guard let payload = message.body as? [String: Any] else {
                    #if DEBUG
                    print(
                        "[GuardianHQ][MapBridge] missionPointClick ERROR body is not [String:Any]: \(String(describing: message.body))"
                    )
                    #endif
                    return
                }
                let rawID = payload["id"]
                #if DEBUG
                print(
                    "[GuardianHQ][MapBridge] missionPointClick payload keys=\(payload.keys.sorted().joined(separator: ",")) id=\(String(describing: rawID)) idSwiftType=\(String(describing: type(of: rawID)))"
                )
                #endif
                guard let idStr = OSMMapView.WKScriptPayloadBridge.optionalString(rawID) else {
                    #if DEBUG
                    print(
                        "[GuardianHQ][MapBridge] missionPointClick ERROR id is not String (WebKit payload mismatch)"
                    )
                    #endif
                    return
                }
                guard let uuid = UUID(uuidString: idStr) else {
                    #if DEBUG
                    print(
                        "[GuardianHQ][MapBridge] missionPointClick ERROR id string is not a valid UUID: \(idStr)"
                    )
                    #endif
                    return
                }
                #if DEBUG
                print(
                    "[GuardianHQ][MapBridge] missionPointClick OK → onMissionPointClick(\(uuid.uuidString))"
                )
                #endif
                noteLayerPointerDeliveredToSwift()
                onMissionPointClick(uuid)
                return
            }

            if message.name == "missionPointDoubleClick",
               let payload = message.body as? [String: Any],
               let idStr = OSMMapView.WKScriptPayloadBridge.optionalString(payload["id"]),
               let uuid = UUID(uuidString: idStr) {
                noteLayerPointerDeliveredToSwift()
                onMissionPointDoubleClick(uuid)
                return
            }

            if message.name == "missionPointMove",
               let payload = message.body as? [String: Any],
               let idStr = OSMMapView.WKScriptPayloadBridge.optionalString(payload["id"]),
               let uuid = UUID(uuidString: idStr),
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                onMissionPointMoved(uuid, lat, lon)
            }

            if message.name == "mapViewportCenter",
               let payload = message.body as? [String: Any],
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                onViewportCenterChanged(lat, lon)
            }

            if message.name == "taskPathClick",
               let payload = message.body as? [String: Any],
               let idStr = payload["taskPathId"] as? String,
               let taskPathID = UUID(uuidString: idStr),
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                noteLayerPointerDeliveredToSwift()
                onTaskPathTap(GuardianMapTaskPathPointerEvent(taskPathID: taskPathID, lat: lat, lon: lon))
                return
            }

            if message.name == "taskPathDoubleClick",
               let payload = message.body as? [String: Any],
               let idStr = payload["taskPathId"] as? String,
               let taskPathID = UUID(uuidString: idStr),
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                noteLayerPointerDeliveredToSwift()
                onTaskPathDoubleTap(GuardianMapTaskPathPointerEvent(taskPathID: taskPathID, lat: lat, lon: lon))
                return
            }

            if message.name == "homeClick",
               let payload = message.body as? [String: Any],
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                noteLayerPointerDeliveredToSwift()
                onHomeTap(GuardianMapHomePointerEvent(lat: lat, lon: lon))
                return
            }

            if message.name == "homeDoubleClick",
               let payload = message.body as? [String: Any],
               let lat = OSMMapView.WKScriptPayloadBridge.double(payload["lat"]),
               let lon = OSMMapView.WKScriptPayloadBridge.double(payload["lon"]) {
                noteLayerPointerDeliveredToSwift()
                onHomeDoubleTap(GuardianMapHomePointerEvent(lat: lat, lon: lon))
                return
            }
        }
    }
}

private extension OSMMapView {
    static let html = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
  <style>
    html, body, #map { height: 100%; margin: 0; background: #111; }
    .leaflet-container { background: #111; }
    .guardian-context-menu {
      position: absolute;
      z-index: 4000;
      min-width: 170px;
      background: rgba(24, 26, 31, 0.98);
      border: 1px solid rgba(255,255,255,0.14);
      border-radius: 8px;
      box-shadow: 0 6px 18px rgba(0,0,0,0.45);
      overflow: hidden;
      user-select: none;
    }
    .guardian-context-item {
      display: block;
      width: 100%;
      text-align: left;
      background: transparent;
      border: 0;
      color: #e5e7eb;
      padding: 8px 10px;
      font: 12px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      cursor: pointer;
    }
    .guardian-context-item:hover {
      background: rgba(59,130,246,0.28);
    }
    @keyframes guardianSimSyncSpin {
      from { transform: rotate(0deg); }
      to { transform: rotate(360deg); }
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <script>
    const map = L.map('map', { zoomControl: true, maxZoom: 24 }).setView([20, 0], 2);
    const standardLayer = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxNativeZoom: 19,
      maxZoom: 24,
      attribution: '&copy; OpenStreetMap contributors'
    });
    const satelliteLayer = L.tileLayer(
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      { maxNativeZoom: 19, maxZoom: 24, attribution: 'Tiles &copy; Esri' }
    );
    standardLayer.addTo(map);

    const waypointMarkers = [];
    var headingCone = null;
    var cameraCone = null;
    /** Stable id → marker so hub-driven ``setMissionData`` patches do not ``removeLayer`` every tick.
     *  Full tear-down was leaving polylines intact (good) but destroying marker DOM under the cursor — clicks
     *  fell through to the map / hit polylines while vehicle / mission-point ``click`` rarely fired. */
    const vehicleMarkerById = new Map();
    const missionPointMarkerById = new Map();
    const pathLines = [];
    const state = { lastDataSignature: null, lastRecenterNonce: -1, lastFullMissionSig: null, lastStructureSig: null };
    let contextMenuEl = null;
    let followedVehicleMarkerID = null;
    let contextMenuPolicy = { vehicleActions: [], waypointActions: [], homeActions: [], missionPointActions: [] };
    /** Some WebKit + Leaflet stacks still deliver `map.on('click')` after marker / polyline `click`
     *  even when `L.DomEvent.stop(e)` runs on the layer handler. Skip posting `mapClick` briefly. */
    var guardianSuppressBackgroundMapClickUntilMs = 0;
    function guardianMarkLayerMapClickSuppressed() {
      guardianSuppressBackgroundMapClickUntilMs = Date.now() + 150;
    }

    map.on('click', function(e) {
      hideContextMenu();
      if (Date.now() < guardianSuppressBackgroundMapClickUntilMs) {
        return;
      }
      window.webkit.messageHandlers.mapClick.postMessage({
        lat: e.latlng.lat,
        lon: e.latlng.lng
      });
    });
    map.on('movestart zoomstart', hideContextMenu);

    let viewportCenterDebounce = null;
    function emitViewportCenter() {
      if (viewportCenterDebounce) clearTimeout(viewportCenterDebounce);
      viewportCenterDebounce = setTimeout(() => {
        try {
          const c = map.getCenter();
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapViewportCenter) {
            window.webkit.messageHandlers.mapViewportCenter.postMessage({ lat: c.lat, lon: c.lng });
          }
        } catch (e) {}
      }, 140);
    }
    map.on('moveend', emitViewportCenter);
    map.on('zoomend', emitViewportCenter);

    function contextActionTitle(action) {
      switch (action) {
        case 'followVehicle': return 'Follow marker';
        case 'stopFollowingVehicle': return 'Stop following';
        case 'centerMarker': return 'Center map here';
        case 'deleteWaypoint': return 'Delete waypoint';
        case 'deleteMissionPoint': return 'Delete map point';
        default: return action;
      }
    }

    function hideContextMenu() {
      if (contextMenuEl && contextMenuEl.parentNode) {
        contextMenuEl.parentNode.removeChild(contextMenuEl);
      }
      contextMenuEl = null;
    }

    /** Leaflet listens on the map container; menu is inside that container, so
     *  pointer events would bubble and trigger map click (e.g. new waypoint).
     *  Stop bubble on the menu subtree and defer removal so the menu is not
     *  torn down mid-dispatch (avoids click-through on WebKit). */
    function shieldContextMenuFromMapPointerEvents(menuEl) {
      const stopBubble = (ev) => {
        ev.stopPropagation();
      };
      ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'click', 'dblclick', 'wheel', 'contextmenu'].forEach((type) => {
        menuEl.addEventListener(type, stopBubble, false);
      });
    }

    function markerActionsForType(markerType) {
      if (markerType === 'vehicle') {
        const base = contextMenuPolicy.vehicleActions || [];
        return base.filter((action) => {
          if (action === 'followVehicle') return !followedVehicleMarkerID;
          if (action === 'stopFollowingVehicle') return !!followedVehicleMarkerID;
          return true;
        });
      }
      if (markerType === 'waypoint') return contextMenuPolicy.waypointActions || [];
      if (markerType === 'home') return contextMenuPolicy.homeActions || [];
      if (markerType === 'missionPoint') return contextMenuPolicy.missionPointActions || [];
      return [];
    }

    function openContextMenu(e, markerType, markerID, lat, lon) {
      const actions = markerActionsForType(markerType);
      if (!actions || actions.length === 0) return;
      hideContextMenu();
      if (e.originalEvent) L.DomEvent.preventDefault(e.originalEvent);

      const container = map.getContainer();
      const menu = document.createElement('div');
      menu.className = 'guardian-context-menu';
      actions.forEach((action) => {
        const item = document.createElement('button');
        item.className = 'guardian-context-item';
        item.type = 'button';
        item.textContent = contextActionTitle(action);
        item.addEventListener('click', (ev) => {
          L.DomEvent.stop(ev);
          if (action === 'centerMarker') {
            map.panTo([lat, lon], { animate: true, duration: 0.25 });
          }
          window.webkit.messageHandlers.markerContextAction.postMessage({
            action: action,
            markerType: markerType,
            markerID: markerID || null,
            lat: lat,
            lon: lon
          });
          queueMicrotask(() => {
            hideContextMenu();
          });
        });
        menu.appendChild(item);
      });
      shieldContextMenuFromMapPointerEvents(menu);
      container.appendChild(menu);
      contextMenuEl = menu;

      const point = map.latLngToContainerPoint([lat, lon]);
      const rect = container.getBoundingClientRect();
      const maxLeft = Math.max(0, rect.width - menu.offsetWidth - 8);
      const maxTop = Math.max(0, rect.height - menu.offsetHeight - 8);
      const left = Math.min(maxLeft, Math.max(6, point.x + 6));
      const top = Math.min(maxTop, Math.max(6, point.y + 6));
      menu.style.left = `${left}px`;
      menu.style.top = `${top}px`;
    }

    function applyStyle(style) {
      if (style === 'satellite') {
        if (map.hasLayer(standardLayer)) map.removeLayer(standardLayer);
        if (!map.hasLayer(satelliteLayer)) satelliteLayer.addTo(map);
      } else {
        if (map.hasLayer(satelliteLayer)) map.removeLayer(satelliteLayer);
        if (!map.hasLayer(standardLayer)) standardLayer.addTo(map);
      }
    }

    function pathColor(index) {
      const hue = (index * 137.508) % 360;
      return `hsl(${hue}, 88%, 62%)`;
    }

    function nearestSegmentInsertIndex(latlngs, clickLatLng) {
      if (!latlngs || latlngs.length < 2) return latlngs.length;
      const p = map.project(clickLatLng, map.getZoom());
      let bestDist = Number.MAX_VALUE;
      let bestIdx = 0;
      for (let i = 0; i < latlngs.length - 1; i++) {
        const a = map.project(latlngs[i], map.getZoom());
        const b = map.project(latlngs[i + 1], map.getZoom());
        const abx = b.x - a.x, aby = b.y - a.y;
        const apx = p.x - a.x, apy = p.y - a.y;
        const ab2 = abx * abx + aby * aby;
        const t = ab2 === 0 ? 0 : Math.max(0, Math.min(1, (apx * abx + apy * aby) / ab2));
        const cx = a.x + t * abx, cy = a.y + t * aby;
        const dx = p.x - cx, dy = p.y - cy;
        const d2 = dx * dx + dy * dy;
        if (d2 < bestDist) {
          bestDist = d2;
          bestIdx = i + 1;
        }
      }
      return bestIdx;
    }

    function conePoints(lat, lon, bearingDeg, spreadDeg, lengthRatio) {
      const centerPoint = map.latLngToContainerPoint([lat, lon]);
      const size = map.getSize();
      const coneLengthPx = Math.max(24, Math.min(size.x, size.y) * lengthRatio);

      function projectPoint(point, bearingDeg, distancePx) {
        const rad = (bearingDeg * Math.PI) / 180.0;
        const dx = Math.sin(rad) * distancePx;
        const dy = -Math.cos(rad) * distancePx;
        return L.point(point.x + dx, point.y + dy);
      }

      const leftPoint = projectPoint(centerPoint, bearingDeg - spreadDeg, coneLengthPx);
      const rightPoint = projectPoint(centerPoint, bearingDeg + spreadDeg, coneLengthPx);
      const left = map.containerPointToLatLng(leftPoint);
      const right = map.containerPointToLatLng(rightPoint);
      return [[lat, lon], [left.lat, left.lng], [right.lat, right.lng]];
    }

    function headingColor(headingDeg) {
      const normalized = ((headingDeg % 360) + 360) % 360;
      return `hsl(${normalized}, 88%, 58%)`;
    }

    /** When home + vehicle share the same lat/lon, bounds are degenerate and fitBounds zooms in too far — treat as one point. */
    function collapsedCenterIfAllSame(pts) {
      if (!pts || pts.length === 0) return null;
      if (pts.length === 1) return pts[0];
      const lat0 = pts[0][0];
      const lon0 = pts[0][1];
      for (let i = 1; i < pts.length; i++) {
        if (Math.abs(pts[i][0] - lat0) > 1e-7 || Math.abs(pts[i][1] - lon0) > 1e-7) return null;
      }
      return [lat0, lon0];
    }

    const defaultSinglePointZoom = 15;

    function guardianPanToRetainZoom(lat, lon) {
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) return;
      map.panTo([lat, lon], { animate: true, duration: 0.28 });
    }

    /** Fit map to WGS84 pairs `[[lat,lon],…]` — padding + max zoom aligned with ``setMissionData`` recenter paths. */
    /** MC-R triage “show on map”: zoom in as far as the viewport allows (``maxZoom`` 19) while fitting all points.
     *  Filters unset (0,0) / invalid coords and pads nearly-degenerate bounds so Leaflet does not pick a world-scale zoom. */
    function guardianFitBoundsForPoints(pairs) {
      if (!pairs || pairs.length === 0) return;
      const pts = [];
      for (const pr of pairs) {
        if (!Array.isArray(pr) || pr.length !== 2) continue;
        const la = pr[0], lo = pr[1];
        if (!Number.isFinite(la) || !Number.isFinite(lo)) continue;
        if (la === 0 && lo === 0) continue;
        if (la < -85 || la > 85 || lo < -180 || lo > 180) continue;
        pts.push([la, lo]);
      }
      if (pts.length === 0) return;
      const triageMaxZoom = 19;
      const triagePadding = [18, 18];
      const collapsed = collapsedCenterIfAllSame(pts);
      if (collapsed) {
        map.setView(collapsed, Math.min(triageMaxZoom, 17));
      } else if (pts.length === 1) {
        map.setView(pts[0], Math.min(triageMaxZoom, 17));
      } else {
        let b = L.latLngBounds(pts);
        const ne = b.getNorthEast();
        const sw = b.getSouthWest();
        const h = Math.abs(ne.lat - sw.lat);
        const w = Math.abs(ne.lng - sw.lng);
        if (h < 1e-5 || w < 1e-5) {
          b = b.pad(0.02);
        }
        map.fitBounds(b, { padding: triagePadding, maxZoom: triageMaxZoom, animate: true, duration: 0.28 });
      }
    }

    /** Excludes **heading** (yaw updates every hub sample) — including it forced ``setIcon`` every tick and
     *  rebuilt the DivIcon subtree under the cursor. Heading is patched separately via ``guardianPatchVehicleHeadingWedge``. */
    function guardianVehicleChromeSigNoPos(vm) {
      return [vm.selected ? 1 : 0, vm.draggable ? 1 : 0, vm.showLabel ? 1 : 0,
        String(vm.label || ''), String(vm.color || ''), String(vm.image || ''), vm.pendingSimSync ? 1 : 0].join('\u{001f}');
    }

    function guardianPatchVehicleHeadingWedge(marker, vm, size) {
      try {
        const root = marker.getElement && marker.getElement();
        if (!root) return;
        const wedge = root.querySelector('.guardian-vehicle-heading-wedge');
        if (!Number.isFinite(vm.heading)) {
          if (wedge) wedge.style.display = 'none';
          return;
        }
        if (wedge) {
          wedge.style.display = '';
          wedge.style.transform = 'rotate(' + vm.heading + 'deg)';
          wedge.style.transformOrigin = '50% ' + (size / 2 + 5) + 'px';
        }
      } catch (e) {}
    }

    function guardianMissionPointChromeSigNoPos(mp) {
      const chip = (mp.chipCompact != null && mp.chipCompact !== '') ? String(mp.chipCompact) : String(mp.chip || '');
      return [mp.selected ? 1 : 0, mp.closed ? 1 : 0, String(mp.kind || ''), chip].join('\u{001f}');
    }

    function wireGuardianVehiclePointerEvents(marker, idStr) {
      marker.on('contextmenu', function(e) {
        const pos = e.target.getLatLng();
        openContextMenu(e, 'vehicle', idStr, pos.lat, pos.lng);
      });
      marker.on('click', function(e) {
        const pos = e.target.getLatLng();
        L.DomEvent.stop(e);
        guardianMarkLayerMapClickSuppressed();
        window.webkit.messageHandlers.vehicleClick.postMessage({ id: idStr, lat: pos.lat, lon: pos.lng });
      });
      marker.on('dblclick', function(e) {
        const pos = e.target.getLatLng();
        L.DomEvent.stop(e);
        guardianMarkLayerMapClickSuppressed();
        window.webkit.messageHandlers.vehicleDoubleClick.postMessage({ id: idStr, lat: pos.lat, lon: pos.lng });
      });
    }

    function wireGuardianVehicleDragEnd(marker, idStr) {
      marker.on('dragend', function(e) {
        const pos = e.target.getLatLng();
        window.webkit.messageHandlers.vehicleMove.postMessage({ id: idStr, lat: pos.lat, lon: pos.lng });
      });
    }

    function wireGuardianMissionPointPointerEvents(marker, idStr) {
      marker.on('click', function(e) {
        L.DomEvent.stop(e);
        guardianMarkLayerMapClickSuppressed();
        window.webkit.messageHandlers.missionPointClick.postMessage({ id: idStr });
      });
      marker.on('dblclick', function(e) {
        L.DomEvent.stop(e);
        guardianMarkLayerMapClickSuppressed();
        window.webkit.messageHandlers.missionPointDoubleClick.postMessage({ id: idStr });
      });
      marker.on('contextmenu', function(e) {
        const pos = e.target.getLatLng();
        openContextMenu(e, 'missionPoint', idStr, pos.lat, pos.lng);
      });
    }

    function wireGuardianMissionPointDragEnd(marker, idStr) {
      marker.on('dragend', function(e) {
        const pos = e.target.getLatLng();
        window.webkit.messageHandlers.missionPointMove.postMessage({ id: idStr, lat: pos.lat, lon: pos.lng });
      });
    }

    /** Reconcile roster vehicle + mission-point markers (paths/home untouched). Prefer ``setLatLng`` + icon
     *  refresh over ``removeLayer`` so hub-driven patches do not destroy the DOM node under an in-flight click. */
    function rebuildVehicleAndMissionPointMarkers(missionVehicleMarkers, missionPointMarkersArg, points) {
      const nextVehicleIds = new Set();
      if (missionVehicleMarkers && missionVehicleMarkers.length > 0) {
        missionVehicleMarkers.forEach((vm) => {
          if (!vm.id || !Number.isFinite(vm.lat) || !Number.isFinite(vm.lon)) return;
          const idStr = String(vm.id);
          nextVehicleIds.add(idStr);
          const size = vm.selected ? 36 : 32;
          const border = vm.selected ? 3 : 2;
          const inner = Math.max(14, size - (border * 2) - 2);
          const ringColor = vm.color || '#94a3b8';
          const headingArrow = Number.isFinite(vm.heading)
            ? `<div class="guardian-vehicle-heading-wedge" style="
                position:absolute;
                top:-5px;
                left:50%;
                width:0;
                height:0;
                margin-left:-5px;
                border-left:5px solid transparent;
                border-right:5px solid transparent;
                border-bottom:10px solid rgba(255,255,255,0.95);
                transform: rotate(${vm.heading}deg);
                transform-origin: 50% ${size/2 + 5}px;
                filter: drop-shadow(0 0 2px rgba(0,0,0,0.9));
                pointer-events:none;
              "></div>`
            : '';
          const imageHTML = vm.image
            ? `<img src="${vm.image}" alt="" draggable="false" style="-webkit-user-drag:none;user-drag:none;width:${inner}px;height:${inner}px;border-radius:999px;object-fit:cover;display:block;"/>`
            : `<div style="width:${inner}px;height:${inner}px;border-radius:999px;background:#1f2937;touch-action:none;-webkit-user-drag:none;"></div>`;
          const pendingSimSync = !!vm.pendingSimSync;
          const syncSpinner = pendingSimSync
            ? `<div title="Syncing vehicle position with telemetry…" style="position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:22px;height:22px;border-radius:999px;background:rgba(15,23,42,0.92);border:1px solid rgba(255,255,255,0.38);display:flex;align-items:center;justify-content:center;pointer-events:none;box-shadow:0 1px 5px rgba(0,0,0,0.55);z-index:4;">
                 <span style="display:block;width:11px;height:11px;border-radius:50%;border:2px solid rgba(255,255,255,0.2);border-top-color:#fff;animation:guardianSimSyncSpin 0.72s linear infinite;"></span>
               </div>`
            : '';
          const vehicleZ = vm.draggable ? 2500 : (vm.selected ? 1200 : 600);
          const icon = L.divIcon({
            className: 'mission-vehicle-dot',
            html: `<div style="position:relative;width:${size}px;height:${size}px;touch-action:none;-webkit-user-drag:none;">${headingArrow}<div style="width:${size}px;height:${size}px;border-radius:999px;border:${border}px solid ${ringColor};background:#0b0f14;display:flex;align-items:center;justify-content:center;box-shadow:0 0 0 1px rgba(0,0,0,0.55);overflow:hidden;touch-action:none;">${imageHTML}</div>${syncSpinner}</div>`,
            iconSize: [size, size],
            iconAnchor: [size / 2, size / 2]
          });
          const chromeSig = guardianVehicleChromeSigNoPos(vm);
          let marker = vehicleMarkerById.get(idStr);
          if (!marker) {
            marker = L.marker([vm.lat, vm.lon], {
              draggable: !!vm.draggable,
              zIndexOffset: vehicleZ,
              title: vm.label || '',
              icon: icon
            }).addTo(map);
            marker._guardianVehicleChromeSig = chromeSig;
            wireGuardianVehiclePointerEvents(marker, idStr);
            vehicleMarkerById.set(idStr, marker);
            if (vm.showLabel && vm.label && vm.selected) {
              marker.bindTooltip(vm.label, { permanent: true, direction: 'top', offset: [0, -10], opacity: 0.95 });
            }
          } else {
            marker.setLatLng([vm.lat, vm.lon]);
            marker.setZIndexOffset(vehicleZ);
            marker.options.title = vm.label || '';
            if (marker._guardianVehicleChromeSig !== chromeSig) {
              marker._guardianVehicleChromeSig = chromeSig;
              marker.setIcon(icon);
              marker.unbindTooltip();
              if (vm.showLabel && vm.label && vm.selected) {
                marker.bindTooltip(vm.label, { permanent: true, direction: 'top', offset: [0, -10], opacity: 0.95 });
              }
            } else {
              const root = marker.getElement && marker.getElement();
              const wedge = root && root.querySelector('.guardian-vehicle-heading-wedge');
              if (Number.isFinite(vm.heading) && !wedge) {
                marker.setIcon(icon);
              }
            }
          }
          guardianPatchVehicleHeadingWedge(marker, vm, size);
          if (vm.draggable && marker.dragging) {
            marker.dragging.enable();
          } else if (marker.dragging) {
            marker.dragging.disable();
          }
          marker.off('dragend');
          if (vm.draggable) {
            wireGuardianVehicleDragEnd(marker, idStr);
          }
          points.push([vm.lat, vm.lon]);
        });
      }
      for (const idStr of Array.from(vehicleMarkerById.keys())) {
        if (!nextVehicleIds.has(idStr)) {
          const m = vehicleMarkerById.get(idStr);
          map.removeLayer(m);
          vehicleMarkerById.delete(idStr);
        }
      }

      const nextMissionPointIds = new Set();
      if (missionPointMarkersArg && missionPointMarkersArg.length > 0) {
        missionPointMarkersArg.forEach((mp) => {
          if (!Number.isFinite(mp.lat) || !Number.isFinite(mp.lon) || !mp.id) return;
          const idStr = String(mp.id);
          nextMissionPointIds.add(idStr);
          const isExtraction = mp.kind === 'extraction';
          const hue = isExtraction ? 150 : 32;
          const border = mp.selected ? '3px solid #fff' : '2px solid rgba(0,0,0,0.55)';
          const opacity = mp.closed ? 0.42 : 1.0;
          const deco = mp.closed ? 'line-through' : 'none';
          const sz = mp.selected ? 30 : 22;
          const chipC = (mp.chipCompact != null && mp.chipCompact !== '') ? String(mp.chipCompact) : (mp.chip || '');
          const labelText = chipC;
          const fontPx = mp.selected ? 11 : 10;
          const ellip = mp.selected ? 'ellipsis' : 'clip';
          const grabCursor = mp.selected ? 'grab' : 'pointer';
          const html = `<div style="opacity:${opacity};width:${sz}px;height:${sz}px;transform:rotate(45deg);background:hsl(${hue},85%,52%);border:${border};box-shadow:0 0 0 1px rgba(0,0,0,0.45);display:flex;align-items:center;justify-content:center;cursor:${grabCursor};-webkit-user-select:none;user-select:none;touch-action:none;">
            <span style="transform:rotate(-45deg);font:${fontPx}px/1 -apple-system,sans-serif;font-weight:700;color:#0b0f14;max-width:${sz - 4}px;overflow:hidden;text-overflow:${ellip};white-space:nowrap;text-decoration:${deco};-webkit-user-select:none;user-select:none;pointer-events:none">${labelText.replace(/</g,'')}</span>
          </div>`;
          const icon = L.divIcon({
            className: 'mission-point-pin',
            html: html,
            iconSize: [sz, sz],
            iconAnchor: [sz / 2, sz / 2]
          });
          const chromeSig = guardianMissionPointChromeSigNoPos(mp);
          const mpZ = mp.selected ? 900 : 400;
          let marker = missionPointMarkerById.get(idStr);
          if (!marker) {
            marker = L.marker([mp.lat, mp.lon], {
              draggable: !!mp.selected,
              zIndexOffset: mpZ,
              icon: icon
            }).addTo(map);
            marker._guardianMissionPointChromeSig = chromeSig;
            wireGuardianMissionPointPointerEvents(marker, idStr);
            missionPointMarkerById.set(idStr, marker);
          } else {
            marker.setLatLng([mp.lat, mp.lon]);
            marker.setZIndexOffset(mpZ);
            if (marker._guardianMissionPointChromeSig !== chromeSig) {
              marker._guardianMissionPointChromeSig = chromeSig;
              marker.setIcon(icon);
            }
          }
          if (mp.selected && marker.dragging) {
            marker.dragging.enable();
          } else if (marker.dragging) {
            marker.dragging.disable();
          }
          marker.off('dragend');
          if (mp.selected) {
            wireGuardianMissionPointDragEnd(marker, idStr);
          }
          points.push([mp.lat, mp.lon]);
        });
      }
      for (const idStr of Array.from(missionPointMarkerById.keys())) {
        if (!nextMissionPointIds.has(idStr)) {
          const m = missionPointMarkerById.get(idStr);
          map.removeLayer(m);
          missionPointMarkerById.delete(idStr);
        }
      }
    }

    function setMissionData(home, allTasksCoords, taskPathIds, selectedWaypoints, selectedWaypointIndex, missionVehicleMarkers, mapStyle, recenterNonce, headingPreview, cameraPreview, followVehicleMarkerID, menuPolicy, preserveView, isEditingTask, missionPointPlacementArmed, missionPointMarkersArg) {
      const geometryTasks = (allTasksCoords || []).filter(path => path && path.length > 0);
      const fullMissionSig = JSON.stringify({
        home: home,
        geometryTasks: geometryTasks,
        taskPathIds: taskPathIds || null,
        selectedWaypoints: selectedWaypoints || [],
        selectedWaypointIndex: selectedWaypointIndex,
        missionVehicleMarkers: missionVehicleMarkers || [],
        mapStyle: mapStyle,
        recenterNonce: recenterNonce,
        headingPreview: headingPreview,
        cameraPreview: cameraPreview,
        followVehicleMarkerID: followVehicleMarkerID || null,
        menuPolicy: menuPolicy || {},
        preserveView: !!preserveView,
        isEditingTask: !!isEditingTask,
        missionPointPlacementArmed: !!missionPointPlacementArmed,
        missionPoints: missionPointMarkersArg || []
      });
      if (fullMissionSig === state.lastFullMissionSig) {
        return;
      }

      const structureSig = JSON.stringify({
        home: home,
        geometryTasks: geometryTasks,
        taskPathIds: taskPathIds || null,
        selectedWaypoints: selectedWaypoints || [],
        selectedWaypointIndex: selectedWaypointIndex,
        mapStyle: mapStyle,
        headingPreview: headingPreview,
        cameraPreview: cameraPreview,
        followVehicleMarkerID: followVehicleMarkerID || null,
        menuPolicy: menuPolicy || {},
        preserveView: !!preserveView,
        isEditingTask: !!isEditingTask,
        missionPointPlacementArmed: !!missionPointPlacementArmed
      });
      const canPatchMarkersOnly = state.lastStructureSig !== null && structureSig === state.lastStructureSig;

      if (canPatchMarkersOnly) {
        followedVehicleMarkerID = followVehicleMarkerID || null;
        contextMenuPolicy = menuPolicy || { vehicleActions: [], waypointActions: [], homeActions: [], missionPointActions: [] };
        applyStyle(mapStyle);
        map.getContainer().style.cursor = (isEditingTask || missionPointPlacementArmed) ? 'pointer' : '';

        const points = [];
        if (home) {
          points.push([home.lat, home.lon]);
        }
        pathLines.forEach((line) => {
          try {
            if (!line || !line.getLatLngs) return;
            const lls = line.getLatLngs();
            (lls || []).forEach((pt) => {
              if (pt && typeof pt.lat === 'number' && typeof pt.lng === 'number') {
                points.push([pt.lat, pt.lng]);
              }
            });
          } catch (e) {}
        });
        rebuildVehicleAndMissionPointMarkers(missionVehicleMarkers, missionPointMarkersArg, points);

        if (followedVehicleMarkerID) {
          const followMarker = (missionVehicleMarkers || []).find((m) => m.id === followedVehicleMarkerID);
          if (followMarker && Number.isFinite(followMarker.lat) && Number.isFinite(followMarker.lon)) {
            map.panTo([followMarker.lat, followMarker.lon], { animate: true, duration: 0.25 });
          }
        }

        const dataSignature = JSON.stringify({
          home: home,
          geometryTasks: geometryTasks,
          missionVehicleMarkers: missionVehicleMarkers
        });
        const dataChanged = state.lastDataSignature !== dataSignature;
        state.lastDataSignature = dataSignature;
        const forceRecenter = state.lastRecenterNonce !== recenterNonce;
        state.lastRecenterNonce = recenterNonce;

        if ((dataChanged && !preserveView) || forceRecenter) {
          const collapsed = collapsedCenterIfAllSame(points);
          if (collapsed) {
            map.setView(collapsed, defaultSinglePointZoom);
          } else if (points.length > 1) {
            map.fitBounds(points, { padding: [30, 30], maxZoom: defaultSinglePointZoom });
          } else if (points.length === 1) {
            map.setView(points[0], defaultSinglePointZoom);
          } else if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition(
              function(pos) {
                map.setView([pos.coords.latitude, pos.coords.longitude], 6);
              },
              function() {
                map.setView([20, 0], 2);
              }
            );
          } else {
            map.setView([20, 0], 2);
          }
        }

        state.lastFullMissionSig = fullMissionSig;
        return;
      }

      followedVehicleMarkerID = followVehicleMarkerID || null;
      contextMenuPolicy = menuPolicy || { vehicleActions: [], waypointActions: [], homeActions: [], missionPointActions: [] };
      if (headingCone) { map.removeLayer(headingCone); headingCone = null; }
      if (cameraCone) { map.removeLayer(cameraCone); cameraCone = null; }
      while (pathLines.length > 0) {
        const line = pathLines.pop();
        map.removeLayer(line);
      }
      while (waypointMarkers.length > 0) {
        const m = waypointMarkers.pop();
        map.removeLayer(m);
      }
      applyStyle(mapStyle);
      map.getContainer().style.cursor = (isEditingTask || missionPointPlacementArmed) ? 'pointer' : '';

      const points = [];
      const dataSignature = JSON.stringify({
        home: home,
        geometryTasks: geometryTasks,
        missionVehicleMarkers: missionVehicleMarkers
      });
      const dataChanged = state.lastDataSignature !== dataSignature;
      state.lastDataSignature = dataSignature;
      const forceRecenter = state.lastRecenterNonce !== recenterNonce;
      state.lastRecenterNonce = recenterNonce;

      if (home) {
        points.push([home.lat, home.lon]);
      }

      if (allTasksCoords && allTasksCoords.length > 0) {
        const idsAligned = taskPathIds && taskPathIds.length === allTasksCoords.length;
        allTasksCoords.forEach((taskCoords, pathIdx) => {
          if (!taskCoords || taskCoords.length === 0) return;
          const latlngs = taskCoords.map(p => [p.lat, p.lon]);
          const idx = pathLines.length;
          const pathId = idsAligned ? taskPathIds[pathIdx] : null;
          const useWideHit = pathId && !isEditingTask;
          const line = L.polyline(latlngs, {
            color: pathColor(idx),
            weight: 3,
            interactive: pathId ? !useWideHit : false
          }).addTo(map);
          pathLines.push(line);
          for (const p of latlngs) points.push(p);
          if (pathId) {
            const wireTaskPathPointer = function(poly) {
              poly.on('click', function(e) {
                // Must stop the **Leaflet** event, not only `originalEvent`: otherwise the same
                // gesture still satisfies `map.on('click', …)` → `mapClick` → Swift clears task focus
                // immediately after `taskPathClick` (MC-R log filter appeared to “flicker”).
                L.DomEvent.stop(e);
                guardianMarkLayerMapClickSuppressed();
                window.webkit.messageHandlers.taskPathClick.postMessage({
                  taskPathId: pathId,
                  lat: e.latlng.lat,
                  lon: e.latlng.lng
                });
              });
              poly.on('dblclick', function(e) {
                L.DomEvent.stop(e);
                guardianMarkLayerMapClickSuppressed();
                window.webkit.messageHandlers.taskPathDoubleClick.postMessage({
                  taskPathId: pathId,
                  lat: e.latlng.lat,
                  lon: e.latlng.lng
                });
              });
            };
            if (useWideHit) {
              const hitLine = L.polyline(latlngs, {
                color: '#0b1220',
                opacity: 0,
                weight: 14,
                interactive: true
              }).addTo(map);
              pathLines.push(hitLine);
              wireTaskPathPointer(hitLine);
            } else {
              wireTaskPathPointer(line);
            }
          }
        });
      }

      if (isEditingTask && selectedWaypoints && selectedWaypoints.length > 0) {
        const selectedLatLngs = selectedWaypoints.map(wp => [wp.lat, wp.lon]);
        if (selectedLatLngs.length > 1) {
          const routeLine = L.polyline(selectedLatLngs, { color: '#ffffff', weight: 3, opacity: 0.25 }).addTo(map);
          routeLine.on('click', function(e) {
            L.DomEvent.stop(e);
            guardianMarkLayerMapClickSuppressed();
            const insertIdx = nearestSegmentInsertIndex(routeLine.getLatLngs(), e.latlng);
            window.webkit.messageHandlers.routeInsert.postMessage({
              idx: insertIdx,
              lat: e.latlng.lat,
              lon: e.latlng.lng
            });
          });
          pathLines.push(routeLine);
        }

        selectedWaypoints.forEach((wp) => {
          if (wp.anchor === false) {
            return;
          }
          const isSelected = selectedWaypointIndex === wp.idx;
          const marker = L.marker([wp.lat, wp.lon], {
            draggable: isEditingTask && wp.anchor !== false,
            zIndexOffset: isSelected ? 1000 : 0,
            icon: L.divIcon({
              className: 'wp-dot',
              html: isSelected
                ? '<div style="width:14px;height:14px;border-radius:999px;background:#000;border:2px solid #fff;"></div>'
                : '<div style="width:10px;height:10px;border-radius:999px;background:#fff;border:2px solid #111;"></div>',
              iconSize: isSelected ? [18, 18] : [14, 14],
              iconAnchor: isSelected ? [9, 9] : [7, 7]
            })
          }).addTo(map);
          if (isSelected) {
            marker.setZIndexOffset(1000);
          }
          marker.on('click', function(e) {
            L.DomEvent.stop(e);
            guardianMarkLayerMapClickSuppressed();
            window.webkit.messageHandlers.waypointClick.postMessage({ idx: wp.idx });
          });
          if (isEditingTask) {
            marker.on('dragend', function(e) {
              const pos = e.target.getLatLng();
              window.webkit.messageHandlers.waypointMove.postMessage({
                idx: wp.idx,
                lat: pos.lat,
                lon: pos.lng
              });
            });
            marker.on('contextmenu', function(e) {
              openContextMenu(e, 'waypoint', String(wp.idx), wp.lat, wp.lon);
            });
          }
          waypointMarkers.push(marker);
        });
      }

      rebuildVehicleAndMissionPointMarkers(missionVehicleMarkers, missionPointMarkersArg, points);

      if (followedVehicleMarkerID) {
        const followMarker = (missionVehicleMarkers || []).find((m) => m.id === followedVehicleMarkerID);
        if (followMarker && Number.isFinite(followMarker.lat) && Number.isFinite(followMarker.lon)) {
          map.panTo([followMarker.lat, followMarker.lon], { animate: true, duration: 0.25 });
        }
      }

      if (headingPreview && Number.isFinite(headingPreview.lat) && Number.isFinite(headingPreview.lon) && Number.isFinite(headingPreview.heading)) {
        const coneColor = headingColor(headingPreview.heading);
        headingCone = L.polygon(
          conePoints(headingPreview.lat, headingPreview.lon, headingPreview.heading, 22, 0.2),
          {
            color: coneColor,
            fillColor: coneColor,
            weight: 2,
            opacity: 0.95,
            fillOpacity: 0.26,
            interactive: false
          }
        ).addTo(map);
      }

      if (cameraPreview &&
          Number.isFinite(cameraPreview.lat) &&
          Number.isFinite(cameraPreview.lon) &&
          Number.isFinite(cameraPreview.bearing) &&
          Number.isFinite(cameraPreview.fovDeg)) {
        const cameraSpread = Math.max(2, Math.min(85, cameraPreview.fovDeg / 2));
        cameraCone = L.polygon(
          conePoints(cameraPreview.lat, cameraPreview.lon, cameraPreview.bearing, cameraSpread, 0.2),
          {
            color: '#22d3ee',
            fillColor: '#22d3ee',
            weight: 2,
            opacity: 0.9,
            fillOpacity: 0.2,
            interactive: false
          }
        ).addTo(map);
      }

      if ((dataChanged && !preserveView) || forceRecenter) {
        const collapsed = collapsedCenterIfAllSame(points);
        if (collapsed) {
          map.setView(collapsed, defaultSinglePointZoom);
        } else if (points.length > 1) {
          map.fitBounds(points, { padding: [30, 30], maxZoom: defaultSinglePointZoom });
        } else if (points.length === 1) {
          map.setView(points[0], defaultSinglePointZoom);
        } else if (navigator.geolocation) {
          navigator.geolocation.getCurrentPosition(
            function(pos) {
              map.setView([pos.coords.latitude, pos.coords.longitude], 6);
            },
            function() {
              map.setView([20, 0], 2);
            }
          );
        } else {
          map.setView([20, 0], 2);
        }
      }

      state.lastFullMissionSig = fullMissionSig;
      state.lastStructureSig = structureSig;
    }
  </script>
</body>
</html>
"""
}
