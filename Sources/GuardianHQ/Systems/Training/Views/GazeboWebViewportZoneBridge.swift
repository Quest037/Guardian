import Foundation

/// Pushes World Builder zone editor state into the embedded gzweb viewer.
@MainActor
final class GazeboWebViewportZoneBridge: ObservableObject {
    @Published private(set) var tick = UUID()
    @Published var placementToolActive = false
    @Published var tapToEditEnabled = false
    @Published var placementKind: WorldBuilderZoneKind = .start
    @Published var zones: WorldBuilderZonesSnapshot = .empty
    @Published var obstacles: [TrainingEnvironmentObstacleRecord] = []

    func pushZones(_ zones: WorldBuilderZonesSnapshot) {
        self.zones = zones
        tick = UUID()
    }

    func syncFromManifest(_ manifest: TrainingEnvironmentManifest?) {
        guard let manifest else {
            zones = .empty
            tick = UUID()
            return
        }
        zones = WorldBuilderZoneManifestSupport.zones(from: manifest)
        tick = UUID()
    }

    /// Pushes placement flags and zone snapshot to the viewer in one update.
    func pushEditorState(
        placementActive: Bool,
        tapToEditEnabled: Bool,
        placementKind: WorldBuilderZoneKind,
        zones: WorldBuilderZonesSnapshot,
        obstacles: [TrainingEnvironmentObstacleRecord],
        mapHalfExtentM: Double,
        maxZoneRadiusM: Double = WorldBuilderZoneState.maxRadiusM
    ) {
        self.placementToolActive = placementActive
        self.tapToEditEnabled = tapToEditEnabled
        self.placementKind = placementKind
        self.zones = zones
        self.obstacles = obstacles
        self.mapHalfExtentM = mapHalfExtentM
        self.maxZoneRadiusM = maxZoneRadiusM
        tick = UUID()
    }

    var mapHalfExtentM: Double = 500
    var maxZoneRadiusM: Double = WorldBuilderZoneState.maxRadiusM

    var javaScriptExpression: String {
        let payload = ZoneEditorJSState(
            placementActive: placementToolActive,
            tapToEditEnabled: tapToEditEnabled,
            placementKind: placementKind.rawValue,
            zones: zones,
            obstacles: obstacles,
            mapHalfExtentM: mapHalfExtentM,
            maxZoneRadiusM: maxZoneRadiusM
        )
        guard let data = try? JSONEncoder().encode(payload) else {
            return "window.guardianViewer?.setZoneEditorState?.({})"
        }
        let b64 = data.base64EncodedString()
        return """
        (function () {
          if (!window.guardianViewer?.setZoneEditorState) return false;
          const state = JSON.parse(atob('\(b64)'));
          return window.guardianViewer.setZoneEditorState(state);
        })()
        """
    }
}

private struct ZoneEditorJSState: Encodable {
    var placementActive: Bool
    var tapToEditEnabled: Bool
    var placementKind: String
    var zones: WorldBuilderZonesSnapshot
    var obstacles: [TrainingEnvironmentObstacleRecord]
    var mapHalfExtentM: Double
    var maxZoneRadiusM: Double
}
