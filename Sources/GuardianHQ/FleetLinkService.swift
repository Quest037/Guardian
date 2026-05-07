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

/// Lightweight `Error`-conforming wrapper for parameter-read/write failures
/// surfaced to callers of `getVehicleIntParameter` / `setVehicleIntParameter`.
/// Wraps an already-formatted human-readable string so call sites can simply
/// `print(error)` or `error.message` without unpacking MAVSDK error types.
struct FleetLinkParameterError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
    var localizedDescription: String { message }
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
    @Published private(set) var vehicleModelsByVehicleID: [String: FleetVehicleModel] = [:]
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
        /// One-shot: request MAVSDK battery stream rate and optional PX4 SIM battery capacity.
        var didApplyMavlinkBatteryTuning = false

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
    /// Last N surfaced STATUSTEXT lines per vehicle (for Paladin / command error context).
    private var recentVehicleStatusMessagesByVehicleID: [String: [String]] = [:]
    private let vehicleStatusContextMaxLines = 12
    /// One "mission cycle finished" emission per execution; reset when progress shows `current < total`.
    private var autopilotMissionCompletionLatchByVehicleID: [String: Bool] = [:]
    /// Deduplicate noisy recurring lines from SITL stdout (see `SimulationStdoutLogDedupeState`).
    private var simulationStdoutLogDedupe = SimulationStdoutLogDedupeState()
    /// Vehicle stream keys (`sysid:n`) created by `registerSimulatedVehicle` (built-in SITL only).
    private var simulatedFleetVehicleIDs: Set<String> = []

    /// Fires when MAVSDK mission progress indicates a full mission run has finished (`current >= total`).
    var onAutopilotMissionCycleFinished: ((String) -> Void)?

    /// Per-vehicle lines that also appear in the global log (STATUSTEXT, mission progress), for Mission Control Paladin.
    /// Arguments: `vehicleID`, untagged line (no `[sysid:n]` prefix).
    var onMirrorFleetLineToPaladin: ((String, String) -> Void)?

    init(userDefaults: UserDefaults = .standard) {
        configuration = Self.load(from: userDefaults) ?? .defaults
        GuardianAppQuitCoordinator.shared.noteFleetLinkServiceCreated(self)
    }

    /// Stops every `mavsdk_server` / `Drone` session and clears in-memory link state (logs, telemetry maps, ports).
    func teardownAllForApplicationQuit() {
        onAutopilotMissionCycleFinished = nil
        onMirrorFleetLineToPaladin = nil
        stopAllVehicleSessions()
        usedGrpcPorts.removeAll()
        logLines.removeAll(keepingCapacity: true)
        logLinesByVehicleID.removeAll(keepingCapacity: true)
        telemetry = nil
        hubTelemetry = nil
        telemetryByVehicleID.removeAll(keepingCapacity: true)
        hubTelemetryByVehicleID.removeAll(keepingCapacity: true)
        vehicleIDBySystemID.removeAll(keepingCapacity: true)
        vehicleModelsByVehicleID.removeAll(keepingCapacity: true)
        vehicleStatusByVehicleID.removeAll(keepingCapacity: true)
        recentVehicleStatusMessagesByVehicleID.removeAll(keepingCapacity: true)
        autopilotMissionCompletionLatchByVehicleID.removeAll(keepingCapacity: true)
        simulationStdoutLogDedupe.reset()
        simulatedFleetVehicleIDs.removeAll(keepingCapacity: true)
        bridgePhase = .inactive
        lastError = nil
    }

    func applyConfiguration(_ config: FleetLinkConfiguration) {
        configuration = config
        save()
    }

    func setSimulateEnabled(_ enabled: Bool) {
        isSimulateEnabled = enabled
    }

    /// Read an integer autopilot parameter for a connected vehicle.
    func getVehicleIntParameter(
        vehicleID: String,
        name: String,
        source: String,
        onResult: @escaping @MainActor (Result<Int32, FleetLinkParameterError>) -> Void
    ) {
        guard let session = sessionsByVehicleID[vehicleID] else {
            onResult(.failure(FleetLinkParameterError(message: "No MAVSDK session for vehicle.")))
            return
        }
        session.drone.param.getParamInt(name: name)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onSuccess: { [weak self] value in
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog(
                            "Param read [source=\(source)] \(name)=\(value)",
                            vehicleID: vehicleID
                        )
                        onResult(.success(value))
                    }
                },
                onFailure: { [weak self] error in
                    Task { @MainActor [weak self] in
                        let detail = self?.mavsdkPublicErrorDescription(error) ?? error.localizedDescription
                        self?.appendVehicleLog(
                            "Param read failed [source=\(source)] \(name): \(detail)",
                            vehicleID: vehicleID
                        )
                        onResult(.failure(FleetLinkParameterError(message: detail)))
                    }
                }
            )
            .disposed(by: session.bag)
    }

    /// Set an integer autopilot parameter for a connected vehicle.
    func setVehicleIntParameter(
        vehicleID: String,
        name: String,
        value: Int32,
        source: String,
        onResult: (@MainActor (Result<Void, FleetLinkParameterError>) -> Void)? = nil
    ) {
        guard let session = sessionsByVehicleID[vehicleID] else {
            onResult?(.failure(FleetLinkParameterError(message: "No MAVSDK session for vehicle.")))
            return
        }
        session.drone.param.setParamInt(name: name, value: value)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onCompleted: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog(
                            "Param set [source=\(source)] \(name)=\(value)",
                            vehicleID: vehicleID
                        )
                        onResult?(.success(()))
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        let detail = self?.mavsdkPublicErrorDescription(error) ?? error.localizedDescription
                        self?.appendVehicleLog(
                            "Param set failed [source=\(source)] \(name)=\(value): \(detail)",
                            vehicleID: vehicleID
                        )
                        onResult?(.failure(FleetLinkParameterError(message: detail)))
                    }
                }
            )
            .disposed(by: session.bag)
    }

    func registerSimulatedVehicle(
        systemID: Int,
        mavlinkConnectionURL: String,
        autopilotStack: FleetAutopilotStack? = nil,
        vehicleType: FleetVehicleType = .unknown,
        spawnDefaults: SimSpawnDefaults? = nil
    ) {
        let vehicleID = "sysid:\(systemID)"
        if sessionsByVehicleID[vehicleID] != nil {
            appendVehicleLog("Replacing stale MAVSDK session before reconnecting sim.", vehicleID: vehicleID)
            stopSession(vehicleID: vehicleID)
        }
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
        ensureVehicleModel(
            vehicleID: vehicleID,
            systemID: systemID,
            vehicleType: vehicleType,
            initialStatus: .init(stage: .starting)
        )
        if let autopilotStack {
            if var model = vehicleModelsByVehicleID[vehicleID] {
                model.applyTelemetryMutation { hub in
                    hub.autopilotStack = autopilotStack
                }
                vehicleModelsByVehicleID[vehicleID] = model
                hubTelemetryByVehicleID[vehicleID] = model.data.telemetry
                telemetryByVehicleID[vehicleID] = model.collections.telemetrySnapshot
            }
        }
        if let defaults = spawnDefaults, var model = vehicleModelsByVehicleID[vehicleID] {
            model.applyTelemetryMutation { hub in
                hub.headingDeg = defaults.headingDeg
                hub.batteryRemainingPercent = defaults.batteryPercent
                hub.batteryVoltageV = defaults.batteryVoltageV
                hub.batteryCurrentA = defaults.batteryCurrentA
            }
            vehicleModelsByVehicleID[vehicleID] = model
            hubTelemetryByVehicleID[vehicleID] = model.data.telemetry
            telemetryByVehicleID[vehicleID] = model.collections.telemetrySnapshot
        }
        logLinesByVehicleID[vehicleID] = []
        simulatedFleetVehicleIDs.insert(vehicleID)
        start(session: session)
    }

    func unregisterSimulatedVehicle(systemID: Int) {
        let vehicleID = "sysid:\(systemID)"
        stopSession(vehicleID: vehicleID)
    }

    func stopAllVehicleSessions() {
        for vehicleID in Array(sessionsByVehicleID.keys) {
            stopSession(vehicleID: vehicleID)
        }
        bridgePhase = .inactive
    }

    func clearStaleVehicleStateWhenNoSitlAlive() {
        if !sessionsByVehicleID.isEmpty {
            appendLog("Clearing orphaned MAVSDK session(s) (\(sessionsByVehicleID.count)) — no sim processes alive.")
            stopAllVehicleSessions()
        }
        telemetry = nil
        hubTelemetry = nil
        telemetryByVehicleID.removeAll(keepingCapacity: true)
        hubTelemetryByVehicleID.removeAll(keepingCapacity: true)
        vehicleIDBySystemID.removeAll(keepingCapacity: true)
        vehicleModelsByVehicleID.removeAll(keepingCapacity: true)
        vehicleStatusByVehicleID.removeAll(keepingCapacity: true)
        recentVehicleStatusMessagesByVehicleID.removeAll(keepingCapacity: true)
        autopilotMissionCompletionLatchByVehicleID.removeAll(keepingCapacity: true)
        simulatedFleetVehicleIDs.removeAll(keepingCapacity: true)
        bridgePhase = .awaitingVehicle
    }

    func vehicleStatus(forVehicleID vehicleID: String) -> VehicleLifecycleStatus? {
        vehicleModelsByVehicleID[vehicleID]?.collections.lifecycleStatus
            ?? vehicleStatusByVehicleID[vehicleID]
    }

    func vehicleOperationalModel(forVehicleID vehicleID: String) -> FleetVehicleOperationalModel {
        if let model = vehicleModelsByVehicleID[vehicleID] {
            return model.collections.operational
        }
        return FleetVehicleOperationalModel(
            hub: hubTelemetryByVehicleID[vehicleID],
            lifecycleStatus: vehicleStatusByVehicleID[vehicleID]
        )
    }

    func primaryVehicleOperationalModel() -> FleetVehicleOperationalModel {
        FleetVehicleOperationalModel(hub: hubTelemetry, lifecycleStatus: nil)
    }

    func vehicleModel(forVehicleID vehicleID: String) -> FleetVehicleModel? {
        vehicleModelsByVehicleID[vehicleID]
    }

    /// Leaflet / Mission Control marker colour — from the fleet model when present, otherwise the same stable default as `FleetVehicleModel` uses on creation.
    func mapColorHex(forVehicleID vehicleID: String) -> String {
        if let hex = vehicleModelsByVehicleID[vehicleID]?.data.mapColorHex { return hex }
        return FleetVehicleModel.defaultMapColorHex(forVehicleID: vehicleID)
    }

    /// Raise the gate so lower-priority sources stop issuing (e.g. `.manualTakeover` blocks Paladin until reset to `.paladin`).
    func setCommandAuthorityGate(vehicleID: String, minimumCategory: FleetVehicleCommandCategory) {
        ensureVehicleModel(vehicleID: vehicleID, systemID: nil, initialStatus: .init(stage: .connecting))
        guard var model = vehicleModelsByVehicleID[vehicleID] else { return }
        model.functions.commandGateMinimumPriority = minimumCategory.arbitrationPriority
        vehicleModelsByVehicleID[vehicleID] = model
        appendVehicleLog(
            "Command authority gate set to \(minimumCategory.rawValue) (min priority \(minimumCategory.arbitrationPriority)).",
            vehicleID: vehicleID
        )
    }

    /// Command dispatch entrypoint for Paladin and future manual-control systems.
    @discardableResult
    func executeVehicleCommand(
        vehicleID: String,
        command: FleetVehicleCommand,
        source: String,
        category: FleetVehicleCommandCategory = .paladin,
        onPaladinCommandOutcome: (@MainActor (PaladinFleetCommandAsyncOutcome) -> Void)? = nil
    ) -> UUID? {
        ensureVehicleModel(vehicleID: vehicleID, systemID: nil, initialStatus: .init(stage: .connecting))
        guard var model = vehicleModelsByVehicleID[vehicleID] else {
            onPaladinCommandOutcome?(.failed("No vehicle model for this stream key."))
            return nil
        }
        if category.arbitrationPriority < model.functions.commandGateMinimumPriority {
            appendVehicleLog(
                "Command rejected [source=\(source) category=\(category.rawValue)]: below gate (\(model.functions.commandGateMinimumPriority)).",
                vehicleID: vehicleID
            )
            onPaladinCommandOutcome?(
                .failed(
                    "Command rejected: authority gate on this vehicle requires a higher-priority source than \(category.rawValue)."
                )
            )
            return nil
        }
        let commandID = model.queueCommand(command, source: source, category: category)
        model.markCommandStatus(commandID: commandID, status: .sent)
        vehicleModelsByVehicleID[vehicleID] = model
        appendVehicleLog(
            "Command queued [source=\(source) category=\(category.rawValue)] \(describe(command: command))",
            vehicleID: vehicleID
        )

        guard let session = sessionsByVehicleID[vehicleID] else {
            markVehicleCommand(vehicleID: vehicleID, commandID: commandID, status: .failed("No MAVSDK session for vehicle."))
            appendVehicleLog("Command failed: no MAVSDK session.", vehicleID: vehicleID)
            onPaladinCommandOutcome?(.failed("No MAVSDK session for vehicle."))
            return commandID
        }

        if case .uploadAndStartMission(let items) = command {
            runUploadArmStartMissionPipeline(
                session: session,
                vehicleID: vehicleID,
                commandID: commandID,
                command: command,
                items: items,
                onPaladinCommandOutcome: onPaladinCommandOutcome
            )
            return commandID
        }

        let completion: Completable
        switch command {
        case .arm:
            completion = session.drone.action.arm()
        case .disarm:
            completion = session.drone.action.disarm()
        case .holdPosition:
            completion = session.drone.action.hold()
        case .returnToLaunch:
            completion = session.drone.action.returnToLaunch()
        case .land:
            completion = session.drone.action.land()
        case .gotoCoordinate(let coord, let relativeAltitudeM, let yawDeg):
            let fallbackBaseAlt = hubTelemetryByVehicleID[vehicleID]?.absoluteAltM ?? 0
            let targetAbsoluteAlt = fallbackBaseAlt + relativeAltitudeM
            completion = session.drone.action.gotoLocation(
                latitudeDeg: coord.lat,
                longitudeDeg: coord.lon,
                absoluteAltitudeM: Float(targetAbsoluteAlt),
                yawDeg: Float(yawDeg)
            )
        case .uploadAndStartMission:
            preconditionFailure("uploadAndStartMission must use runUploadArmStartMissionPipeline")
        case .manualControl(let manual):
            completion = completionForManualControl(
                manual,
                vehicleID: vehicleID,
                session: session
            )
        }

        completion
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onCompleted: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.markVehicleCommand(vehicleID: vehicleID, commandID: commandID, status: .succeeded)
                        self?.appendVehicleLog("Command succeeded: \(self?.describe(command: command) ?? "command")", vehicleID: vehicleID)
                        onPaladinCommandOutcome?(.succeeded)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        let raw = self?.mavsdkPublicErrorDescription(error) ?? error.localizedDescription
                        let detail = self?.augmentCommandFailureDetail(vehicleID: vehicleID, detail: raw) ?? raw
                        self?.markVehicleCommand(
                            vehicleID: vehicleID,
                            commandID: commandID,
                            status: .failed(detail)
                        )
                        self?.appendVehicleLog("Command error: \(detail)", vehicleID: vehicleID)
                        onPaladinCommandOutcome?(.failed(detail))
                    }
                }
            )
            .disposed(by: session.bag)

        return commandID
    }

    /// Human-readable MAVSDK failure (autopilot `resultStr` + enum case), not only `localizedDescription`.
    private func mavsdkPublicErrorDescription(_ error: Error) -> String {
        if let e = error as? Mavsdk.Action.ActionError {
            let tail = e.description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if tail.isEmpty { return String(describing: e.code) }
            return "\(String(describing: e.code)): \(tail)"
        }
        if let e = error as? Mavsdk.Mission.MissionError {
            let tail = e.description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if tail.isEmpty { return String(describing: e.code) }
            return "\(String(describing: e.code)): \(tail)"
        }
        return error.localizedDescription
    }

    /// Whether to mirror this STATUSTEXT into Guardian logs (stack-agnostic; light keyword filter on `.info` only).
    private func shouldSurfaceVehicleStatusText(_ type: Telemetry.StatusTextType, text: String) -> Bool {
        switch type {
        case .debug:
            return false
        case .info:
            let lower = text.lowercased()
            let keys = [
                "preflight", "arming", "arm", "disarm", "denied", "fail", "compass", "magnetometer",
                "gps", "ekf", "health", "calib", "rc not found", "fence", "crash",
            ]
            return keys.contains { lower.contains($0) }
        case .notice, .warning, .error, .critical, .alert, .emergency, .UNRECOGNIZED:
            return true
        }
    }

    private func statusTextTypeLabel(_ type: Telemetry.StatusTextType) -> String {
        switch type {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        case .alert: return "ALERT"
        case .emergency: return "EMERGENCY"
        case .UNRECOGNIZED(let i): return "ST(\(i))"
        }
    }

    private func appendRecentVehicleStatusLine(vehicleID: String, line: String) {
        var arr = recentVehicleStatusMessagesByVehicleID[vehicleID] ?? []
        arr.append(line)
        if arr.count > vehicleStatusContextMaxLines {
            arr.removeFirst(arr.count - vehicleStatusContextMaxLines)
        }
        recentVehicleStatusMessagesByVehicleID[vehicleID] = arr
    }

    /// Appends the last few surfaced vehicle STATUSTEXT lines so Paladin / fleet errors are actionable.
    private func augmentCommandFailureDetail(vehicleID: String, detail: String) -> String {
        guard let arr = recentVehicleStatusMessagesByVehicleID[vehicleID], !arr.isEmpty else {
            return detail
        }
        let tail = arr.suffix(4).joined(separator: " | ")
        if tail.count <= 400 {
            return "\(detail) — Context: \(tail)"
        }
        let prefix = String(tail.prefix(397))
        return "\(detail) — Context: \(prefix)…"
    }

    /// Upload, arm, and start mission as separate steps so logs / Paladin see **which** step failed.
    private func runUploadArmStartMissionPipeline(
        session: VehicleSession,
        vehicleID: String,
        commandID: UUID,
        command: FleetVehicleCommand,
        items: [Mavsdk.Mission.MissionItem],
        onPaladinCommandOutcome: (@MainActor (PaladinFleetCommandAsyncOutcome) -> Void)?
    ) {
        let plan = Mavsdk.Mission.MissionPlan(missionItems: items)
        let drone = session.drone

        // After a run finishes, PX4 often keeps the mission “current index” at the last item. A fresh
        // `uploadMission` + `startMission()` can still resume from that index (e.g. item 8 of 9),
        // which looks like the mission “jumps” near the end and then fails or loiters. Reset to the
        // first waypoint before arm/start (MAVSDK: setCurrentMissionItem(0) restarts from the beginning).
        drone.mission.uploadMission(missionPlan: plan)
            .andThen(drone.mission.setCurrentMissionItem(index: 0))
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onCompleted: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog(
                            "Mission plan uploaded; current waypoint set to first; requesting arm…",
                            vehicleID: vehicleID
                        )
                    }
                    drone.action.arm()
                        .observe(on: MainScheduler.asyncInstance)
                        .subscribe(
                            onCompleted: { [weak self] in
                                Task { @MainActor [weak self] in
                                    self?.appendVehicleLog("Arm acknowledged; starting mission…", vehicleID: vehicleID)
                                }
                                drone.mission.startMission()
                                    .observe(on: MainScheduler.asyncInstance)
                                    .subscribe(
                                        onCompleted: { [weak self] in
                                            Task { @MainActor [weak self] in
                                                guard let self else { return }
                                                self.markVehicleCommand(vehicleID: vehicleID, commandID: commandID, status: .succeeded)
                                                self.appendVehicleLog(
                                                    "Command succeeded: \(self.describe(command: command))",
                                                    vehicleID: vehicleID
                                                )
                                                onPaladinCommandOutcome?(.succeeded)
                                            }
                                        },
                                        onError: { [weak self] error in
                                            Task { @MainActor [weak self] in
                                                guard let self else { return }
                                                let msg = self.mavsdkPublicErrorDescription(error)
                                                let detail = self.augmentCommandFailureDetail(
                                                    vehicleID: vehicleID,
                                                    detail: "after arm, start mission failed: \(msg)"
                                                )
                                                self.markVehicleCommand(
                                                    vehicleID: vehicleID,
                                                    commandID: commandID,
                                                    status: .failed(detail)
                                                )
                                                self.appendVehicleLog("Command error: \(detail)", vehicleID: vehicleID)
                                                onPaladinCommandOutcome?(.failed(detail))
                                            }
                                        }
                                    )
                                    .disposed(by: session.bag)
                            },
                            onError: { [weak self] error in
                                Task { @MainActor [weak self] in
                                    guard let self else { return }
                                    let msg = self.mavsdkPublicErrorDescription(error)
                                    let detail = self.augmentCommandFailureDetail(
                                        vehicleID: vehicleID,
                                        detail: "after upload, arm failed: \(msg)"
                                    )
                                    self.markVehicleCommand(
                                        vehicleID: vehicleID,
                                        commandID: commandID,
                                        status: .failed(detail)
                                    )
                                    self.appendVehicleLog("Command error: \(detail)", vehicleID: vehicleID)
                                    onPaladinCommandOutcome?(.failed(detail))
                                }
                            }
                        )
                        .disposed(by: session.bag)
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let msg = self.mavsdkPublicErrorDescription(error)
                        let detail = self.augmentCommandFailureDetail(
                            vehicleID: vehicleID,
                            detail: "mission prepare failed (upload or set first waypoint): \(msg)"
                        )
                        self.markVehicleCommand(
                            vehicleID: vehicleID,
                            commandID: commandID,
                            status: .failed(detail)
                        )
                        self.appendVehicleLog("Command error: \(detail)", vehicleID: vehicleID)
                        onPaladinCommandOutcome?(.failed(detail))
                    }
                }
            )
            .disposed(by: session.bag)
    }

    func updateSimulationLifecycleFromSitlLog(systemID: Int, line: String) {
        let vehicleID = "sysid:\(systemID)"
        let lowered = line.lowercased()
        let currentStage = vehicleModelsByVehicleID[vehicleID]?.collections.lifecycleStatus.stage
            ?? vehicleStatusByVehicleID[vehicleID]?.stage
            ?? .starting

        guard let inferred = Self.inferLifecycleStageFromSitlLogLine(lowered) else { return }
        guard !Self.simLogLifecycleUpdateWouldRegress(current: currentStage, inferred: inferred) else { return }
        applyLifecycleStatus(.init(stage: inferred), vehicleID: vehicleID)
    }

    /// Parses **SITL stdout** (not `[sysid:n]` MAVSDK lines). Kept narrow so we never downgrade `.connecting` / `.awaitingTelemetry` / `.live` back to “booting” from unrelated substrings (e.g. `reboot` contains `boot`, `started` is not `starting` but broad `starting` was dangerous).
    private static func inferLifecycleStageFromSitlLogLine(_ lowered: String) -> VehicleLifecycleStage? {
        if lowered.contains("waf") || lowered.contains("compil") || lowered.contains("building") {
            return .compiling
        }
        if lowered.contains("waiting for heartbeat")
            || (lowered.contains("waiting to discover") && lowered.contains("system")) {
            return .awaitingTelemetry
        }
        if lowered.contains("px4 starting")
            || (lowered.contains("startup script") && lowered.contains("init.d-posix")) {
            return .starting
        }
        return nil
    }

    /// When `true`, skip applying `inferred` from sim logs so MAVSDK-driven stages are not overwritten.
    private static func simLogLifecycleUpdateWouldRegress(current: VehicleLifecycleStage, inferred: VehicleLifecycleStage) -> Bool {
        switch inferred {
        case .starting:
            switch current {
            case .connecting, .reconnecting, .awaitingTelemetry, .live:
                return true
            default:
                return false
            }
        case .compiling:
            switch current {
            case .connecting, .reconnecting, .awaitingTelemetry, .live:
                return true
            default:
                return false
            }
        case .awaitingTelemetry:
            switch current {
            case .live:
                return true
            default:
                return false
            }
        case .connecting, .reconnecting, .live, .stopped, .failed:
            return false
        }
    }

    func vehicleLogIDs() -> [String] {
        logLinesByVehicleID.keys.sorted()
    }

    func combinedLogs(filteredVehicleIDs: Set<String>) -> [String] {
        if filteredVehicleIDs.isEmpty {
            return logLines
        }
        let prefixes: [String] = filteredVehicleIDs.map { displayShortID(forVehicleID: $0) }
        return logLines.filter { line in
            prefixes.contains { line.contains("[\($0)]") }
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
        ensureVehicleModel(vehicleID: vehicleID, systemID: systemID, initialStatus: .init(stage: .connecting))
        applyLifecycleStatus(.init(stage: .connecting), vehicleID: vehicleID)
        session.runner.onLogLine = { [weak self] line in
            self?.appendVehicleLog(line, vehicleID: vehicleID)
        }
        session.runner.onTerminated = { [weak self] code in
            guard let self else { return }
            self.appendVehicleLog("mavsdk_server exited (code \(code)).", vehicleID: vehicleID)
            self.applyLifecycleStatus(
                VehicleLifecycleStatus(
                stage: .failed,
                sentenceOverride: "The MAVSDK server exited with code \(code), so telemetry is unavailable for this vehicle."
                ),
                vehicleID: vehicleID
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
                        self.applyLifecycleStatus(VehicleLifecycleStatus(
                            stage: state.isConnected ? .awaitingTelemetry : .reconnecting
                        ), vehicleID: vehicleID)
                        if state.isConnected {
                            self.applyMavlinkBatteryTelemetryTuningOnce(session: session, vehicleID: vehicleID)
                        }
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
                        if b.voltageV.isFinite, b.voltageV > 0 {
                            hub.batteryVoltageV = Double(b.voltageV)
                        }
                        // MAVLink unknown (-1) is scaled to a small negative fraction in MAVSDK; do not wipe a good %.
                        if let frac = Self.normalizedMavsdkBatteryFraction0to1(b.remainingPercent) {
                            hub.batteryRemainingPercent = frac
                        }
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

        session.drone.telemetry.statusText
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] st in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let text = st.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, self.shouldSurfaceVehicleStatusText(st.type, text: text) else { return }
                    let label = self.statusTextTypeLabel(st.type)
                    let line = "Vehicle message [\(label)]: \(text)"
                    self.appendVehicleLog(line, vehicleID: vehicleID)
                    self.appendRecentVehicleStatusLine(vehicleID: vehicleID, line: line)
                    self.onMirrorFleetLineToPaladin?(vehicleID, line)
                }
            })
            .disposed(by: session.bag)

        session.drone.mission.missionProgress
            .observe(on: MainScheduler.asyncInstance)
            .distinctUntilChanged()
            .subscribe(onNext: { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let cur = progress.current
                    let tot = progress.total
                    self.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                        hub.missionProgressCurrent = cur
                        hub.missionProgressTotal = tot
                    }
                    if tot > 0, cur < tot {
                        self.autopilotMissionCompletionLatchByVehicleID[vehicleID] = false
                    }
                    if tot > 0, cur >= tot {
                        let latched = self.autopilotMissionCompletionLatchByVehicleID[vehicleID] ?? false
                        if !latched {
                            self.autopilotMissionCompletionLatchByVehicleID[vehicleID] = true
                            let doneLine = "Autopilot mission run complete (progress \(cur)/\(tot)); notifying schedule."
                            self.appendVehicleLog(doneLine, vehicleID: vehicleID)
                            self.onMirrorFleetLineToPaladin?(vehicleID, doneLine)
                            self.onAutopilotMissionCycleFinished?(vehicleID)
                        }
                    }
                    let progLine = "Autopilot mission progress: item \(cur) of \(tot)."
                    self.appendVehicleLog(progLine, vehicleID: vehicleID)
                    self.onMirrorFleetLineToPaladin?(vehicleID, progLine)
                }
            })
            .disposed(by: session.bag)
    }

    private func stopSession(vehicleID: String) {
        guard let session = sessionsByVehicleID.removeValue(forKey: vehicleID) else { return }
        simulatedFleetVehicleIDs.remove(vehicleID)
        recentVehicleStatusMessagesByVehicleID[vehicleID] = nil
        autopilotMissionCompletionLatchByVehicleID[vehicleID] = nil
        session.bag = DisposeBag()
        session.drone.disconnect()
        session.runner.stop()
        releaseGrpcPort(session.grpcPort)
        hubTelemetryByVehicleID.removeValue(forKey: vehicleID)
        telemetryByVehicleID.removeValue(forKey: vehicleID)
        vehicleIDBySystemID.removeValue(forKey: session.systemID)
        applyLifecycleStatus(.init(stage: .stopped), vehicleID: vehicleID)
        if hubTelemetryByVehicleID.isEmpty {
            telemetry = nil
            hubTelemetry = nil
            bridgePhase = .awaitingVehicle
        }
    }

    func clearLog() {
        logLines.removeAll(keepingCapacity: true)
        logLinesByVehicleID.removeAll(keepingCapacity: true)
        simulationStdoutLogDedupe.reset()
    }

    func appendSimulationLog(_ line: String) {
        guard let toEmit = simulationStdoutLogDedupe.lineToAppendOrNil(line) else { return }
        appendLog(toEmit)
    }

    private func applyNativeTelemetry(vehicleID: String, systemID: Int, mutate: (inout FleetHubVehicleTelemetry) -> Void) {
        let wasAlreadyLive = vehicleStatusByVehicleID[vehicleID]?.stage == .live
        ensureVehicleModel(vehicleID: vehicleID, systemID: systemID, initialStatus: .init(stage: .connecting))
        if var model = vehicleModelsByVehicleID[vehicleID] {
            model.data.systemID = systemID
            model.applyTelemetryMutation(mutate)
            vehicleModelsByVehicleID[vehicleID] = model
            hubTelemetryByVehicleID[vehicleID] = model.data.telemetry
            telemetryByVehicleID[vehicleID] = model.collections.telemetrySnapshot
        }
        vehicleIDBySystemID[systemID] = vehicleID
        if let hub = hubTelemetryByVehicleID[vehicleID],
           !wasAlreadyLive,
           (hub.latitudeDeg != nil || hub.batteryRemainingPercent != nil || hub.gpsNumSatellites != nil || hub.healthArmable != nil) {
            appendVehicleLog("Telemetry active.", vehicleID: vehicleID)
        }
        applyLifecycleStatus(.init(stage: .live), vehicleID: vehicleID)
        hubTelemetry = hubTelemetryByVehicleID[vehicleID]
        telemetry = telemetryByVehicleID[vehicleID]
    }

    /// Resolves one vehicle stream from the keyed telemetry hub.
    func hubTelemetry(forVehicleID vehicleID: String) -> FleetHubVehicleTelemetry? {
        vehicleModelsByVehicleID[vehicleID]?.data.telemetry ?? hubTelemetryByVehicleID[vehicleID]
    }

    /// Resolves the active bridge stream key for a MAVLink system id, if discovered.
    func vehicleID(forSystemID systemID: Int) -> String? {
        vehicleIDBySystemID[systemID]
    }

    private func ensureVehicleModel(
        vehicleID: String,
        systemID: Int?,
        vehicleType: FleetVehicleType = .unknown,
        initialStatus: VehicleLifecycleStatus
    ) {
        if var existing = vehicleModelsByVehicleID[vehicleID] {
            if existing.data.systemID == nil, let systemID {
                existing.data.systemID = systemID
            }
            if existing.data.vehicleType == .unknown, vehicleType != .unknown {
                existing.data.vehicleType = vehicleType
            }
            vehicleModelsByVehicleID[vehicleID] = existing
            return
        }
        vehicleModelsByVehicleID[vehicleID] = FleetVehicleModel(
            vehicleID: vehicleID,
            systemID: systemID,
            vehicleType: vehicleType,
            initialStatus: initialStatus
        )
    }

    /// Promotes a previously-`unknown` vehicle type once the airframe is identified (e.g. MAV_TYPE inference,
    /// roster pick metadata). No-op when the model is already classified.
    func setVehicleType(_ type: FleetVehicleType, forVehicleID vehicleID: String) {
        guard type != .unknown else { return }
        guard var model = vehicleModelsByVehicleID[vehicleID] else { return }
        guard model.data.vehicleType != type else { return }
        model.data.vehicleType = type
        vehicleModelsByVehicleID[vehicleID] = model
    }

    /// Canonical short ID shown across logs, vehicle cards, and headers (e.g. `UAV-C:1`). Falls back to a `VEH:N`
    /// derived from the vehicleID tail when no model exists yet (very early in connection lifecycle).
    func displayShortID(forVehicleID vehicleID: String) -> String {
        if let model = vehicleModelsByVehicleID[vehicleID] {
            return model.displayShortID
        }
        let tail = vehicleID.split(separator: ":").last.map(String.init) ?? vehicleID
        return "VEH:\(tail)"
    }

    private func applyLifecycleStatus(_ status: VehicleLifecycleStatus, vehicleID: String) {
        vehicleStatusByVehicleID[vehicleID] = status
        if var model = vehicleModelsByVehicleID[vehicleID] {
            model.applyLifecycleStatus(status)
            vehicleModelsByVehicleID[vehicleID] = model
            telemetryByVehicleID[vehicleID] = model.collections.telemetrySnapshot
            hubTelemetryByVehicleID[vehicleID] = model.data.telemetry
        } else {
            vehicleModelsByVehicleID[vehicleID] = FleetVehicleModel(
                vehicleID: vehicleID,
                systemID: nil,
                initialStatus: status
            )
        }
    }

    /// MAVSDK maps MAVLink unknown `battery_remaining` (-1) as a small negative fraction; valid remaining is **0…1** (fraction) or **0…100** (percent) from the wire.
    private static func normalizedMavsdkBatteryFraction0to1(_ remainingPercent: Float) -> Double? {
        guard remainingPercent.isFinite else { return nil }
        if remainingPercent < 0 { return nil }
        if remainingPercent <= 1.0 + 1e-3 {
            return Double(min(1, max(0, remainingPercent)))
        }
        if remainingPercent <= 100 {
            return Double(remainingPercent) / 100.0
        }
        return nil
    }

    /// Request faster battery-related MAVLink via MAVSDK, and for **PX4 SITL** set a non-zero `BAT1_CAPACITY` so remaining % is estimable.
    private func applyMavlinkBatteryTelemetryTuningOnce(session: VehicleSession, vehicleID: String) {
        guard !session.didApplyMavlinkBatteryTuning else { return }
        session.didApplyMavlinkBatteryTuning = true

        session.drone.telemetry.setRateBattery(rateHz: 5.0)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onCompleted: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog("Set MAVSDK battery telemetry stream rate to 5 Hz.", vehicleID: vehicleID)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog(
                            "Battery telemetry set-rate unavailable: \(error.localizedDescription)",
                            vehicleID: vehicleID
                        )
                    }
                }
            )
            .disposed(by: session.bag)

        guard simulatedFleetVehicleIDs.contains(vehicleID) else { return }
        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack ?? .unknown
        guard stack == .px4 else { return }

        session.drone.param.setParamInt(name: "BAT1_CAPACITY", value: 5000)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onCompleted: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog(
                            "Applied SIM default BAT1_CAPACITY=5000 (mAh) for PX4 battery telemetry.",
                            vehicleID: vehicleID
                        )
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog(
                            "SIM BAT1_CAPACITY default skipped: \(error.localizedDescription)",
                            vehicleID: vehicleID
                        )
                    }
                }
            )
            .disposed(by: session.bag)
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > logLineLimit {
            logLines.removeFirst(logLines.count - logLineLimit)
        }
    }

    private func appendVehicleLog(_ line: String, vehicleID: String) {
        let tagged = "[\(displayShortID(forVehicleID: vehicleID))] \(line)"
        appendLog(tagged)
        var vehicleLogs = logLinesByVehicleID[vehicleID] ?? []
        vehicleLogs.append(line)
        if vehicleLogs.count > logLinesPerVehicleLimit {
            vehicleLogs.removeFirst(vehicleLogs.count - logLinesPerVehicleLimit)
        }
        logLinesByVehicleID[vehicleID] = vehicleLogs
    }

    private func markVehicleCommand(vehicleID: String, commandID: UUID, status: FleetVehicleCommandStatus) {
        guard var model = vehicleModelsByVehicleID[vehicleID] else { return }
        model.markCommandStatus(commandID: commandID, status: status)
        vehicleModelsByVehicleID[vehicleID] = model
    }

    private func describe(command: FleetVehicleCommand) -> String {
        switch command {
        case .arm:
            return "arm"
        case .disarm:
            return "disarm"
        case .holdPosition:
            return "holdPosition"
        case .gotoCoordinate(let coord, let relativeAltitudeM, let yawDeg):
            return String(
                format: "goto(lat=%.6f lon=%.6f relAlt=%.1f yaw=%.1f)",
                coord.lat,
                coord.lon,
                relativeAltitudeM,
                yawDeg
            )
        case .uploadAndStartMission(let items):
            return "uploadAndStartMission(\(items.count) items)"
        case .returnToLaunch:
            return "returnToLaunch"
        case .land:
            return "land"
        case .manualControl(let manual):
            return "manualControl(intent=\(manual.intent.rawValue) class=\(manual.vehicleClass.rawValue))"
        }
    }

    private func completionForManualControl(
        _ manual: ManualControlIntentCommand,
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        let yawStepDeg = manual.stepProfile.yawDeg
        let hub = hubTelemetryByVehicleID[vehicleID]
        switch manual.intent {
        case .toggleArm:
            if hub?.isArmed == true {
                return session.drone.action.disarm()
            }
            return session.drone.action.arm()
        case .engage:
            // Return/Engage: enter a stable low hover for keyboard-driving takeover.
            if manual.vehicleClass == .uav {
                return completionForUAVEngageHover(
                    vehicleID: vehicleID,
                    session: session,
                    hub: hub
                )
            }
            // Ground/surface/sub classes: engage is "ready/active" without forcing hold.
            if hub?.isArmed != true {
                return session.drone.action.arm()
            }
            return Completable.empty()
        case .terminate:
            // UAVs return home; surface/ground/sub default to hold/stop behavior.
            switch manual.vehicleClass {
            case .uav:
                return session.drone.action.returnToLaunch()
            case .ugv, .usv, .uuv, .unknown:
                return session.drone.action.hold()
            }
        case .yawLeft, .yawRight:
            guard let lat = hub?.latitudeDeg, let lon = hub?.longitudeDeg else {
                return Completable.error(NSError(domain: "FleetLinkService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No position telemetry for yaw command."]))
            }
            let currentYaw = hub?.headingDeg ?? 0
            let delta = manual.intent == .yawLeft ? -yawStepDeg : yawStepDeg
            let currentAbsoluteAlt = hub?.absoluteAltM ?? 0
            return session.drone.action.gotoLocation(
                latitudeDeg: lat,
                longitudeDeg: lon,
                absoluteAltitudeM: Float(currentAbsoluteAlt),
                yawDeg: Float(Self.normalizedDegrees(currentYaw + delta))
            )
        case .moveForward, .moveBackward, .moveLeft, .moveRight, .ascend, .descend:
            guard let hub else {
                return Completable.error(NSError(domain: "FleetLinkService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No telemetry for manual movement command."]))
            }
            return completionForManualMoveIntent(manual, hub: hub, session: session, vehicleID: vehicleID)
        }
    }

    /// UAV Live Drive engage pipeline:
    /// 1) Arm if needed.
    /// 2) Take off if disarmed or still on/near ground.
    /// 3) For PX4, request ALTCTL/ALTHOLD.
    /// 4) Hold a low hover setpoint (~0.1m AGL) at current lat/lon/yaw.
    private func completionForUAVEngageHover(
        vehicleID: String,
        session: VehicleSession,
        hub: FleetHubVehicleTelemetry?
    ) -> Completable {
        let isArmed = hub?.isArmed == true
        let relAlt = hub?.relativeAltM ?? 0
        let shouldTakeoff = !isArmed || relAlt < 0.05

        var pipeline: Completable = isArmed ? .empty() : session.drone.action.arm()
        if shouldTakeoff {
            pipeline = pipeline.andThen(session.drone.action.takeoff())
        }
        pipeline = pipeline.andThen(
            requestPX4AltitudeControlModeIfAvailable(vehicleID: vehicleID, session: session)
        )

        guard
            let lat = hub?.latitudeDeg,
            let lon = hub?.longitudeDeg,
            let absAlt = hub?.absoluteAltM
        else {
            return pipeline
        }

        let inferredGroundAbsAlt = absAlt - relAlt
        let targetAbsoluteAlt = inferredGroundAbsAlt + 0.1
        let yaw = hub?.headingDeg ?? 0
        return pipeline.andThen(
            session.drone.action.gotoLocation(
                latitudeDeg: lat,
                longitudeDeg: lon,
                absoluteAltitudeM: Float(targetAbsoluteAlt),
                yawDeg: Float(Self.normalizedDegrees(yaw))
            )
        )
    }

    /// Best-effort PX4 engage mode request for keyboard takeover (`Return` key).
    /// Tries `ALTCTL` first, then `ALTHOLD` for stacks/aliases that differ.
    private func requestPX4AltitudeControlModeIfAvailable(
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack
            ?? hubTelemetryByVehicleID[vehicleID]?.autopilotStack
            ?? .unknown
        guard stack == .px4 else { return Completable.empty() }

        return session.drone.shell.send(command: "commander mode altctl")
            .catch { _ in
                session.drone.shell.send(command: "commander mode althold")
            }
    }

    private func completionForManualMoveIntent(
        _ manual: ManualControlIntentCommand,
        hub: FleetHubVehicleTelemetry,
        session: VehicleSession,
        vehicleID: String
    ) -> Completable {
        let lateralForwardBackwardStepM = manual.stepProfile.moveForwardBackwardM
        let lateralStrafeStepM = manual.stepProfile.moveLeftRightM
        let verticalStepM = manual.stepProfile.verticalM
        guard let lat = hub.latitudeDeg, let lon = hub.longitudeDeg else {
            return Completable.error(NSError(domain: "FleetLinkService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No position telemetry for movement command."]))
        }
        let heading = hub.headingDeg ?? 0
        let currentAbsoluteAlt = hub.absoluteAltM ?? 0
        var verticalDeltaM = 0.0
        var bearing = heading
        var distanceM = 0.0

        switch manual.intent {
        case .moveForward:
            bearing = heading
            distanceM = lateralForwardBackwardStepM
        case .moveBackward:
            bearing = heading + 180
            distanceM = lateralForwardBackwardStepM
        case .moveLeft:
            bearing = heading - 90
            distanceM = lateralStrafeStepM
        case .moveRight:
            bearing = heading + 90
            distanceM = lateralStrafeStepM
        case .ascend:
            guard manual.vehicleClass == .uav || manual.vehicleClass == .uuv else {
                appendVehicleLog("Manual control ignored: vertical axis unavailable for this vehicle class.", vehicleID: vehicleID)
                return Completable.empty()
            }
            verticalDeltaM += verticalStepM
        case .descend:
            guard manual.vehicleClass == .uav || manual.vehicleClass == .uuv else {
                appendVehicleLog("Manual control ignored: vertical axis unavailable for this vehicle class.", vehicleID: vehicleID)
                return Completable.empty()
            }
            verticalDeltaM -= verticalStepM
        default:
            break
        }

        let nextRelAlt = (hub.relativeAltM ?? 0) + verticalDeltaM
        if manual.vehicleClass == .uav, nextRelAlt < 0 {
            appendVehicleLog("Manual control blocked: UAV target altitude would be below ground.", vehicleID: vehicleID)
            return Completable.empty()
        }
        if manual.vehicleClass == .uuv, nextRelAlt > 0 {
            appendVehicleLog("Manual control blocked: UUV target altitude would be above waterline.", vehicleID: vehicleID)
            return Completable.empty()
        }

        let target = Self.coordinateOffset(fromLat: lat, lon: lon, meters: distanceM, bearingDeg: bearing)
        let targetAbsoluteAlt = currentAbsoluteAlt + verticalDeltaM
        return session.drone.action.gotoLocation(
            latitudeDeg: target.lat,
            longitudeDeg: target.lon,
            absoluteAltitudeM: Float(targetAbsoluteAlt),
            yawDeg: Float(Self.normalizedDegrees(heading))
        )
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: 360)
        if r < 0 { return r + 360 }
        return r
    }

    private static func coordinateOffset(fromLat lat: Double, lon: Double, meters: Double, bearingDeg: Double) -> (lat: Double, lon: Double) {
        guard meters > 0 else { return (lat, lon) }
        let r = 6_371_000.0
        let δ = meters / r
        let θ = bearingDeg * .pi / 180
        let φ1 = lat * .pi / 180
        let λ1 = lon * .pi / 180
        let sinφ1 = sin(φ1), cosφ1 = cos(φ1)
        let sinδ = sin(δ), cosδ = cos(δ)
        let sinφ2 = sinφ1 * cosδ + cosφ1 * sinδ * cos(θ)
        let φ2 = asin(sinφ2)
        let y = sin(θ) * sinδ * cosφ1
        let x = cosδ - sinφ1 * sinφ2
        let λ2 = λ1 + atan2(y, x)
        return (φ2 * 180 / .pi, λ2 * 180 / .pi)
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

