import Foundation

/// Pushes World Builder obstacle editor state into the embedded gzweb viewer.
@MainActor
final class GazeboWebViewportObstacleBridge: ObservableObject {
    @Published private(set) var tick = UUID()
    @Published var editorActive = false
    @Published var placementActive = false
    @Published var selectedID: String?
    @Published var draft = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
    @Published var obstacles: [TrainingEnvironmentObstacleRecord] = []
    @Published var mapHalfExtentM: Double = 500
    @Published var zones: WorldBuilderZonesSnapshot = .empty
    @Published var deletingID: String?

    func pushEditorState(
        editorActive: Bool,
        placementActive: Bool,
        selectedID: String?,
        draft: TrainingEnvironmentObstacleRecord,
        obstacles: [TrainingEnvironmentObstacleRecord],
        mapHalfExtentM: Double,
        zones: WorldBuilderZonesSnapshot,
        deletingID: String? = nil
    ) {
        self.editorActive = editorActive
        self.placementActive = placementActive
        self.selectedID = selectedID
        self.draft = draft
        self.obstacles = obstacles
        self.mapHalfExtentM = mapHalfExtentM
        self.zones = zones
        self.deletingID = deletingID
        tick = UUID()
    }

    var javaScriptExpression: String {
        let snapshot = WorldBuilderObstaclesEditorSnapshot.make(
            editorActive: editorActive,
            selectedID: selectedID,
            placementActive: placementActive,
            draft: draft,
            obstacles: obstacles,
            mapHalfExtentM: mapHalfExtentM,
            zones: zones,
            deletingID: deletingID
        )
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return "window.guardianViewer?.setObstacleEditorState?.({})"
        }
        let b64 = data.base64EncodedString()
        return """
        (function () {
          const post = (msg) => {
            try {
              window.webkit?.messageHandlers?.guardianObstacles?.postMessage(
                JSON.stringify({ type: 'obstaclePlaceDebug', message: msg })
              );
            } catch (_) { /* bridge not ready */ }
          };
          if (!window.guardianViewer?.setObstacleEditorState) {
            post('expr — guardianViewer.setObstacleEditorState missing');
            return false;
          }
          let state;
          try {
            state = JSON.parse(atob('\(b64)'));
          } catch (err) {
            post('expr — JSON.parse failed: ' + (err?.message || err));
            return false;
          }
          const ok = window.guardianViewer.setObstacleEditorState(state);
          const prep = window.guardianViewer?.prepareObstaclePlacement?.();
          post('expr — setObstacleEditorState returned ' + ok + ' prepare=' + prep);
          return ok;
        })()
        """
    }
}
