import SwiftUI
import WebKit

enum MapTileStyle: String, CaseIterable, Identifiable {
    case standard
    case satellite
    var id: String { rawValue }
}

struct OSMMapView: NSViewRepresentable {
    var home: RouteHome?
    var allPathCoords: [RouteCoordinate]
    var selectedPathWaypoints: [RouteWaypoint]
    var mapStyle: MapTileStyle
    var onMapClick: (Double, Double) -> Void
    var onWaypointClick: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMapClick: onMapClick, onWaypointClick: onWaypointClick)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "mapClick")
        controller.add(context.coordinator, name: "waypointClick")

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

        let allCoordsJSON = allPathCoords
            .map { "{\"lat\":\($0.lat),\"lon\":\($0.lon)}" }
            .joined(separator: ",")
        let waypointsJSON = selectedPathWaypoints.enumerated().map { idx, wp in
            "{\"idx\":\(idx),\"lat\":\(wp.coord.lat),\"lon\":\(wp.coord.lon)}"
        }.joined(separator: ",")
        let js = "setMissionData(\(homeJSON), [\(allCoordsJSON)], [\(waypointsJSON)], \"\(mapStyle.rawValue)\");"
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

        init(
            onMapClick: @escaping (Double, Double) -> Void,
            onWaypointClick: @escaping (Int) -> Void
        ) {
            self.onMapClick = onMapClick
            self.onWaypointClick = onWaypointClick
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
    var pathLine = null;
    let state = { lastDataSignature: null };

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

    function setMissionData(home, allPathCoords, selectedWaypoints, mapStyle) {
      if (homeMarker) { map.removeLayer(homeMarker); homeMarker = null; }
      if (pathLine) { map.removeLayer(pathLine); pathLine = null; }
      while (waypointMarkers.length > 0) {
        const m = waypointMarkers.pop();
        map.removeLayer(m);
      }
      applyStyle(mapStyle);

      const points = [];
      const dataSignature = JSON.stringify({
        home: home,
        allPathCoords: allPathCoords
      });
      const dataChanged = state.lastDataSignature !== dataSignature;
      state.lastDataSignature = dataSignature;

      if (home) {
        homeMarker = L.circleMarker([home.lat, home.lon], {
          radius: 8,
          color: '#3b82f6',
          fillColor: '#3b82f6',
          fillOpacity: 0.9
        }).addTo(map);
        points.push([home.lat, home.lon]);
      }

      if (allPathCoords && allPathCoords.length > 0) {
        const latlngs = allPathCoords.map(p => [p.lat, p.lon]);
        pathLine = L.polyline(latlngs, { color: '#38bdf8', weight: 3 }).addTo(map);
        for (const p of latlngs) points.push(p);
      }

      if (selectedWaypoints && selectedWaypoints.length > 0) {
        selectedWaypoints.forEach((wp) => {
          const marker = L.circleMarker([wp.lat, wp.lon], {
            radius: 6,
            color: '#f59e0b',
            fillColor: '#f59e0b',
            fillOpacity: 0.9
          }).addTo(map);
          marker.on('click', function() {
            window.webkit.messageHandlers.waypointClick.postMessage({ idx: wp.idx });
          });
          waypointMarkers.push(marker);
        });
      }

      if (dataChanged) {
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
