import SwiftUI
import WebKit

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
}

struct OSMMapView: NSViewRepresentable {
    var home: RouteHome?
    var allTasksCoords: [[RouteCoordinate]]
    var selectedTaskWaypoints: [RouteWaypoint]
    var selectedWaypointIndex: Int?
    var vehicleMarkers: [MapVehicleMarker]
    var mapStyle: MapTileStyle
    var recenterNonce: Int
    var headingPreview: HeadingPreview?
    var cameraPreview: CameraPreview?
    var followedVehicleMarkerID: String?
    var preserveView: Bool
    var isEditingTask: Bool
    var contextMenuPolicy: GuardianMapContextMenuPolicy
    var onMapClick: (Double, Double) -> Void
    var onVehicleMarkerMoved: (String, Double, Double) -> Void
    var onContextAction: (GuardianMapContextActionEvent) -> Void
    var onWaypointClick: (Int) -> Void
    var onWaypointMoved: (Int, Double, Double) -> Void
    var onWaypointDelete: (Int) -> Void
    var onTaskMapInsert: (Int, Double, Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMapClick: onMapClick,
            onVehicleMarkerMoved: onVehicleMarkerMoved,
            onContextAction: onContextAction,
            onWaypointClick: onWaypointClick,
            onWaypointMoved: onWaypointMoved,
            onWaypointDelete: onWaypointDelete,
            onTaskMapInsert: onTaskMapInsert
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "mapClick")
        controller.add(context.coordinator, name: "vehicleMove")
        controller.add(context.coordinator, name: "waypointClick")
        controller.add(context.coordinator, name: "waypointMove")
        controller.add(context.coordinator, name: "waypointDelete")
        controller.add(context.coordinator, name: "routeInsert")
        controller.add(context.coordinator, name: "markerContextAction")

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
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let homeJSON: String
        if let home {
            homeJSON = "{\"lat\":\(home.coord.lat),\"lon\":\(home.coord.lon)}"
        } else {
            homeJSON = "null"
        }

        let allPathsJSON = allTasksCoords.map { path in
            "[\(path.map { "{\"lat\":\($0.lat),\"lon\":\($0.lon)}" }.joined(separator: ","))]"
        }.joined(separator: ",")
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
            return "{\"id\":\(Self.jsStringLiteral(marker.id)),\"lat\":\(marker.lat),\"lon\":\(marker.lon),\"label\":\(Self.jsStringLiteral(marker.label)),\"color\":\(Self.jsStringLiteral(marker.colorHex)),\"image\":\(imageJSON),\"showLabel\":\(marker.showLabel ? "true" : "false"),\"selected\":\(marker.selected ? "true" : "false"),\"draggable\":\(marker.draggable ? "true" : "false"),\(headingJSON)}"
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
        let contextMenuPolicyJSON = """
        {"vehicleActions":[\(contextMenuPolicy.vehicleActions.map { Self.jsStringLiteral($0.rawValue) }.joined(separator: ","))],"waypointActions":[\(contextMenuPolicy.waypointActions.map { Self.jsStringLiteral($0.rawValue) }.joined(separator: ","))],"homeActions":[\(contextMenuPolicy.homeActions.map { Self.jsStringLiteral($0.rawValue) }.joined(separator: ","))]}
        """
        let js = "setMissionData(\(homeJSON), [\(allPathsJSON)], [\(waypointsJSON)], \(selectedWaypointIndexJS), [\(vehicleMarkersJSON)], \"\(mapStyle.rawValue)\", \(recenterNonce), \(headingPreviewJSON), \(cameraPreviewJSON), \(followedVehicleMarkerIDJSON), \(contextMenuPolicyJSON), \(preserveView ? "true" : "false"), \(isEditingTask ? "true" : "false"));"
        context.coordinator.queueMissionUpdate(script: js)
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
        private let onMapClick: (Double, Double) -> Void
        private let onVehicleMarkerMoved: (String, Double, Double) -> Void
        private let onContextAction: (GuardianMapContextActionEvent) -> Void
        private let onWaypointClick: (Int) -> Void
        private let onWaypointMoved: (Int, Double, Double) -> Void
        private let onWaypointDelete: (Int) -> Void
        private let onTaskMapInsert: (Int, Double, Double) -> Void

        init(
            onMapClick: @escaping (Double, Double) -> Void,
            onVehicleMarkerMoved: @escaping (String, Double, Double) -> Void,
            onContextAction: @escaping (GuardianMapContextActionEvent) -> Void,
            onWaypointClick: @escaping (Int) -> Void,
            onWaypointMoved: @escaping (Int, Double, Double) -> Void,
            onWaypointDelete: @escaping (Int) -> Void,
            onTaskMapInsert: @escaping (Int, Double, Double) -> Void
        ) {
            self.onMapClick = onMapClick
            self.onVehicleMarkerMoved = onVehicleMarkerMoved
            self.onContextAction = onContextAction
            self.onWaypointClick = onWaypointClick
            self.onWaypointMoved = onWaypointMoved
            self.onWaypointDelete = onWaypointDelete
            self.onTaskMapInsert = onTaskMapInsert
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishInitialLoad = true
            lastAppliedMissionScript = nil
            let script = latestMissionScript ?? pendingScript
            guard let script else { return }
            lastAppliedMissionScript = script
            pendingScript = nil
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "mapClick",
               let payload = message.body as? [String: Any],
               let lat = payload["lat"] as? Double,
               let lon = payload["lon"] as? Double {
                onMapClick(lat, lon)
                return
            }

            if message.name == "waypointClick",
               let payload = message.body as? [String: Any],
               let idx = payload["idx"] as? Int {
                onWaypointClick(idx)
            }

            if message.name == "waypointMove",
               let payload = message.body as? [String: Any],
               let idx = payload["idx"] as? Int,
               let lat = payload["lat"] as? Double,
               let lon = payload["lon"] as? Double {
                onWaypointMoved(idx, lat, lon)
            }

            if message.name == "waypointDelete",
               let payload = message.body as? [String: Any],
               let idx = payload["idx"] as? Int {
                onWaypointDelete(idx)
            }

            if message.name == "routeInsert",
               let payload = message.body as? [String: Any],
               let idx = payload["idx"] as? Int,
               let lat = payload["lat"] as? Double,
               let lon = payload["lon"] as? Double {
                onTaskMapInsert(idx, lat, lon)
            }

            if message.name == "vehicleMove",
               let payload = message.body as? [String: Any],
               let id = payload["id"] as? String,
               let lat = payload["lat"] as? Double,
               let lon = payload["lon"] as? Double {
                onVehicleMarkerMoved(id, lat, lon)
            }

            if message.name == "markerContextAction",
               let payload = message.body as? [String: Any],
               let actionRaw = payload["action"] as? String,
               let markerTypeRaw = payload["markerType"] as? String,
               let action = GuardianMapContextAction(rawValue: actionRaw),
               let markerType = GuardianMapMarkerType(rawValue: markerTypeRaw),
               let lat = payload["lat"] as? Double,
               let lon = payload["lon"] as? Double {
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
    var homeMarker = null;
    var headingCone = null;
    var cameraCone = null;
    const vehicleMarkers = [];
    const pathLines = [];
    const state = { lastDataSignature: null, lastRecenterNonce: -1, lastFullMissionSig: null };
    let contextMenuEl = null;
    let followedVehicleMarkerID = null;
    let contextMenuPolicy = { vehicleActions: [], waypointActions: [], homeActions: [] };

    map.on('click', function(e) {
      hideContextMenu();
      window.webkit.messageHandlers.mapClick.postMessage({
        lat: e.latlng.lat,
        lon: e.latlng.lng
      });
    });
    map.on('movestart zoomstart', hideContextMenu);

    function contextActionTitle(action) {
      switch (action) {
        case 'followVehicle': return 'Follow marker';
        case 'stopFollowingVehicle': return 'Stop following';
        case 'centerMarker': return 'Center map here';
        case 'deleteWaypoint': return 'Delete waypoint';
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

    function setMissionData(home, allTasksCoords, selectedWaypoints, selectedWaypointIndex, missionVehicleMarkers, mapStyle, recenterNonce, headingPreview, cameraPreview, followVehicleMarkerID, menuPolicy, preserveView, isEditingTask) {
      const geometryTasks = (allTasksCoords || []).filter(path => path && path.length > 0);
      const fullMissionSig = JSON.stringify({
        home: home,
        geometryTasks: geometryTasks,
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
        isEditingTask: !!isEditingTask
      });
      if (fullMissionSig === state.lastFullMissionSig) {
        return;
      }
      state.lastFullMissionSig = fullMissionSig;

      followedVehicleMarkerID = followVehicleMarkerID || null;
      contextMenuPolicy = menuPolicy || { vehicleActions: [], waypointActions: [], homeActions: [] };
      if (homeMarker) { map.removeLayer(homeMarker); homeMarker = null; }
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
      while (vehicleMarkers.length > 0) {
        const m = vehicleMarkers.pop();
        map.removeLayer(m);
      }
      applyStyle(mapStyle);
      map.getContainer().style.cursor = isEditingTask ? 'pointer' : '';

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
        homeMarker = L.circleMarker([home.lat, home.lon], {
          radius: 8,
          color: '#3b82f6',
          fillColor: '#3b82f6',
          fillOpacity: 0.9
        }).addTo(map);
        homeMarker.on('contextmenu', function(e) {
          openContextMenu(e, 'home', 'home', home.lat, home.lon);
        });
        points.push([home.lat, home.lon]);
      }

      if (allTasksCoords && allTasksCoords.length > 0) {
        allTasksCoords.forEach(taskCoords => {
          if (!taskCoords || taskCoords.length === 0) return;
          const latlngs = taskCoords.map(p => [p.lat, p.lon]);
          const idx = pathLines.length;
          const line = L.polyline(latlngs, { color: pathColor(idx), weight: 3 }).addTo(map);
          pathLines.push(line);
          for (const p of latlngs) points.push(p);
        });
      }

      if (isEditingTask && selectedWaypoints && selectedWaypoints.length > 0) {
        const selectedLatLngs = selectedWaypoints.map(wp => [wp.lat, wp.lon]);
        if (selectedLatLngs.length > 1) {
          const routeLine = L.polyline(selectedLatLngs, { color: '#ffffff', weight: 3, opacity: 0.25 }).addTo(map);
          routeLine.on('click', function(e) {
            if (e.originalEvent) L.DomEvent.stop(e.originalEvent);
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
          marker.on('click', function() {
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

      if (missionVehicleMarkers && missionVehicleMarkers.length > 0) {
        missionVehicleMarkers.forEach((vm) => {
          if (!Number.isFinite(vm.lat) || !Number.isFinite(vm.lon)) return;
          const size = vm.selected ? 36 : 32;
          const border = vm.selected ? 3 : 2;
          const inner = Math.max(14, size - (border * 2) - 2);
          const ringColor = vm.color || '#94a3b8';
          const headingArrow = Number.isFinite(vm.heading)
            ? `<div style="
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
            ? `<img src="${vm.image}" alt="" style="width:${inner}px;height:${inner}px;border-radius:999px;object-fit:cover;display:block;"/>`
            : `<div style="width:${inner}px;height:${inner}px;border-radius:999px;background:#1f2937;"></div>`;
          const marker = L.marker([vm.lat, vm.lon], {
            draggable: !!vm.draggable,
            title: vm.label || '',
            icon: L.divIcon({
              className: 'mission-vehicle-dot',
              html: `<div style="position:relative;width:${size}px;height:${size}px;">${headingArrow}<div style="width:${size}px;height:${size}px;border-radius:999px;border:${border}px solid ${ringColor};background:#0b0f14;display:flex;align-items:center;justify-content:center;box-shadow:0 0 0 1px rgba(0,0,0,0.55);overflow:hidden;">${imageHTML}</div></div>`,
              iconSize: [size, size],
              iconAnchor: [size / 2, size / 2]
            })
          }).addTo(map);
          if (vm.showLabel && vm.label && vm.selected) {
            marker.bindTooltip(vm.label, { permanent: true, direction: 'top', offset: [0, -10], opacity: 0.95 });
          }
          if (vm.draggable && vm.id) {
            marker.on('dragend', function(e) {
              const pos = e.target.getLatLng();
              window.webkit.messageHandlers.vehicleMove.postMessage({
                id: vm.id,
                lat: pos.lat,
                lon: pos.lng
              });
            });
          }
          marker.on('contextmenu', function(e) {
            openContextMenu(e, 'vehicle', vm.id || null, vm.lat, vm.lon);
          });
          vehicleMarkers.push(marker);
          points.push([vm.lat, vm.lon]);
          // Heading wedge removed for vehicle markers (arrow already shows heading).
        });
      }

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
    }
  </script>
</body>
</html>
"""
}
