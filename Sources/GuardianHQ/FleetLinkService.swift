import AppKit
import Combine
import Foundation

/// Phase of the Python MAVSDK bridge relative to the vehicle on the wire.
enum TelemetryBridgePhase: Equatable {
    /// Bridge process not running or server off.
    case inactive
    /// Bridge process launched; waiting for handshake JSON from Python.
    case connecting
    /// Connected to `mavsdk_server` over gRPC; waiting for a discovered MAVLink system.
    case awaitingVehicle
    /// A system was discovered; telemetry streams are running.
    case live
}

/// Owns persisted fleet link settings, `mavsdk_server`, and the Python MAVSDK bridge (telemetry JSON).
@MainActor
final class FleetLinkService: ObservableObject {
    private static let defaultsKey = "fleetLink.configuration.v1"
    private static let logLineLimit = 80

    @Published private(set) var configuration: FleetLinkConfiguration
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var logLines: [String] = []

    /// Where the Python bridge is in the connect / discover / stream lifecycle.
    @Published private(set) var bridgePhase: TelemetryBridgePhase = .inactive
    /// Best-effort live state for the first vehicle the bridge sees (SITL / hardware).
    @Published private(set) var telemetry: FleetTelemetrySnapshot?
    /// Full merged hub snapshot from every `mavsdk_bridge.py` stream (see `FleetHubVehicleTelemetry`).
    @Published private(set) var hubTelemetry: FleetHubVehicleTelemetry?
    /// Top-bar “Simulate” switch — only meaningful while the server is running; cleared when the server stops.
    @Published private(set) var isSimulateEnabled = false

    private var runner: MavsdkServerRunner?
    private var bridgeRunner: MavsdkBridgeRunner?
    /// Held for removal on teardown; `nonisolated(unsafe)` so `deinit` can unregister without Sendable issues.
    nonisolated(unsafe) private var terminateObserver: NSObjectProtocol?

    init(userDefaults: UserDefaults = .standard) {
        configuration = Self.load(from: userDefaults) ?? .defaults
        // `queue: nil` runs the block synchronously on the thread that posts the notification
        // (main for AppKit quit), so child processes can exit before the app tears down.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.stopServer()
            }
        }
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }

    func applyConfiguration(_ config: FleetLinkConfiguration) {
        configuration = config
        save()
    }

    /// Updates the Simulate switch; no-op if the server is not running.
    func setSimulateEnabled(_ enabled: Bool) {
        guard isRunning else { return }
        isSimulateEnabled = enabled
    }

    /// Starts `mavsdk_server` if not already running. Returns `false` if launch failed (see `lastError`).
    @discardableResult
    func startServer() -> Bool {
        guard !isRunning else { return true }
        lastError = nil
        telemetry = nil
        hubTelemetry = nil
        bridgePhase = .inactive

        let runner = MavsdkServerRunner()
        runner.onLogLine = { [weak self] line in
            guard let self else { return }
            self.appendLog(line)
        }
        runner.onTerminated = { [weak self] code in
            guard let self else { return }
            self.stopPythonBridge()
            self.runner = nil
            self.isRunning = false
            self.isSimulateEnabled = false
            self.bridgePhase = .inactive
            self.telemetry = nil
            self.hubTelemetry = nil
            self.appendLog("mavsdk_server exited (code \(code)).")
        }
        do {
            let mavsdkConfig = Self.mavsdkConfigurationIncludingDefaultPx4SihUdpouts(configuration)
            try runner.start(configuration: mavsdkConfig)
            self.runner = runner
            isRunning = true
            appendLog("Started mavsdk_server (gRPC \(configuration.grpcPort), \(configuration.primaryMavlinkConnectionURL)).")
            schedulePythonBridgeStart()
            return true
        } catch {
            lastError = error.localizedDescription
            runner.onLogLine = nil
            runner.onTerminated = nil
            self.runner = nil
            return false
        }
    }

    func stopServer() {
        isSimulateEnabled = false
        stopPythonBridge()
        guard let runner else { return }
        appendLog("Stopping mavsdk_server…")
        runner.stop()
    }

    /// PX4 SIH GCS MAVLink listens on UDP `18570 + instance` (see `SitlLaunchRecipe.px4SihGcsUdpPort`).
    /// `mavsdk_server` must have matching `udpout://…` args or the Python bridge never sees a vehicle while ArduPilot
    /// (MAVProxy → primary `udpin` port) does. Merge defaults **without persisting** so hardware + sim stay complementary.
    private static func mavsdkConfigurationIncludingDefaultPx4SihUdpouts(_ base: FleetLinkConfiguration) -> FleetLinkConfiguration {
        var c = base
        let maxInstances = 16
        for i in 0..<maxInstances {
            let url = "udpout://127.0.0.1:\(SitlLaunchRecipe.px4SihGcsUdpPort(instance: i))"
            let already = c.additionalMavlinkConnectionURLs.contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == url
            }
            if !already {
                c.additionalMavlinkConnectionURLs.append(url)
            }
        }
        return c
    }

    func clearLog() {
        logLines.removeAll(keepingCapacity: true)
    }

    /// Appends a line to the same log as `mavsdk_server` (used by SITL child processes).
    func appendSimulationLog(_ line: String) {
        appendLog(line)
    }

    /// While **Simulate** is on, drop cached “first vehicle” state when every SITL process has stopped.
    /// MAVSDK does not always tear down the discovered system when `px4` exits, which left stale telemetry
    /// and a phantom Live row after the sim card disappeared.
    func clearStaleVehicleStateWhenNoSitlAlive() {
        guard isSimulateEnabled else { return }
        telemetry = nil
        hubTelemetry = nil
        if bridgePhase == .live {
            bridgePhase = .awaitingVehicle
            appendLog("Simulation vehicle ended — reconnecting telemetry bridge for the next MAVLink system.")
        }
        restartPythonBridgeForFreshMavsdkDiscovery()
    }

    /// Stops and restarts `mavsdk_bridge.py` so `drone.connect()` runs again (avoids stale first-vehicle state after SITL exit).
    private func restartPythonBridgeForFreshMavsdkDiscovery() {
        guard isRunning, bridgeRunner != nil else { return }
        stopPythonBridge()
        schedulePythonBridgeStart()
    }

    private func schedulePythonBridgeStart() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard self.isRunning else { return }
            self.startPythonBridge()
        }
    }

    private func startPythonBridge() {
        guard isRunning, bridgeRunner == nil else { return }
        guard let scriptDir = MavsdkBridgeLocator.bridgeDirectoryURL() else {
            appendLog("MavsdkBridge bundle missing — rebuild the app.")
            lastError = "MavsdkBridge resources not found."
            return
        }

        let bridge = MavsdkBridgeRunner()
        bridge.onStdoutLine = { [weak self] line in
            guard let self else { return }
            self.handleBridgeStdoutLine(line)
        }
        bridge.onStderrLine = { [weak self] line in
            guard let self else { return }
            self.appendLog("[bridge] \(line)")
        }
        bridge.onTerminated = { [weak self] code in
            guard let self else { return }
            self.bridgeRunner = nil
            self.bridgePhase = .inactive
            self.appendLog("mavsdk_bridge.py exited (code \(code)).")
            self.telemetry = nil
            self.hubTelemetry = nil
        }

        do {
            try bridge.start(
                grpcHost: "127.0.0.1",
                grpcPort: configuration.grpcPort,
                scriptDirectory: scriptDir
            )
            bridgeRunner = bridge
            bridgePhase = .connecting
            appendLog("Started mavsdk_bridge.py (MAVSDK-Python).")
        } catch {
            lastError = error.localizedDescription
            appendLog("Could not start bridge: \(error.localizedDescription)")
            bridge.onStdoutLine = nil
            bridge.onStderrLine = nil
            bridge.onTerminated = nil
        }
    }

    private func stopPythonBridge() {
        guard let bridge = bridgeRunner else {
            bridgePhase = .inactive
            telemetry = nil
            hubTelemetry = nil
            return
        }
        appendLog("Stopping mavsdk_bridge.py…")
        bridge.stop()
        // Keep `bridgeRunner` until `onTerminated` runs so the process isn’t orphaned.
    }

    private func handleBridgeStdoutLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let env = try? decoder.decode(BridgeHubEnvelope.self, from: data) else { return }

        var hub = hubTelemetry ?? .empty

        switch env.type {
        case "bridge_listening":
            bridgePhase = .awaitingVehicle
            hub.autopilotStack = .unknown
            appendLog(
                "Bridge connected to MAVSDK (gRPC \(env.host ?? "?"):\(env.port.map(String.init) ?? "?")) — waiting for a MAVLink system on the link."
            )
        case "bridge_ready":
            bridgePhase = .live
            appendLog("Bridge ready — vehicle discovered (gRPC \(env.host ?? "?"):\(env.port.map(String.init) ?? "?")).")
        case "bridge_error":
            let msg = env.message ?? "unknown"
            appendLog("bridge error: \(msg)")
            if msg.contains("missing_mavsdk_python_package") {
                lastError = "Live telemetry couldn’t start. The optional components for this machine may be missing—check the server log or documentation for your build."
            }
            return
        default:
            hub.merge(env)
        }

        hub.lastUpdate = Date()
        hubTelemetry = hub
        telemetry = hub.telemetrySnapshot()
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > Self.logLineLimit {
            logLines.removeFirst(logLines.count - Self.logLineLimit)
        }
    }

    private func save(userDefaults: UserDefaults = .standard) {
        do {
            let data = try JSONEncoder().encode(configuration)
            userDefaults.set(data, forKey: Self.defaultsKey)
        } catch {
            lastError = "Failed to save fleet link settings: \(error.localizedDescription)"
        }
    }

    private static func load(from userDefaults: UserDefaults) -> FleetLinkConfiguration? {
        guard let data = userDefaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(FleetLinkConfiguration.self, from: data)
    }
}

