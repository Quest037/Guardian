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
        let call: String
        switch action {
        case .defaultView:
            call = "resetDefaultView()"
        case .birdseye:
            call = "fitBirdseyeView()"
        }
        return "(window.guardianViewer?.sceneReady?.() && window.guardianViewer.\(call)) || false"
    }
}
