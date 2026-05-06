import SwiftUI
import WebKit

enum MapTileStyle: String, CaseIterable, Identifiable, Codable {
    case standard
    case satellite
    var id: String { rawValue }
}

struct HeadingPreview {
    var lat: Double
    var lon: Double
    var heading: Double
}

struct CameraPreview {
    var lat: Double
    var lon: Double
    var bearing: Double
    var fovDeg: Double
}

struct OSMMapView: NSViewRepresentable {
    var home: RouteHome?
    var allPathsCoords: [[RouteCoordinate]]
    var selectedPathWaypoints: [RouteWaypoint]
    var selectedWaypointIndex: Int?
    var mapStyle: MapTileStyle
    var recenterNonce: Int
    var headingPreview: HeadingPreview?
    var cameraPreview: CameraPreview?
    var preserveView: Bool
    var isEditingPath: Bool
    var onMapClick: (Double, Double) -> Void
    var onWaypointClick: (Int) -> Void
    var onWaypointMoved: (Int, Double, Double) -> Void
    var onWaypointDelete: (Int) -> Void
    var onPathInsert: (Int, Double, Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMapClick: onMapClick,
            onWaypointClick: onWaypointClick,
            onWaypointMoved: onWaypointMoved,
            onWaypointDelete: onWaypointDelete,
            onPathInsert: onPathInsert
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "mapClick")
        controller.add(context.coordinator, name: "waypointClick")
        controller.add(context.coordinator, name: "waypointMove")
        controller.add(context.coordinator, name: "waypointDelete")
        controller.add(context.coordinator, name: "routeInsert")

        let config = WKWebViewConfiguration()
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let homeJSON: String
        if let home {
            homeJSON = "{\"lat\":\(home.coord.lat),\"lon\":\(home.coord.lon)}"
        } else {
            homeJSON = "null"
        }

        let allPathsJSON = allPathsCoords.map { path in
            "[\(path.map { "{\"lat\":\($0.lat),\"lon\":\($0.lon)}" }.joined(separator: ","))]"
        }.joined(separator: ",")
        let waypointsJSON = selectedPathWaypoints.enumerated().map { idx, wp in
            "{\"idx\":\(idx),\"lat\":\(wp.coord.lat),\"lon\":\(wp.coord.lon)}"
        }.joined(separator: ",")
        let selectedWaypointIndexJS = selectedWaypointIndex.map(String.init) ?? "null"
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
        let js = "setMissionData(\(homeJSON), [\(allPathsJSON)], [\(waypointsJSON)], \(selectedWaypointIndexJS), \"\(mapStyle.rawValue)\", \(recenterNonce), \(headingPreviewJSON), \(cameraPreviewJSON), \(preserveView ? "true" : "false"), \(isEditingPath ? "true" : "false"));"
        context.coordinator.apply(script: js)
    }
}

extension OSMMapView {
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var pendingScript: String?
        private var didFinishInitialLoad = false
        private let onMapClick: (Double, Double) -> Void
        private let onWaypointClick: (Int) -> Void
        private let onWaypointMoved: (Int, Double, Double) -> Void
        private let onWaypointDelete: (Int) -> Void
        private let onPathInsert: (Int, Double, Double) -> Void

        init(
            onMapClick: @escaping (Double, Double) -> Void,
            onWaypointClick: @escaping (Int) -> Void,
            onWaypointMoved: @escaping (Int, Double, Double) -> Void,
            onWaypointDelete: @escaping (Int) -> Void,
            onPathInsert: @escaping (Int, Double, Double) -> Void
        ) {
            self.onMapClick = onMapClick
            self.onWaypointClick = onWaypointClick
            self.onWaypointMoved = onWaypointMoved
            self.onWaypointDelete = onWaypointDelete
            self.onPathInsert = onPathInsert
        }

        func apply(script: String) {
            pendingScript = script
            guard didFinishInitialLoad, let webView else { return }
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishInitialLoad = true
            if let pendingScript {
                webView.evaluateJavaScript(pendingScript, completionHandler: nil)
            }
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
                onPathInsert(idx, lat, lon)
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
    const pathLines = [];
    const state = { lastDataSignature: null, lastRecenterNonce: -1 };

    map.on('click', function(e) {
      window.webkit.messageHandlers.mapClick.postMessage({
        lat: e.latlng.lat,
        lon: e.latlng.lng
      });
    });

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

    function setMissionData(home, allPathsCoords, selectedWaypoints, selectedWaypointIndex, mapStyle, recenterNonce, headingPreview, cameraPreview, preserveView, isEditingPath) {
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
      applyStyle(mapStyle);
      map.getContainer().style.cursor = isEditingPath ? 'pointer' : '';

      const points = [];
      const geometryPaths = (allPathsCoords || []).filter(path => path && path.length > 0);
      const dataSignature = JSON.stringify({
        home: home,
        geometryPaths: geometryPaths
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
        points.push([home.lat, home.lon]);
      }

      if (allPathsCoords && allPathsCoords.length > 0) {
        allPathsCoords.forEach(pathCoords => {
          if (!pathCoords || pathCoords.length === 0) return;
          const latlngs = pathCoords.map(p => [p.lat, p.lon]);
          const idx = pathLines.length;
          const line = L.polyline(latlngs, { color: pathColor(idx), weight: 3 }).addTo(map);
          pathLines.push(line);
          for (const p of latlngs) points.push(p);
        });
      }

      if (isEditingPath && selectedWaypoints && selectedWaypoints.length > 0) {
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
          const isSelected = selectedWaypointIndex === wp.idx;
          const marker = L.marker([wp.lat, wp.lon], {
            draggable: isEditingPath,
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
          if (isEditingPath) {
            marker.on('dragend', function(e) {
              const pos = e.target.getLatLng();
              window.webkit.messageHandlers.waypointMove.postMessage({
                idx: wp.idx,
                lat: pos.lat,
                lon: pos.lng
              });
            });
            marker.on('contextmenu', function() {
              window.webkit.messageHandlers.waypointDelete.postMessage({ idx: wp.idx });
            });
          }
          waypointMarkers.push(marker);
        });
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
        if (points.length > 1) {
          map.fitBounds(points, { padding: [30, 30] });
        } else if (points.length === 1) {
          map.setView(points[0], 14);
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
