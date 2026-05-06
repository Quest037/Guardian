import AppKit
import Combine
import Foundation
import Mavsdk
import RxSwift

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
    /// Multi-vehicle hub snapshots keyed by bridge `vehicle_id` (e.g. `sysid:1`).
    @Published private(set) var hubTelemetryByVehicleID: [String: FleetHubVehicleTelemetry] = [:]
    /// Compact per-vehicle snapshots keyed by bridge `vehicle_id`.
    @Published private(set) var telemetryByVehicleID: [String: FleetTelemetrySnapshot] = [:]
    /// Runtime bridge routing map from MAVLink system id to bridge vehicle stream key.
    @Published private(set) var vehicleIDBySystemID: [Int: String] = [:]
    /// Top-bar “Simulate” switch — only meaningful while the server is running; cleared when the server stops.
    @Published private(set) var isSimulateEnabled = false

    private var runner: MavsdkServerRunner?
    private var bridgeRunner: MavsdkBridgeRunner?
    private var telemetryActivationLoggedVehicleIDs: Set<String> = []
    private var trackedSystemIDs: Set<Int> = []
    private var nativeDrone: Drone?
    private var nativeTelemetryDisposeBag = DisposeBag()
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

    /// Vehicle-owned telemetry model: subscriptions follow active vehicle system IDs.
    func setTrackedSystemIDs(_ ids: Set<Int>) {
        let normalized = Set(ids.filter { $0 > 0 && $0 < 256 })
        guard normalized != trackedSystemIDs else { return }
        trackedSystemIDs = normalized
        guard isRunning else { return }
        appendLog("[bridge] tracked system IDs updated: \(normalized.sorted())")
        if let bridgeRunner {
            bridgeRunner.updateSystemIDs(normalized.sorted())
        } else {
            schedulePythonBridgeStart()
        }
    }

    /// Starts `mavsdk_server` if not already running. Returns `false` if launch failed (see `lastError`).
    @discardableResult
    func startServer() -> Bool {
        guard !isRunning else { return true }
        lastError = nil
        telemetry = nil
        hubTelemetry = nil
        telemetryByVehicleID.removeAll(keepingCapacity: true)
        hubTelemetryByVehicleID.removeAll(keepingCapacity: true)
        vehicleIDBySystemID.removeAll(keepingCapacity: true)
        telemetryActivationLoggedVehicleIDs.removeAll(keepingCapacity: true)
        trackedSystemIDs.removeAll(keepingCapacity: true)
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
            self.telemetryByVehicleID.removeAll(keepingCapacity: true)
            self.hubTelemetryByVehicleID.removeAll(keepingCapacity: true)
            self.vehicleIDBySystemID.removeAll(keepingCapacity: true)
            self.telemetryActivationLoggedVehicleIDs.removeAll(keepingCapacity: true)
            self.trackedSystemIDs.removeAll(keepingCapacity: true)
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
        telemetryByVehicleID.removeAll(keepingCapacity: true)
        hubTelemetryByVehicleID.removeAll(keepingCapacity: true)
        vehicleIDBySystemID.removeAll(keepingCapacity: true)
        telemetryActivationLoggedVehicleIDs.removeAll(keepingCapacity: true)
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
        guard isRunning, nativeDrone == nil else { return }
        bridgePhase = .connecting
        appendLog("Starting native MAVSDK-Swift telemetry client.")
        nativeTelemetryDisposeBag = DisposeBag()

        let drone = Drone()
        nativeDrone = drone
        drone.connect(mavsdkServerAddress: "127.0.0.1", mavsdkServerPort: Int32(configuration.grpcPort))
            .subscribe(
                onCompleted: { [weak self] in
                    guard let self else { return }
                    self.appendLog("Native MAVSDK-Swift client attached to mavsdk_server.")
                    self.bridgePhase = .awaitingVehicle
                },
                onError: { [weak self] error in
                    guard let self else { return }
                    self.appendLog("[native] connect error: \(error.localizedDescription)")
                    self.lastError = "Native telemetry client failed to connect: \(error.localizedDescription)"
                    self.bridgePhase = .inactive
                }
            )
            .disposed(by: nativeTelemetryDisposeBag)

        drone.core.connectionState
            .subscribe(
                onNext: { [weak self] state in
                    guard let self else { return }
                    self.bridgePhase = state.isConnected ? .live : .awaitingVehicle
                },
                onError: { [weak self] error in
                    self?.appendLog("[native] core.connectionState stream error: \(error.localizedDescription)")
                }
            )
            .disposed(by: nativeTelemetryDisposeBag)

        let vehicleID = trackedSystemIDs.sorted().first.map { "sysid:\($0)" } ?? "sysid:1"
        let systemID = trackedSystemIDs.sorted().first ?? 1
        vehicleIDBySystemID[systemID] = vehicleID

        drone.telemetry.position
            .subscribe(onNext: { [weak self] pos in
                self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                    hub.latitudeDeg = pos.latitudeDeg
                    hub.longitudeDeg = pos.longitudeDeg
                    hub.absoluteAltM = Double(pos.absoluteAltitudeM)
                    hub.relativeAltM = Double(pos.relativeAltitudeM)
                }
            }, onError: { [weak self] error in
                self?.appendLog("[native] position stream error: \(error.localizedDescription)")
            })
            .disposed(by: nativeTelemetryDisposeBag)

        drone.telemetry.battery
            .subscribe(onNext: { [weak self] b in
                self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                    hub.batteryId = b.id
                    hub.batteryVoltageV = Double(b.voltageV)
                    hub.batteryRemainingPercent = Double(b.remainingPercent)
                }
            }, onError: { [weak self] error in
                self?.appendLog("[native] battery stream error: \(error.localizedDescription)")
            })
            .disposed(by: nativeTelemetryDisposeBag)

        drone.telemetry.flightMode
            .subscribe(onNext: { [weak self] mode in
                self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                    hub.flightMode = String(describing: mode)
                }
            }, onError: { [weak self] error in
                self?.appendLog("[native] flightMode stream error: \(error.localizedDescription)")
            })
            .disposed(by: nativeTelemetryDisposeBag)

        drone.telemetry.armed
            .subscribe(onNext: { [weak self] armed in
                self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                    hub.isArmed = armed
                }
            }, onError: { [weak self] error in
                self?.appendLog("[native] armed stream error: \(error.localizedDescription)")
            })
            .disposed(by: nativeTelemetryDisposeBag)

        drone.telemetry.gpsInfo
            .subscribe(onNext: { [weak self] g in
                self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                    hub.gpsNumSatellites = g.numSatellites
                    hub.gpsFixType = String(describing: g.fixType)
                }
            }, onError: { [weak self] error in
                self?.appendLog("[native] gpsInfo stream error: \(error.localizedDescription)")
            })
            .disposed(by: nativeTelemetryDisposeBag)

        drone.telemetry.health
            .subscribe(onNext: { [weak self] h in
                self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                    hub.healthGyrometerCalibrationOk = h.isGyrometerCalibrationOk
                    hub.healthAccelerometerCalibrationOk = h.isAccelerometerCalibrationOk
                    hub.healthMagnetometerCalibrationOk = h.isMagnetometerCalibrationOk
                    hub.healthLocalPositionOk = h.isLocalPositionOk
                    hub.healthGlobalPositionOk = h.isGlobalPositionOk
                    hub.healthHomePositionOk = h.isHomePositionOk
                    hub.healthArmable = h.isArmable
                }
            }, onError: { [weak self] error in
                self?.appendLog("[native] health stream error: \(error.localizedDescription)")
            })
            .disposed(by: nativeTelemetryDisposeBag)
    }

    private func stopPythonBridge() {
        bridgeRunner = nil
        nativeTelemetryDisposeBag = DisposeBag()
        nativeDrone?.disconnect()
        nativeDrone = nil
        bridgePhase = .inactive
        telemetry = nil
        hubTelemetry = nil
        telemetryByVehicleID.removeAll(keepingCapacity: true)
        hubTelemetryByVehicleID.removeAll(keepingCapacity: true)
        vehicleIDBySystemID.removeAll(keepingCapacity: true)
        telemetryActivationLoggedVehicleIDs.removeAll(keepingCapacity: true)
    }

    private func applyNativeTelemetry(vehicleID: String, systemID: Int, mutate: (inout FleetHubVehicleTelemetry) -> Void) {
        var hub = hubTelemetryByVehicleID[vehicleID] ?? .empty
        mutate(&hub)
        hub.lastUpdate = Date()
        hubTelemetryByVehicleID[vehicleID] = hub
        telemetryByVehicleID[vehicleID] = hub.telemetrySnapshot()
        vehicleIDBySystemID[systemID] = vehicleID
        if !telemetryActivationLoggedVehicleIDs.contains(vehicleID),
           (hub.latitudeDeg != nil || hub.batteryRemainingPercent != nil || hub.gpsNumSatellites != nil || hub.healthArmable != nil) {
            telemetryActivationLoggedVehicleIDs.insert(vehicleID)
            appendLog("[native] telemetry active [vehicle_id=\(vehicleID) system_id=\(systemID)]")
        }
        hubTelemetry = hub
        telemetry = hub.telemetrySnapshot()
    }

    private func handleBridgeStdoutLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let env = try? decoder.decode(BridgeHubEnvelope.self, from: data) else { return }

        let vehicleID = env.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedVehicleID = (vehicleID?.isEmpty == false) ? vehicleID! : "sysid:unknown"
        if let sid = env.systemId {
            vehicleIDBySystemID[sid] = resolvedVehicleID
        }
        var hub = hubTelemetryByVehicleID[resolvedVehicleID] ?? .empty

        switch env.type {
        case "bridge_listening":
            bridgePhase = .awaitingVehicle
            appendLog(
                "Bridge connected to MAVSDK (gRPC \(env.host ?? "?"):\(env.port.map(String.init) ?? "?")) — waiting for a MAVLink system on the link."
            )
            return
        case "bridge_ready":
            bridgePhase = .live
            if env.systemId != nil {
                appendLog(
                    "[bridge] discovered vehicle stream [vehicle_id=\(resolvedVehicleID) system_id=\(env.systemId ?? -1)] grpc=\(env.host ?? "?"):\(env.port.map(String.init) ?? "?")"
                )
            }
            return
        case "bridge_error":
            let msg = env.message ?? "unknown"
            if msg.contains("connect_rpc_timeout:mavsdk_connect_call_did_not_complete") {
                appendLog("[bridge] warning [vehicle_id=\(resolvedVehicleID) system_id=\(env.systemId ?? -1)] \(msg)")
            } else {
                appendLog("[bridge] error [vehicle_id=\(resolvedVehicleID) system_id=\(env.systemId ?? -1)] \(msg)")
            }
            if msg.contains("missing_mavsdk_python_package") {
                lastError = "Live telemetry couldn’t start. The optional components for this machine may be missing—check the server log or documentation for your build."
            } else if msg.contains("system_selector_unavailable:python_mavsdk_ctor_has_no_sysid") {
                lastError = "Live telemetry could not bind each MAVLink system separately. Update bridge dependencies (`make bridge-deps`) so MAVSDK-Python supports per-system selection."
            }
            return
        case "bridge_system_ids_updated":
            appendLog("[bridge] active system IDs updated.")
            return
        default:
            hub.merge(env)
        }

        hub.lastUpdate = Date()
        hubTelemetryByVehicleID[resolvedVehicleID] = hub
        telemetryByVehicleID[resolvedVehicleID] = hub.telemetrySnapshot()
        if !telemetryActivationLoggedVehicleIDs.contains(resolvedVehicleID),
           (hub.latitudeDeg != nil || hub.batteryRemainingPercent != nil || hub.gpsNumSatellites != nil || hub.healthArmable != nil) {
            telemetryActivationLoggedVehicleIDs.insert(resolvedVehicleID)
            appendLog(
                "[bridge] telemetry active [vehicle_id=\(resolvedVehicleID) system_id=\(env.systemId ?? -1)] event=\(env.type)"
            )
        }

        // Backward-compat fields used in older UI: mirror the most recently updated vehicle.
        hubTelemetry = hub
        telemetry = hub.telemetrySnapshot()
    }

    /// Resolves one vehicle stream from the keyed telemetry hub.
    func hubTelemetry(forVehicleID vehicleID: String) -> FleetHubVehicleTelemetry? {
        hubTelemetryByVehicleID[vehicleID]
    }

    /// Resolves the active bridge stream key for a MAVLink system id, if discovered.
    func vehicleID(forSystemID systemID: Int) -> String? {
        vehicleIDBySystemID[systemID]
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

