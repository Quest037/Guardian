import AppKit
import Combine
import Foundation
import Mavsdk
import RxSwift

/// Phase of the Python MAVSDK bridge relative to the vehicle on the wire.
enum TelemetryBridgePhase: Equatable {
    case inactive
    case connecting
    case awaitingVehicle
    case live
}

@MainActor
final class FleetLinkService: ObservableObject {
    private static let defaultsKey = "fleetLink.configuration.v1"
    private var logLineLimit = 350
    private var logLinesPerVehicleLimit = 450

    @Published private(set) var configuration: FleetLinkConfiguration
    @Published private(set) var isRunning = true
    @Published private(set) var lastError: String?
    @Published private(set) var logLines: [String] = []
    @Published private(set) var logLinesByVehicleID: [String: [String]] = [:]

    @Published private(set) var bridgePhase: TelemetryBridgePhase = .awaitingVehicle
    @Published private(set) var telemetry: FleetTelemetrySnapshot?
    @Published private(set) var hubTelemetry: FleetHubVehicleTelemetry?
    @Published private(set) var hubTelemetryByVehicleID: [String: FleetHubVehicleTelemetry] = [:]
    @Published private(set) var telemetryByVehicleID: [String: FleetTelemetrySnapshot] = [:]
    @Published private(set) var vehicleIDBySystemID: [Int: String] = [:]
    @Published private(set) var vehicleStatusByVehicleID: [String: VehicleLifecycleStatus] = [:]
    @Published private(set) var isSimulateEnabled = true

    private final class VehicleSession {
        let vehicleID: String
        let systemID: Int
        let grpcPort: Int
        let mavlinkConnectionURL: String
        let runner: MavsdkServerRunner
        let drone: Drone
        var bag = DisposeBag()

        init(vehicleID: String, systemID: Int, grpcPort: Int, mavlinkConnectionURL: String, runner: MavsdkServerRunner, drone: Drone) {
            self.vehicleID = vehicleID
            self.systemID = systemID
            self.grpcPort = grpcPort
            self.mavlinkConnectionURL = mavlinkConnectionURL
            self.runner = runner
            self.drone = drone
        }
    }

    private var sessionsByVehicleID: [String: VehicleSession] = [:]
    private var usedGrpcPorts: Set<Int> = []
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
                self.stopAllVehicleSessions()
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

    func setSimulateEnabled(_ enabled: Bool) {
        isSimulateEnabled = enabled
    }

    func registerSimulatedVehicle(systemID: Int, mavlinkConnectionURL: String) {
        let vehicleID = "sysid:\(systemID)"
        guard sessionsByVehicleID[vehicleID] == nil else { return }
        let grpcPort = allocateGrpcPort()
        let runner = MavsdkServerRunner()
        let drone = Drone()
        let session = VehicleSession(
            vehicleID: vehicleID,
            systemID: systemID,
            grpcPort: grpcPort,
            mavlinkConnectionURL: mavlinkConnectionURL,
            runner: runner,
            drone: drone
        )
        sessionsByVehicleID[vehicleID] = session
        vehicleIDBySystemID[systemID] = vehicleID
        vehicleStatusByVehicleID[vehicleID] = VehicleLifecycleStatus(stage: .starting)
        logLinesByVehicleID[vehicleID] = []
        start(session: session)
    }

    func unregisterSimulatedVehicle(systemID: Int) {
        let vehicleID = "sysid:\(systemID)"
        stopSession(vehicleID: vehicleID)
    }

    func stopAllVehicleSessions() {
        for vehicleID in sessionsByVehicleID.keys {
            stopSession(vehicleID: vehicleID)
        }
        bridgePhase = .inactive
    }

    func clearStaleVehicleStateWhenNoSitlAlive() {
        telemetry = nil
        hubTelemetry = nil
        telemetryByVehicleID.removeAll(keepingCapacity: true)
        hubTelemetryByVehicleID.removeAll(keepingCapacity: true)
        vehicleIDBySystemID.removeAll(keepingCapacity: true)
        bridgePhase = sessionsByVehicleID.isEmpty ? .awaitingVehicle : .connecting
    }

    func vehicleStatus(forVehicleID vehicleID: String) -> VehicleLifecycleStatus? {
        vehicleStatusByVehicleID[vehicleID]
    }

    func vehicleOperationalModel(forVehicleID vehicleID: String) -> FleetVehicleOperationalModel {
        FleetVehicleOperationalModel(
            hub: hubTelemetryByVehicleID[vehicleID],
            lifecycleStatus: vehicleStatusByVehicleID[vehicleID]
        )
    }

    func primaryVehicleOperationalModel() -> FleetVehicleOperationalModel {
        FleetVehicleOperationalModel(hub: hubTelemetry, lifecycleStatus: nil)
    }

    func updateSimulationLifecycleFromSitlLog(systemID: Int, line: String) {
        let vehicleID = "sysid:\(systemID)"
        let lowered = line.lowercased()
        if lowered.contains("waf") || lowered.contains("compil") || lowered.contains("building") {
            vehicleStatusByVehicleID[vehicleID] = VehicleLifecycleStatus(stage: .compiling)
            return
        }
        if lowered.contains("starting") || lowered.contains("boot") {
            vehicleStatusByVehicleID[vehicleID] = VehicleLifecycleStatus(stage: .starting)
            return
        }
        if lowered.contains("waiting for heartbeat") || lowered.contains("heartbeat") {
            vehicleStatusByVehicleID[vehicleID] = VehicleLifecycleStatus(stage: .awaitingTelemetry)
        }
    }

    func vehicleLogIDs() -> [String] {
        logLinesByVehicleID.keys.sorted()
    }

    func combinedLogs(filteredVehicleIDs: Set<String>) -> [String] {
        if filteredVehicleIDs.isEmpty {
            return logLines
        }
        return logLines.filter { line in
            filteredVehicleIDs.contains { line.contains("[\($0)]") }
        }
    }

    func applyLogRetentionProfile(_ profile: LogRetentionProfile) {
        switch profile {
        case .short:
            logLineLimit = 200
            logLinesPerVehicleLimit = 250
        case .default:
            logLineLimit = 350
            logLinesPerVehicleLimit = 450
        case .long:
            logLineLimit = 900
            logLinesPerVehicleLimit = 1200
        }
        if logLines.count > logLineLimit {
            logLines.removeFirst(logLines.count - logLineLimit)
        }
        for key in logLinesByVehicleID.keys {
            if var lines = logLinesByVehicleID[key], lines.count > logLinesPerVehicleLimit {
                lines.removeFirst(lines.count - logLinesPerVehicleLimit)
                logLinesByVehicleID[key] = lines
            }
        }
    }

    private func allocateGrpcPort() -> Int {
        var candidate = max(50_100, configuration.grpcPort)
        while usedGrpcPorts.contains(candidate) {
            candidate += 1
        }
        usedGrpcPorts.insert(candidate)
        return candidate
    }

    private func releaseGrpcPort(_ port: Int) {
        usedGrpcPorts.remove(port)
    }

    private func start(session: VehicleSession) {
        let vehicleID = session.vehicleID
        let systemID = session.systemID
        bridgePhase = .connecting
        vehicleStatusByVehicleID[vehicleID] = VehicleLifecycleStatus(stage: .connecting)
        session.runner.onLogLine = { [weak self] line in
            self?.appendVehicleLog(line, vehicleID: vehicleID)
        }
        session.runner.onTerminated = { [weak self] code in
            guard let self else { return }
            self.appendVehicleLog("mavsdk_server exited (code \(code)).", vehicleID: vehicleID)
            self.vehicleStatusByVehicleID[vehicleID] = VehicleLifecycleStatus(
                stage: .failed,
                sentenceOverride: "The MAVSDK server exited with code \(code), so telemetry is unavailable for this vehicle."
            )
        }
        do {
            var config = configuration
            config.grpcPort = session.grpcPort
            config.primaryMavlinkConnectionURL = session.mavlinkConnectionURL
            config.additionalMavlinkConnectionURLs = []
            try session.runner.start(configuration: config)
            appendVehicleLog("Started mavsdk_server gRPC \(session.grpcPort) (\(session.mavlinkConnectionURL))", vehicleID: vehicleID)
            session.drone.connect(mavsdkServerAddress: "127.0.0.1", mavsdkServerPort: Int32(session.grpcPort))
                .subscribe(
                    onCompleted: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.appendVehicleLog("Native telemetry client connected.", vehicleID: vehicleID)
                        }
                    },
                    onError: { [weak self] error in
                        Task { @MainActor [weak self] in
                            self?.appendVehicleLog("Telemetry connect error: \(error.localizedDescription)", vehicleID: vehicleID)
                        }
                    }
                )
                .disposed(by: session.bag)

            session.drone.core.connectionState
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(onNext: { [weak self] state in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.bridgePhase = state.isConnected ? .live : .awaitingVehicle
                        self.vehicleStatusByVehicleID[vehicleID] = VehicleLifecycleStatus(
                            stage: state.isConnected ? .awaitingTelemetry : .reconnecting
                        )
                    }
                })
                .disposed(by: session.bag)

            bindTelemetry(for: session, vehicleID: vehicleID, systemID: systemID)
        } catch {
            appendVehicleLog("Failed to start session: \(error.localizedDescription)", vehicleID: vehicleID)
            lastError = error.localizedDescription
            stopSession(vehicleID: vehicleID)
        }
    }

    private func bindTelemetry(for session: VehicleSession, vehicleID: String, systemID: Int) {
        session.drone.telemetry.position
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] pos in
                Task { @MainActor [weak self] in
                    self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                        hub.latitudeDeg = pos.latitudeDeg
                        hub.longitudeDeg = pos.longitudeDeg
                        hub.absoluteAltM = Double(pos.absoluteAltitudeM)
                        hub.relativeAltM = Double(pos.relativeAltitudeM)
                    }
                }
            })
            .disposed(by: session.bag)
        session.drone.telemetry.battery
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] b in
                Task { @MainActor [weak self] in
                    self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                        hub.batteryId = b.id
                        hub.batteryVoltageV = Double(b.voltageV)
                        hub.batteryRemainingPercent = Double(b.remainingPercent)
                        // Native Telemetry.Battery currently exposes voltage + remaining only.
                        // Current draw and time remaining are filled by bridge JSON when available.
                    }
                }
            })
            .disposed(by: session.bag)
        session.drone.telemetry.flightMode
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] mode in
                Task { @MainActor [weak self] in
                    self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                        hub.flightMode = String(describing: mode)
                    }
                }
            })
            .disposed(by: session.bag)
        session.drone.telemetry.armed
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] armed in
                Task { @MainActor [weak self] in
                    self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                        hub.isArmed = armed
                    }
                }
            })
            .disposed(by: session.bag)
        session.drone.telemetry.gpsInfo
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] g in
                Task { @MainActor [weak self] in
                    self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                        hub.gpsNumSatellites = g.numSatellites
                        hub.gpsFixType = String(describing: g.fixType)
                    }
                }
            })
            .disposed(by: session.bag)
        session.drone.telemetry.health
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] h in
                Task { @MainActor [weak self] in
                    self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                        hub.healthGyrometerCalibrationOk = h.isGyrometerCalibrationOk
                        hub.healthAccelerometerCalibrationOk = h.isAccelerometerCalibrationOk
                        hub.healthMagnetometerCalibrationOk = h.isMagnetometerCalibrationOk
                        hub.healthLocalPositionOk = h.isLocalPositionOk
                        hub.healthGlobalPositionOk = h.isGlobalPositionOk
                        hub.healthHomePositionOk = h.isHomePositionOk
                        hub.healthArmable = h.isArmable
                    }
                }
            })
            .disposed(by: session.bag)
    }

    private func stopSession(vehicleID: String) {
        guard let session = sessionsByVehicleID.removeValue(forKey: vehicleID) else { return }
        session.bag = DisposeBag()
        session.drone.disconnect()
        session.runner.stop()
        releaseGrpcPort(session.grpcPort)
        hubTelemetryByVehicleID.removeValue(forKey: vehicleID)
        telemetryByVehicleID.removeValue(forKey: vehicleID)
        vehicleIDBySystemID.removeValue(forKey: session.systemID)
        vehicleStatusByVehicleID[vehicleID] = VehicleLifecycleStatus(stage: .stopped)
        if hubTelemetryByVehicleID.isEmpty {
            telemetry = nil
            hubTelemetry = nil
            bridgePhase = .awaitingVehicle
        }
    }

    func clearLog() {
        logLines.removeAll(keepingCapacity: true)
        logLinesByVehicleID.removeAll(keepingCapacity: true)
    }

    func appendSimulationLog(_ line: String) {
        appendLog(line)
    }

    private func applyNativeTelemetry(vehicleID: String, systemID: Int, mutate: (inout FleetHubVehicleTelemetry) -> Void) {
        let wasAlreadyLive = vehicleStatusByVehicleID[vehicleID]?.stage == .live
        var hub = hubTelemetryByVehicleID[vehicleID] ?? .empty
        mutate(&hub)
        hub.lastUpdate = Date()
        hubTelemetryByVehicleID[vehicleID] = hub
        telemetryByVehicleID[vehicleID] = hub.telemetrySnapshot()
        vehicleIDBySystemID[systemID] = vehicleID
        if !wasAlreadyLive,
           (hub.latitudeDeg != nil || hub.batteryRemainingPercent != nil || hub.gpsNumSatellites != nil || hub.healthArmable != nil) {
            appendVehicleLog("Telemetry active.", vehicleID: vehicleID)
        }
        vehicleStatusByVehicleID[vehicleID] = VehicleLifecycleStatus(stage: .live)
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
        if logLines.count > logLineLimit {
            logLines.removeFirst(logLines.count - logLineLimit)
        }
    }

    private func appendVehicleLog(_ line: String, vehicleID: String) {
        let tagged = "[\(vehicleID)] \(line)"
        appendLog(tagged)
        var vehicleLogs = logLinesByVehicleID[vehicleID] ?? []
        vehicleLogs.append(line)
        if vehicleLogs.count > logLinesPerVehicleLimit {
            vehicleLogs.removeFirst(vehicleLogs.count - logLinesPerVehicleLimit)
        }
        logLinesByVehicleID[vehicleID] = vehicleLogs
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

