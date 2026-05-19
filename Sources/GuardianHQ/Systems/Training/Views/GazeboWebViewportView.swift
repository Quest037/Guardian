import AppKit
import SwiftUI
import WebKit

/// Accepts the first click without requiring prior window focus (macOS map placement).
private final class GazeboWebViewportWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Harmonic web visualization (`gzweb` SceneManager) in a ``WKWebView``.
struct GazeboWebViewportView: View {
    let websocketPort: Int
    let gazeboWorldName: String
    let phase: GazeboEmbeddedViewportState.Phase
    var cameraBridge: GazeboWebViewportCameraBridge?
    var cameraCommandTick: UUID?
    var zoneBridge: GazeboWebViewportZoneBridge?
    var zoneCommandTick: UUID?
    var obstacleBridge: GazeboWebViewportObstacleBridge?
    var obstacleCommandTick: UUID?
    var showsCameraDebugHUD: Bool = false
    var groundHalfExtentM: Double = 500
    var onZonesChanged: ((WorldBuilderZonesSnapshot, Bool) -> Void)?
    var onZoneEditRequest: ((WorldBuilderZoneKind) -> Void)?
    var onZoneDeleteRequest: ((WorldBuilderZoneKind) -> Void)?
    var onObstaclesChanged: (([TrainingEnvironmentObstacleRecord], String?, Bool) -> Void)?
    var onObstacleDeleteRequest: ((String) -> Void)?
    var onObstaclePlaceRequest: ((Double, Double) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ZStack {
            GazeboWebViewportRepresentable(
                websocketPort: websocketPort,
                gazeboWorldName: gazeboWorldName,
                cameraBridge: cameraBridge,
                cameraCommandTick: cameraCommandTick,
                zoneBridge: zoneBridge,
                zoneCommandTick: zoneCommandTick,
                obstacleBridge: obstacleBridge,
                obstacleCommandTick: obstacleCommandTick,
                showsCameraDebugHUD: showsCameraDebugHUD,
                groundHalfExtentM: groundHalfExtentM,
                onZonesChanged: onZonesChanged,
                onZoneEditRequest: onZoneEditRequest,
                onZoneDeleteRequest: onZoneDeleteRequest,
                onObstaclesChanged: onObstaclesChanged,
                onObstacleDeleteRequest: onObstacleDeleteRequest,
                onObstaclePlaceRequest: onObstaclePlaceRequest
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
    let zoneBridge: GazeboWebViewportZoneBridge?
    let zoneCommandTick: UUID?
    let obstacleBridge: GazeboWebViewportObstacleBridge?
    let obstacleCommandTick: UUID?
    let showsCameraDebugHUD: Bool
    let groundHalfExtentM: Double
    let onZonesChanged: ((WorldBuilderZonesSnapshot, Bool) -> Void)?
    let onZoneEditRequest: ((WorldBuilderZoneKind) -> Void)?
    let onZoneDeleteRequest: ((WorldBuilderZoneKind) -> Void)?
    let onObstaclesChanged: (([TrainingEnvironmentObstacleRecord], String?, Bool) -> Void)?
    let onObstacleDeleteRequest: ((String) -> Void)?
    let onObstaclePlaceRequest: ((Double, Double) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onZonesChanged: onZonesChanged,
            onZoneEditRequest: onZoneEditRequest,
            onZoneDeleteRequest: onZoneDeleteRequest,
            onObstaclesChanged: onObstaclesChanged,
            onObstacleDeleteRequest: onObstacleDeleteRequest,
            onObstaclePlaceRequest: onObstaclePlaceRequest
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        if #available(macOS 11.0, *) {
            config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        }
        config.userContentController.add(context.coordinator, name: Coordinator.zonesMessageHandlerName)
        config.userContentController.add(context.coordinator, name: Coordinator.obstaclesMessageHandlerName)

        let webView = GazeboWebViewportWebView(frame: .zero, configuration: config)
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
            context.coordinator.lastZoneTick = nil
            context.coordinator.lastObstacleTick = nil
        } else if context.coordinator.loadedCameraDebug != showsCameraDebugHUD {
            context.coordinator.loadedCameraDebug = showsCameraDebugHUD
            syncCameraDebugHUD(on: webView, enabled: showsCameraDebugHUD)
        }

        if let zoneBridge, let tick = zoneCommandTick,
           context.coordinator.lastZoneTick != tick {
            context.coordinator.lastZoneTick = tick
            dispatchZoneState(on: webView, bridge: zoneBridge, attempt: 0)
        }

        if let obstacleBridge, let tick = obstacleCommandTick,
           context.coordinator.lastObstacleTick != tick {
            context.coordinator.lastObstacleTick = tick
            dispatchObstacleState(on: webView, bridge: obstacleBridge, attempt: 0)
        }

        guard let cameraBridge, let tick = cameraCommandTick else { return }
        guard context.coordinator.lastCameraTick != tick else { return }
        context.coordinator.lastCameraTick = tick
        dispatchCameraCommand(on: webView, bridge: cameraBridge, attempt: 0)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: Coordinator.zonesMessageHandlerName)
        controller.removeScriptMessageHandler(forName: Coordinator.obstaclesMessageHandlerName)
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

    private func dispatchZoneState(
        on webView: WKWebView,
        bridge: GazeboWebViewportZoneBridge,
        attempt: Int
    ) {
        let expression = bridge.javaScriptExpression
        webView.evaluateJavaScript(expression) { result, error in
            if error == nil, let ok = result as? Bool, ok { return }
            guard attempt < 48 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                dispatchZoneState(on: webView, bridge: bridge, attempt: attempt + 1)
            }
        }
    }

    private func dispatchObstacleState(
        on webView: WKWebView,
        bridge: GazeboWebViewportObstacleBridge,
        attempt: Int
    ) {
        let expression = bridge.javaScriptExpression
        webView.evaluateJavaScript(expression) { result, error in
            if error == nil, let ok = result as? Bool, ok { return }
            guard attempt < 48 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                dispatchObstacleState(on: webView, bridge: bridge, attempt: attempt + 1)
            }
        }
    }

    private func dispatchCameraCommand(
        on webView: WKWebView,
        bridge: GazeboWebViewportCameraBridge,
        attempt: Int
    ) {
        let expression = bridge.javaScriptExpression
        webView.evaluateJavaScript(expression) { result, error in
            if error == nil, let ok = result as? Bool, ok { return }
            guard attempt < 48 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                dispatchCameraCommand(on: webView, bridge: bridge, attempt: attempt + 1)
            }
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        static let zonesMessageHandlerName = "guardianZones"
        static let obstaclesMessageHandlerName = "guardianObstacles"

        weak var webView: WKWebView?
        var loadedPort: Int?
        var loadedWorldName: String?
        var loadedGroundHalf: Double?
        var loadedCameraDebug: Bool?
        var lastCameraTick: UUID?
        var lastZoneTick: UUID?
        var lastObstacleTick: UUID?
        private let onZonesChanged: ((WorldBuilderZonesSnapshot, Bool) -> Void)?
        private let onZoneEditRequest: ((WorldBuilderZoneKind) -> Void)?
        private let onZoneDeleteRequest: ((WorldBuilderZoneKind) -> Void)?
        private let onObstaclesChanged: (([TrainingEnvironmentObstacleRecord], String?, Bool) -> Void)?
        private let onObstacleDeleteRequest: ((String) -> Void)?
        private let onObstaclePlaceRequest: ((Double, Double) -> Void)?

        init(
            onZonesChanged: ((WorldBuilderZonesSnapshot, Bool) -> Void)?,
            onZoneEditRequest: ((WorldBuilderZoneKind) -> Void)?,
            onZoneDeleteRequest: ((WorldBuilderZoneKind) -> Void)?,
            onObstaclesChanged: (([TrainingEnvironmentObstacleRecord], String?, Bool) -> Void)?,
            onObstacleDeleteRequest: ((String) -> Void)?,
            onObstaclePlaceRequest: ((Double, Double) -> Void)?
        ) {
            self.onZonesChanged = onZonesChanged
            self.onZoneEditRequest = onZoneEditRequest
            self.onZoneDeleteRequest = onZoneDeleteRequest
            self.onObstaclesChanged = onObstaclesChanged
            self.onObstacleDeleteRequest = onObstacleDeleteRequest
            self.onObstaclePlaceRequest = onObstaclePlaceRequest
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let raw = message.body as? String,
                  let data = raw.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(ViewportMessageEnvelope.self, from: data) else { return }
            Task { @MainActor in
                switch message.name {
                case Self.zonesMessageHandlerName:
                    switch envelope.type {
                    case "zonesChanged":
                        guard let zones = envelope.zones else { return }
                        onZonesChanged?(zones, envelope.outOfBounds ?? false)
                    case "zoneEditRequest":
                        guard let kind = envelope.zoneKind else { return }
                        onZoneEditRequest?(kind)
                    case "deleteZoneRequest":
                        guard let kind = envelope.zoneKind else { return }
                        onZoneDeleteRequest?(kind)
                    default:
                        break
                    }
                case Self.obstaclesMessageHandlerName:
                    switch envelope.type {
                    case "obstaclesChanged":
                        onObstaclesChanged?(
                            envelope.obstacles ?? [],
                            envelope.selectedID,
                            envelope.outOfBounds ?? false
                        )
                    case "deleteObstacleRequest":
                        if let id = envelope.obstacleID {
                            onObstacleDeleteRequest?(id)
                        }
                    case "placeObstacle":
                        if let x = envelope.centerXM, let y = envelope.centerYM {
                            onObstaclePlaceRequest?(x, y)
                        }
                    default:
                        break
                    }
                default:
                    break
                }
            }
        }
    }
}

private struct ViewportMessageEnvelope: Decodable {
    var type: String
    var kind: String?
    var zones: WorldBuilderZonesSnapshot?
    var obstacles: [TrainingEnvironmentObstacleRecord]?
    var selectedID: String?
    var obstacleID: String?
    var centerXM: Double?
    var centerYM: Double?
    var outOfBounds: Bool?

    var zoneKind: WorldBuilderZoneKind? {
        guard let kind else { return nil }
        return WorldBuilderZoneKind(rawValue: kind)
    }
}
