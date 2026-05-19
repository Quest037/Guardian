import SwiftUI
import WebKit

/// Harmonic web visualization (`gzweb` SceneManager) in a ``WKWebView``.
struct GazeboWebViewportView: View {
    let websocketPort: Int
    let gazeboWorldName: String
    let phase: GazeboEmbeddedViewportState.Phase
    var cameraBridge: GazeboWebViewportCameraBridge?
    var cameraCommandTick: UUID?
    var showsCameraDebugHUD: Bool = false
    var groundHalfExtentM: Double = 500

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ZStack {
            GazeboWebViewportRepresentable(
                websocketPort: websocketPort,
                gazeboWorldName: gazeboWorldName,
                cameraBridge: cameraBridge,
                cameraCommandTick: cameraCommandTick,
                showsCameraDebugHUD: showsCameraDebugHUD,
                groundHalfExtentM: groundHalfExtentM
            )

            if case .failed(let message) = phase {
                failedOverlay(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedOverlay(_ text: String) -> some View {
        ZStack {
            theme.backgroundRaised.opacity(0.92)
            Text(text)
                .font(GuardianTypography.Scale.body.font())
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(GuardianSpacing.lg)
        }
    }
}

private struct GazeboWebViewportRepresentable: NSViewRepresentable {
    let websocketPort: Int
    let gazeboWorldName: String
    let cameraBridge: GazeboWebViewportCameraBridge?
    let cameraCommandTick: UUID?
    let showsCameraDebugHUD: Bool
    let groundHalfExtentM: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        if #available(macOS 11.0, *) {
            config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        reload(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedPort != websocketPort
            || context.coordinator.loadedWorldName != gazeboWorldName
            || context.coordinator.loadedGroundHalf != groundHalfExtentM {
            reload(webView: webView)
            context.coordinator.loadedPort = websocketPort
            context.coordinator.loadedWorldName = gazeboWorldName
            context.coordinator.loadedGroundHalf = groundHalfExtentM
            context.coordinator.loadedCameraDebug = showsCameraDebugHUD
            context.coordinator.lastCameraTick = nil
        } else if context.coordinator.loadedCameraDebug != showsCameraDebugHUD {
            context.coordinator.loadedCameraDebug = showsCameraDebugHUD
            syncCameraDebugHUD(on: webView, enabled: showsCameraDebugHUD)
        }

        guard let cameraBridge, let tick = cameraCommandTick else { return }
        guard context.coordinator.lastCameraTick != tick else { return }
        context.coordinator.lastCameraTick = tick
        dispatchCameraCommand(on: webView, bridge: cameraBridge, attempt: 0)
    }

    private func reload(webView: WKWebView) {
        guard let base = Bundle.module.url(
            forResource: "guardian_viewer",
            withExtension: "html",
            subdirectory: "GazeboWeb"
        ) else {
            let html = """
            <html><body style='background:#222;color:#ccc;font-family:-apple-system,sans-serif;padding:16px'>
            <p>Gazebo web viewer assets are missing from this build.</p>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
            return
        }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "port", value: "\(websocketPort)"),
            URLQueryItem(name: "world", value: gazeboWorldName),
            URLQueryItem(name: "groundHalf", value: String(format: "%.3f", groundHalfExtentM)),
        ]
        if showsCameraDebugHUD {
            components.queryItems?.append(URLQueryItem(name: "cameraDebug", value: "1"))
        }
        let query = components.url(relativeTo: base) ?? base
        let gazeboWebRoot = base.deletingLastPathComponent()
        webView.loadFileURL(query, allowingReadAccessTo: gazeboWebRoot)
    }

    private func syncCameraDebugHUD(on webView: WKWebView, enabled: Bool) {
        let flag = enabled ? "true" : "false"
        webView.evaluateJavaScript("window.guardianViewer?.setCameraDebugEnabled(\(flag))")
    }

    private func dispatchCameraCommand(
        on webView: WKWebView,
        bridge: GazeboWebViewportCameraBridge,
        attempt: Int
    ) {
        let expression = bridge.javaScriptExpression
        webView.evaluateJavaScript(expression) { result, error in
            if error == nil, let ok = result as? Bool, ok { return }
            guard attempt < 24 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                dispatchCameraCommand(on: webView, bridge: bridge, attempt: attempt + 1)
            }
        }
    }

    final class Coordinator {
        weak var webView: WKWebView?
        var loadedPort: Int?
        var loadedWorldName: String?
        var loadedGroundHalf: Double?
        var loadedCameraDebug: Bool?
        var lastCameraTick: UUID?
    }
}
