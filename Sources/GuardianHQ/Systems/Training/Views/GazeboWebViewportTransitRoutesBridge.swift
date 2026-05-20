import Foundation

/// Pushes Training transit route polylines (Nav2 / fallback) into the gzweb viewer as thick tubes.
@MainActor
final class GazeboWebViewportTransitRoutesBridge: ObservableObject {
    @Published private(set) var tick = UUID()
    @Published private(set) var routes: [TrainingLabTransitRouteOverlayPath] = []

    func clear() {
        routes = []
        tick = UUID()
    }

    func push(routes: [TrainingLabTransitRouteOverlayPath]) {
        self.routes = routes
        tick = UUID()
    }

    var javaScriptExpression: String {
        let payload = TransitRoutesJSState(routes: routes.map { route in
            TransitRoutesJSRoute(
                id: route.id,
                label: route.squadLabel,
                source: route.pathSource.rawValue,
                points: route.points.map { point in
                    TransitRoutesJSPoint(xM: point.xM, yM: point.yM, zM: point.zM)
                }
            )
        })
        guard let data = try? JSONEncoder().encode(payload) else {
            return """
            (function () {
              if (window.guardianViewer?.setTransitRouteOverlayState) {
                window.guardianViewer.setTransitRouteOverlayState({ routes: [] });
              }
              return false;
            })()
            """
        }
        let b64 = data.base64EncodedString()
        return """
        (function () {
          if (!window.guardianViewer?.setTransitRouteOverlayState) return false;
          const state = JSON.parse(atob('\(b64)'));
          return window.guardianViewer.setTransitRouteOverlayState(state);
        })()
        """
    }
}

private struct TransitRoutesJSState: Encodable {
    var routes: [TransitRoutesJSRoute]
}

private struct TransitRoutesJSRoute: Encodable {
    var id: String
    var label: String
    var source: String
    var points: [TransitRoutesJSPoint]
}

private struct TransitRoutesJSPoint: Encodable {
    var xM: Double
    var yM: Double
    var zM: Double
}
