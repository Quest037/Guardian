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
    var formationSlotsBridge: GazeboWebViewportFormationSlotsBridge?
    var formationSlotsCommandTick: UUID?
    var transitRoutesBridge: GazeboWebViewportTransitRoutesBridge?
    var transitRoutesCommandTick: UUID?
    var showsCameraDebugHUD: Bool = false
    var groundHalfExtentM: Double = 500
    var orbitMinDistanceM: Double = 50
    var onZonesChanged: ((WorldBuilderZonesSnapshot, Bool) -> Void)?
    var onZoneEditRequest: ((WorldBuilderZoneKind) -> Void)?
    var onZoneDeleteRequest: ((WorldBuilderZoneKind) -> Void)?
    var onObstaclesChanged: (([TrainingEnvironmentObstacleRecord], String?, Bool) -> Void)?
    var onObstacleDeleteRequest: ((String) -> Void)?
    var onObstaclePlaceRequest: ((Double, Double) -> Void)?
    var onObstaclePlaceDebug: ((String) -> Void)?
    var onFormationSlotGroupMoved: ((UUID, TrainingLabFormationSlotGeometry.ZonePhase, Double, Double, Double, Bool) -> Void)?
    var onFormationSlotSelected: ((UUID?) -> Void)?
    var onFormationSlotDebug: ((String) -> Void)?

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
                formationSlotsBridge: formationSlotsBridge,
                formationSlotsCommandTick: formationSlotsCommandTick,
                transitRoutesBridge: transitRoutesBridge,
                transitRoutesCommandTick: transitRoutesCommandTick,
                showsCameraDebugHUD: showsCameraDebugHUD,
                groundHalfExtentM: groundHalfExtentM,
                orbitMinDistanceM: orbitMinDistanceM,
                onZonesChanged: onZonesChanged,
                onZoneEditRequest: onZoneEditRequest,
                onZoneDeleteRequest: onZoneDeleteRequest,
                onObstaclesChanged: onObstaclesChanged,
                onObstacleDeleteRequest: onObstacleDeleteRequest,
                onObstaclePlaceRequest: onObstaclePlaceRequest,
                onObstaclePlaceDebug: onObstaclePlaceDebug,
                onFormationSlotGroupMoved: onFormationSlotGroupMoved,
                onFormationSlotSelected: onFormationSlotSelected,
                onFormationSlotDebug: onFormationSlotDebug
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
    let formationSlotsBridge: GazeboWebViewportFormationSlotsBridge?
    let formationSlotsCommandTick: UUID?
    let transitRoutesBridge: GazeboWebViewportTransitRoutesBridge?
    let transitRoutesCommandTick: UUID?
    let showsCameraDebugHUD: Bool
    let groundHalfExtentM: Double
    let orbitMinDistanceM: Double
    let onZonesChanged: ((WorldBuilderZonesSnapshot, Bool) -> Void)?
    let onZoneEditRequest: ((WorldBuilderZoneKind) -> Void)?
    let onZoneDeleteRequest: ((WorldBuilderZoneKind) -> Void)?
    let onObstaclesChanged: (([TrainingEnvironmentObstacleRecord], String?, Bool) -> Void)?
    let onObstacleDeleteRequest: ((String) -> Void)?
    let onObstaclePlaceRequest: ((Double, Double) -> Void)?
    let onObstaclePlaceDebug: ((String) -> Void)?
    let onFormationSlotGroupMoved: ((UUID, TrainingLabFormationSlotGeometry.ZonePhase, Double, Double, Double, Bool) -> Void)?
    let onFormationSlotSelected: ((UUID?) -> Void)?
    let onFormationSlotDebug: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onZonesChanged: onZonesChanged,
            onZoneEditRequest: onZoneEditRequest,
            onZoneDeleteRequest: onZoneDeleteRequest,
            onObstaclesChanged: onObstaclesChanged,
            onObstacleDeleteRequest: onObstacleDeleteRequest,
            onObstaclePlaceRequest: onObstaclePlaceRequest,
            onObstaclePlaceDebug: onObstaclePlaceDebug,
            onFormationSlotGroupMoved: onFormationSlotGroupMoved,
            onFormationSlotSelected: onFormationSlotSelected,
            onFormationSlotDebug: onFormationSlotDebug
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
        config.userContentController.add(context.coordinator, name: Coordinator.formationSlotsMessageHandlerName)

        let webView = GazeboWebViewportWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif
        context.coordinator.webView = webView
        reload(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedPort != websocketPort
            || context.coordinator.loadedWorldName != gazeboWorldName
            || context.coordinator.loadedGroundHalf != groundHalfExtentM
            || context.coordinator.loadedOrbitMinDistance != orbitMinDistanceM {
            reload(webView: webView)
            context.coordinator.loadedPort = websocketPort
            context.coordinator.loadedWorldName = gazeboWorldName
            context.coordinator.loadedGroundHalf = groundHalfExtentM
            context.coordinator.loadedOrbitMinDistance = orbitMinDistanceM
            context.coordinator.loadedCameraDebug = showsCameraDebugHUD
            context.coordinator.lastCameraTick = nil
            context.coordinator.lastZoneTick = nil
            context.coordinator.lastObstacleTick = nil
            context.coordinator.lastFormationSlotsTick = nil
            context.coordinator.lastTransitRoutesTick = nil
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

        if let formationSlotsBridge, let tick = formationSlotsCommandTick,
           context.coordinator.lastFormationSlotsTick != tick {
            context.coordinator.lastFormationSlotsTick = tick
            dispatchFormationSlotsState(on: webView, bridge: formationSlotsBridge, attempt: 0)
        }

        if let transitRoutesBridge, let tick = transitRoutesCommandTick,
           context.coordinator.lastTransitRoutesTick != tick {
            context.coordinator.lastTransitRoutesTick = tick
            dispatchTransitRoutesState(on: webView, bridge: transitRoutesBridge, attempt: 0)
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
        controller.removeScriptMessageHandler(forName: Coordinator.formationSlotsMessageHandlerName)
    }

    private func dispatchFormationSlotsState(
        on webView: WKWebView,
        bridge: GazeboWebViewportFormationSlotsBridge,
        attempt: Int
    ) {
        let expression = bridge.javaScriptExpression
        webView.evaluateJavaScript(expression) { result, error in
            if error == nil, Self.javaScriptBool(result) { return }
            guard attempt < 48 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                dispatchFormationSlotsState(on: webView, bridge: bridge, attempt: attempt + 1)
            }
        }
    }

    private func dispatchTransitRoutesState(
        on webView: WKWebView,
        bridge: GazeboWebViewportTransitRoutesBridge,
        attempt: Int
    ) {
        let expression = bridge.javaScriptExpression
        webView.evaluateJavaScript(expression) { result, error in
            if error == nil, Self.javaScriptBool(result) { return }
            guard attempt < 48 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                dispatchTransitRoutesState(on: webView, bridge: bridge, attempt: attempt + 1)
            }
        }
    }

    private func reload(webView: WKWebView) {
        guard let base = GuardianBundledResourceLocator.gazeboWebViewerHTMLURL() else {
            let html = """
            <html><body style='background:#222;color:#ccc;font-family:-apple-system,sans-serif;padding:16px'>
            <p>Gazebo web viewer assets are missing from this build.</p>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
            return
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "port", value: "\(websocketPort)"),
            URLQueryItem(name: "world", value: gazeboWorldName),
            URLQueryItem(name: "groundHalf", value: String(format: "%.3f", groundHalfExtentM)),
            URLQueryItem(name: "orbitMinDistance", value: String(format: "%.2f", orbitMinDistanceM)),
        ]
        if showsCameraDebugHUD {
            queryItems.append(URLQueryItem(name: "cameraDebug", value: "1"))
        }
        // Merge query onto the file URL directly — empty `URLComponents().url(relativeTo:)`
        // can drop params in some WebKit loads; `location.search` may still be empty on file://.
        let query: URL
        if var components = URLComponents(url: base, resolvingAgainstBaseURL: false) {
            components.queryItems = queryItems
            query = components.url ?? base
        } else {
            query = base
        }
        let gazeboWebRoot =
            GuardianBundledResourceLocator.trainingSimulationResourceBundles
                .compactMap(\.resourceURL)
                .first { url in
                    FileManager.default.fileExists(
                        atPath: url.appendingPathComponent("dist", isDirectory: true).path
                    )
                }
            ?? base.deletingLastPathComponent()
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

    private static func javaScriptBool(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    private func dispatchObstacleState(
        on webView: WKWebView,
        bridge: GazeboWebViewportObstacleBridge,
        attempt: Int
    ) {
        let expression = bridge.javaScriptExpression
        let placeDebug = onObstaclePlaceDebug
        if attempt == 0 {
            placeDebug?(
                "bridge dispatch editor=\(bridge.editorActive) placement=\(bridge.placementActive) obstacles=\(bridge.obstacles.count)"
            )
        }
        webView.evaluateJavaScript(expression) { result, error in
            let ok = Self.javaScriptBool(result)
            if error == nil, ok {
                if attempt > 0 {
                    placeDebug?("bridge setObstacleEditorState ok (attempt \(attempt + 1))")
                }
                return
            }
            guard attempt < 48 else {
                let errText = error?.localizedDescription ?? "none"
                let resultText = String(describing: result)
                placeDebug?(
                    "bridge setObstacleEditorState failed after 48 tries error=\(errText) result=\(resultText) parsedOk=\(ok)"
                )
                return
            }
            if attempt == 0 || attempt == 5 || attempt == 11 {
                let errText = error?.localizedDescription ?? "none"
                placeDebug?(
                    "bridge retry \(attempt + 1) error=\(errText) result=\(String(describing: result)) parsedOk=\(ok)"
                )
            }
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
        static let formationSlotsMessageHandlerName = "guardianFormationSlots"

        weak var webView: WKWebView?
        var loadedPort: Int?
        var loadedWorldName: String?
        var loadedGroundHalf: Double?
        var loadedOrbitMinDistance: Double?
        var loadedCameraDebug: Bool?
        var lastCameraTick: UUID?
        var lastZoneTick: UUID?
        var lastObstacleTick: UUID?
        var lastFormationSlotsTick: UUID?
        var lastTransitRoutesTick: UUID?
        private let onZonesChanged: ((WorldBuilderZonesSnapshot, Bool) -> Void)?
        private let onZoneEditRequest: ((WorldBuilderZoneKind) -> Void)?
        private let onZoneDeleteRequest: ((WorldBuilderZoneKind) -> Void)?
        private let onObstaclesChanged: (([TrainingEnvironmentObstacleRecord], String?, Bool) -> Void)?
        private let onObstacleDeleteRequest: ((String) -> Void)?
        private let onObstaclePlaceRequest: ((Double, Double) -> Void)?
        private let onObstaclePlaceDebug: ((String) -> Void)?
        private let onFormationSlotGroupMoved: ((UUID, TrainingLabFormationSlotGeometry.ZonePhase, Double, Double, Double, Bool) -> Void)?
        private let onFormationSlotSelected: ((UUID?) -> Void)?
        private let onFormationSlotDebug: ((String) -> Void)?

        init(
            onZonesChanged: ((WorldBuilderZonesSnapshot, Bool) -> Void)?,
            onZoneEditRequest: ((WorldBuilderZoneKind) -> Void)?,
            onZoneDeleteRequest: ((WorldBuilderZoneKind) -> Void)?,
            onObstaclesChanged: (([TrainingEnvironmentObstacleRecord], String?, Bool) -> Void)?,
            onObstacleDeleteRequest: ((String) -> Void)?,
            onObstaclePlaceRequest: ((Double, Double) -> Void)?,
            onObstaclePlaceDebug: ((String) -> Void)? = nil,
            onFormationSlotGroupMoved: ((UUID, TrainingLabFormationSlotGeometry.ZonePhase, Double, Double, Double, Bool) -> Void)? = nil,
            onFormationSlotSelected: ((UUID?) -> Void)? = nil,
            onFormationSlotDebug: ((String) -> Void)? = nil
        ) {
            self.onZonesChanged = onZonesChanged
            self.onZoneEditRequest = onZoneEditRequest
            self.onZoneDeleteRequest = onZoneDeleteRequest
            self.onObstaclesChanged = onObstaclesChanged
            self.onObstacleDeleteRequest = onObstacleDeleteRequest
            self.onObstaclePlaceRequest = onObstaclePlaceRequest
            self.onObstaclePlaceDebug = onObstaclePlaceDebug
            self.onFormationSlotGroupMoved = onFormationSlotGroupMoved
            self.onFormationSlotSelected = onFormationSlotSelected
            self.onFormationSlotDebug = onFormationSlotDebug
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let raw = message.body as? String,
                  let data = raw.data(using: .utf8) else {
                onObstaclePlaceDebug?("bridge decode failed — message body not a string")
                return
            }
            guard let envelope = try? JSONDecoder().decode(ViewportMessageEnvelope.self, from: data) else {
                if message.name == Self.obstaclesMessageHandlerName {
                    onObstaclePlaceDebug?("bridge decode failed — invalid JSON envelope")
                }
                return
            }
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
                case Self.formationSlotsMessageHandlerName:
                    switch envelope.type {
                    case "formationSlotGroupMoved":
                        guard let squadID = envelope.squadUUID,
                              let phase = envelope.zonePhase,
                              let centerXM = envelope.centerXM,
                              let centerYM = envelope.centerYM,
                              let headingDeg = envelope.headingDeg
                        else { return }
                        onFormationSlotGroupMoved?(
                            squadID,
                            phase,
                            centerXM,
                            centerYM,
                            headingDeg,
                            envelope.outOfBounds ?? false
                        )
                    case "formationSlotSelected":
                        onFormationSlotSelected?(envelope.squadUUID)
                    case "formationSlotDebug":
                        if let message = envelope.message {
                            onFormationSlotDebug?(message)
                        }
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
                        } else {
                            onObstaclePlaceDebug?("bridge placeObstacle — missing centerXM/centerYM")
                        }
                    case "obstaclePlaceDebug":
                        if let message = envelope.message {
                            onObstaclePlaceDebug?(message)
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
    var squadID: String?
    var centerXM: Double?
    var centerYM: Double?
    var headingDeg: Double?
    var outOfBounds: Bool?
    var message: String?

    var zoneKind: WorldBuilderZoneKind? {
        guard let kind else { return nil }
        return WorldBuilderZoneKind(rawValue: kind)
    }

    var squadUUID: UUID? {
        guard let squadID else { return nil }
        return UUID(uuidString: squadID)
    }

    var zonePhase: TrainingLabFormationSlotGeometry.ZonePhase? {
        guard let kind else { return nil }
        return TrainingLabFormationSlotGeometry.ZonePhase(rawValue: kind)
    }
}
