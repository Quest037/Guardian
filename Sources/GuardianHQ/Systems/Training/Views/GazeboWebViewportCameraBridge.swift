import Foundation

/// Commands World Builder sends to the embedded gzweb ``WKWebView`` (camera presets).
@MainActor
final class GazeboWebViewportCameraBridge: ObservableObject {
    enum Action: Equatable, Sendable {
        case defaultView
        case birdseye
    }

    @Published private(set) var tick = UUID()
    private(set) var action: Action = .defaultView

    func trigger(_ action: Action) {
        self.action = action
        tick = UUID()
    }

    var javaScriptExpression: String {
        switch action {
        case .defaultView:
            "window.guardianViewer.resetDefaultView()"
        case .birdseye:
            "window.guardianViewer.fitBirdseyeView()"
        }
    }
}
