import Combine
import Foundation

struct GazeboRunningWorld: Identifiable, Equatable {
    let id: UUID
    let purpose: GazeboSessionPurpose
    let environmentID: String?
    let worldPath: String
    let instanceIndex: Int
    let logDirectoryPath: String
    /// `<world name="…">` from the loaded SDF (gzweb scene handshake).
    let gazeboSDFWorldName: String
    /// Set when World Builder uses the embedded web viewport (`gz launch` websocket bridge).
    let websocketPort: Int?
    /// Manifest `floorSize` token (e.g. `micro`) when this session started.
    let floorSizeLabel: String?
    var isAlive: Bool
    var lastExitCode: Int32?
    let startedAt: Date
}

/// Spawns and supervises Gazebo Harmonic (`gz sim`) worlds. Call only from orchestrators (World Builder, Training, Formation) — not at app launch.
@MainActor
final class GazeboService: ObservableObject {
    @Published private(set) var worlds: [GazeboRunningWorld] = []
    @Published private(set) var lastError: String?
    @Published private(set) var embeddedViewport: GazeboEmbeddedViewportState?

    weak var fleetLink: FleetLinkService?

    private var runners: [UUID: GazeboProcessRunner] = [:]
    private var websocketRunners: [UUID: GazeboProcessRunner] = [:]
    private var simSceneTrackers: [UUID: GazeboSimSceneReadinessTracker] = [:]
    private var nextInstanceIndex = 0
    private var vehicleVisualsBySystemID: [Int: GazeboSpawnedVehicleVisual] = [:]

    private struct GazeboSpawnedVehicleVisual: Equatable {
        let worldID: UUID
        let worldName: String
        let instanceIndex: Int
        let modelName: String
        let mavlinkSystemID: Int
    }

    init() {
        GuardianAppQuitCoordinator.shared.noteGazeboServiceCreated(self)
    }

    func attachFleetLink(_ link: FleetLinkService) {
        fleetLink = link
    }

    var runtimeAvailable: Bool {
        GazeboLocator.gzExecutablePath() != nil
    }

    func blockUntilColdLaunchBlitzFinishedIfNeeded() {
        GuardianGazeboOrphanBlitz.blockUntilColdLaunchBlitzFinishedIfNeeded()
    }

    func worlds(withPurpose purpose: GazeboSessionPurpose) -> [GazeboRunningWorld] {
        worlds.filter { $0.purpose == purpose && $0.isAlive }
    }

    /// True when the embedded gzweb viewport for this world is connected and ready (not starting or failed).
    func isEmbeddedViewportLive(worldID: UUID?) -> Bool {
        guard let worldID, let viewport = embeddedViewport, viewport.worldID == worldID else { return false }
        if case .live = viewport.phase { return true }
        return false
    }

    func isWorldAlive(id: UUID) -> Bool {
        worlds.first(where: { $0.id == id })?.isAlive == true
    }

    func firstAliveRunWorldID() -> UUID? {
        worlds.first(where: { $0.isAlive && $0.purpose == .run })?.id
    }

    /// Alive World Builder preview session for the same catalogue id or on-disk world path.
    func firstAliveBuilderWorldID(environmentID: String?, worldFilePath: String) -> UUID? {
        let normalizedPath = Self.normalizedWorldFilePath(worldFilePath)
        return worlds.first { row in
            guard row.isAlive, row.purpose == .preview || row.purpose == .build else { return false }
            if let environmentID, let rowEnv = row.environmentID, rowEnv == environmentID {
                return true
            }
            return Self.normalizedWorldFilePath(row.worldPath) == normalizedPath
        }?.id
    }

    private static func normalizedWorldFilePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// Reuse an embedded gzweb session only when path, environment, and manifest `floorSize` match.
    static func canReuseEmbeddedWorld(
        existing: GazeboRunningWorld,
        worldPath: String,
        environmentID: String?,
        floorSizeLabel: String?
    ) -> Bool {
        guard existing.isAlive else { return false }
        if normalizedWorldFilePath(existing.worldPath) != normalizedWorldFilePath(worldPath) {
            return false
        }
        if let environmentID, let rowEnv = existing.environmentID, rowEnv != environmentID {
            return false
        }
        let requested = floorSizeLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let loaded = existing.floorSizeLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !requested.isEmpty, requested == loaded else { return false }
        guard let sideM = TrainingEnvironmentWorldSDF.parseOpenFieldFloorSideM(from: URL(fileURLWithPath: worldPath)) else {
            return false
        }
        let expected = TrainingEnvironmentFloorSize.resolved(from: requested).floorSideM
        return abs(sideM - expected) < 0.001
    }

    /// Inserts a class-coloured box (or optional custom mesh) for one built-in SITL into a **``.run``** world
    /// (Training / Formation). World Builder sessions do not call this — they author terrain/obstacles/zones only.
    @discardableResult
    func spawnVehicleProxy(
        worldID: UUID,
        mavlinkSystemID: Int,
        params: GazeboVehicleSpawnParams
    ) async -> Bool {
        guard let row = worlds.first(where: { $0.id == worldID && $0.isAlive }) else {
            lastError = "Gazebo world is not running."
            fleetLink?.appendSimulationLog("Gazebo: vehicle proxy skipped — world is not running.")
            return false
        }
        if vehicleVisualsBySystemID[mavlinkSystemID] != nil {
            await removeVehicleProxy(mavlinkSystemID: mavlinkSystemID)
        }

        let footprint = VehicleClassSizeCatalogue.footprint(
            vehicleClass: params.vehicleClass,
            tier: params.vehicleSizeTier
        )
        let modelBase = GazeboVehicleModelSDFWriter.sanitizeModelName("guardian_veh_sysid_\(mavlinkSystemID)")

        do {
            let written = try GazeboVehicleModelSDFWriter.writeTemporaryModel(
                modelName: modelBase,
                params: params,
                footprint: footprint
            )
            try await GazeboEntityFactoryClient.createModel(
                worldName: row.gazeboSDFWorldName,
                instanceIndex: row.instanceIndex,
                sdfURL: written.sdfURL,
                modelName: written.modelName,
                pose: params.pose,
                footprintHeightM: footprint.metres().heightM
            )
            vehicleVisualsBySystemID[mavlinkSystemID] = GazeboSpawnedVehicleVisual(
                worldID: worldID,
                worldName: row.gazeboSDFWorldName,
                instanceIndex: row.instanceIndex,
                modelName: written.modelName,
                mavlinkSystemID: mavlinkSystemID
            )
            let kind = written.usesCustomMesh ? "mesh" : "box"
            fleetLink?.appendSimulationLog(
                "Gazebo: vehicle \(kind) \(written.modelName) — \(params.vehicleClass.classCode) \(params.vehicleSizeTier.displayName) (\(footprint.dimensionsLabelCm))."
            )
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = message
            fleetLink?.appendSimulationLog("Gazebo: vehicle proxy spawn failed — \(message)")
            return false
        }
    }

    func removeVehicleProxy(mavlinkSystemID: Int) async {
        guard let visual = vehicleVisualsBySystemID.removeValue(forKey: mavlinkSystemID) else { return }
        await GazeboEntityFactoryClient.removeModel(
            worldName: visual.worldName,
            instanceIndex: visual.instanceIndex,
            gazeboModelName: visual.modelName
        )
        fleetLink?.appendSimulationLog("Gazebo: removed vehicle proxy \(visual.modelName).")
    }

    /// Starts `gz sim` for a world file or catalogue package.
    @discardableResult
    func spawnWorld(
        purpose: GazeboSessionPurpose,
        worldURL: URL? = nil,
        environmentID: String? = nil,
        package: TrainingEnvironmentPackage? = nil,
        floorSizeLabel: String? = nil
    ) async -> UUID? {
        blockUntilColdLaunchBlitzFinishedIfNeeded()

        if GazeboSessionLaunchPolicy.requiresSimulateEnabled(for: purpose),
           fleetLink?.isSimulateEnabled != true {
            lastError = "Turn on Simulate in the top bar before starting a training world."
            fleetLink?.appendSimulationLog("Gazebo (\(GazeboSessionLaunchPolicy.logLabel(for: purpose))): blocked — Simulate is off.")
            return nil
        }

        guard runtimeAvailable else {
            lastError = GazeboError.missingRuntime.errorDescription
            fleetLink?.appendSimulationLog("Gazebo: runtime not found (run make gazebo-runtime).")
            return nil
        }

        let resolvedPackage = package ?? environmentID.flatMap { TrainingEnvironmentCatalogue.package(id: $0) }
        let requestedEnvironmentID = resolvedPackage?.id ?? environmentID

        let resolvedWorld: URL?
        if let pkg = resolvedPackage {
            resolvedWorld = pkg.worldFileURL()
        } else {
            resolvedWorld = worldURL ?? GazeboLocator.bundledEmptyWorldURL()
        }

        guard let world = resolvedWorld else {
            lastError = GazeboError.missingWorldFile("world.sdf").errorDescription
            return nil
        }

        let resolvedFloorSizeLabel = resolvedPackage?.manifest.floorSize ?? floorSizeLabel

        if GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: purpose) {
            if let existingID = firstAliveRunWorldID(),
               isEmbeddedViewportLive(worldID: existingID),
               let existing = worlds.first(where: { $0.id == existingID }) {
                if Self.canReuseEmbeddedWorld(
                    existing: existing,
                    worldPath: world.path,
                    environmentID: requestedEnvironmentID,
                    floorSizeLabel: resolvedFloorSizeLabel
                ) {
                    return existingID
                }
            }
            if purpose == .preview || purpose == .build {
                let builderPath = Self.normalizedWorldFilePath(world.path)
                if let existingID = firstAliveBuilderWorldID(
                    environmentID: requestedEnvironmentID,
                    worldFilePath: builderPath
                ),
                   let existing = worlds.first(where: { $0.id == existingID }) {
                    if Self.canReuseEmbeddedWorld(
                        existing: existing,
                        worldPath: world.path,
                        environmentID: requestedEnvironmentID,
                        floorSizeLabel: resolvedFloorSizeLabel
                    ) {
                        if !isEmbeddedViewportLive(worldID: existingID) {
                            await startEmbeddedWebBridge(
                                worldID: existingID,
                                instanceIndex: existing.instanceIndex,
                                gazeboWorldName: existing.gazeboSDFWorldName
                            )
                        }
                        return existingID
                    }
                }
            }
            await stopEmbeddedViewportWorlds()
        }

        let aliveCount = worlds.filter(\.isAlive).count
        if aliveCount >= GazeboConcurrency.maxConcurrentWorlds {
            lastError = "At most \(GazeboConcurrency.maxConcurrentWorlds) Gazebo world(s) can run at once on this machine."
            fleetLink?.appendSimulationLog("Gazebo: concurrent world cap reached (\(GazeboConcurrency.maxConcurrentWorlds)).")
            return nil
        }

        let instance: Int
        if GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: purpose) {
            instance = 0
        } else {
            instance = nextInstanceIndex
            nextInstanceIndex += 1
        }
        let headless = GazeboSessionLaunchPolicy.headless(for: purpose)
        let sdfWorldName = TrainingEnvironmentWorldSDF.parseWorldName(from: world)
            ?? TrainingEnvironmentWorldSDF.defaultWorldName

        let spec: GazeboProcessSpec
        do {
            spec = try GazeboLaunchRecipe.simSpec(
                worldURL: world,
                instanceIndex: instance,
                headless: headless,
                purpose: purpose
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = message
            fleetLink?.appendSimulationLog("Gazebo: launch failed — \(message)")
            return nil
        }

        let id = UUID()
        let runner = GazeboProcessRunner()
        let sceneTracker: GazeboSimSceneReadinessTracker?
        if GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: purpose) {
            let tracker = GazeboSimSceneReadinessTracker()
            simSceneTrackers[id] = tracker
            sceneTracker = tracker
        } else {
            sceneTracker = nil
        }
        runner.onLogLine = { [weak self] line in
            sceneTracker?.consume(line)
            self?.fleetLink?.appendSimulationLog("Gazebo: \(line)")
        }
        runner.onTerminated = { [weak self] code in
            self?.handleTerminated(worldID: id, exitCode: code)
        }

        do {
            try runner.start(spec: spec)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = message
            fleetLink?.appendSimulationLog("Gazebo: start failed — \(message)")
            return nil
        }

        runners[id] = runner
        let envLabel = resolvedPackage?.manifest.displayName ?? environmentID ?? world.lastPathComponent
        let row = GazeboRunningWorld(
            id: id,
            purpose: purpose,
            environmentID: resolvedPackage?.id ?? environmentID,
            worldPath: spec.worldPath,
            instanceIndex: instance,
            logDirectoryPath: spec.logDirectoryURL.path,
            gazeboSDFWorldName: sdfWorldName,
            websocketPort: nil,
            floorSizeLabel: resolvedFloorSizeLabel,
            isAlive: true,
            lastExitCode: nil,
            startedAt: Date()
        )
        worlds.append(row)
        lastError = nil
        fleetLink?.appendSimulationLog(
            "Gazebo (\(GazeboSessionLaunchPolicy.logLabel(for: purpose))): started \(envLabel) (logs: \(spec.logDirectoryURL.path))"
        )

        if GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: purpose) {
            await startEmbeddedWebBridge(worldID: id, instanceIndex: instance, gazeboWorldName: sdfWorldName)
        }

        return id
    }

    /// Stops every alive embedded-viewport sim (World Builder preview/build and Training `.run`) and its websocket bridge.
    func stopAllPreviewAndBuildWorlds() {
        let ids = embeddedViewportWorldIDs()
        var ports: Set<Int> = [GazeboLaunchRecipe.websocketPort(forInstanceIndex: 0)]
        for id in ids {
            guard let row = worlds.first(where: { $0.id == id }) else { continue }
            ports.insert(row.websocketPort ?? GazeboLaunchRecipe.websocketPort(forInstanceIndex: row.instanceIndex))
        }
        for id in ids {
            stopWorld(id: id)
        }
        if let viewportID = embeddedViewport?.worldID, !ids.contains(viewportID) {
            stopWebsocketBridge(worldID: viewportID)
        }
        embeddedViewport = nil
        for port in ports {
            GuardianTcpPortUtilities.terminateListeners(on: port)
        }
        GuardianGazeboOrphanBlitz.kickoffWhenAllWorldsStopped()
    }

    /// Stops embedded gzweb sessions, waits for sim + websocket exit, and reaps stale port listeners.
    func stopAllEmbeddedViewportWorldsCompletely() async {
        let worldIDs = embeddedViewportWorldIDs()
        stopAllPreviewAndBuildWorlds()
        await waitForEmbeddedViewportTeardown(worldIDs: worldIDs)
    }

    /// One embedded sim at a time (shared websocket port + transport partition).
    private func stopEmbeddedViewportWorlds() async {
        await stopAllEmbeddedViewportWorldsCompletely()
    }

    func stopWorld(id: UUID) {
        stopWebsocketBridge(worldID: id)
        runners[id]?.stop()
    }

    func stopAll(purpose: GazeboSessionPurpose? = nil) {
        for row in worlds where row.isAlive {
            if let purpose, row.purpose != purpose { continue }
            stopWorld(id: row.id)
        }
    }

    private func embeddedViewportWorldIDs() -> [UUID] {
        worlds
            .filter { $0.isAlive && GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: $0.purpose) }
            .map(\.id)
    }

    private func waitForEmbeddedViewportTeardown(
        worldIDs: [UUID],
        timeout: TimeInterval = 8
    ) async {
        let ports: Set<Int> = {
            var out: Set<Int> = [GazeboLaunchRecipe.websocketPort(forInstanceIndex: 0)]
            for id in worldIDs {
                guard let row = worlds.first(where: { $0.id == id }) else { continue }
                out.insert(row.websocketPort ?? GazeboLaunchRecipe.websocketPort(forInstanceIndex: row.instanceIndex))
            }
            return out
        }()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let simRunning = worldIDs.contains { runners[$0]?.isRunning == true }
            let wsRunning = worldIDs.contains { websocketRunners[$0]?.isRunning == true }
            if !simRunning, !wsRunning { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        for id in worldIDs {
            _ = await runners[id]?.stopAndWait(timeout: max(0.5, timeout / Double(max(worldIDs.count, 1))))
            _ = await websocketRunners[id]?.stopAndWait(timeout: max(0.5, timeout / Double(max(worldIDs.count, 1))))
            runners[id] = nil
            websocketRunners[id] = nil
        }

        for port in ports {
            GuardianTcpPortUtilities.terminateListeners(on: port)
            _ = await GuardianTcpPortUtilities.waitForTcpPortBindable(port: port, timeout: 2)
        }

        for id in worldIDs {
            if let idx = worlds.firstIndex(where: { $0.id == id }) {
                worlds[idx].isAlive = false
            }
            runners[id] = nil
            websocketRunners[id] = nil
            simSceneTrackers[id] = nil
        }
        embeddedViewport = nil
        GuardianGazeboOrphanBlitz.kickoffWhenAllWorldsStopped()
    }

    func stopAllForApplicationQuit() {
        stopAll()
        GuardianGazeboOrphanBlitz.runBlocking()
    }

    private func handleWebsocketTerminated(worldID: UUID, exitCode: Int32) {
        websocketRunners[worldID] = nil
        guard let idx = worlds.firstIndex(where: { $0.id == worldID }) else { return }
        let port = worlds[idx].websocketPort
            ?? GazeboLaunchRecipe.websocketPort(forInstanceIndex: worlds[idx].instanceIndex)
        if embeddedViewport?.worldID == worldID {
            let detail = exitCode == 0
                ? "Websocket bridge stopped."
                : "Websocket bridge stopped (code \(exitCode))."
            let worldName = worlds[idx].gazeboSDFWorldName
            embeddedViewport = GazeboEmbeddedViewportState(
                worldID: worldID,
                websocketPort: port,
                gazeboWorldName: worldName,
                phase: .failed(detail)
            )
        }
        if exitCode != 0 {
            fleetLink?.appendSimulationLog("Gazebo: websocket bridge exited with code \(exitCode).")
        }
    }

    private func handleTerminated(worldID: UUID, exitCode: Int32) {
        runners[worldID] = nil
        simSceneTrackers[worldID] = nil
        stopWebsocketBridge(worldID: worldID)
        let orphanedSystemIDs = vehicleVisualsBySystemID.filter { $0.value.worldID == worldID }.map(\.key)
        for systemID in orphanedSystemIDs {
            vehicleVisualsBySystemID.removeValue(forKey: systemID)
        }
        guard let idx = worlds.firstIndex(where: { $0.id == worldID }) else { return }
        worlds[idx].isAlive = false
        worlds[idx].lastExitCode = exitCode
        if embeddedViewport?.worldID == worldID {
            embeddedViewport = nil
        }
        if exitCode != 0 {
            fleetLink?.appendSimulationLog("Gazebo: world exited with code \(exitCode).")
        }
        if worlds.allSatisfy({ !$0.isAlive }) {
            GuardianGazeboOrphanBlitz.kickoffWhenAllWorldsStopped()
        }
    }

    private func startEmbeddedWebBridge(worldID: UUID, instanceIndex: Int, gazeboWorldName: String) async {
        let port = GazeboLaunchRecipe.websocketPort(forInstanceIndex: instanceIndex)
        embeddedViewport = GazeboEmbeddedViewportState(
            worldID: worldID,
            websocketPort: port,
            gazeboWorldName: gazeboWorldName,
            phase: .starting
        )

        guard GazeboLocator.isWebsocketServerPluginAvailable else {
            let message = GazeboLocator.websocketServerPluginInstallHint
            failEmbeddedViewport(worldID: worldID, port: port, gazeboWorldName: gazeboWorldName, message: message)
            fleetLink?.appendSimulationLog("Gazebo: websocket plugin not found — \(message)")
            return
        }

        do {
            let launchURL = try GazeboLaunchRecipe.writeWebsocketLaunchFile(port: port, instanceIndex: instanceIndex)
            await waitForSimScenePublishing(worldID: worldID, timeout: 30)
            try await launchEmbeddedWebsocketBridgeWithRetries(
                worldID: worldID,
                instanceIndex: instanceIndex,
                port: port,
                gazeboWorldName: gazeboWorldName,
                launchFileURL: launchURL
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            failEmbeddedViewport(worldID: worldID, port: port, gazeboWorldName: gazeboWorldName, message: message)
            fleetLink?.appendSimulationLog("Gazebo: websocket bridge failed — \(message)")
        }
    }

    private func launchEmbeddedWebsocketBridgeWithRetries(
        worldID: UUID,
        instanceIndex: Int,
        port: Int,
        gazeboWorldName: String,
        launchFileURL: URL
    ) async throws {
        let maxAttempts = 3
        var lastFailure = "Websocket bridge did not start on port \(port)."

        var protectedPIDs = Set<pid_t>()
        if let simPID = runners[worldID]?.processIdentifier {
            protectedPIDs.insert(simPID)
        }

        for attempt in 1...maxAttempts {
            if attempt > 1 {
                stopWebsocketBridge(worldID: worldID)
                fleetLink?.appendSimulationLog(
                    "Gazebo: retrying websocket bridge on port \(port) (attempt \(attempt)/\(maxAttempts))…"
                )
            }

            GuardianTcpPortUtilities.terminateListeners(on: port, excludingPIDs: protectedPIDs)
            let portFree = await GuardianTcpPortUtilities.waitForTcpPortBindable(port: port, timeout: 3)
            if !portFree {
                lastFailure = "Port \(port) is still in use. Stop Gazebo, wait a moment, then preview again."
                GuardianGazeboOrphanBlitz.kickoffWhenAllWorldsStopped()
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            let spec = try GazeboLaunchRecipe.websocketLaunchSpec(
                port: port,
                instanceIndex: instanceIndex,
                launchFileURL: launchFileURL
            )
            let logTracker = GazeboWebsocketBridgeLogTracker()
            let wsRunner = GazeboProcessRunner()
            wsRunner.onLogLine = { [weak self] line in
                logTracker.consume(line)
                self?.fleetLink?.appendSimulationLog("Gazebo WS: \(line)")
            }
            wsRunner.onTerminated = { [weak self] code in
                self?.handleWebsocketTerminated(worldID: worldID, exitCode: code)
            }
            try wsRunner.start(spec: spec)
            websocketRunners[worldID] = wsRunner

            let listening = await waitForWebsocketBridgeReady(
                port: port,
                wsRunner: wsRunner,
                logTracker: logTracker,
                timeout: 12
            )

            guard listening, wsRunner.isRunning, !logTracker.serverBindFailed, !logTracker.sceneInfoQueryFailed else {
                lastFailure = logTracker.serverBindFailed
                    ? "Websocket server could not bind port \(port) (often a stale gz-launch). Use Stop Gazebo and try again."
                    : logTracker.sceneInfoQueryFailed
                    ? "Websocket bridge could not read the scene from the simulator (transport not ready)."
                    : "Websocket bridge exited before listening on port \(port)."
                stopWebsocketBridge(worldID: worldID)
                continue
            }

            try? await Task.sleep(nanoseconds: 800_000_000)

            patchRunningWorldWebsocketPort(worldID: worldID, port: port)
            embeddedViewport = GazeboEmbeddedViewportState(
                worldID: worldID,
                websocketPort: port,
                gazeboWorldName: gazeboWorldName,
                phase: .live
            )
            fleetLink?.appendSimulationLog("Gazebo: websocket bridge listening on port \(port).")
            return
        }

        stopWebsocketBridge(worldID: worldID)
        throw GazeboError.startFailed(lastFailure)
    }

    private func waitForWebsocketBridgeReady(
        port: Int,
        wsRunner: GazeboProcessRunner,
        logTracker: GazeboWebsocketBridgeLogTracker,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let minimumWarmup: TimeInterval = 1.2
        let stableListen: TimeInterval = 2.5
        let started = Date()
        var listenStableSince: Date?

        while Date() < deadline {
            if logTracker.serverBindFailed || logTracker.sceneInfoQueryFailed || !wsRunner.isRunning {
                return false
            }

            let warmedUp = Date().timeIntervalSince(started) >= minimumWarmup
            if warmedUp, GuardianTcpPortUtilities.isTcpPortListening(port: port) {
                if listenStableSince == nil {
                    listenStableSince = Date()
                } else if Date().timeIntervalSince(listenStableSince!) >= stableListen {
                    guard await GuardianTcpPortUtilities.canOpenGazeboWebsocket(port: port, timeout: 3) else {
                        return false
                    }
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    return !logTracker.serverBindFailed
                        && !logTracker.sceneInfoQueryFailed
                        && wsRunner.isRunning
                }
            } else {
                listenStableSince = nil
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private func patchRunningWorldWebsocketPort(worldID: UUID, port: Int) {
        guard let idx = worlds.firstIndex(where: { $0.id == worldID }) else { return }
        let row = worlds[idx]
        worlds[idx] = GazeboRunningWorld(
            id: row.id,
            purpose: row.purpose,
            environmentID: row.environmentID,
            worldPath: row.worldPath,
            instanceIndex: row.instanceIndex,
            logDirectoryPath: row.logDirectoryPath,
            gazeboSDFWorldName: row.gazeboSDFWorldName,
            websocketPort: port,
            floorSizeLabel: row.floorSizeLabel,
            isAlive: row.isAlive,
            lastExitCode: row.lastExitCode,
            startedAt: row.startedAt
        )
    }

    private func failEmbeddedViewport(
        worldID: UUID,
        port: Int,
        gazeboWorldName: String,
        message: String
    ) {
        embeddedViewport = GazeboEmbeddedViewportState(
            worldID: worldID,
            websocketPort: port,
            gazeboWorldName: gazeboWorldName,
            phase: .failed(message)
        )
        lastError = message
    }

    private func stopWebsocketBridge(worldID: UUID) {
        websocketRunners[worldID]?.stop()
        websocketRunners[worldID] = nil
        if embeddedViewport?.worldID == worldID {
            embeddedViewport = nil
        }
    }

    private func waitForSimScenePublishing(worldID: UUID, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if simSceneTrackers[worldID]?.scenePublishing == true {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return
            }
            if runners[worldID]?.isRunning != true {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        fleetLink?.appendSimulationLog(
            "Gazebo: scene publish wait timed out; starting websocket bridge anyway."
        )
    }
}

/// Parses gz-launch websocket plugin stderr for bind / scene handshake failures.
@MainActor
final class GazeboWebsocketBridgeLogTracker {
    private(set) var serverBindFailed = false
    private(set) var sceneInfoQueryFailed = false

    func consume(_ line: String) {
        if line.contains("Unable to create websocket server") {
            serverBindFailed = true
        }
        if line.contains("Failed to get the scene information") {
            sceneInfoQueryFailed = true
        }
    }
}

/// Tracks `gz sim -s` logs until scene topics are published (embedded web viewport).
@MainActor
final class GazeboSimSceneReadinessTracker {
    private(set) var scenePublishing = false

    func consume(_ line: String) {
        if line.contains("Publishing scene information") {
            scenePublishing = true
        }
    }
}
