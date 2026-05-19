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
    @Published var deletingID: String?

    func pushEditorState(
        editorActive: Bool,
        placementActive: Bool,
        selectedID: String?,
        draft: TrainingEnvironmentObstacleRecord,
        obstacles: [TrainingEnvironmentObstacleRecord],
        mapHalfExtentM: Double,
        deletingID: String? = nil
    ) {
        self.editorActive = editorActive
        self.placementActive = placementActive
        self.selectedID = selectedID
        self.draft = draft
        self.obstacles = obstacles
        self.mapHalfExtentM = mapHalfExtentM
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
            deletingID: deletingID
        )
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return "window.guardianViewer?.setObstacleEditorState?.({})"
        }
        let b64 = data.base64EncodedString()
        return """
        (function () {
          if (!window.guardianViewer?.setObstacleEditorState) return false;
          const state = JSON.parse(atob('\(b64)'));
          return window.guardianViewer.setObstacleEditorState(state);
        })()
        """
    }
}
