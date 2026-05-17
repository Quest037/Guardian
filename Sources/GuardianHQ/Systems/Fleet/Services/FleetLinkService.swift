import AppKit
import Combine
import Foundation
import Mavsdk
@preconcurrency import RxSwift

/// Shared Rx scheduler for MAVSDK generated plugins that call blocking `wait()` inside `subscribe`.
/// RxSwift does not mark schedulers `Sendable`; the box is immutable after init and only used for `subscribe(on:)`.
private final class FleetLinkMavsdkBlockingRpcSchedulerBox: @unchecked Sendable {
    let scheduler: SchedulerType
    init() {
        scheduler = ConcurrentDispatchQueueScheduler(qos: .userInitiated)
    }
}

private let fleetLinkMavsdkBlockingRpcBox = FleetLinkMavsdkBlockingRpcSchedulerBox()

/// Delivers Rx `Completable` terminal events from async work without blocking the subscribing thread.
private final class FleetLinkCompletableSink: @unchecked Sendable {
    private let observer: (CompletableEvent) -> Void

    init(_ observer: @escaping (CompletableEvent) -> Void) {
        self.observer = observer
    }

    func completed() {
        observer(.completed)
    }

    func failed(_ error: Error) {
        observer(.error(error))
    }
}

/// Rx bridge for ``FleetLinkService/awaitCompletableForManualStream`` — must be `nonisolated` so
/// `subscribe(on:)` / `observe(on:)` callbacks are not `@MainActor`-isolated while running off the UI thread.
private enum FleetLinkMavsdkCompletableBridge {
    nonisolated static func awaitBridged(_ completable: Completable) async throws {
        try await withCheckedThrowingContinuation { cont in
            _ = subscribe(
                completable,
                onCompleted: { cont.resume() },
                onError: { cont.resume(throwing: $0) }
            )
        }
    }

    nonisolated static func subscribe(
        _ completable: Completable,
        onCompleted: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> Disposable {
        completable
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onCompleted: onCompleted, onError: onError)
    }

    /// `Completable.create` subscribe handler for PX4 raw SET_MODE — factory is `nonisolated` so
    /// ``awaitBridged`` does not execute a `@MainActor` closure on the MAVSDK worker queue.
    nonisolated static func px4SetModeCompletable(
        port: UInt16,
        targetSystem: UInt8,
        mainMode: Px4ModeCommander.MainMode,
        subMode: UInt8,
        logTag: String,
        appendLog: @escaping @Sendable (String) -> Void
    ) -> Completable {
        Completable.create { observer in
            let sink = FleetLinkCompletableSink(observer)
            Task {
                await Px4ModeCommander.setMode(
                    port: port,
                    targetSystem: targetSystem,
                    mainMode: mainMode,
                    subMode: subMode
                )
                appendLog(
                    "PX4 SET_MODE \(mainMode) (sub=\(subMode)) sent (\(logTag), gcs udp 127.0.0.1:\(port), target_system=\(targetSystem))."
                )
                sink.completed()
            }
            return Disposables.create()
        }
    }

    nonisolated static func mavlinkCommandLongCompletable(
        request: MavlinkCommandLongRequest,
        port: UInt16,
        targetSystem: UInt8,
        appendLog: @escaping @Sendable (String) -> Void,
        appendError: @escaping @Sendable (String, Error) -> Void
    ) -> Completable {
        Completable.create { observer in
            let sink = FleetLinkCompletableSink(observer)
            Task {
                do {
                    try await MavlinkCommandLongSender.send(
                        request: request,
                        port: port,
                        targetSystem: targetSystem
                    )
                    appendLog(
                        "MAVLink COMMAND_LONG \(request.command) (\(request.humanLabel)) sent (udp 127.0.0.1:\(port), target_system=\(targetSystem))."
                    )
                    sink.completed()
                } catch {
                    appendError(
                        "MAVLink COMMAND_LONG \(request.command) failed (\(request.humanLabel)).",
                        error
                    )
                    sink.failed(error)
                }
            }
            return Disposables.create()
        }
    }

    nonisolated static func px4GotoOffboardCompletable(
        performMove: @escaping @MainActor @Sendable () async throws -> Void
    ) -> Completable {
        Completable.create { observer in
            let sink = FleetLinkCompletableSink(observer)
            Task { @MainActor in
                do {
                    try await performMove()
                    sink.completed()
                } catch {
                    sink.failed(error)
                }
            }
            return Disposables.create()
        }
    }
}

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

    /// MC-R operator debug overlays and verbose diagnostics (Settings bar toggle).
    @Published private(set) var isDebugEnabled = false

    func setDebugEnabled(_ enabled: Bool) {
        guard isDebugEnabled != enabled else { return }
        isDebugEnabled = enabled
    }

    @Published private(set) var bridgePhase: TelemetryBridgePhase = .awaitingVehicle
    @Published private(set) var telemetry: FleetTelemetrySnapshot?
    @Published private(set) var hubTelemetry: FleetHubVehicleTelemetry?
    @Published private(set) var hubTelemetryByVehicleID: [String: FleetHubVehicleTelemetry] = [:]
    @Published private(set) var telemetryByVehicleID: [String: FleetTelemetrySnapshot] = [:]
    @Published private(set) var vehicleIDBySystemID: [Int: String] = [:]
    @Published private(set) var vehicleModelsByVehicleID: [String: FleetVehicleModel] = [:]
    @Published private(set) var vehicleStatusByVehicleID: [String: VehicleLifecycleStatus] = [:]
    @Published private(set) var isSimulateEnabled = true

    /// Vehicle IDs that completed **PX4 UGV** offboard park; Mission Control may surface **Continue mission** until cleared.
    @Published private(set) var mcrOperatorParkAwaitingContinueVehicleIDs: Set<String> = []

    /// Publishes intermediate and terminal events from in-flight MAVSDK Calibration
    /// plugin procedures. Layer 1 recipe runners / Layer 2 wizards / plugins subscribe
    /// here to surface progress percentages, operator prompts ("Rotate vehicle"), and
    /// cancellation. The Layer 0 catalogue still returns one terminal
    /// ``FleetCommandResponse`` per `do.calibrate.*` invocation; this side channel is
    /// purely supplementary.
    var calibrationProgressEventsPublisher: AnyPublisher<FleetCalibrationProgressEvent, Never> {
        calibrationProgressSubject.eraseToAnyPublisher()
    }
    private let calibrationProgressSubject = PassthroughSubject<FleetCalibrationProgressEvent, Never>()

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
        /// Continuous body-velocity / virtual-stick streamer. Created on demand when the
        /// operator activates a Live Drive freestyle session and torn down when the session ends.
        var manualStream: ManualControlStream?
        /// Mission Control squad convoy wingman OFFBOARD / Guided position stream (not Live Drive).
        var formationFollowStream: FormationFollowStream?
        /// One-shot: after MAVSDK reports connected, `applySimState` reinforces spawn pose/SIM fields from `SimSpawnDefaults`.
        var pendingSpawnSimState: FleetSimState?

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
    /// One "mission cycle finished" emission per execution; reset when progress advances in-leg.
    private var autopilotMissionCompletionLatchByVehicleID: [String: Bool] = [:]
    /// True after `current` has entered an in-progress leg (`0 < current < total`, or single-item `current == total` after `0`).
    private var autopilotMissionCycleHasInProgressLegByVehicleID: [String: Bool] = [:]
    /// Last `(current,total)` mirrored to the vehicle log + Paladin for MAVSDK mission progress (drops duplicate emissions).
    private var lastMissionProgressLoggedPairByVehicleID: [String: (cur: Int32, tot: Int32)] = [:]
    /// Throttled clock for Mission Control / map surfaces that only need **coarse** follow of multi-vehicle hub churn.
    @Published private(set) var hubFleetTelemetryTick: UInt64 = 0
    private var hubFleetTickLastEmit = Date.distantPast
    private var hubFleetTickWorkItem: DispatchWorkItem?
    private var lastTelemetryMutationVehicleID: String?
    /// Deduplicate noisy recurring lines from SITL stdout (see `SimulationStdoutLogDedupeState`).
    private var simulationStdoutLogDedupe = SimulationStdoutLogDedupeState()
    /// Vehicle stream keys (`sysid:n`) created by `registerSimulatedVehicle` (built-in SITL only).
    private var simulatedFleetVehicleIDs: Set<String> = []

    /// Per-stream narrow observation for MC‑R roster tiles (strategy **A** — ``README_FULL.md`` → **MC-R live UI row contracts** → **Fleet per-vehicle observation strategy (locked)**).
    private var mcrRosterLiveChannelsByVehicleID: [String: FleetVehicleLiveChannel] = [:]
    private var mcrRosterLiveChannelRefCount: [String: Int] = [:]

    /// Live Drive **control session**: the vehicle ID that may receive `liveDrive.*` `.manualTakeover` commands
    /// and manual-control stream updates. Set when any LD session starts (freestyle or mission, SIM or live); cleared when it ends.
    private var liveDriveControlSessionVehicleID: String?

    /// Fires when MAVSDK mission progress indicates a full mission run has finished (`current >= total`).
    var onAutopilotMissionCycleFinished: ((String) -> Void)?

    /// Per-vehicle lines that also appear in the global log (STATUSTEXT, mission progress), for Mission Control Paladin.
    /// Arguments: `vehicleID`, untagged line (no `[sysid:n]` prefix).
    var onMirrorFleetLineToPaladin: ((String, String) -> Void)?

    init(userDefaults: UserDefaults = .standard) {
        configuration = Self.load(from: userDefaults) ?? .defaults
        GuardianAppQuitCoordinator.shared.noteFleetLinkServiceCreated(self)
    }

    // MARK: - MC‑R per-vehicle live channels (roster strip)

    /// Returns the per-stream live channel (creates if missing; **does not** change retain count). Pair with ``mcrRosterRetainLiveChannel(forVehicleID:)`` / ``mcrRosterReleaseLiveChannel(forVehicleID:)`` from the tile lifecycle.
    func mcrRosterLiveChannel(forVehicleID vehicleID: String) -> FleetVehicleLiveChannel {
        if let existing = mcrRosterLiveChannelsByVehicleID[vehicleID] { return existing }
        let created = FleetVehicleLiveChannel(vehicleID: vehicleID)
        mcrRosterLiveChannelsByVehicleID[vehicleID] = created
        return created
    }

    func mcrRosterRetainLiveChannel(forVehicleID vehicleID: String) {
        _ = mcrRosterLiveChannel(forVehicleID: vehicleID)
        mcrRosterLiveChannelRefCount[vehicleID, default: 0] += 1
    }

    func mcrRosterReleaseLiveChannel(forVehicleID vehicleID: String) {
        guard let current = mcrRosterLiveChannelRefCount[vehicleID] else { return }
        let next = current - 1
        if next <= 0 {
            mcrRosterLiveChannelRefCount[vehicleID] = nil
            // Drop the registry entry so long MC-R sessions do not accumulate `FleetVehicleLiveChannel`
            // shells for stream ids that scrolled away. SwiftUI `ObservedObject` keeps the instance
            // alive until the row tears down; the next `mcrRosterLiveChannel(forVehicleID:)` creates fresh.
            if let channel = mcrRosterLiveChannelsByVehicleID.removeValue(forKey: vehicleID) {
                channel.clearFleetSlice()
            }
        } else {
            mcrRosterLiveChannelRefCount[vehicleID] = next
        }
    }

    private func refreshMcrRosterLiveChannelsAfterHubTick() {
        guard !mcrRosterLiveChannelRefCount.isEmpty else { return }
        for vehicleID in mcrRosterLiveChannelRefCount.keys {
            guard (mcrRosterLiveChannelRefCount[vehicleID] ?? 0) > 0 else { continue }
            mcrRosterLiveChannelsByVehicleID[vehicleID]?.refresh(from: self)
        }
    }

    /// Publishes ``hubFleetTelemetryTick`` then refreshes retained MC‑R channels — **single hub-facing exit** beside
    /// ``scheduleHubFleetTelemetryTickThrottled`` / session teardown so coalesced UI never observes a tick without a channel pass.
    private func publishHubFleetTelemetryTickAndRefreshMcrChannels() {
        hubFleetTelemetryTick &+= 1
        refreshMcrRosterLiveChannelsAfterHubTick()
    }

    private func clearMcrRosterLiveChannelFleetSlicesForAllKeys() {
        for channel in mcrRosterLiveChannelsByVehicleID.values {
            channel.clearFleetSlice()
        }
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
        autopilotMissionCycleHasInProgressLegByVehicleID.removeAll(keepingCapacity: true)
        simulationStdoutLogDedupe.reset()
        simulatedFleetVehicleIDs.removeAll(keepingCapacity: true)
        liveDriveControlSessionVehicleID = nil
        bridgePhase = .inactive
        lastError = nil
        mcrOperatorParkAwaitingContinueVehicleIDs.removeAll()
        hubFleetTickWorkItem?.cancel()
        hubFleetTickWorkItem = nil
        lastTelemetryMutationVehicleID = nil
        hubFleetTickLastEmit = .distantPast
        lastMissionProgressLoggedPairByVehicleID.removeAll(keepingCapacity: true)
        mcrRosterLiveChannelsByVehicleID.removeAll(keepingCapacity: true)
        mcrRosterLiveChannelRefCount.removeAll(keepingCapacity: true)
    }

    /// Install or clear the Live Drive control session (see `liveDriveControlSessionVehicleID`).
    func setLiveDriveControlSessionVehicle(_ vehicleID: String?) {
        liveDriveControlSessionVehicleID = vehicleID
        if let id = vehicleID {
            appendVehicleLog("Live Drive control session active [\(id)].", vehicleID: id)
        }
    }

    /// Clear the control session only when it still points at this vehicle (safe for teardown / discard).
    func clearLiveDriveControlSessionVehicleIfMatches(vehicleID: String) {
        guard liveDriveControlSessionVehicleID == vehicleID else { return }
        liveDriveControlSessionVehicleID = nil
        appendVehicleLog("Live Drive control session cleared.", vehicleID: vehicleID)
    }

    /// Clears Live Drive control session and MC‑R **park awaiting continue** latches after a Mission Control run
    /// reaches **completed**, so post-run automation (SIM clean up) is not blocked by operator-session gates.
    func clearOperatorSessionHintsAfterMissionRunCompleted() {
        if let vid = liveDriveControlSessionVehicleID {
            liveDriveControlSessionVehicleID = nil
            appendVehicleLog("Live Drive control session cleared (mission run completed).", vehicleID: vid)
        }
        let parkedIDs = Array(mcrOperatorParkAwaitingContinueVehicleIDs)
        mcrOperatorParkAwaitingContinueVehicleIDs.removeAll()
        for vid in parkedIDs {
            appendVehicleLog("MC-R operator park await-continue cleared (mission run completed).", vehicleID: vid)
        }
    }

    func applyConfiguration(_ config: FleetLinkConfiguration) {
        configuration = config
        save()
    }

    func setSimulateEnabled(_ enabled: Bool) {
        isSimulateEnabled = enabled
    }

    /// `true` when this vehicle stream is a **Guardian-managed** built-in SITL (``applySimState`` / spawn handshake).
    func isGuardianManagedSitlStream(vehicleID: String) -> Bool {
        simulatedFleetVehicleIDs.contains(vehicleID)
    }

    /// Stream keys for Guardian-managed SITLs that still have an active MAVSDK session (deterministic order).
    func guardianManagedSitlSessionVehicleIDsSorted() -> [String] {
        sessionsByVehicleID.keys.filter { isGuardianManagedSitlStream(vehicleID: $0) }.sorted()
    }

    /// Best-effort **manual stream stop + mission pause + offboard stop** for the given stream keys (Mission Run SIM clean up Phase A).
    ///
    /// Mirrors the early steps of ``runParkSequence`` so motion from OFFBOARD / mission execution is damped **before**
    /// the park recipe runs in the same async cleanup pass. Per-vehicle failures are logged; returns how many IDs were targeted.
    @discardableResult
    func awaitGuardianSitlMotionStopAfterMissionRunCompleted(vehicleIDs: [String]) async -> Int {
        guard !vehicleIDs.isEmpty else { return 0 }
        await performGuardianSitlMotionStopAfterMissionRunCompleted(vehicleIDs: vehicleIDs)
        return vehicleIDs.count
    }

    /// Per-vehicle outcome for ``performRunCleanupSimKill(vehicleID:)`` (Mission Run SIM cleanup).
    enum RunCleanupSimKillOutcome: Equatable {
        case skippedNoSession
        case succeeded
        case failed
    }

    /// Best-effort **manual stream stop** + MAVSDK ``Action/kill`` (force disarm) on one **Guardian-managed SITL** stream.
    ///
    /// Used by Mission Run complete SIM cleanup instead of the park recipe so SITLs return to a disarmed, motor-off state
    /// even when higher-level recipes would fail or prompt the operator.
    func performRunCleanupSimKill(vehicleID: String) async -> RunCleanupSimKillOutcome {
        guard let session = sessionsByVehicleID[vehicleID] else { return .skippedNoSession }
        guard isGuardianManagedSitlStream(vehicleID: vehicleID) else { return .skippedNoSession }
        appendVehicleLog("Mission run complete: SIM cleanup kill (force disarm) starting.", vehicleID: vehicleID)
        await stopManualControlStream(vehicleID: vehicleID)
        do {
            try await awaitCompletableForManualStream(session.drone.action.kill())
            appendVehicleLog("Mission run complete: SIM cleanup kill acknowledged.", vehicleID: vehicleID)
            return .succeeded
        } catch {
            appendVehicleLog(
                "Mission run complete: SIM cleanup kill failed (\(mavsdkPublicErrorDescription(error))).",
                vehicleID: vehicleID
            )
            return .failed
        }
    }

    /// Clears the **Continue mission** affordance latch for this vehicle (after the operator queues continue, or to discard stale UI).
    func clearMcrOperatorParkAwaitingContinue(vehicleID: String) {
        guard mcrOperatorParkAwaitingContinueVehicleIDs.contains(vehicleID) else { return }
        var next = mcrOperatorParkAwaitingContinueVehicleIDs
        next.remove(vehicleID)
        mcrOperatorParkAwaitingContinueVehicleIDs = next
    }

    /// Mission Control triage phase for live roster / berth detail (PX4 UGV park latch vs on-mission heuristic).
    func mcrOperatorVehiclePhase(vehicleID: String) -> FleetMcrOperatorVehiclePhase {
        if mcrOperatorParkAwaitingContinueVehicleIDs.contains(vehicleID) {
            return .operatorParkAwaitingContinue
        }
        guard let hub = hubTelemetryByVehicleID[vehicleID] else { return .unknown }
        if Self.hubTelemetrySuggestsMissionExecution(hub) { return .onMission }
        return .unknown
    }

    private static func hubTelemetrySuggestsMissionExecution(_ hub: FleetHubVehicleTelemetry) -> Bool {
        guard hub.isArmed else { return false }
        let mode = hub.flightMode.lowercased()
        if mode.contains("mission") { return true }
        if let t = hub.missionProgressTotal, let c = hub.missionProgressCurrent, t > 0, c < t { return true }
        return false
    }

    private func recordMcrOperatorParkAwaitingContinue(vehicleID: String) {
        var next = mcrOperatorParkAwaitingContinueVehicleIDs
        next.insert(vehicleID)
        mcrOperatorParkAwaitingContinueVehicleIDs = next
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
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
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

    /// Read a floating-point autopilot parameter for a connected vehicle.
    func getVehicleFloatParameter(
        vehicleID: String,
        name: String,
        source: String,
        onResult: @escaping @MainActor (Result<Float, FleetLinkParameterError>) -> Void
    ) {
        guard let session = sessionsByVehicleID[vehicleID] else {
            onResult(.failure(FleetLinkParameterError(message: "No MAVSDK session for vehicle.")))
            return
        }
        session.drone.param.getParamFloat(name: name)
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
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
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
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

    /// Set a floating-point autopilot parameter for a connected vehicle.
    func setVehicleFloatParameter(
        vehicleID: String,
        name: String,
        value: Float,
        source: String,
        onResult: (@MainActor (Result<Void, FleetLinkParameterError>) -> Void)? = nil
    ) {
        guard let session = sessionsByVehicleID[vehicleID] else {
            onResult?(.failure(FleetLinkParameterError(message: "No MAVSDK session for vehicle.")))
            return
        }
        session.drone.param.setParamFloat(name: name, value: value)
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
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

    /// Stack-agnostic SIM battery-drain toggle used by operational flows (LiveDrive / MC Running).
    /// - PX4: sets `SIM_BAT_DRAIN` (`0` = disabled, `>0` = seconds for a full 100→0% discharge **while armed**).
    ///   Upstream `BatterySimulator` **resets to 100% whenever disarmed**, so disarmed LD/MC-R will look “stuck” at full.
    /// - ArduPilot: sets `SIM_BATT_CAP_AH` (`0` = no integrator model / static pack, `>0` = capacity for the SITL battery model).
    ///   Remaining charge only moves with **non‑zero battery current** (e.g. motor load); idling at ~0 A yields little or no drop.
    func setSimBatteryDrainEnabled(
        vehicleID: String,
        enabled: Bool,
        rate: SimBatteryDrainRate = .normal,
        source: String,
        onResult: (@MainActor (Result<Void, FleetLinkParameterError>) -> Void)? = nil
    ) {
        guard simulatedFleetVehicleIDs.contains(vehicleID) else {
            onResult?(.failure(FleetLinkParameterError(message: "Battery drain control applies to SIM vehicles only.")))
            return
        }
        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack ?? .unknown
        switch stack {
        case .px4:
            let drainSeconds: Float = enabled ? rate.px4FullDischargeSeconds : 0
            setVehicleFloatParameter(
                vehicleID: vehicleID,
                name: "SIM_BAT_DRAIN",
                value: drainSeconds,
                source: source,
                onResult: onResult
            )
        case .ardupilot:
            // ArduPilot SITL depletion model is active only when capacity Ah is positive.
            let capacityAh: Float = enabled ? rate.ardupilotCapacityAh : 0.0
            setVehicleFloatParameter(
                vehicleID: vehicleID,
                name: "SIM_BATT_CAP_AH",
                value: capacityAh,
                source: source,
                onResult: onResult
            )
        case .unknown:
            onResult?(.failure(FleetLinkParameterError(message: "Autopilot stack unknown; cannot apply SIM drain toggle.")))
        }
    }

    /// Applies `state` to a **Guardian-managed SITL** stream via MAVLink params (pose + optional SIM knobs).
    ///
    /// This is the **single entrypoint** for SIM state on the wire. Used by:
    /// - Spawn handshake (`sitl.spawnHandshake`), after MAVSDK connects
    /// - Mission Control‑E and future “SIM recovery / arm prep” flows (build a `FleetSimState`, call here)
    ///
    /// - **ArduPilot:** `SIM_OPOS_LAT` / `SIM_OPOS_LNG` / `SIM_OPOS_ALT` / `SIM_OPOS_HDG` — same family as `sim_vehicle.py -l`.
    ///   Optional `SIM_BATT_VOLTAGE`, `SIM_BATT_CAP_AH` when present on `state`.
    /// - **PX4 SIH:** `SIH_LOC_LAT0` / `SIH_LOC_LON0` / `SIH_LOC_H0` / `SIH_LOC_HDG0`; optional `SIM_BAT_DRAIN` when set on `state`.
    ///
    /// When callers must change ArduPilot `SIM_BATT_CAP_AH`, stop any manual control stream and call
    /// `setSimBatteryDrainEnabled(false)` first so the parameter is writable.
    func applySimState(
        vehicleID: String,
        state: FleetSimState,
        autopilotStack: FleetAutopilotStack,
        source: String
    ) async {
        guard simulatedFleetVehicleIDs.contains(vehicleID) else {
            appendVehicleLog("applySimState skipped: not a Guardian SITL stream [\(source)].", vehicleID: vehicleID)
            return
        }
        guard sessionsByVehicleID[vehicleID] != nil else { return }

        let altM = Float(state.absoluteAltitudeM ?? 0)
        let tagBase = "\(source).pose"

        switch autopilotStack {
        case .ardupilot:
            await awaitSetSimStateFloatBestEffort(
                vehicleID: vehicleID,
                name: "SIM_OPOS_LAT",
                value: Float(state.latitudeDeg),
                logTag: "\(tagBase).SIM_OPOS_LAT"
            )
            await awaitSetSimStateFloatBestEffort(
                vehicleID: vehicleID,
                name: "SIM_OPOS_LNG",
                value: Float(state.longitudeDeg),
                logTag: "\(tagBase).SIM_OPOS_LNG"
            )
            await awaitSetSimStateFloatBestEffort(
                vehicleID: vehicleID,
                name: "SIM_OPOS_ALT",
                value: altM,
                logTag: "\(tagBase).SIM_OPOS_ALT"
            )
            await awaitSetSimStateFloatBestEffort(
                vehicleID: vehicleID,
                name: "SIM_OPOS_HDG",
                value: state.yawDeg,
                logTag: "\(tagBase).SIM_OPOS_HDG"
            )
            appendVehicleLog(
                "applySimState: ArduPilot SIM_OPOS_* applied [\(source)].",
                vehicleID: vehicleID
            )
            if let v = state.batteryVoltageV, v > 0.1 {
                await awaitSetSimStateFloatBestEffort(
                    vehicleID: vehicleID,
                    name: "SIM_BATT_VOLTAGE",
                    value: Float(v),
                    logTag: "\(tagBase).SIM_BATT_VOLTAGE"
                )
            }
            if let cap = state.ardupilotSimBattCapAh, cap > 0 {
                await awaitSetSimStateFloatBestEffort(
                    vehicleID: vehicleID,
                    name: "SIM_BATT_CAP_AH",
                    value: cap,
                    logTag: "\(tagBase).SIM_BATT_CAP_AH"
                )
            }
        case .px4:
            await awaitSetSimStateFloatBestEffort(
                vehicleID: vehicleID,
                name: "SIH_LOC_LAT0",
                value: Float(state.latitudeDeg),
                logTag: "\(tagBase).SIH_LOC_LAT0"
            )
            await awaitSetSimStateFloatBestEffort(
                vehicleID: vehicleID,
                name: "SIH_LOC_LON0",
                value: Float(state.longitudeDeg),
                logTag: "\(tagBase).SIH_LOC_LON0"
            )
            await awaitSetSimStateFloatBestEffort(
                vehicleID: vehicleID,
                name: "SIH_LOC_H0",
                value: altM,
                logTag: "\(tagBase).SIH_LOC_H0"
            )
            // Mirror of ArduPilot's SIM_OPOS_HDG — PX4 SIH's heading initial uses the same `SIH_LOC_*`
            // family. `awaitSetSimStateFloatBestEffort` tolerates "param not found" gracefully (logs +
            // continues), so on PX4 builds where this name differs we'll see the failure in the vehicle
            // log and can rename here without touching anything else.
            await awaitSetSimStateFloatBestEffort(
                vehicleID: vehicleID,
                name: "SIH_LOC_HDG0",
                value: state.yawDeg,
                logTag: "\(tagBase).SIH_LOC_HDG0"
            )
            if let drain = state.px4SimBatDrain {
                await awaitSetSimStateFloatBestEffort(
                    vehicleID: vehicleID,
                    name: "SIM_BAT_DRAIN",
                    value: drain,
                    logTag: "\(tagBase).SIM_BAT_DRAIN"
                )
            }
            appendVehicleLog(
                "applySimState: PX4 SIH_LOC_* (+ SIM_BAT_DRAIN if set) [\(source)].",
                vehicleID: vehicleID
            )
        case .unknown:
            appendVehicleLog(
                "applySimState skipped: autopilot stack unknown [\(source)].",
                vehicleID: vehicleID
            )
            return
        }

        reflectAppliedSimStateInHubTelemetry(
            vehicleID: vehicleID,
            state: state,
            autopilotStack: autopilotStack,
            source: source
        )
    }

    /// Best-effort SIM pack reset after Mission Run **completed** cleanup: disable depletion, push nominal SIM battery params where applicable, patch hub **100%** remaining (Guardian SITL only).
    func applySimBatteryFullChargeAfterRunCleanup(
        vehicleID: String,
        autopilotStack: FleetAutopilotStack,
        source: String
    ) async {
        guard simulatedFleetVehicleIDs.contains(vehicleID) else {
            appendVehicleLog("applySimBatteryFull skipped: not Guardian SITL [\(source)].", vehicleID: vehicleID)
            return
        }
        guard sessionsByVehicleID[vehicleID] != nil else {
            appendVehicleLog("applySimBatteryFull skipped: no session [\(source)].", vehicleID: vehicleID)
            return
        }
        guard autopilotStack != .unknown else {
            appendVehicleLog("applySimBatteryFull skipped: stack unknown [\(source)].", vehicleID: vehicleID)
            return
        }
        let drainSource = "\(source).drain_off"
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            setSimBatteryDrainEnabled(vehicleID: vehicleID, enabled: false, source: drainSource) { _ in
                cont.resume()
            }
        }
        let defaults = SimSpawnDefaults.default
        switch autopilotStack {
        case .ardupilot:
            await awaitSetSimStateFloatBestEffort(
                vehicleID: vehicleID,
                name: "SIM_BATT_CAP_AH",
                value: 0,
                logTag: "\(source).SIM_BATT_CAP_AH"
            )
            await awaitSetSimStateFloatBestEffort(
                vehicleID: vehicleID,
                name: "SIM_BATT_VOLTAGE",
                value: Float(defaults.batteryVoltageV),
                logTag: "\(source).SIM_BATT_VOLTAGE"
            )
        case .px4:
            await awaitSetSimStateFloatBestEffort(
                vehicleID: vehicleID,
                name: "SIM_BAT_DRAIN",
                value: 0,
                logTag: "\(source).SIM_BAT_DRAIN"
            )
        case .unknown:
            break
        }
        reflectSimBatteryFullChargeInHub(vehicleID: vehicleID, source: source)
    }

    private func reflectSimBatteryFullChargeInHub(vehicleID: String, source: String) {
        guard let session = sessionsByVehicleID[vehicleID] else {
            appendVehicleLog("reflectSimBatteryFull skipped: no session [\(source)].", vehicleID: vehicleID)
            return
        }
        let lifecycle = vehicleStatusByVehicleID[vehicleID] ?? VehicleLifecycleStatus(stage: .live)
        let existingType = vehicleModelsByVehicleID[vehicleID]?.data.vehicleType ?? .unknown
        ensureVehicleModel(
            vehicleID: vehicleID,
            systemID: session.systemID,
            vehicleType: existingType,
            initialStatus: lifecycle
        )
        guard var model = vehicleModelsByVehicleID[vehicleID] else {
            appendVehicleLog("reflectSimBatteryFull skipped: no vehicle model [\(source)].", vehicleID: vehicleID)
            return
        }
        let defaults = SimSpawnDefaults.default
        model.applyTelemetryMutation { hub in
            hub.batteryRemainingPercent = 100
            hub.batteryVoltageV = defaults.batteryVoltageV
            hub.batteryCurrentA = defaults.batteryCurrentA
        }
        vehicleModelsByVehicleID[vehicleID] = model
        hubTelemetryByVehicleID[vehicleID] = model.data.telemetry
        telemetryByVehicleID[vehicleID] = model.collections.telemetrySnapshot
        hubTelemetry = hubTelemetryByVehicleID[vehicleID]
        telemetry = telemetryByVehicleID[vehicleID]
        lastTelemetryMutationVehicleID = vehicleID
        scheduleHubFleetTelemetryTickThrottled()
        appendVehicleLog(
            "Hub battery patched to full (SIM cleanup) [\(source)].",
            vehicleID: vehicleID
        )
    }

    /// MAVSDK pose/attitude can lag behind SIM param teleports (`SIM_OPOS_*` / `SIH_LOC_*`). Patch hub immediately so
    /// map markers, fleet cards, and Live Drive health cards match the state we just pushed on the wire.
    private func reflectAppliedSimStateInHubTelemetry(
        vehicleID: String,
        state: FleetSimState,
        autopilotStack: FleetAutopilotStack,
        source: String
    ) {
        guard let session = sessionsByVehicleID[vehicleID] else {
            appendVehicleLog("reflectSimStateInHub skipped: no MAVSDK session [\(source)].", vehicleID: vehicleID)
            return
        }
        let lifecycle = vehicleStatusByVehicleID[vehicleID] ?? VehicleLifecycleStatus(stage: .live)
        let existingType = vehicleModelsByVehicleID[vehicleID]?.data.vehicleType ?? .unknown
        ensureVehicleModel(
            vehicleID: vehicleID,
            systemID: session.systemID,
            vehicleType: existingType,
            initialStatus: lifecycle
        )
        guard var model = vehicleModelsByVehicleID[vehicleID] else {
            appendVehicleLog("reflectSimStateInHub skipped: no vehicle model after ensure [\(source)].", vehicleID: vehicleID)
            return
        }

        let heading = Self.normalizedDegrees(Double(state.yawDeg))
        let appliedAbsAlt = state.absoluteAltitudeM ?? 0
        model.applyTelemetryMutation { hub in
            if autopilotStack != .unknown {
                hub.autopilotStack = autopilotStack
            }
            hub.latitudeDeg = state.latitudeDeg
            hub.longitudeDeg = state.longitudeDeg
            hub.absoluteAltM = appliedAbsAlt
            hub.altitudeAmslM = appliedAbsAlt
            hub.altitudeRelativeM = hub.homeAbsoluteAltM.map { appliedAbsAlt - $0 }
            if let home = hub.homeAbsoluteAltM {
                hub.relativeAltM = appliedAbsAlt - home
            }
            hub.headingDeg = heading
            hub.yawDeg = heading
            hub.rollDeg = 0
            hub.pitchDeg = 0
            hub.velocityNorthMS = 0
            hub.velocityEastMS = 0
            hub.velocityDownMS = 0
            hub.positionVelNorthM = 0
            hub.positionVelEastM = 0
            hub.positionVelDownM = 0
            hub.positionVelVnMS = 0
            hub.positionVelVeMS = 0
            hub.positionVelVdMS = 0
            hub.positionVelHeadingDeg = heading
            if let v = state.batteryVoltageV, v > 0.1 {
                hub.batteryVoltageV = v
            }
        }
        vehicleModelsByVehicleID[vehicleID] = model
        hubTelemetryByVehicleID[vehicleID] = model.data.telemetry
        telemetryByVehicleID[vehicleID] = model.collections.telemetrySnapshot
        hubTelemetry = hubTelemetryByVehicleID[vehicleID]
        telemetry = telemetryByVehicleID[vehicleID]
        lastTelemetryMutationVehicleID = vehicleID
        scheduleHubFleetTelemetryTickThrottled()
        appendVehicleLog(
            "Hub telemetry hydrated from applied sim state [\(source)] (lat/lon/alt/hdg + stale motion cleared).",
            vehicleID: vehicleID
        )
    }

    private func awaitSetSimStateFloatBestEffort(vehicleID: String, name: String, value: Float, logTag: String) async {
        guard let session = sessionsByVehicleID[vehicleID] else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.drone.param.setParamFloat(name: name, value: value)
                .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(
                    onCompleted: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.appendVehicleLog("applySimState param set [\(logTag)] \(name)=\(value).", vehicleID: vehicleID)
                            cont.resume()
                        }
                    },
                    onError: { [weak self] error in
                        Task { @MainActor [weak self] in
                            let d = self?.mavsdkPublicErrorDescription(error) ?? error.localizedDescription
                            self?.appendVehicleLog("applySimState param failed [\(logTag)] \(name): \(d).", vehicleID: vehicleID)
                            cont.resume()
                        }
                    }
                )
                .disposed(by: session.bag)
        }
    }

    /// After SITL spawn, once MAVSDK is connected, re-apply `SimSpawnDefaults` on the wire (see `applySimState`).
    private func scheduleApplyPendingSpawnSimStateIfNeeded(session: VehicleSession, vehicleID: String) {
        guard let payload = session.pendingSpawnSimState else { return }
        session.pendingSpawnSimState = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard self.sessionsByVehicleID[vehicleID] === session else { return }
            let stack = self.vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack ?? .unknown
            await self.applySimState(
                vehicleID: vehicleID,
                state: payload,
                autopilotStack: stack,
                source: "sitl.spawnHandshake"
            )
        }
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
        if let defaults = spawnDefaults {
            session.pendingSpawnSimState = FleetSimState(spawnDefaults: defaults)
        }
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
        lastTelemetryMutationVehicleID = vehicleID
        scheduleHubFleetTelemetryTickThrottled()
        start(session: session)
    }

    /// Tear down and recreate the MAVSDK session for a built-in SITL (same URL), waiting briefly for the UDP listen port to free.
    @discardableResult
    func reconnectSimulatedVehicleSession(
        systemID: Int,
        mavlinkConnectionURL: String,
        autopilotStack: FleetAutopilotStack,
        vehicleType: FleetVehicleType,
        spawnDefaults: SimSpawnDefaults? = nil
    ) async -> Bool {
        lastError = nil
        let vehicleID = "sysid:\(systemID)"
        if sessionsByVehicleID[vehicleID] != nil {
            appendVehicleLog("Replacing stale MAVSDK session before reconnecting sim.", vehicleID: vehicleID)
            stopSession(vehicleID: vehicleID)
        } else {
            appendVehicleLog("Starting MAVSDK session for reconnect.", vehicleID: vehicleID)
        }

        if let port = GuardianUdpPortUtilities.udpInboundListenPort(from: mavlinkConnectionURL) {
            let freed = await GuardianUdpPortUtilities.waitForUdpInboundPortBindable(port: port, timeout: 2.5)
            if !freed {
                appendVehicleLog(
                    "Reconnect: UDP port \(port) still busy after wait; starting MAVSDK anyway.",
                    vehicleID: vehicleID
                )
            }
        } else {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        registerSimulatedVehicle(
            systemID: systemID,
            mavlinkConnectionURL: mavlinkConnectionURL,
            autopilotStack: autopilotStack,
            vehicleType: vehicleType,
            spawnDefaults: spawnDefaults
        )
        guard sessionsByVehicleID[vehicleID] != nil else {
            if lastError == nil {
                lastError = "MAVSDK session did not start."
            }
            return false
        }
        appendVehicleLog("Reconnect scheduled MAVSDK session (\(mavlinkConnectionURL)).", vehicleID: vehicleID)
        return true
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
        autopilotMissionCycleHasInProgressLegByVehicleID.removeAll(keepingCapacity: true)
        simulatedFleetVehicleIDs.removeAll(keepingCapacity: true)
        liveDriveControlSessionVehicleID = nil
        bridgePhase = .awaitingVehicle
        clearMcrRosterLiveChannelFleetSlicesForAllKeys()
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

    /// Records a recipe-run / probe outcome on the FVM (unified ``FleetVehicleModel/Functions/recipeRunHistory`` ring).
    ///
    /// Appends one row to the per-vehicle recipe-run ring; set ``RecipeRunHistoryKind`` explicitly (arm probes
    /// use ``RecipeRunHistoryKind/preflightArmProbe``). The newest entry may repaint ``FleetVehicleModel.collections/calibration``
    /// when it fails with remediation that maps to a calibration system. History is capped to ``FleetVehicleModel/recipeRunHistoryCap``.
    func recordRecipeRun(
        vehicleID: String,
        source: String,
        kind: RecipeRunHistoryKind,
        outcome: SingleVehiclePreflightProbeResult
    ) {
        ensureVehicleModel(vehicleID: vehicleID, systemID: nil, initialStatus: .init(stage: .connecting))
        guard var model = vehicleModelsByVehicleID[vehicleID] else { return }
        let entry = RecipeRunHistoryEntry(source: source, kind: kind, outcome: outcome)
        model.recordRecipeRun(entry)
        vehicleModelsByVehicleID[vehicleID] = model
        appendVehicleLog(
            "Recipe run recorded [\(kind.rawValue)] [source=\(source)] \(outcome.passed ? "passed" : "failed"): \(outcome.detail)",
            vehicleID: vehicleID
        )
    }

    /// Clears the per-vehicle recipe-run ring (operator dismiss in the calibration modal banner, or automation
    /// reset before a new sequence). Recomputes the calibration collection so any recipe-run marker overlay drops.
    func clearRecipeRuns(vehicleID: String) {
        guard var model = vehicleModelsByVehicleID[vehicleID] else { return }
        guard !model.functions.recipeRunHistory.isEmpty else { return }
        model.clearRecipeRuns()
        vehicleModelsByVehicleID[vehicleID] = model
        appendVehicleLog("Recipe runs cleared.", vehicleID: vehicleID)
    }

    /// Raise the gate so lower-priority sources stop issuing (e.g. `.manualTakeover` blocks automation until reset to `.missionControl` / `.paladin`).
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

    /// Blocks `liveDrive.*` `.manualTakeover` unless an active Live Drive control session holds this `vehicleID`.
    /// Non–Live Drive sources and other categories are unaffected.
    private func liveDriveAllowsManualTakeoverCommand(
        vehicleID: String,
        source: String,
        category: FleetVehicleCommandCategory
    ) -> Bool {
        guard category == .manualTakeover else { return true }
        guard source.hasPrefix("liveDrive.") else { return true }
        return liveDriveControlSessionVehicleID == vehicleID
    }

    /// Command dispatch entrypoint for Mission Control, Live Drive, and other fleet command sources.
    @discardableResult
    func executeVehicleCommand(
        vehicleID: String,
        command: FleetVehicleCommand,
        source: String,
        category: FleetVehicleCommandCategory = .missionControl,
        onCommandOutcome: (@MainActor (FleetCommandAsyncOutcome) -> Void)? = nil
    ) -> UUID? {
        ensureVehicleModel(vehicleID: vehicleID, systemID: nil, initialStatus: .init(stage: .connecting))
        guard var model = vehicleModelsByVehicleID[vehicleID] else {
            onCommandOutcome?(.failed("No vehicle model for this stream key."))
            return nil
        }
        if category.arbitrationPriority < model.functions.commandGateMinimumPriority {
            appendVehicleLog(
                "Command rejected [source=\(source) category=\(category.rawValue)]: below gate (\(model.functions.commandGateMinimumPriority)).",
                vehicleID: vehicleID
            )
            onCommandOutcome?(
                .failed(
                    "Command rejected: authority gate on this vehicle requires a higher-priority source than \(category.rawValue)."
                )
            )
            return nil
        }
        if !liveDriveAllowsManualTakeoverCommand(vehicleID: vehicleID, source: source, category: category) {
            appendVehicleLog(
                "Live Drive: blocked \(source) — no active control session (start a Live Drive session first).",
                vehicleID: vehicleID
            )
            onCommandOutcome?(.failed("Live Drive has no active session for this vehicle."))
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
            onCommandOutcome?(.failed("No MAVSDK session for vehicle."))
            return commandID
        }

        if case .park = command {
            runParkPipeline(
                session: session,
                vehicleID: vehicleID,
                commandID: commandID,
                command: command,
                onCommandOutcome: onCommandOutcome
            )
            return commandID
        }

        if subscribeMissionSingleIfNeeded(
            vehicleID: vehicleID,
            commandID: commandID,
            command: command,
            session: session,
            onCommandOutcome: onCommandOutcome
        ) {
            return commandID
        }

        // When non-nil, `onError` appends a decoded-wire summary so logs show what Guardian sent to MAVSDK.
        var geofenceUploadWireForErrorLog: FleetVehicleCommandGeofenceUploadPayload?

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
        case .park:
            preconditionFailure("park must use runParkPipeline")
        case .idle:
            completion = completionForIdleManualMode(vehicleID: vehicleID, session: session)
        case .gotoCoordinate(let coord, let relativeAltitudeM, let yawDeg):
            completion = completionForGotoCoordinate(
                coord: coord,
                relativeAltitudeM: relativeAltitudeM,
                yawDeg: yawDeg,
                vehicleID: vehicleID,
                session: session
            )
        case .uploadMission(let items):
            completion = completionForUploadMissionOnly(
                items: items,
                vehicleID: vehicleID,
                session: session
            )
        case .uploadGeofence(let wire):
            geofenceUploadWireForErrorLog = wire
            let polygons = wire.polygons.map(\.mavsdkPolygon)
            let circles = wire.circles.map(\.mavsdkCircle)
            logGeofenceUploadMavsdkDiagnostics(vehicleID: vehicleID, wire: wire, polygons: polygons, circles: circles)
            completion = session.drone.geofence.uploadGeofence(polygons: polygons, circles: circles)
        case .clearGeofence:
            completion = session.drone.geofence.clearGeofence()
        case .missionClear:
            completion = session.drone.mission.clearMission()
        case .missionStart:
            completion = session.drone.mission.startMission()
        case .missionPause:
            completion = session.drone.mission.pauseMission()
        case .missionSetCurrentItem(let index):
            completion = session.drone.mission.setCurrentMissionItem(index: index)
        case .missionSetRtlAfter(let enable):
            completion = session.drone.mission.setReturnToLaunchAfterMission(enable: enable)
        case .cancelMissionUpload:
            completion = session.drone.mission.cancelMissionUpload()
        case .cancelMissionDownload:
            completion = session.drone.mission.cancelMissionDownload()
        case .missionDownloadPlanJSON, .missionIsFinishedQuery, .missionGetRtlAfter:
            preconditionFailure("Mission Single-backed commands must use subscribeMissionSingleIfNeeded")
        case .manualControl(let manual):
            completion = completionForManualControl(
                manual,
                vehicleID: vehicleID,
                session: session
            )
        case .calibrateMavsdk(let kind):
            completion = completionForMavsdkCalibration(
                kind: kind,
                vehicleID: vehicleID,
                session: session
            )
        case .mavlinkCommandLong(let request):
            completion = completionForMavlinkCommandLong(
                request: request,
                vehicleID: vehicleID,
                session: session
            )
        case .cancelCalibration:
            completion = session.drone.calibration.cancel()
        case .setParameterFloat(let name, let value):
            completion = completionForSetParameterFloatWithReadBack(
                name: name,
                value: Float(value),
                vehicleID: vehicleID,
                session: session
            )
        case .setParameterInt(let name, let value):
            completion = completionForSetParameterIntWithReadBack(
                name: name,
                value: value,
                vehicleID: vehicleID,
                session: session
            )
        case .setMode(let mode):
            completion = completionForSetMode(
                mode: mode,
                vehicleID: vehicleID,
                session: session
            )
        case .offboardStop:
            completion = OffboardCoordinator.offboardStopCompletable(drone: session.drone)
        case .rebootAutopilot:
            completion = session.drone.action.reboot()
        }

        completion
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onCompleted: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.markVehicleCommand(vehicleID: vehicleID, commandID: commandID, status: .succeeded)
                        self?.appendVehicleLog("Command succeeded: \(self?.describe(command: command) ?? "command")", vehicleID: vehicleID)
                        onCommandOutcome?(.succeeded)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        var raw = self?.mavsdkPublicErrorDescription(error) ?? error.localizedDescription
                        if let wire = geofenceUploadWireForErrorLog, let strongSelf = self {
                            raw += " — geofence wire (MAVSDK sees lat/lon + fenceType; circles use center+radius): \(strongSelf.geofenceUploadWireSummary(wire: wire))"
                        }
                        let detail = self?.augmentCommandFailureDetail(vehicleID: vehicleID, detail: raw) ?? raw
                        self?.markVehicleCommand(
                            vehicleID: vehicleID,
                            commandID: commandID,
                            status: .failed(detail)
                        )
                        self?.appendVehicleLog("Command error: \(detail)", vehicleID: vehicleID)
                        onCommandOutcome?(.failed(detail))
                    }
                }
            )
            .disposed(by: session.bag)

        return commandID
    }

    /// UGV / USV / UUV **Park** at Live Drive session end: `Action.hold()` then `Action.disarm()`.
    ///
    /// MAVSDK `hold()` moves the vehicle into a hold navigation state but **often leaves the platform armed**
    /// (ArduPilot Rover and PX4 rovers). Operators expect Park to be safe to approach; disarm completes that.
    ///
    /// UAV "Loiter" also maps to `.holdPosition` in the UI but must **not** auto-disarm mid-air — callers
    /// should only invoke this for surface / ground classes.
    func awaitLiveDriveSurfaceParkHoldAndDisarm(vehicleID: String) async {
        guard let session = sessionsByVehicleID[vehicleID] else {
            appendVehicleLog("Live Drive park sequence: skipped (no MAVSDK session).", vehicleID: vehicleID)
            return
        }
        appendVehicleLog("Live Drive park sequence: hold then disarm.", vehicleID: vehicleID)
        do {
            try await awaitCompletableForManualStream(session.drone.action.hold())
            appendVehicleLog("Live Drive park sequence: hold acknowledged.", vehicleID: vehicleID)
        } catch {
            let d = mavsdkPublicErrorDescription(error)
            appendVehicleLog("Live Drive park sequence: hold failed (\(d)); attempting disarm anyway.", vehicleID: vehicleID)
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        do {
            try await awaitCompletableForManualStream(session.drone.action.disarm())
            appendVehicleLog("Live Drive park sequence: disarm acknowledged.", vehicleID: vehicleID)
        } catch {
            appendVehicleLog(
                "Live Drive park sequence: disarm failed (\(mavsdkPublicErrorDescription(error))).",
                vehicleID: vehicleID
            )
        }
    }

    /// UGV / USV / UUV **RTL → Park** at Live Drive session end: drive home, then HOLD + disarm.
    ///
    /// Why this exists vs. plain `Action.returnToLaunch()`: ArduPilot Rover and PX4 rover RTL drive the
    /// vehicle home and (depending on `RTL_AUTODISARM_DELAY` / equivalent) usually auto-disarm at the
    /// destination — but they leave the *flight mode* in RTL, not HOLD. Operator mental model is
    /// "RTL = go home and park", so the post-RTL state should match Park: HOLD mode + disarmed. Without
    /// this follow-up, the rover sits at home in RTL mode and the next mission/manual stint has to clear
    /// that state explicitly.
    ///
    /// Sequencing:
    ///   1. Issue `returnToLaunch()`.
    ///   2. Wait for the auto-disarm transition (`hub.isArmed` flips to `false`) — that's the closest
    ///      universally-reliable signal that the rover has actually arrived. Bounded with a generous
    ///      timeout so a stuck RTL doesn't hang the session-end task forever.
    ///   3. Push `hold()` to set HOLD mode (works whether or not the vehicle auto-disarmed).
    ///   4. Belt-and-braces `disarm()` in case auto-disarm didn't fire (e.g. operator has
    ///      `RTL_AUTODISARM_DELAY = 0` on ArduPilot, or PX4 cold-set custom params).
    ///
    /// **Surface / ground classes only** — UAV RTL ends in LAND, which already disarms after touchdown
    /// and must not be followed by a HOLD push (would interrupt the descent).
    func awaitLiveDriveSurfaceRTLHomeAndPark(vehicleID: String) async {
        guard let session = sessionsByVehicleID[vehicleID] else {
            appendVehicleLog("Live Drive RTL→park: skipped (no MAVSDK session).", vehicleID: vehicleID)
            return
        }
        appendVehicleLog("Live Drive RTL→park: returnToLaunch issued.", vehicleID: vehicleID)
        do {
            try await awaitCompletableForManualStream(session.drone.action.returnToLaunch())
        } catch {
            let d = mavsdkPublicErrorDescription(error)
            appendVehicleLog("Live Drive RTL→park: returnToLaunch failed (\(d)); attempting park anyway.", vehicleID: vehicleID)
        }

        // Wait for arrival (= auto-disarm). 90 s covers a ~450 m drive at 5 m/s with margin; on SITL
        // the home → spawn distance is usually < 30 m so this typically resolves in < 30 s.
        let arrivalTimeoutMs: Int = 90_000
        let pollIntervalMs: Int = 250
        let pollIntervalNs: UInt64 = UInt64(pollIntervalMs) * 1_000_000
        var elapsedMs = 0
        var arrived = false
        // Skip the wait entirely if the vehicle is already disarmed (rare but possible, e.g. RTL on a
        // SITL rover that was already at home and triggered auto-disarm immediately).
        if hubTelemetryByVehicleID[vehicleID]?.isArmed == false {
            arrived = true
        }
        while !arrived && elapsedMs < arrivalTimeoutMs {
            try? await Task.sleep(nanoseconds: pollIntervalNs)
            elapsedMs += pollIntervalMs
            if hubTelemetryByVehicleID[vehicleID]?.isArmed == false {
                arrived = true
            }
        }
        if arrived {
            appendVehicleLog("Live Drive RTL→park: arrival detected (auto-disarmed after \(elapsedMs) ms).", vehicleID: vehicleID)
        } else {
            appendVehicleLog(
                "Live Drive RTL→park: arrival timeout (\(arrivalTimeoutMs) ms); pushing HOLD anyway.",
                vehicleID: vehicleID
            )
        }

        do {
            try await awaitCompletableForManualStream(session.drone.action.hold())
            appendVehicleLog("Live Drive RTL→park: hold acknowledged.", vehicleID: vehicleID)
        } catch {
            let d = mavsdkPublicErrorDescription(error)
            appendVehicleLog("Live Drive RTL→park: hold failed (\(d)); attempting disarm anyway.", vehicleID: vehicleID)
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        // Disarm is a no-op if already disarmed; MAVSDK returns success and we just log either way.
        if hubTelemetryByVehicleID[vehicleID]?.isArmed == true {
            do {
                try await awaitCompletableForManualStream(session.drone.action.disarm())
                appendVehicleLog("Live Drive RTL→park: disarm acknowledged.", vehicleID: vehicleID)
            } catch {
                appendVehicleLog(
                    "Live Drive RTL→park: disarm failed (\(mavsdkPublicErrorDescription(error))).",
                    vehicleID: vehicleID
                )
            }
        } else {
            appendVehicleLog("Live Drive RTL→park: already disarmed; skipping explicit disarm.", vehicleID: vehicleID)
        }
    }

    // MARK: - Formation follow stream (Mission Control wingmen)

    func isFormationFollowStreaming(vehicleID: String) -> Bool {
        sessionsByVehicleID[vehicleID]?.formationFollowStream?.isRunning == true
    }

    /// Pause and clear onboard mission so wingman OFFBOARD is not competing with AUTO/navigator (v1 convoy follow).
    func prepareVehicleForFormationFollow(vehicleID: String) async {
        guard let session = sessionsByVehicleID[vehicleID] else {
            appendVehicleLog("Formation follow prep: no MAVSDK session.", vehicleID: vehicleID)
            return
        }
        do {
            try await awaitCompletableForManualStream(session.drone.mission.pauseMission())
            appendVehicleLog("Formation follow prep: mission pause acknowledged.", vehicleID: vehicleID)
        } catch {
            appendVehicleLog(
                "Formation follow prep: mission pause skipped (\(mavsdkPublicErrorDescription(error))).",
                vehicleID: vehicleID
            )
        }
        do {
            try await awaitCompletableForManualStream(session.drone.mission.clearMission())
            appendVehicleLog("Formation follow prep: mission clear acknowledged.", vehicleID: vehicleID)
        } catch {
            appendVehicleLog(
                "Formation follow prep: mission clear skipped (\(mavsdkPublicErrorDescription(error))).",
                vehicleID: vehicleID
            )
        }
    }

    /// Start ~10 Hz global setpoint streaming for a wingman (caller primes ArduPilot **guided** when needed).
    @discardableResult
    func startFormationFollowStream(
        vehicleID: String,
        initialTarget: FormationFollowStream.Target
    ) async -> Bool {
        guard let session = sessionsByVehicleID[vehicleID] else {
            appendVehicleLog("Formation follow: no MAVSDK session.", vehicleID: vehicleID)
            return false
        }
        if let existing = session.formationFollowStream, existing.isRunning {
            existing.updateTarget(initialTarget)
            return true
        }
        let renewWithoutMissionPrep = session.formationFollowStream != nil
        session.formationFollowStream = nil
        if !renewWithoutMissionPrep {
            await prepareVehicleForFormationFollow(vehicleID: vehicleID)
        }
        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack
            ?? hubTelemetryByVehicleID[vehicleID]?.autopilotStack
            ?? .unknown
        if stack == .ardupilot {
            let uClass = vehicleModelsByVehicleID[vehicleID]?.data.vehicleType.universalClass ?? .unknown
            if uClass == .uav || uClass == .ugv || uClass == .usv {
                do {
                    try await awaitCompletableForManualStream(
                        ardupilotSetModeCompletable(
                            mode: .guided,
                            vehicleID: vehicleID,
                            session: session,
                            vehicleClass: uClass
                        )
                    )
                } catch {
                    appendVehicleLog(
                        "Formation follow: guided mode failed (\(mavsdkPublicErrorDescription(error))).",
                        vehicleID: vehicleID
                    )
                    return false
                }
            }
        }
        let uClass = vehicleModelsByVehicleID[vehicleID]?.data.vehicleType.universalClass ?? .unknown
        let stream = FormationFollowStream(
            drone: session.drone,
            stack: stack,
            universalClass: uClass,
            initialTarget: initialTarget,
            awaitCompletable: { [weak self] c in
                guard let self else { return }
                try await self.awaitCompletableForManualStream(c)
            },
            log: { [weak self] line in
                self?.appendVehicleLog(line, vehicleID: vehicleID)
            }
        )
        session.formationFollowStream = stream
        let started = await stream.start()
        if !started {
            session.formationFollowStream = nil
            appendVehicleLog("Formation follow: stream failed to enter OFFBOARD/GUIDED.", vehicleID: vehicleID)
            return false
        }
        let mode = hubTelemetryByVehicleID[vehicleID]?.flightMode.lowercased() ?? ""
        if stack == .px4, !mode.contains("offboard") {
            appendVehicleLog(
                "Formation follow: stream active but flight mode is '\(hubTelemetryByVehicleID[vehicleID]?.flightMode ?? "unknown")' (expected OFFBOARD).",
                vehicleID: vehicleID
            )
        }
        return true
    }

    /// When `true`, MRE should not push new formation setpoints (catalogue recipe or manual stream owns the vehicle).
    func shouldDeferFormationFollowSetpoints(vehicleID: String) -> Bool {
        if isManualControlStreaming(vehicleID: vehicleID) { return true }
        if FleetRecipeRunner.shared.hasActiveRun(forVehicleID: vehicleID) { return true }
        return false
    }

    func updateFormationFollowTarget(vehicleID: String, target: FormationFollowStream.Target) {
        guard !shouldDeferFormationFollowSetpoints(vehicleID: vehicleID) else { return }
        sessionsByVehicleID[vehicleID]?.formationFollowStream?.updateTarget(target)
    }

    func stopFormationFollowStream(vehicleID: String) async {
        guard let session = sessionsByVehicleID[vehicleID],
              let stream = session.formationFollowStream
        else { return }
        session.formationFollowStream = nil
        await stream.stop()
    }

    // MARK: - Manual Control Stream (Live Drive continuous setpoints)

    /// True if a continuous manual-control stream is currently driving this vehicle.
    func isManualControlStreaming(vehicleID: String) -> Bool {
        sessionsByVehicleID[vehicleID]?.manualStream?.isRunning == true
    }

    /// Start a continuous manual-control stream for a vehicle.
    ///
    /// - Parameters:
    ///   - vehicleID: Stream key (e.g. `"sysid:1"`).
    ///   - mode: `.offboard` for body-velocity setpoints (best for keyboard);
    ///           `.manualControl` for normalized stick input (best for analog gamepad).
    ///   - autoTakeoff: When `true`, arm the vehicle and issue a takeoff before entering
    ///                  Offboard mode if the vehicle is on or near the ground. UAV-only behaviour;
    ///                  callers should pass `false` for ground / surface / sub vehicles.
    /// - Returns: `true` if the plugin entered streaming mode successfully.
    @discardableResult
    func startManualControlStream(
        vehicleID: String,
        mode: ManualControlStream.Mode,
        autoTakeoff: Bool,
        profile: ManualControlStepProfile
    ) async -> Bool {
        guard let session = sessionsByVehicleID[vehicleID] else {
            appendVehicleLog("Manual stream: cannot start, no MAVSDK session.", vehicleID: vehicleID)
            return false
        }

        guard liveDriveControlSessionVehicleID == vehicleID else {
            appendVehicleLog(
                "Manual stream: refused — no Live Drive control session for this vehicle (start a session first).",
                vehicleID: vehicleID
            )
            return false
        }

        if let existing = session.manualStream, existing.isRunning {
            return true
        }

        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack
            ?? hubTelemetryByVehicleID[vehicleID]?.autopilotStack
            ?? .unknown

        if autoTakeoff {
            await runAutoTakeoffIfNeeded(vehicleID: vehicleID, session: session)
        }

        let stream = ManualControlStream(
            vehicleID: vehicleID,
            drone: session.drone,
            stack: stack,
            mode: mode,
            profile: profile,
            log: { [weak self] line in
                Task { @MainActor [weak self] in
                    self?.appendVehicleLog(line, vehicleID: vehicleID)
                }
            }
        )
        session.manualStream = stream

        let started = await stream.start()
        if !started {
            session.manualStream = nil
            return false
        }

        // PX4 ground keyboard path: now that the 30 Hz `MANUAL_CONTROL` stream is
        // primed, push the autopilot from HOLD into MANUAL via raw MAVLink. The
        // `Shell.send("commander mode manual")` route silently fails on PX4 SITL
        // (no `mavlink_shell` on the Onboard link) — see `Px4ModeCommander` for
        // the full diagnosis. We give the rover module ~300 ms to register the
        // freshly-published `manual_control_setpoint` topic before issuing the
        // mode change so the commander accepts the transition instead of bouncing
        // straight back to HOLD on the RC-loss failsafe watchdog.
        if mode == .px4GroundManual, let port = px4GcsUdpPort(for: session) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            let target = UInt8(clamping: session.systemID)
            // No log closure — Px4ModeCommander only emits errors on UDP-send
            // failure to localhost, which essentially never happens in SITL,
            // and forwarding a `(String) -> Void` from `@MainActor` to a
            // `nonisolated` async helper trips Swift 6 strict-concurrency.
            await Px4ModeCommander.setMode(
                port: port,
                targetSystem: target,
                mainMode: .manual
            )
            appendVehicleLog(
                "PX4 SET_MODE manual sent (liveDrive.streamStart, gcs udp 127.0.0.1:\(port), target_system=\(target)).",
                vehicleID: vehicleID
            )
        }

        return true
    }

    /// Refresh the per-vehicle profile (e.g. after the operator edits max speeds in Settings).
    func updateManualControlProfile(vehicleID: String, profile: ManualControlStepProfile) {
        sessionsByVehicleID[vehicleID]?.manualStream?.updateProfile(profile)
    }

    /// Push a fresh operator intent (-1…1 per axis) to the active stream.
    /// Safe no-op if no stream is running for this vehicle.
    func updateManualControlIntent(
        vehicleID: String,
        forward: Double,
        right: Double,
        up: Double,
        yawRate: Double
    ) {
        guard let stream = sessionsByVehicleID[vehicleID]?.manualStream, stream.isRunning else { return }
        guard liveDriveControlSessionVehicleID == vehicleID else { return }
        stream.update(intent: .init(forward: forward, right: right, up: up, yawRate: yawRate))
    }

    /// Stop the active manual control stream and exit Offboard / ManualControl mode.
    func stopManualControlStream(vehicleID: String) async {
        guard let session = sessionsByVehicleID[vehicleID], let stream = session.manualStream else { return }
        session.manualStream = nil
        await stream.stop()
    }

    /// Best-effort UAV pre-flight: arm if needed, take off, give the autopilot a few seconds to
    /// climb to default takeoff altitude before we steal control with Offboard. No-op if the
    /// vehicle is already airborne (relative altitude > 1.0 m).
    private func runAutoTakeoffIfNeeded(vehicleID: String, session: VehicleSession) async {
        let hub = hubTelemetryByVehicleID[vehicleID]
        let alreadyAirborne = (hub?.relativeAltM ?? 0) > 1.0
        if alreadyAirborne { return }

        let isArmed = hub?.isArmed == true
        if !isArmed {
            do {
                try await awaitCompletableForManualStream(session.drone.action.arm())
                appendVehicleLog("Manual stream: arm acknowledged.", vehicleID: vehicleID)
            } catch {
                let detail = mavsdkPublicErrorDescription(error)
                appendVehicleLog("Manual stream: arm failed: \(detail). Continuing with takeoff anyway.", vehicleID: vehicleID)
            }
        }

        do {
            try await awaitCompletableForManualStream(session.drone.action.takeoff())
            appendVehicleLog("Manual stream: takeoff acknowledged; waiting for climb to settle.", vehicleID: vehicleID)
        } catch {
            let detail = mavsdkPublicErrorDescription(error)
            appendVehicleLog("Manual stream: takeoff failed: \(detail). Operator can still keyboard-drive once airborne.", vehicleID: vehicleID)
            return
        }
        // `action.takeoff()` returns when the autopilot acknowledges MAV_CMD_NAV_TAKEOFF, NOT when
        // the vehicle has reached takeoff altitude. Give it a few seconds to climb and stabilise
        // before we yank control with Offboard or it'll fight the takeoff sequence.
        try? await Task.sleep(nanoseconds: 4_000_000_000)
    }

    /// Bridge a single-shot RxSwift `Completable` to async/await. The Rx pipeline keeps itself
    /// alive until it terminates; dropping the returned Disposable is safe and intentional.
    ///
    /// MAVSDK generated plugins may call blocking NIO `wait()` inside `subscribe`; always schedule on
    /// ``fleetLinkMavsdkBlockingRpcBox`` so the main thread never runs `CurrentThreadScheduler` work.
    private func awaitCompletableForManualStream(_ completable: Completable) async throws {
        try await FleetLinkMavsdkCompletableBridge.awaitBridged(completable)
    }

    /// Walks `NSError` / `NSUnderlyingErrorKey` to surface gRPC / transport wrappers above a MAVSDK plugin error.
    private func NSErrorUnderlyingChainDescription(_ error: Error) -> String? {
        var parts: [String] = []
        var current: Error? = error
        var depth = 0
        while let err = current, depth < 8 {
            depth += 1
            let ns = err as NSError
            var line = "\(ns.domain)(\(ns.code)): \(ns.localizedDescription)"
            if let reason = ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                let t = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { line += " [failureReason: \(t)]" }
            }
            if let suggestion = ns.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String {
                let t = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { line += " [recovery: \(t)]" }
            }
            parts.append(line)
            current = ns.userInfo[NSUnderlyingErrorKey] as? Error
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ← ")
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
        if let e = error as? Mavsdk.Offboard.OffboardError {
            let tail = e.description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if tail.isEmpty { return String(describing: e.code) }
            return "\(String(describing: e.code)): \(tail)"
        }
        if let e = error as? Mavsdk.Geofence.GeofenceError {
            return geofenceErrorPublicDescription(e, bridgedError: error)
        }
        let base = error.localizedDescription
        if let chain = NSErrorUnderlyingChainDescription(error), !chain.isEmpty {
            return "\(base) — NSError chain: \(chain)"
        }
        return base
    }

    /// MAVSDK `GeofenceError` carries `code` + autopilot `resultStr` in `description`; add FC-agnostic hints and any bridged NSError chain.
    private func geofenceErrorPublicDescription(_ e: Mavsdk.Geofence.GeofenceError, bridgedError: Error) -> String {
        let tail = e.description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let resultStr = tail.isEmpty ? "<empty autopilot resultStr>" : tail
        var out = "Geofence.\(String(describing: e.code)) resultStr=\(resultStr)"
        switch e.code {
        case .invalidArgument:
            out += " — Hint: MAVSDK maps several fence mission-transfer failures to invalidArgument (e.g. fewer than 3 vertices, duplicate consecutive coordinates, inconsistent fence sequence, polygon rejected by FC, geofence upload while the onboard mission is still empty, or upload not accepted in current vehicle/mode state). Guardian sends **mission upload before geofence** in `do.mission.upload`; the autopilot string above is the only FC-specific detail MAVSDK exposes here."
        case .tooManyGeofenceItems:
            out += " — Hint: fence item count exceeds what the autopilot / MAVSDK transfer will accept."
        case .timeout:
            out += " — Hint: mission-protocol fence upload timed out (link or FC busy)."
        case .busy:
            out += " — Hint: autopilot reported busy; retry after mission/fence transfer completes."
        case .noSystem:
            out += " — Hint: no system / session on the MAVSDK link when the call ran."
        case .error, .unknown:
            out += " — Hint: generic geofence failure; check FC STATUSTEXT and mission/fence support for this platform."
        case .success:
            break
        case .UNRECOGNIZED(let code):
            out += " — Hint: unrecognized MAVSDK geofence result raw value \(code)."
        }
        if let chain = NSErrorUnderlyingChainDescription(bridgedError), chain.contains(" ← ") {
            out += " — NSError chain: \(chain)"
        }
        return out
    }

    /// One-line summary of decoded `geofencePolygonsJSON` (polygons + circles) before MAVSDK upload.
    private func geofenceUploadWireSummary(wire: FleetVehicleCommandGeofenceUploadPayload) -> String {
        if wire.isEmpty { return "0 polygon(s), 0 circle(s)" }
        var parts: [String] = []
        for (idx, p) in wire.polygons.enumerated() {
            let n = p.points.count
            var seg = "poly#\(idx + 1) fenceType=\(p.fenceType) vertices=\(n)"
            if let f = p.points.first {
                seg += String(format: " first=(%.6f,%.6f)", f.latitudeDeg, f.longitudeDeg)
            }
            if let l = p.points.last {
                seg += String(format: " last=(%.6f,%.6f)", l.latitudeDeg, l.longitudeDeg)
            }
            var dupAdjacent = false
            if n >= 2 {
                for k in 1..<p.points.count {
                    let a = p.points[k - 1], b = p.points[k]
                    if abs(a.latitudeDeg - b.latitudeDeg) < 1e-9, abs(a.longitudeDeg - b.longitudeDeg) < 1e-9 {
                        dupAdjacent = true
                        break
                    }
                }
            }
            if dupAdjacent { seg += " [adjacent duplicate coordinate]" }
            parts.append(seg)
        }
        for (idx, c) in wire.circles.enumerated() {
            let seg = String(
                format: "circle#%d fenceType=%@ r=%.1fm center=(%.6f,%.6f)",
                idx + 1,
                c.fenceType,
                c.radiusMeters,
                c.latitudeDeg,
                c.longitudeDeg
            )
            parts.append(seg)
        }
        return parts.joined(separator: " | ")
    }

    // MARK: Geofence upload — MAVSDK diagnostics (copy/paste JSON)

    /// Single-line JSON for operators pasting into tickets: Swift ``Geofence/GeofenceData`` input, Guardian decoded wire mirror,
    /// and where MAVLink fence items are actually built (mavsdk_server, not Swift).
    private func logGeofenceUploadMavsdkDiagnostics(
        vehicleID: String,
        wire: FleetVehicleCommandGeofenceUploadPayload,
        polygons: [Mavsdk.Geofence.Polygon],
        circles: [Mavsdk.Geofence.Circle]
    ) {
        let dto = GeofenceUploadMavsdkDiagnosticDTO(
            schema: "guardianhq.fleet.geofence_upload_debug.v2",
            grpcMethod: "/mavsdk.rpc.geofence.GeofenceService/UploadGeofence",
            mavsdkSwiftPolygonsPassedToUploadGeofence: polygons.map { Self.geofenceSwiftPolygonDTO(from: $0) },
            mavsdkSwiftCirclesPassedToUploadGeofence: circles.map { Self.geofenceSwiftCircleDTO(from: $0) },
            guardianDecodedPolygonPayloadsParallelToSwiftPolygons: wire.polygons.map { Self.geofenceGuardianPayloadDTO(from: $0) },
            guardianDecodedCirclePayloadsParallelToSwiftCircles: wire.circles.map { Self.geofenceGuardianCirclePayloadDTO(from: $0) },
            grpcVersusMavlinkNote: Self.geofenceGrpcVersusMavlinkNote
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(dto), let json = String(data: data, encoding: .utf8) else {
            appendVehicleLog(
                "GEOFENCE_MAVSDK_UPLOAD_DEBUG_JSON {\"error\":\"failed_to_encode_diagnostic_json\"}",
                vehicleID: vehicleID
            )
            return
        }
        appendVehicleLog("GEOFENCE_MAVSDK_UPLOAD_DEBUG_JSON \(json)", vehicleID: vehicleID)
    }

    private struct GeofenceUploadMavsdkDiagnosticDTO: Encodable {
        let schema: String
        let grpcMethod: String
        let mavsdkSwiftPolygonsPassedToUploadGeofence: [GeofenceSwiftPolygonDTO]
        let mavsdkSwiftCirclesPassedToUploadGeofence: [GeofenceSwiftCircleDTO]
        let guardianDecodedPolygonPayloadsParallelToSwiftPolygons: [GeofenceGuardianPayloadDTO]
        let guardianDecodedCirclePayloadsParallelToSwiftCircles: [GeofenceGuardianCirclePayloadDTO]
        let grpcVersusMavlinkNote: String
    }

    private struct GeofenceSwiftPolygonDTO: Encodable {
        let fenceType: String
        let fenceTypeUnrecognizedEnumValue: Int?
        let points: [GeofencePointDTO]
    }

    private struct GeofenceSwiftCircleDTO: Encodable {
        let fenceType: String
        let fenceTypeUnrecognizedEnumValue: Int?
        let latitudeDeg: Double
        let longitudeDeg: Double
        let radius: Float
    }

    private struct GeofenceGuardianCirclePayloadDTO: Encodable {
        let fenceType: String
        let latitudeDeg: Double
        let longitudeDeg: Double
        let radiusMeters: Double
    }

    private struct GeofenceGuardianPayloadDTO: Encodable {
        let fenceType: String
        let points: [GeofencePointDTO]
    }

    private struct GeofencePointDTO: Encodable {
        let latitudeDeg: Double
        let longitudeDeg: Double
    }

    private static let geofenceGrpcVersusMavlinkNote: String = {
        "The Swift API calls Geofence.uploadGeofence(polygons:circles:) which wraps ``GeofenceData`` in "
            + "`mavsdk.rpc.geofence.UploadGeofenceRequest` over gRPC to mavsdk_server. "
            + "Fence MISSION_ITEM_INT rows (MAV_MISSION_TYPE_FENCE) are assembled inside mavsdk_server "
            + "(e.g. geofence plugin C++); GuardianHQ does not receive those per-item MAVLink payloads on this path. "
            + "Use PX4 / mavlink-router logs or a MAVLink capture for on-wire fence items."
    }()

    private static func geofenceSwiftCircleDTO(from circle: Mavsdk.Geofence.Circle) -> GeofenceSwiftCircleDTO {
        let (token, raw): (String, Int?) = {
            switch circle.fenceType {
            case .inclusion: return ("FENCE_TYPE_INCLUSION", nil)
            case .exclusion: return ("FENCE_TYPE_EXCLUSION", nil)
            case .UNRECOGNIZED(let code): return ("UNRECOGNIZED", code)
            }
        }()
        return GeofenceSwiftCircleDTO(
            fenceType: token,
            fenceTypeUnrecognizedEnumValue: raw,
            latitudeDeg: circle.point.latitudeDeg,
            longitudeDeg: circle.point.longitudeDeg,
            radius: circle.radius
        )
    }

    private static func geofenceGuardianCirclePayloadDTO(from payload: FleetVehicleCommandGeofenceCirclePayload) -> GeofenceGuardianCirclePayloadDTO {
        GeofenceGuardianCirclePayloadDTO(
            fenceType: payload.fenceType,
            latitudeDeg: payload.latitudeDeg,
            longitudeDeg: payload.longitudeDeg,
            radiusMeters: payload.radiusMeters
        )
    }

    private static func geofenceSwiftPolygonDTO(from polygon: Mavsdk.Geofence.Polygon) -> GeofenceSwiftPolygonDTO {
        let (token, raw): (String, Int?) = {
            switch polygon.fenceType {
            case .inclusion: return ("FENCE_TYPE_INCLUSION", nil)
            case .exclusion: return ("FENCE_TYPE_EXCLUSION", nil)
            case .UNRECOGNIZED(let code): return ("UNRECOGNIZED", code)
            }
        }()
        let pts = polygon.points.map { GeofencePointDTO(latitudeDeg: $0.latitudeDeg, longitudeDeg: $0.longitudeDeg) }
        return GeofenceSwiftPolygonDTO(fenceType: token, fenceTypeUnrecognizedEnumValue: raw, points: pts)
    }

    private static func geofenceGuardianPayloadDTO(from payload: FleetVehicleCommandGeofencePolygonPayload) -> GeofenceGuardianPayloadDTO {
        GeofenceGuardianPayloadDTO(
            fenceType: payload.fenceType,
            points: payload.points.map { GeofencePointDTO(latitudeDeg: $0.latitudeDeg, longitudeDeg: $0.longitudeDeg) }
        )
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

    /// Class-aware park: stop streaming, **best-effort mission pause** (skipped for PX4 UGV offboard park), then land/surface/hold+disarm per ``UniversalVehicleClass``,
    /// ending in ``Action/hold()`` where the surface-ground path uses it (PX4 UGV offboard park omits the final hold).
    private func runParkPipeline(
        session: VehicleSession,
        vehicleID: String,
        commandID: UUID,
        command: FleetVehicleCommand,
        onCommandOutcome: (@MainActor (FleetCommandAsyncOutcome) -> Void)?
    ) {
        let vehicleType = vehicleModelsByVehicleID[vehicleID]?.data.vehicleType ?? .unknown
        let universal = vehicleType.universalClass
        appendVehicleLog(
            "Park pipeline starting (vehicleType=\(vehicleType.rawValue) universal=\(universal.rawValue)).",
            vehicleID: vehicleID
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.runParkSequence(
                    vehicleID: vehicleID,
                    session: session,
                    vehicleType: vehicleType,
                    universalClass: universal
                )
                self.markVehicleCommand(vehicleID: vehicleID, commandID: commandID, status: .succeeded)
                self.appendVehicleLog(
                    "Command succeeded: \(self.describe(command: command))",
                    vehicleID: vehicleID
                )
                onCommandOutcome?(.succeeded)
            } catch {
                let detail = (error as NSError).localizedDescription
                let augmented = self.augmentCommandFailureDetail(vehicleID: vehicleID, detail: detail)
                self.markVehicleCommand(
                    vehicleID: vehicleID,
                    commandID: commandID,
                    status: .failed(augmented)
                )
                self.appendVehicleLog("Command error: \(augmented)", vehicleID: vehicleID)
                onCommandOutcome?(.failed(augmented))
            }
        }
    }

    /// Cancels an in-flight fleet recipe (e.g. move+park) and stops OFFBOARD / mission execution before operator park or policy retry.
    func cancelActiveRecipeAndStopMotionForOperatorIntervention(vehicleID: String) async {
        guard let session = sessionsByVehicleID[vehicleID] else { return }
        if FleetRecipeRunner.shared.hasActiveRun(forVehicleID: vehicleID) {
            _ = FleetRecipeRunner.shared.cancel(vehicleID: vehicleID)
            appendVehicleLog(
                "Operator stop: cancelled active fleet recipe before park or policy retry.",
                vehicleID: vehicleID
            )
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        do {
            try await awaitCompletableForManualStream(OffboardCoordinator.offboardStopCompletable(drone: session.drone))
            appendVehicleLog("Operator stop: offboard stop acknowledged.", vehicleID: vehicleID)
        } catch {
            appendVehicleLog(
                "Operator stop: offboard stop skipped or failed (\(mavsdkPublicErrorDescription(error))).",
                vehicleID: vehicleID
            )
        }
        await parkPauseMissionBestEffort(vehicleID: vehicleID, session: session, logContext: "Operator stop")
    }

    /// Same awaited stabilisation as operator catalogue **Park** (``runParkSequence``) — used before policy retry redispatch.
    func awaitOperatorEngageStabilizePark(vehicleID: String) async -> Bool {
        guard let session = sessionsByVehicleID[vehicleID] else { return false }
        let vehicleType = vehicleModelsByVehicleID[vehicleID]?.data.vehicleType ?? .unknown
        let universalClass = vehicleType.universalClass
        do {
            try await runParkSequence(
                vehicleID: vehicleID,
                session: session,
                vehicleType: vehicleType,
                universalClass: universalClass
            )
            return true
        } catch {
            appendVehicleLog(
                "Operator policy retry: park stabilisation failed (\(error.localizedDescription)).",
                vehicleID: vehicleID
            )
            return false
        }
    }

    /// After ``cancelActiveRecipeAndStopMotionForOperatorIntervention``, wait until the per-vehicle recipe slot is free so a single redispatch does not stack on a zombie run.
    func awaitOperatorPolicyWindDownJoltPreparation(
        vehicleID: String,
        maxWaitNanoseconds: UInt64 = 3_000_000_000
    ) async {
        await cancelActiveRecipeAndStopMotionForOperatorIntervention(vehicleID: vehicleID)
        let deadline = DispatchTime.now().uptimeNanoseconds + maxWaitNanoseconds
        while FleetRecipeRunner.shared.hasActiveRun(forVehicleID: vehicleID),
              DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if FleetRecipeRunner.shared.hasActiveRun(forVehicleID: vehicleID) {
            _ = FleetRecipeRunner.shared.cancel(vehicleID: vehicleID)
            appendVehicleLog(
                "Operator policy retry: recipe slot still busy after wait — requested cancel again.",
                vehicleID: vehicleID
            )
        }
    }

    private func runParkSequence(
        vehicleID: String,
        session: VehicleSession,
        vehicleType: FleetVehicleType,
        universalClass: UniversalVehicleClass
    ) async throws {
        let parkPoseSnapshot = px4ParkPoseHold(for: vehicleID)
        await stopManualControlStream(vehicleID: vehicleID)
        await cancelActiveRecipeAndStopMotionForOperatorIntervention(vehicleID: vehicleID)
        let px4UgvOffboardPark = parkUsesPx4UgvOffboardPark(vehicleType: vehicleType, vehicleID: vehicleID)
        switch universalClass {
        case .uuv:
            try await parkSequenceUUV(vehicleID: vehicleID, session: session)
        case .ugv, .usv:
            if px4UgvOffboardPark, universalClass == .ugv {
                try await parkSequencePx4UgvOffboardZeroVelocityPark(
                    vehicleID: vehicleID,
                    session: session,
                    poseHold: parkPoseSnapshot
                )
            } else {
                try await parkSequenceSurfaceGround(
                    vehicleID: vehicleID,
                    session: session,
                    vehicleType: vehicleType,
                    poseHold: parkPoseSnapshot
                )
            }
        case .uav, .unknown:
            try await parkSequenceUAVOrUnknown(vehicleID: vehicleID, session: session)
        }
    }

    private func parkUsesPx4UgvOffboardPark(vehicleType: FleetVehicleType, vehicleID: String) -> Bool {
        guard vehicleType.universalClass == .ugv else { return false }
        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack
            ?? hubTelemetryByVehicleID[vehicleID]?.autopilotStack
            ?? .unknown
        return stack == .px4
    }

    private func parkHub(_ vehicleID: String) -> FleetHubVehicleTelemetry? {
        hubTelemetryByVehicleID[vehicleID]
    }

    /// Hub heading for park / hold (prefer attitude-derived ``FleetHubVehicleTelemetry/headingDeg``).
    private func resolvedParkHeadingDeg(for hub: FleetHubVehicleTelemetry?) -> Double {
        hub?.headingDeg ?? hub?.yawDeg ?? 0
    }

    private func px4ParkPoseHold(for vehicleID: String) -> OffboardCoordinator.Px4ParkPoseHold? {
        guard let hub = parkHub(vehicleID),
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else { return nil }
        let alt = Float(hub.absoluteAltM ?? hub.altitudeAmslM ?? 0)
        let yaw = Float(resolvedParkHeadingDeg(for: hub))
        return OffboardCoordinator.Px4ParkPoseHold(
            latitudeDeg: lat,
            longitudeDeg: lon,
            absoluteAltitudeM: alt,
            yawDeg: yaw
        )
    }

    /// Best-effort ``Mission/pauseMission()`` before land/hold/disarm so onboard mission execution stops
    /// (same MAVSDK call as ``FleetVehicleCommand/missionPause``). Stacks with no mission or unsupported
    /// pause fail here — we log and continue so **Park** still completes.
    private func parkPauseMissionBestEffort(
        vehicleID: String,
        session: VehicleSession,
        logContext: String = "Park"
    ) async {
        do {
            try await awaitCompletableForManualStream(session.drone.mission.pauseMission())
            appendVehicleLog("\(logContext): mission pause acknowledged.", vehicleID: vehicleID)
        } catch {
            let tail = logContext == "Park" ? "continuing park." : "continuing motion stop."
            appendVehicleLog(
                "\(logContext): mission pause skipped or failed (\(mavsdkPublicErrorDescription(error))) — \(tail)",
                vehicleID: vehicleID
            )
        }
    }

    private func performGuardianSitlMotionStopAfterMissionRunCompleted(vehicleIDs: [String]) async {
        for vehicleID in vehicleIDs {
            guard let session = sessionsByVehicleID[vehicleID] else { continue }
            let vehicleType = vehicleModelsByVehicleID[vehicleID]?.data.vehicleType ?? .unknown
            appendVehicleLog(
                "Mission run complete: motion-stop pass (manual stream / mission pause / offboard stop).",
                vehicleID: vehicleID
            )
            await stopManualControlStream(vehicleID: vehicleID)
            let px4UgvOffboardPark = parkUsesPx4UgvOffboardPark(vehicleType: vehicleType, vehicleID: vehicleID)
            if !px4UgvOffboardPark {
                await parkPauseMissionBestEffort(vehicleID: vehicleID, session: session, logContext: "Mission run complete")
            } else {
                appendVehicleLog(
                    "Mission run complete: skipping mission pause (PX4 UGV offboard policy — same as park path).",
                    vehicleID: vehicleID
                )
            }
            do {
                try await awaitCompletableForManualStream(OffboardCoordinator.offboardStopCompletable(drone: session.drone))
                appendVehicleLog("Mission run complete: offboard stop acknowledged.", vehicleID: vehicleID)
            } catch {
                appendVehicleLog(
                    "Mission run complete: offboard stop skipped or failed (\(mavsdkPublicErrorDescription(error))).",
                    vehicleID: vehicleID
                )
            }
        }
    }

    /// PX4 **UGV** park: OFFBOARD zero body-velocity brake (no `Mission.pauseMission` — see ``runParkSequence``), **no disarm** (stays armed), **no `Offboard.stop`** until continue recipe.
    private func parkSequencePx4UgvOffboardZeroVelocityPark(
        vehicleID: String,
        session: VehicleSession,
        poseHold: OffboardCoordinator.Px4ParkPoseHold?
    ) async throws {
        if let poseHold {
            appendVehicleLog(
                String(
                    format: "Park: PX4 UGV OFFBOARD hold at current pose (heading %.1f°).",
                    poseHold.yawDeg
                ),
                vehicleID: vehicleID
            )
        } else {
            appendVehicleLog(
                "Park: PX4 UGV OFFBOARD zero-velocity path (no hub pose — heading not locked).",
                vehicleID: vehicleID
            )
        }
        try await awaitCompletableForManualStream(
            completionForSetMode(mode: .guided, vehicleID: vehicleID, session: session)
        )
        appendVehicleLog("Park: OFFBOARD (guided) mode step completed.", vehicleID: vehicleID)
        try await OffboardCoordinator.runPx4ParkZeroVelocityBrakeLoop(
            drone: session.drone,
            awaitCompletable: { [weak self] (c: Completable) in
                guard let self else {
                    throw NSError(
                        domain: "FleetLinkService",
                        code: 93,
                        userInfo: [NSLocalizedDescriptionKey: "Fleet link shut down during PX4 UGV park."]
                    )
                }
                try await self.awaitCompletableForManualStream(c)
            },
            horizontalGroundSpeedMS: { [weak self] in self?.parkHub(vehicleID)?.horizontalGroundSpeedMS },
            poseHold: poseHold,
            appendDiagnostic: { [weak self] line in
                self?.appendVehicleLog("Park: \(line)", vehicleID: vehicleID)
            }
        )
        appendVehicleLog(
            "Park: PX4 UGV park complete — offboard still active, vehicle left armed; continue recipe runs do.offboard.stop first.",
            vehicleID: vehicleID
        )
        try await Task.sleep(nanoseconds: 250_000_000)
        recordMcrOperatorParkAwaitingContinue(vehicleID: vehicleID)
    }

    /// PX4 wheeled UGV (UGV-W preset): first stop-motion uses raw ``SET_MODE`` hold (catalogue ``FleetVehicleMode/hold``)
    /// instead of ``Action/hold()`` alone — experimentally some rover builds track QGC-style mode entry better.
    private func parkShouldUsePx4SetModeHoldForFirstSurfaceStop(vehicleType: FleetVehicleType, vehicleID: String) -> Bool {
        guard vehicleType == .ugvWheeled else { return false }
        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack
            ?? hubTelemetryByVehicleID[vehicleID]?.autopilotStack
            ?? .unknown
        return stack == .px4
    }

    /// UGV / USV: stop motion (hold), disarm, then hold again for a clear parked mode.
    ///
    /// **Always issues `Action.disarm()` after hold** — PX4 / MAVSDK rovers often stay armed in
    /// HOLD, and hub ``FleetHubVehicleTelemetry/isArmed`` can lag or remain at the default `false`
    /// until the next telemetry tick. Gating disarm on `isArmed == true` skipped the real disarm
    /// while the vehicle was still armed on the wire (same rationale as
    /// ``awaitLiveDriveSurfaceParkHoldAndDisarm(vehicleID:)``).
    private func parkSequenceSurfaceGround(
        vehicleID: String,
        session: VehicleSession,
        vehicleType: FleetVehicleType,
        poseHold: OffboardCoordinator.Px4ParkPoseHold?
    ) async throws {
        if let poseHold {
            do {
                try await awaitCompletableForManualStream(
                    completionForGotoCoordinate(
                        coord: RouteCoordinate(lat: poseHold.latitudeDeg, lon: poseHold.longitudeDeg),
                        relativeAltitudeM: Double(parkHub(vehicleID)?.relativeAltM ?? 0),
                        yawDeg: Double(poseHold.yawDeg),
                        vehicleID: vehicleID,
                        session: session
                    )
                )
                appendVehicleLog(
                    String(format: "Park: hold current pose (heading %.1f°) before stop/disarm.", poseHold.yawDeg),
                    vehicleID: vehicleID
                )
                try await awaitCompletableForManualStream(
                    OffboardCoordinator.offboardStopCompletable(drone: session.drone)
                )
            } catch {
                appendVehicleLog(
                    "Park: pose hold skipped (\(mavsdkPublicErrorDescription(error))); continuing stop/disarm.",
                    vehicleID: vehicleID
                )
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        if parkShouldUsePx4SetModeHoldForFirstSurfaceStop(vehicleType: vehicleType, vehicleID: vehicleID) {
            do {
                try await awaitCompletableForManualStream(
                    completionForSetMode(mode: .hold, vehicleID: vehicleID, session: session)
                )
                appendVehicleLog("Park: PX4 UGV-W SET_MODE hold (first stop) step completed.", vehicleID: vehicleID)
            } catch {
                appendVehicleLog(
                    "Park: PX4 UGV-W SET_MODE hold failed (\(mavsdkPublicErrorDescription(error))) — trying Action.hold().",
                    vehicleID: vehicleID
                )
                do {
                    try await awaitCompletableForManualStream(session.drone.action.hold())
                    appendVehicleLog("Park: Action.hold fallback acknowledged (stop motion).", vehicleID: vehicleID)
                } catch {
                    appendVehicleLog(
                        "Park: Action.hold fallback failed (\(mavsdkPublicErrorDescription(error))); continuing to disarm.",
                        vehicleID: vehicleID
                    )
                }
            }
        } else {
            do {
                try await awaitCompletableForManualStream(session.drone.action.hold())
                appendVehicleLog("Park: hold acknowledged (stop motion).", vehicleID: vehicleID)
            } catch {
                appendVehicleLog(
                    "Park: hold failed (\(mavsdkPublicErrorDescription(error))); continuing to disarm.",
                    vehicleID: vehicleID
                )
            }
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        let hubArmed = parkHub(vehicleID)?.isArmed
        appendVehicleLog(
            "Park: issuing disarm after hold (hub isArmed snapshot=\(String(describing: hubArmed))).",
            vehicleID: vehicleID
        )
        try await awaitCompletableForManualStream(session.drone.action.disarm())
        appendVehicleLog("Park: disarm acknowledged.", vehicleID: vehicleID)
        try await Task.sleep(nanoseconds: 250_000_000)
        try await awaitCompletableForManualStream(session.drone.action.hold())
        appendVehicleLog("Park: final hold acknowledged (parked).", vehicleID: vehicleID)
    }

    /// UAV (and unknown class): land if telemetry suggests airborne, wait for deck/ground, disarm, hold.
    private func parkSequenceUAVOrUnknown(vehicleID: String, session: VehicleSession) async throws {
        let h = parkHub(vehicleID)
        let airborne = (h?.inAir == true) || ((h?.relativeAltM ?? 0) > 2.0)
        if airborne {
            do {
                try await awaitCompletableForManualStream(session.drone.action.land())
                appendVehicleLog("Park: land command acknowledged; waiting for touchdown…", vehicleID: vehicleID)
            } catch {
                appendVehicleLog(
                    "Park: land failed (\(mavsdkPublicErrorDescription(error))); attempting disarm/hold anyway.",
                    vehicleID: vehicleID
                )
            }
            try await waitParkUntilUAVOnGround(vehicleID: vehicleID, timeoutMs: 120_000)
        } else {
            appendVehicleLog(
                "Park: not airborne (inAir=\(String(describing: h?.inAir)) relAlt=\(String(describing: h?.relativeAltM))); skipping land.",
                vehicleID: vehicleID
            )
        }
        if airborne {
            if parkHub(vehicleID)?.isArmed == true {
                try await awaitCompletableForManualStream(session.drone.action.disarm())
                appendVehicleLog("Park: disarm acknowledged.", vehicleID: vehicleID)
            }
        } else {
            let snap = parkHub(vehicleID)?.isArmed
            appendVehicleLog(
                "Park: issuing disarm after non-airborne path (hub isArmed snapshot=\(String(describing: snap))).",
                vehicleID: vehicleID
            )
            try await awaitCompletableForManualStream(session.drone.action.disarm())
            appendVehicleLog("Park: disarm acknowledged.", vehicleID: vehicleID)
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        try await awaitCompletableForManualStream(session.drone.action.hold())
        appendVehicleLog("Park: hold acknowledged.", vehicleID: vehicleID)
    }

    private func waitParkUntilUAVOnGround(vehicleID: String, timeoutMs: Int) async throws {
        let pollMs = 250
        var elapsed = 0
        while elapsed < timeoutMs {
            let h = parkHub(vehicleID)
            if hubShowsUAVOnDeckForPark(h) {
                appendVehicleLog("Park: ground/on-deck signal after \(elapsed) ms.", vehicleID: vehicleID)
                return
            }
            try await Task.sleep(nanoseconds: UInt64(pollMs) * 1_000_000)
            elapsed += pollMs
        }
        throw NSError(
            domain: "FleetLinkService",
            code: 31,
            userInfo: [NSLocalizedDescriptionKey: "Park: timeout waiting for landed or disarmed state after land."]
        )
    }

    /// Treats MAVSDK / bridge `landed_state` strings (e.g. `ON_GROUND`) as authoritative on-deck, in
    /// addition to armed / in-air / relative-altitude heuristics used before landed-state telemetry existed.
    private func hubShowsUAVOnDeckForPark(_ hub: FleetHubVehicleTelemetry?) -> Bool {
        guard let h = hub else { return false }
        if let landed = h.landedState {
            let norm = landed.lowercased().replacingOccurrences(of: " ", with: "")
            if norm.contains("on_ground") || norm.contains("onground") {
                return true
            }
        }
        return (h.inAir == false)
            || (h.isArmed == false)
            || ((h.relativeAltM ?? 999) < 1.5 && (h.relativeAltM != nil))
    }

    /// UUV: surface when deep or in-air, wait shallow, disarm, hold.
    private func parkSequenceUUV(vehicleID: String, session: VehicleSession) async throws {
        let h = parkHub(vehicleID)
        let needsSurface = (h?.inAir == true) || ((h?.relativeAltM ?? 0) < -0.45)
        if needsSurface, h?.isArmed == true {
            do {
                try await awaitCompletableForManualStream(
                    completionForSetMode(mode: .surface, vehicleID: vehicleID, session: session)
                )
                appendVehicleLog("Park (UUV): surface mode acknowledged; waiting to shallow…", vehicleID: vehicleID)
            } catch {
                appendVehicleLog(
                    "Park (UUV): surface mode failed (\(mavsdkPublicErrorDescription(error))); continuing.",
                    vehicleID: vehicleID
                )
            }
            try await waitParkUntilUUVShallow(vehicleID: vehicleID, timeoutMs: 120_000)
        } else {
            appendVehicleLog(
                "Park (UUV): skipping surface (inAir=\(String(describing: h?.inAir)) relAlt=\(String(describing: h?.relativeAltM)) armed=\(String(describing: h?.isArmed))).",
                vehicleID: vehicleID
            )
        }
        if parkHub(vehicleID)?.isArmed == true {
            try await awaitCompletableForManualStream(session.drone.action.disarm())
            appendVehicleLog("Park (UUV): disarm acknowledged.", vehicleID: vehicleID)
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        try await awaitCompletableForManualStream(session.drone.action.hold())
        appendVehicleLog("Park (UUV): hold acknowledged.", vehicleID: vehicleID)
    }

    private func waitParkUntilUUVShallow(vehicleID: String, timeoutMs: Int) async throws {
        let pollMs = 250
        var elapsed = 0
        while elapsed < timeoutMs {
            let h = parkHub(vehicleID)
            let shallow = (h?.inAir == false)
                || ((h?.relativeAltM ?? -999) > -0.35)
                || (h?.isArmed == false)
            if shallow {
                appendVehicleLog("Park (UUV): shallow / surfaced after \(elapsed) ms.", vehicleID: vehicleID)
                return
            }
            try await Task.sleep(nanoseconds: UInt64(pollMs) * 1_000_000)
            elapsed += pollMs
        }
        throw NSError(
            domain: "FleetLinkService",
            code: 32,
            userInfo: [NSLocalizedDescriptionKey: "Park (UUV): timeout waiting to reach shallow state after surface."]
        )
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

    /// Raw per-vehicle log buffer (matches global prefix filtering used in the UI).
    func storedLogLines(forVehicleID vehicleID: String) -> [String] {
        logLinesByVehicleID[vehicleID] ?? []
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
                            self.scheduleApplyPendingSpawnSimStateIfNeeded(session: session, vehicleID: vehicleID)
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
        // Yaw → heading. Without this, the marker arrow + telemetry "Heading" value never
        // update during keyboard yaw or autopilot turns. We use `attitudeEuler` (ATTITUDE
        // MAVLink message) because it's universally published by both PX4 and ArduPilot,
        // unlike `telemetry.heading` which depends on global-position health on some stacks.
        // `yawDeg` is reported in ±180; `normalizedDegrees` maps it to the 0…360 range
        // that the rest of the app (map marker, telemetry sheet, log formatters) expects.
        session.drone.telemetry.attitudeEuler
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(onNext: { [weak self] euler in
                Task { @MainActor [weak self] in
                    self?.applyNativeTelemetry(vehicleID: vehicleID, systemID: systemID) { hub in
                        hub.headingDeg = Self.normalizedDegrees(Double(euler.yawDeg))
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
                    if tot > 0, cur == 0 {
                        self.autopilotMissionCycleHasInProgressLegByVehicleID[vehicleID] = false
                        self.autopilotMissionCompletionLatchByVehicleID[vehicleID] = false
                    } else if tot > 0, cur > 0 {
                        if cur < tot {
                            self.autopilotMissionCycleHasInProgressLegByVehicleID[vehicleID] = true
                            self.autopilotMissionCompletionLatchByVehicleID[vehicleID] = false
                        } else if cur == tot, tot == 1 {
                            self.autopilotMissionCycleHasInProgressLegByVehicleID[vehicleID] = true
                        }
                    }
                    if tot > 0, cur >= tot {
                        let progressed = self.autopilotMissionCycleHasInProgressLegByVehicleID[vehicleID] ?? false
                        let latched = self.autopilotMissionCompletionLatchByVehicleID[vehicleID] ?? false
                        if progressed, !latched {
                            self.autopilotMissionCompletionLatchByVehicleID[vehicleID] = true
                            let doneLine = "Autopilot mission run complete (progress \(cur)/\(tot)); notifying schedule."
                            self.appendVehicleLog(doneLine, vehicleID: vehicleID)
                            self.onMirrorFleetLineToPaladin?(vehicleID, doneLine)
                            self.onAutopilotMissionCycleFinished?(vehicleID)
                        }
                    }
                    let pair = (cur: cur, tot: tot)
                    let prev = self.lastMissionProgressLoggedPairByVehicleID[vehicleID]
                    if prev?.cur != pair.cur || prev?.tot != pair.tot {
                        self.lastMissionProgressLoggedPairByVehicleID[vehicleID] = pair
                        let progLine = "Autopilot mission progress: item \(cur) of \(tot)."
                        self.appendVehicleLog(progLine, vehicleID: vehicleID)
                        self.onMirrorFleetLineToPaladin?(vehicleID, progLine)
                    }
                }
            })
            .disposed(by: session.bag)
    }

    private func stopSession(vehicleID: String) {
        guard let session = sessionsByVehicleID.removeValue(forKey: vehicleID) else { return }
        if liveDriveControlSessionVehicleID == vehicleID {
            liveDriveControlSessionVehicleID = nil
        }
        simulatedFleetVehicleIDs.remove(vehicleID)
        recentVehicleStatusMessagesByVehicleID[vehicleID] = nil
        autopilotMissionCompletionLatchByVehicleID[vehicleID] = nil
        autopilotMissionCycleHasInProgressLegByVehicleID[vehicleID] = nil
        lastMissionProgressLoggedPairByVehicleID.removeValue(forKey: vehicleID)
        if let stream = session.manualStream {
            session.manualStream = nil
            // Best-effort: stop the manual control stream synchronously enough that the
            // disconnected drone doesn't keep getting setpoints. The Task is fire-and-forget
            // because the gRPC pipe is about to be closed by `drone.disconnect()` anyway.
            Task { await stream.stop() }
        }
        if let formation = session.formationFollowStream {
            session.formationFollowStream = nil
            Task { await formation.stop() }
        }
        session.bag = DisposeBag()
        session.drone.disconnect()
        session.runner.stop()
        releaseGrpcPort(session.grpcPort)
        hubTelemetryByVehicleID.removeValue(forKey: vehicleID)
        telemetryByVehicleID.removeValue(forKey: vehicleID)
        vehicleIDBySystemID.removeValue(forKey: session.systemID)
        // Drop fleet model + status outright. `applyLifecycleStatus(.stopped)` previously kept the model and
        // re-wrote hub/telemetry from **stale** embedded telemetry — with multiple SIMs, that orphaned `sysid:N`
        // was mis-classified as "live hardware" in VehiclesView (`fleetGridEntries` excludes only *current*
        // `sitl.instances` IDs), producing an extra phantom card until the last sim stopped or Simulate toggled off.
        vehicleModelsByVehicleID.removeValue(forKey: vehicleID)
        vehicleStatusByVehicleID.removeValue(forKey: vehicleID)
        recentVehicleStatusMessagesByVehicleID[vehicleID] = nil
        logLinesByVehicleID.removeValue(forKey: vehicleID)
        mcrRosterLiveChannelsByVehicleID[vehicleID]?.clearFleetSlice()
        if hubTelemetryByVehicleID.isEmpty {
            telemetry = nil
            hubTelemetry = nil
            bridgePhase = .awaitingVehicle
            lastTelemetryMutationVehicleID = nil
            publishHubFleetTelemetryTickAndRefreshMcrChannels()
        } else {
            // Primary hub/telemetry snapshots track "last writer"; refreshing avoids leaving them on a torn-down ID.
            if let survivor = hubTelemetryByVehicleID.keys.sorted().first {
                hubTelemetry = hubTelemetryByVehicleID[survivor]
                telemetry = telemetryByVehicleID[survivor]
                lastTelemetryMutationVehicleID = survivor
                publishHubFleetTelemetryTickAndRefreshMcrChannels()
            }
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

    /// Coalesces legacy `hubTelemetry` / `telemetry` snapshot updates and publishes ``hubFleetTelemetryTick`` (via
    /// ``publishHubFleetTelemetryTickAndRefreshMcrChannels``) so Mission Control can run expensive `.onChange` hooks at
    /// human scale instead of once per MAVSDK frame per vehicle. Retained MC‑R ``FleetVehicleLiveChannel`` rows refresh in
    /// the **same** synchronous closure as the tick bump (``README_FULL.md`` → **MC-R live UI row contracts** → **MC-R observation restructure — archived reference (v1 complete)** — §0.2 hub entry points).
    private func scheduleHubFleetTelemetryTickThrottled() {
        let now = Date()
        let minInterval: TimeInterval = 0.12
        let elapsed = now.timeIntervalSince(hubFleetTickLastEmit)
        let emit: () -> Void = { [weak self] in
            guard let self else { return }
            self.hubFleetTickWorkItem = nil
            self.hubFleetTickLastEmit = Date()
            if let vid = self.lastTelemetryMutationVehicleID {
                self.hubTelemetry = self.hubTelemetryByVehicleID[vid]
                self.telemetry = self.telemetryByVehicleID[vid]
            }
            self.publishHubFleetTelemetryTickAndRefreshMcrChannels()
        }
        if elapsed >= minInterval {
            hubFleetTickWorkItem?.cancel()
            hubFleetTickWorkItem = nil
            emit()
            return
        }
        guard hubFleetTickWorkItem == nil else { return }
        let delay = minInterval - elapsed
        let work = DispatchWorkItem { emit() }
        hubFleetTickWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, delay), execute: work)
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
        lastTelemetryMutationVehicleID = vehicleID
        scheduleHubFleetTelemetryTickThrottled()
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

    /// Request faster battery-related MAVLink via MAVSDK, bump the attitude stream so
    /// heading updates feel smooth during yaw, and for **PX4 SITL** set a non-zero
    /// `BAT1_CAPACITY` so remaining % is estimable.
    private func applyMavlinkBatteryTelemetryTuningOnce(session: VehicleSession, vehicleID: String) {
        guard !session.didApplyMavlinkBatteryTuning else { return }
        session.didApplyMavlinkBatteryTuning = true

        // 10 Hz attitude is more than enough for a smooth heading arrow on the map; ATTITUDE
        // MAVLink messages are cheap so this isn't a bandwidth concern. Failure here is
        // logged but non-fatal — the subscription still works at whatever default rate the
        // autopilot publishes.
        session.drone.telemetry.setRateAttitude(rateHz: 10.0)
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onCompleted: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog("Set MAVSDK attitude telemetry stream rate to 10 Hz.", vehicleID: vehicleID)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog(
                            "Attitude telemetry set-rate unavailable: \(error.localizedDescription)",
                            vehicleID: vehicleID
                        )
                    }
                }
            )
            .disposed(by: session.bag)

        session.drone.telemetry.setRateBattery(rateHz: 5.0)
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
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
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
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

        // COM_RC_IN_MODE = 1 (Joystick only).
        //
        // Default is 0 (RC Transmitter only). With 0, PX4 ignores every MAVLink
        // `MANUAL_CONTROL` message because there's no hardware RC link in SIH SITL,
        // so `rc_signal_lost = true`, MANUAL mode is rejected as "no manual control
        // source", and the rover bounces straight back to HOLD. Setting this to 1
        // tells PX4 to treat our MAVLink joystick stream as the canonical manual input
        // source, which is what unblocks `commander mode manual` for the LiveDrive
        // PX4-ground keyboard path.
        //
        // Safe for non-rover PX4 SITLs too: the parameter just changes the input
        // priority; UAVs that aren't using MANUAL_CONTROL aren't affected.
        session.drone.param.setParamInt(name: "COM_RC_IN_MODE", value: 1)
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
            .observe(on: MainScheduler.asyncInstance)
            .subscribe(
                onCompleted: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog(
                            "Applied SIM default COM_RC_IN_MODE=1 (Joystick) so MAVLink MANUAL_CONTROL is accepted.",
                            vehicleID: vehicleID
                        )
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog(
                            "SIM COM_RC_IN_MODE default skipped: \(error.localizedDescription)",
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
        case .uploadMission(let items):
            return "uploadMission(\(items.count) items)"
        case .uploadGeofence(let wire):
            return "uploadGeofence(\(wire.polygons.count) polygon(s), \(wire.circles.count) circle(s))"
        case .clearGeofence:
            return "clearGeofence"
        case .missionClear:
            return "missionClear"
        case .missionStart:
            return "missionStart"
        case .missionPause:
            return "missionPause"
        case .missionSetCurrentItem(let index):
            return "missionSetCurrentItem(index=\(index))"
        case .missionDownloadPlanJSON:
            return "missionDownloadPlanJSON"
        case .missionIsFinishedQuery:
            return "missionIsFinishedQuery"
        case .missionGetRtlAfter:
            return "missionGetRtlAfter"
        case .missionSetRtlAfter(let enable):
            return "missionSetRtlAfter(enable=\(enable))"
        case .cancelMissionUpload:
            return "cancelMissionUpload"
        case .cancelMissionDownload:
            return "cancelMissionDownload"
        case .returnToLaunch:
            return "returnToLaunch"
        case .land:
            return "land"
        case .park:
            return "park"
        case .idle:
            return "idle(manualMode)"
        case .manualControl(let manual):
            return "manualControl(intent=\(manual.intent.rawValue) class=\(manual.vehicleClass.rawValue))"
        case .calibrateMavsdk(let kind):
            return "calibrateMavsdk(\(kind.rawValue))"
        case .mavlinkCommandLong(let request):
            return "mavlinkCommandLong(\(request.command) \(request.humanLabel))"
        case .cancelCalibration:
            return "cancelCalibration"
        case .setParameterFloat(let name, let value):
            return String(format: "setParameterFloat(name=%@ value=%.6f)", name, value)
        case .setParameterInt(let name, let value):
            return "setParameterInt(name=\(name) value=\(value))"
        case .setMode(let mode):
            return "setMode(\(mode.rawValue))"
        case .offboardStop:
            return "offboardStop"
        case .rebootAutopilot:
            return "rebootAutopilot"
        }
    }

    /// Upload-only mission dispatch.
    ///
    /// Uploads the plan, then resets the autopilot's current waypoint to 0 so a re-uploaded plan
    /// always starts from the first item — **stops there**. Arm and start are caller / recipe
    /// responsibilities. Powers `command.fleet.vehicle.do.mission.upload` via
    /// ``FleetVehicleCommand/uploadMission(items:)``.
    private func completionForUploadMissionOnly(
        items: [Mavsdk.Mission.MissionItem],
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        let plan = Mavsdk.Mission.MissionPlan(missionItems: items)
        let drone = session.drone
        appendVehicleLog(
            "Uploading mission plan (\(items.count) item(s)); will reset current waypoint to 0…",
            vehicleID: vehicleID
        )
        return drone.mission.uploadMission(missionPlan: plan)
            .andThen(drone.mission.setCurrentMissionItem(index: 0))
    }

    /// MAVSDK `Mission` plugin calls that return `Single` (download / readbacks) — bridged
    /// into ``FleetCommandAsyncOutcome/succeededWithPayload(_:)`` for Layer 0 normalisers.
    ///
    /// - Returns: `true` when this command was handled (subscription installed); `false`
    ///   when the caller should fall through to the `Completable` pipeline.
    private func subscribeMissionSingleIfNeeded(
        vehicleID: String,
        commandID: UUID,
        command: FleetVehicleCommand,
        session: VehicleSession,
        onCommandOutcome: (@MainActor (FleetCommandAsyncOutcome) -> Void)?
    ) -> Bool {
        let drone = session.drone
        switch command {
        case .missionDownloadPlanJSON:
            drone.mission.downloadMission()
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(
                    onSuccess: { [weak self] plan in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            do {
                                let json = try FleetVehicleCommandMissionItemPayload.encodeMissionPlanToJSON(plan: plan)
                                self.markVehicleCommand(vehicleID: vehicleID, commandID: commandID, status: .succeeded)
                                self.appendVehicleLog(
                                    "Command succeeded: \(self.describe(command: command))",
                                    vehicleID: vehicleID
                                )
                                onCommandOutcome?(.succeededWithPayload(.string(json)))
                            } catch {
                                let detail = "mission download succeeded but JSON encoding failed: \(error.localizedDescription)"
                                self.markVehicleCommand(
                                    vehicleID: vehicleID,
                                    commandID: commandID,
                                    status: .failed(detail)
                                )
                                self.appendVehicleLog("Command error: \(detail)", vehicleID: vehicleID)
                                onCommandOutcome?(.failed(detail))
                            }
                        }
                    },
                    onFailure: { [weak self] error in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let raw = self.mavsdkPublicErrorDescription(error)
                            let detail = self.augmentCommandFailureDetail(vehicleID: vehicleID, detail: raw)
                            self.markVehicleCommand(
                                vehicleID: vehicleID,
                                commandID: commandID,
                                status: .failed(detail)
                            )
                            self.appendVehicleLog("Command error: \(detail)", vehicleID: vehicleID)
                            onCommandOutcome?(.failed(detail))
                        }
                    }
                )
                .disposed(by: session.bag)
            return true

        case .missionIsFinishedQuery:
            drone.mission.isMissionFinished()
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(
                    onSuccess: { [weak self] finished in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.markVehicleCommand(vehicleID: vehicleID, commandID: commandID, status: .succeeded)
                            self.appendVehicleLog(
                                "Command succeeded: \(self.describe(command: command)) → \(finished)",
                                vehicleID: vehicleID
                            )
                            onCommandOutcome?(.succeededWithPayload(.bool(finished)))
                        }
                    },
                    onFailure: { [weak self] error in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let raw = self.mavsdkPublicErrorDescription(error)
                            let detail = self.augmentCommandFailureDetail(vehicleID: vehicleID, detail: raw)
                            self.markVehicleCommand(
                                vehicleID: vehicleID,
                                commandID: commandID,
                                status: .failed(detail)
                            )
                            self.appendVehicleLog("Command error: \(detail)", vehicleID: vehicleID)
                            onCommandOutcome?(.failed(detail))
                        }
                    }
                )
                .disposed(by: session.bag)
            return true

        case .missionGetRtlAfter:
            drone.mission.getReturnToLaunchAfterMission()
                .observe(on: MainScheduler.asyncInstance)
                .subscribe(
                    onSuccess: { [weak self] enabled in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.markVehicleCommand(vehicleID: vehicleID, commandID: commandID, status: .succeeded)
                            self.appendVehicleLog(
                                "Command succeeded: \(self.describe(command: command)) → \(enabled)",
                                vehicleID: vehicleID
                            )
                            onCommandOutcome?(.succeededWithPayload(.bool(enabled)))
                        }
                    },
                    onFailure: { [weak self] error in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let raw = self.mavsdkPublicErrorDescription(error)
                            let detail = self.augmentCommandFailureDetail(vehicleID: vehicleID, detail: raw)
                            self.markVehicleCommand(
                                vehicleID: vehicleID,
                                commandID: commandID,
                                status: .failed(detail)
                            )
                            self.appendVehicleLog("Command error: \(detail)", vehicleID: vehicleID)
                            onCommandOutcome?(.failed(detail))
                        }
                    }
                )
                .disposed(by: session.bag)
            return true

        default:
            return false
        }
    }

    /// Bridge a MAVSDK Calibration plugin `Observable<ProgressData>` into the existing
    /// `Completable` dispatch shape used by `executeVehicleCommand`.
    ///
    /// MAVSDK's calibration entrypoints (`calibrateGyro`, `calibrateAccelerometer`, …)
    /// emit a stream of progress events and terminate on `onCompleted` (success) or
    /// `onError` (failure / operator cancel via `calibration.cancel()`). We discard the
    /// progress payloads in v1 — recipes (Stage B) and the operator wizard (Stage E) get
    /// a single terminal outcome until we add a progress-aware response shape.
    ///
    /// Returning a `Disposables.create` around the inner subscription means a downstream
    /// `dispose()` (e.g. `session.bag` torn down on disconnect) propagates into the
    /// MAVSDK calibration stream, releasing it cleanly.
    private func completionForMavsdkCalibration(
        kind: MavsdkCalibrationKind,
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        let observable: Observable<Calibration.ProgressData>
        switch kind {
        case .gyro:
            observable = session.drone.calibration.calibrateGyro()
        case .accelerometer:
            observable = session.drone.calibration.calibrateAccelerometer()
        case .magnetometer:
            observable = session.drone.calibration.calibrateMagnetometer()
        case .levelHorizon:
            observable = session.drone.calibration.calibrateLevelHorizon()
        case .gimbalAccelerometer:
            observable = session.drone.calibration.calibrateGimbalAccelerometer()
        }
        let subject = self.calibrationProgressSubject
        return Completable.create { completable in
            // MAVSDK emits calibration `ProgressData` on a SwiftNIO event-loop thread. This service
            // is `@MainActor`; touching `calibrationProgressSubject` (or completing the Completable)
            // from NIO trips MainActor / GCD queue assertions and can wedge the app. Serialize the
            // whole stream onto the main scheduler before handling.
            let inner = observable
                .observe(on: MainScheduler.instance)
                .subscribe(
                onNext: { progress in
                    let phase: FleetCalibrationProgressEvent.Phase
                    let fraction: Double?
                    if progress.hasProgress {
                        fraction = Double(progress.progress)
                        phase = .progress
                    } else if progress.hasStatusText {
                        fraction = nil
                        phase = .operatorPrompt
                    } else {
                        fraction = nil
                        phase = .progress
                    }
                    subject.send(
                        FleetCalibrationProgressEvent(
                            vehicleID: vehicleID,
                            kind: kind,
                            phase: phase,
                            progressFraction: fraction,
                            statusText: progress.hasStatusText ? progress.statusText : nil,
                            timestamp: Date()
                        )
                    )
                },
                onError: { error in
                    let detail = (error as NSError).localizedDescription
                    if Self.isCalibrationCancellationDetail(detail) {
                        subject.send(
                            FleetCalibrationProgressEvent(
                                vehicleID: vehicleID,
                                kind: kind,
                                phase: .cancelled,
                                progressFraction: nil,
                                statusText: nil,
                                timestamp: Date()
                            )
                        )
                    } else {
                        subject.send(
                            FleetCalibrationProgressEvent(
                                vehicleID: vehicleID,
                                kind: kind,
                                phase: .failed(detail: detail),
                                progressFraction: nil,
                                statusText: nil,
                                timestamp: Date()
                            )
                        )
                    }
                    completable(.error(error))
                },
                onCompleted: {
                    subject.send(
                        FleetCalibrationProgressEvent(
                            vehicleID: vehicleID,
                            kind: kind,
                            phase: .completed,
                            progressFraction: 1.0,
                            statusText: nil,
                            timestamp: Date()
                        )
                    )
                    completable(.completed)
                }
                )
            return Disposables.create { inner.dispose() }
        }
    }

    /// Heuristic for "this MAVSDK Calibration error means the calibration was
    /// cancelled". Mirrored by the catalogue's stack-converter normaliser so the
    /// Layer 0 outcome surfaces as ``FleetCommandResponse/Outcome/cancelled`` rather
    /// than `.error(.unknown)`. Kept narrow because false positives (treating a
    /// genuine failure as a cancellation) would mute real errors.
    nonisolated static func isCalibrationCancellationDetail(_ detail: String) -> Bool {
        let lower = detail.lowercased()
        if lower.contains("cancelled") || lower.contains("canceled") {
            return true
        }
        if lower.contains("mav_result_canceled") || lower.contains("mav_result_cancelled") {
            return true
        }
        return false
    }

    // MARK: - PX4 move-point (OFFBOARD global setpoints)

    /// Horizontal distance (m) from target before ``runPx4MovePointOffboardStreamingThenStop`` ends streaming.
    private static let px4MovePointOffboardArrivalM: Double = 4.0
    /// Wall-clock budget for OFFBOARD streaming while converging on the target lat/lon.
    private static let px4MovePointOffboardTimeoutMs: Int = 180_000
    /// PX4 expects fresh OFFBOARD setpoints at a few Hz; 10 Hz matches Live Drive headroom.
    private static let px4MovePointOffboardSetpointIntervalMs: Int = 100

    /// **PX4:** ``Action/gotoLocation`` is unreliable while **AUTO / mission** owns navigation.
    /// Move-point instead pauses the mission, streams ``Offboard/setPositionGlobal`` in **OFFBOARD** until
    /// hub lat/lon is within ``px4MovePointOffboardArrivalM``, then ``Offboard/stop`` so **Park** can run normally.
    private func completionForPx4GotoCoordinateViaOffboard(
        coord: RouteCoordinate,
        targetAbsoluteAlt: Double,
        yawDeg: Double,
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        FleetLinkMavsdkCompletableBridge.px4GotoOffboardCompletable { [weak self] in
            guard let self else { return }
            try await self.runPx4MovePointOffboardStreamingThenStop(
                coord: coord,
                targetAbsoluteAlt: targetAbsoluteAlt,
                yawDeg: yawDeg,
                vehicleID: vehicleID,
                session: session
            )
        }
    }

    private func runPx4MovePointOffboardStreamingThenStop(
        coord: RouteCoordinate,
        targetAbsoluteAlt: Double,
        yawDeg: Double,
        vehicleID: String,
        session: VehicleSession
    ) async throws {
        appendVehicleLog(
            "PX4 move-point: best-effort mission pause before OFFBOARD global setpoint move.",
            vehicleID: vehicleID
        )
        do {
            try await awaitCompletableForManualStream(session.drone.mission.pauseMission())
            appendVehicleLog("PX4 move-point: mission pause acknowledged.", vehicleID: vehicleID)
        } catch {
            appendVehicleLog(
                "PX4 move-point: mission pause skipped (\(mavsdkPublicErrorDescription(error))) — continuing.",
                vehicleID: vehicleID
            )
        }

        do {
            try await awaitCompletableForManualStream(session.drone.offboard.stop())
            appendVehicleLog("PX4 move-point: OFFBOARD stop (pre-move) acknowledged.", vehicleID: vehicleID)
        } catch {
            appendVehicleLog(
                "PX4 move-point: OFFBOARD stop (pre-move) skipped (\(mavsdkPublicErrorDescription(error))) — continuing.",
                vehicleID: vehicleID
            )
        }

        let positionGlobal = Offboard.PositionGlobalYaw(
            latDeg: coord.lat,
            lonDeg: coord.lon,
            altM: Float(targetAbsoluteAlt),
            yawDeg: Float(yawDeg),
            altitudeType: .amsl
        )

        try await awaitCompletableForManualStream(
            session.drone.offboard.setPositionGlobal(positionGlobalYaw: positionGlobal)
        )
        try await awaitCompletableForManualStream(session.drone.offboard.start())
        appendVehicleLog(
            "PX4 move-point: OFFBOARD streaming toward target (global position setpoint).",
            vehicleID: vehicleID
        )

        var elapsedMs = 0
        var lastProgressLogMs = 0
        var arrived = false
        while elapsedMs < Self.px4MovePointOffboardTimeoutMs {
            try Task.checkCancellation()
            try await awaitCompletableForManualStream(
                session.drone.offboard.setPositionGlobal(positionGlobalYaw: positionGlobal)
            )
            try await Task.sleep(nanoseconds: UInt64(Self.px4MovePointOffboardSetpointIntervalMs) * 1_000_000)
            elapsedMs += Self.px4MovePointOffboardSetpointIntervalMs

            if let hub = hubTelemetryByVehicleID[vehicleID],
               let lat = hub.latitudeDeg,
               let lon = hub.longitudeDeg {
                let d = MissionRunMovePointParkPlanner.haversineMeters(
                    lat1: lat,
                    lon1: lon,
                    lat2: coord.lat,
                    lon2: coord.lon
                )
                if elapsedMs - lastProgressLogMs >= 5_000 {
                    lastProgressLogMs = elapsedMs
                    appendVehicleLog(
                        String(
                            format: "PX4 move-point: ≈ %.0f m from target horizontal (elapsed %d ms).",
                            d,
                            elapsedMs
                        ),
                        vehicleID: vehicleID
                    )
                }
                if d < Self.px4MovePointOffboardArrivalM {
                    appendVehicleLog(
                        String(format: "PX4 move-point: within %.1f m of target — ending OFFBOARD stream.", d),
                        vehicleID: vehicleID
                    )
                    arrived = true
                    break
                }
            }
        }

        do {
            try await awaitCompletableForManualStream(session.drone.offboard.stop())
            appendVehicleLog("PX4 move-point: OFFBOARD stop after move acknowledged.", vehicleID: vehicleID)
        } catch {
            appendVehicleLog(
                "PX4 move-point: OFFBOARD stop after move failed (\(mavsdkPublicErrorDescription(error))).",
                vehicleID: vehicleID
            )
            throw error
        }

        if !arrived {
            throw NSError(
                domain: "FleetLinkService",
                code: 32,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "PX4 move-point: timed out before hub position reached the target area (check GPS / link / target)."
                ]
            )
        }
    }

    /// ArduPilot only honours ``Action/gotoLocation`` as external navigation when the
    /// vehicle is in **Guided**. Prepend `mode guided` for UAV / UGV / USV so move-point
    /// and similar gotos are not dropped while the stack is still in Hold / Loiter.
    ///
    /// **PX4:** catalogue ``FleetVehicleMode/guided`` maps to **OFFBOARD**; ``Action/gotoLocation`` alone
    /// is a poor fit under **AUTO / mission**, so move-point uses OFFBOARD global position setpoints
    /// (see ``completionForPx4GotoCoordinateViaOffboard``) then stops streaming before downstream **Park**.
    private func completionForGotoCoordinate(
        coord: RouteCoordinate,
        relativeAltitudeM: Double,
        yawDeg: Double,
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        let hub = hubTelemetryByVehicleID[vehicleID]
        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack
            ?? hub?.autopilotStack
            ?? .unknown
        let universalClass = vehicleModelsByVehicleID[vehicleID]?.data.vehicleType.universalClass
            ?? .unknown

        let fallbackBaseAlt = hub?.absoluteAltM ?? 0
        let targetAbsoluteAlt = fallbackBaseAlt + relativeAltitudeM
        let gotoRx = session.drone.action.gotoLocation(
            latitudeDeg: coord.lat,
            longitudeDeg: coord.lon,
            absoluteAltitudeM: targetAbsoluteAlt,
            yawDeg: yawDeg
        )

        if stack == .px4 {
            return completionForPx4GotoCoordinateViaOffboard(
                coord: coord,
                targetAbsoluteAlt: targetAbsoluteAlt,
                yawDeg: yawDeg,
                vehicleID: vehicleID,
                session: session
            )
        }

        guard stack == .ardupilot else { return gotoRx }

        switch universalClass {
        case .uav, .ugv, .usv:
            return ardupilotSetModeCompletable(
                mode: .guided,
                vehicleID: vehicleID,
                session: session,
                vehicleClass: universalClass
            ).andThen(gotoRx)
        case .uuv, .unknown:
            return gotoRx
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
            // Ground/surface/sub classes: arm (if needed) and explicitly leave HOLD-like states.
            var pipeline: Completable = Completable.empty()
            if hub?.isArmed != true {
                pipeline = session.drone.action.arm()
            }
            return pipeline.andThen(
                requestSurfaceOrGroundDriveModeIfAvailable(vehicleID: vehicleID, session: session)
            )
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
                absoluteAltitudeM: currentAbsoluteAlt,
                yawDeg: Self.normalizedDegrees(currentYaw + delta)
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
                absoluteAltitudeM: targetAbsoluteAlt,
                yawDeg: Self.normalizedDegrees(yaw)
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

    /// Best-effort non-UAV engage mode request so Return exits HOLD-style mode.
    private func requestSurfaceOrGroundDriveModeIfAvailable(
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack
            ?? hubTelemetryByVehicleID[vehicleID]?.autopilotStack
            ?? .unknown
        switch stack {
        case .px4:
            // PX4 surface/ground: switch to MANUAL via a raw MAVLink `SET_MODE` packet.
            // We used to send `commander mode manual` through the MAVSDK Shell plugin,
            // but PX4 SITL doesn't run a `mavlink_shell` instance on the Onboard link
            // that mavsdk_server connects through, so SERIAL_CONTROL bytes are silently
            // dropped — the gRPC call "succeeds" without changing the autopilot mode.
            // `Px4ModeCommander.setMode(.manual)` posts the canonical SET_MODE message
            // to PX4's GCS UDP port (the same path QGroundControl uses), which is
            // handled by the standard command pipeline and emits a COMMAND_ACK.
            return sendPx4SetModeCompletable(
                vehicleID: vehicleID,
                session: session,
                mainMode: .manual,
                logTag: "engage"
            )
        case .ardupilot:
            // ArduPilot rover/boat: guided enables external navigation commands.
            return session.drone.shell.send(command: "mode guided")
        case .unknown:
            return Completable.empty()
        }
    }

    /// Set the autopilot's flight / drive mode using a real, stack-specific transport.
    ///
    /// PX4 → raw MAVLink `SET_MODE` to PX4's GCS UDP port via ``Px4ModeCommander``.
    /// MAVSDK Swift's `Action` plugin has no `setMode(...)` helper, and the `Shell`
    /// plugin path silently drops `commander mode <name>` because PX4 SITL doesn't
    /// run a `mavlink_shell` instance on the Onboard link that `mavsdk_server`
    /// connects through. See ``Px4ModeCommander`` for the long-form rationale.
    ///
    /// ArduPilot → `mode <name>` over the MAVSDK `Shell` plugin. AP SITL routes shell
    /// bytes through its mavlink_shell so this path actually changes mode.
    ///
    /// `unknown` stack → try the AP shell path first; if it errors, fall back to the
    /// PX4 raw path. Same heuristic as ``completionForIdleManualMode``.
    ///
    /// Failure detail strings include the literal phrase `"mode not supported"` for
    /// stack/mode combinations the autopilot cannot honour, so the catalogue's
    /// outcome normaliser classifies them as ``FleetCommandErrorKind/modeNotSupported``.
    private func completionForSetMode(
        mode: FleetVehicleMode,
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack
            ?? hubTelemetryByVehicleID[vehicleID]?.autopilotStack
            ?? .unknown
        let universalClass = vehicleModelsByVehicleID[vehicleID]?.data.vehicleType.universalClass
            ?? .unknown

        switch stack {
        case .px4:
            return px4SetModeCompletable(
                mode: mode,
                vehicleID: vehicleID,
                session: session
            )
        case .ardupilot:
            return ardupilotSetModeCompletable(
                mode: mode,
                vehicleID: vehicleID,
                session: session,
                vehicleClass: universalClass
            )
        case .unknown:
            return ardupilotSetModeCompletable(
                mode: mode,
                vehicleID: vehicleID,
                session: session,
                vehicleClass: universalClass
            )
            .catch { _ in
                self.px4SetModeCompletable(
                    mode: mode,
                    vehicleID: vehicleID,
                    session: session
                )
            }
        }
    }

    /// PX4 SET_MODE dispatch. `brake` returns a "mode not supported" failure because
    /// PX4 has no Brake mode (recipes can branch on `.modeNotSupported`).
    private func px4SetModeCompletable(
        mode: FleetVehicleMode,
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        guard let mapping = Self.px4MainSubMode(for: mode) else {
            return Completable.error(NSError(
                domain: "FleetLinkService",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "PX4 mode '\(mode.rawValue)' is not supported (mode not supported)."]
            ))
        }
        return sendPx4SetModeCompletable(
            vehicleID: vehicleID,
            session: session,
            mainMode: mapping.main,
            subMode: mapping.sub,
            logTag: "do.mode=\(mode.rawValue)"
        )
    }

    /// PX4 main-mode + AUTO sub-mode mapping. AUTO modes encode the sub-mode in
    /// `custom_mode`'s high byte; non-AUTO modes leave it at zero.
    /// Source: PX4's `commander/px4_custom_mode.h`.
    private static func px4MainSubMode(
        for mode: FleetVehicleMode
    ) -> (main: Px4ModeCommander.MainMode, sub: UInt8)? {
        switch mode {
        case .manual:    return (.manual,   0)
        case .hold:      return (.auto,     3)   // PX4 AUTO_LOITER
        case .auto:      return (.auto,     4)   // PX4 AUTO_MISSION
        case .mission:   return (.auto,     4)
        case .rtl:       return (.auto,     5)   // PX4 AUTO_RTL
        case .landMode:  return (.auto,     6)   // PX4 AUTO_LAND
        case .guided:    return (.offboard, 0)   // closest analogue PX4 has
        case .brake:     return nil               // PX4 has no brake mode
        case .surface:   return nil               // PX4 has no UUV stack / SURFACE mode
        }
    }

    /// ArduPilot `mode <name>` dispatch via MAVSDK Shell plugin. Hold maps to the
    /// class-correct shell mode (`mode hold` for rovers / boats, `mode loiter` for
    /// UAVs / UUVs); brake is sent verbatim because AP Copter accepts it but AP
    /// Rover / Plane will reject — the rejection bubbles up through the Shell
    /// completable and the converter classifies it as `.modeNotSupported`.
    private func ardupilotSetModeCompletable(
        mode: FleetVehicleMode,
        vehicleID: String,
        session: VehicleSession,
        vehicleClass: UniversalVehicleClass
    ) -> Completable {
        let name = Self.ardupilotShellModeName(for: mode, vehicleClass: vehicleClass)
        appendVehicleLog(
            "ArduPilot SHELL `mode \(name)` sent (do.mode=\(mode.rawValue), class=\(vehicleClass.rawValue)).",
            vehicleID: vehicleID
        )
        return session.drone.shell.send(command: "mode \(name)")
    }

    /// ArduPilot shell mode-name picker. The mapping is intentionally tight — every
    /// value here has been verified against ArduCopter / ArduPlane / Rover / Sub
    /// firmware. New modes are a deliberate extension.
    private static func ardupilotShellModeName(
        for mode: FleetVehicleMode,
        vehicleClass: UniversalVehicleClass
    ) -> String {
        switch mode {
        case .hold:
            // Rover / boat: "hold". UAV / UUV / unknown: "loiter".
            switch vehicleClass {
            case .ugv, .usv: return "hold"
            case .uav, .uuv, .unknown: return "loiter"
            }
        case .manual:   return "manual"
        case .auto:     return "auto"
        case .rtl:      return "rtl"
        case .guided:   return "guided"
        case .mission:  return "auto"   // ArduPilot "auto" runs the loaded mission
        case .landMode: return "land"
        case .brake:    return "brake"  // Copter-only; non-Copter airframes will reject
        case .surface:  return "surface"  // Sub-only (ArduSub mode 9); non-Sub airframes will reject
        }
    }

    /// Wrap `Px4ModeCommander.setMode(...)` in a `Completable` so the existing
    /// command-pipeline plumbing (queueing, status tracking, async outcome
    /// reporting) keeps working without leaking async/await everywhere.
    private func sendPx4SetModeCompletable(
        vehicleID: String,
        session: VehicleSession,
        mainMode: Px4ModeCommander.MainMode,
        subMode: UInt8 = 0,
        logTag: String
    ) -> Completable {
        guard let port = px4GcsUdpPort(for: session) else {
            return Completable.error(NSError(
                domain: "FleetLinkService",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "PX4 GCS UDP port could not be derived from \(session.mavlinkConnectionURL)"]
            ))
        }
        let target = UInt8(clamping: session.systemID)
        let vehicleID = vehicleID
        return FleetLinkMavsdkCompletableBridge.px4SetModeCompletable(
            port: port,
            targetSystem: target,
            mainMode: mainMode,
            subMode: subMode,
            logTag: logTag,
            appendLog: { [weak self] line in
                Task { @MainActor [weak self] in
                    self?.appendVehicleLog(line, vehicleID: vehicleID)
                }
            }
        )
    }

    /// Wrap one raw MAVLink v2 `COMMAND_LONG` send in a `Completable`. This is the
    /// command-catalogue escape hatch for MAVLink atoms that MAVSDK Swift does not
    /// generate, especially calibration procedures.
    private func completionForMavlinkCommandLong(
        request: MavlinkCommandLongRequest,
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack
            ?? hubTelemetryByVehicleID[vehicleID]?.autopilotStack
            ?? .unknown
        guard let port = rawMavlinkUdpPort(for: session, stack: stack) else {
            return Completable.error(NSError(
                domain: "FleetLinkService",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Raw MAVLink COMMAND_LONG UDP port could not be derived from \(session.mavlinkConnectionURL)"]
            ))
        }
        let target = UInt8(clamping: session.systemID)
        let vehicleID = vehicleID
        return FleetLinkMavsdkCompletableBridge.mavlinkCommandLongCompletable(
            request: request,
            port: port,
            targetSystem: target,
            appendLog: { [weak self] line in
                Task { @MainActor [weak self] in
                    self?.appendVehicleLog(line, vehicleID: vehicleID)
                }
            },
            appendError: { [weak self] line, error in
                Task { @MainActor [weak self] in
                    self?.appendVehicleLog(
                        "\(line) \(error.localizedDescription)",
                        vehicleID: vehicleID
                    )
                }
            }
        )
    }

    // MARK: - PARAM_SET with read-back verification (catalogue calibration path)

    /// Wraps `Drone.param.setParamFloat(name:value:)` with a follow-up
    /// `getParamFloat(name:)` and a tolerance-aware equality check. Emits a recognisable
    /// `"PARAM_SET read-back mismatch: …"` error string on mismatch so the catalogue's
    /// stack-converter normaliser (see ``FleetCommandStackConverterShared``) can map
    /// the outcome to ``FleetCommandErrorKind/parameterReadBackMismatch``.
    ///
    /// Used exclusively by the catalogue's `.setParameterFloat` dispatch path —
    /// fire-and-forget param helpers (`setVehicleFloatParameter`, internal bootstrap
    /// writes) deliberately stay un-verified because their callers are diagnostic /
    /// log-only and do not feed the recipe outcome taxonomy.
    ///
    /// **Tolerance:** the autopilot stores params as IEEE-754 single precision and may
    /// silently clamp / quantize on write. We accept a Float round-trip within
    /// `max(1e-4, |expected| * 5e-4)` (≈ 0.05% relative or an absolute floor of `1e-4`)
    /// — tight enough to surface clamping or rejection, loose enough to tolerate
    /// MAVLink wire-quantization.
    private func completionForSetParameterFloatWithReadBack(
        name: String,
        value: Float,
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        let logVehicleID = vehicleID
        let set = session.drone.param.setParamFloat(name: name, value: value)
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
        let verify: Completable = session.drone.param.getParamFloat(name: name)
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
            .observe(on: MainScheduler.asyncInstance)
            .flatMapCompletable { [weak self] actual -> Completable in
                let tolerance = max(Float(1e-4), abs(value) * Float(5e-4))
                if abs(actual - value) <= tolerance {
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog(
                            "Param verified \(name)=\(actual) (expected \(value), tol \(tolerance))",
                            vehicleID: logVehicleID
                        )
                    }
                    return Completable.empty()
                }
                let detail = "PARAM_SET read-back mismatch: \(name) expected \(value), autopilot reports \(actual)"
                Task { @MainActor [weak self] in
                    self?.appendVehicleLog(detail, vehicleID: logVehicleID)
                }
                return Completable.error(NSError(
                    domain: "FleetLinkService.Param.ReadBack",
                    code: 9,
                    userInfo: [NSLocalizedDescriptionKey: detail]
                ))
            }
        return set.andThen(verify)
    }

    /// Wraps `Drone.param.setParamInt(name:value:)` with a follow-up
    /// `getParamInt(name:)` and an exact-equality check. Emits the same
    /// `"PARAM_SET read-back mismatch: …"` error string on mismatch as the float
    /// variant so the catalogue normaliser can map the outcome to
    /// ``FleetCommandErrorKind/parameterReadBackMismatch``.
    ///
    /// Int params are quantized exactly, so any difference between the requested and
    /// reported value is a real outcome (silent clamp, locked param, type coercion).
    private func completionForSetParameterIntWithReadBack(
        name: String,
        value: Int32,
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        let logVehicleID = vehicleID
        let set = session.drone.param.setParamInt(name: name, value: value)
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
        let verify: Completable = session.drone.param.getParamInt(name: name)
            .subscribe(on: fleetLinkMavsdkBlockingRpcBox.scheduler)
            .observe(on: MainScheduler.asyncInstance)
            .flatMapCompletable { [weak self] actual -> Completable in
                if actual == value {
                    Task { @MainActor [weak self] in
                        self?.appendVehicleLog(
                            "Param verified \(name)=\(actual)",
                            vehicleID: logVehicleID
                        )
                    }
                    return Completable.empty()
                }
                let detail = "PARAM_SET read-back mismatch: \(name) expected \(value), autopilot reports \(actual)"
                Task { @MainActor [weak self] in
                    self?.appendVehicleLog(detail, vehicleID: logVehicleID)
                }
                return Completable.error(NSError(
                    domain: "FleetLinkService.Param.ReadBack",
                    code: 9,
                    userInfo: [NSLocalizedDescriptionKey: detail]
                ))
            }
        return set.andThen(verify)
    }

    /// PX4 SITL exposes its "Normal/GCS" MAVLink instance at UDP `18570 + px4_instance`,
    /// where `px4_instance = mavsdkUdpinPort - 14540` for our launch recipe (see
    /// `Px4SitlLocator.px4OffboardRemotePort` and `px4SihGcsUdpPort`). We send raw
    /// MAVLink (SET_MODE) there because (a) the port is stable, (b) the link runs
    /// the standard command set, and (c) we avoid sharing the Onboard port with
    /// `mavsdk_server` and tripping local UDP socket conflicts.
    private func px4GcsUdpPort(for session: VehicleSession) -> UInt16? {
        guard let url = URL(string: session.mavlinkConnectionURL),
              let host = url.host, host.contains("0.0.0.0") || host.contains("127.0.0.1") || host.isEmpty || host == "*",
              let port = url.port,
              port >= 14_540
        else { return nil }
        let instance = port - 14_540
        let gcs = 18_570 + instance
        guard gcs <= UInt16.max else { return nil }
        return UInt16(gcs)
    }

    /// Resolve the local UDP endpoint that should accept raw MAVLink injections for
    /// this stack. PX4 uses its dedicated GCS port; ArduPilot SITL uses MAVProxy's
    /// default output port, which is the same ingress port already handed to
    /// mavsdk_server by `SitlLaunchRecipe`.
    private func rawMavlinkUdpPort(for session: VehicleSession, stack: FleetAutopilotStack) -> UInt16? {
        switch stack {
        case .px4:
            return px4GcsUdpPort(for: session)
        case .ardupilot:
            return mavsdkIngressUdpPort(for: session)
        case .unknown:
            return px4GcsUdpPort(for: session) ?? mavsdkIngressUdpPort(for: session)
        }
    }

    private func mavsdkIngressUdpPort(for session: VehicleSession) -> UInt16? {
        guard let url = URL(string: session.mavlinkConnectionURL),
              let host = url.host,
              host.contains("0.0.0.0") || host.contains("127.0.0.1") || host.isEmpty || host == "*",
              let port = url.port,
              port > 0,
              port <= UInt16.max
        else { return nil }
        return UInt16(port)
    }

    /// Resolve `.idle` to the per-stack shell command that drops the autopilot into its
    /// "MANUAL stick passthrough" mode. The vehicle stops moving (zero stick from the
    /// LiveDrive teardown) but remains in a mode that responds instantly to RC / virtual
    /// stick input — Paladin or the operator can grab control again without re-engaging.
    ///
    /// MAVSDK's `Action` plugin has no `setMode(MANUAL)` helper, so this routes via the
    /// `Shell` plugin. PX4 SITL exposes the firmware shell directly; ArduPilot SITL
    /// accepts a small set of `mode <name>` commands through the same plugin (used today
    /// by the `requestSurfaceOrGroundDriveModeIfAvailable` engage path above).
    private func completionForIdleManualMode(
        vehicleID: String,
        session: VehicleSession
    ) -> Completable {
        let stack = vehicleModelsByVehicleID[vehicleID]?.data.telemetry?.autopilotStack
            ?? hubTelemetryByVehicleID[vehicleID]?.autopilotStack
            ?? .unknown
        switch stack {
        case .px4:
            // Raw MAVLink SET_MODE — see `sendPx4SetModeCompletable` for why
            // `Shell.send("commander mode manual")` doesn't actually move PX4
            // out of HOLD on the Onboard link.
            return sendPx4SetModeCompletable(
                vehicleID: vehicleID,
                session: session,
                mainMode: .manual,
                logTag: "idle"
            )
        case .ardupilot:
            return session.drone.shell.send(command: "mode manual")
        case .unknown:
            // No stack info — best effort: ArduPilot first, then PX4 raw MAVLink.
            return session.drone.shell.send(command: "mode manual")
                .catch { _ in
                    self.sendPx4SetModeCompletable(
                        vehicleID: vehicleID,
                        session: session,
                        mainMode: .manual,
                        logTag: "idle.fallback"
                    )
                }
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
            absoluteAltitudeM: targetAbsoluteAlt,
            yawDeg: Self.normalizedDegrees(heading)
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

    // MARK: - GuardianHQTests (mission-run reserve class gate)

    /// Seeds a **live** stream vehicle so `live:` tokens resolve in ``resolvedFleetStreamVehicleID`` without MAVSDK.
    func seedMissionRunTestLiveVehicle(vehicleID: String, vehicleType: FleetVehicleType, systemID: Int = 9) {
        let lifecycle = VehicleLifecycleStatus(stage: .live)
        let model = FleetVehicleModel(
            vehicleID: vehicleID,
            systemID: systemID,
            vehicleType: vehicleType,
            initialStatus: lifecycle
        )
        vehicleModelsByVehicleID[vehicleID] = model
        vehicleIDBySystemID[systemID] = vehicleID
        telemetryByVehicleID[vehicleID] = model.collections.telemetrySnapshot ?? .empty
    }

    /// Seeds a **Guardian SITL** stream + hub stack for Mission Run SIM cleanup / park policy tests (no MAVSDK).
    func seedMissionRunTestSitlCleanupStream(
        vehicleID: String,
        systemID: Int = 1,
        autopilotStack: FleetAutopilotStack = .px4,
        hub: FleetHubVehicleTelemetry? = nil
    ) {
        simulatedFleetVehicleIDs.insert(vehicleID)
        vehicleIDBySystemID[systemID] = vehicleID
        var seeded = hub ?? FleetHubVehicleTelemetry.empty
        if hub == nil || seeded.autopilotStack == .unknown {
            seeded.autopilotStack = autopilotStack
        }
        hubTelemetryByVehicleID[vehicleID] = seeded
    }
}

