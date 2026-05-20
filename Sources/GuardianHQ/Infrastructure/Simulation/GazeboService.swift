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
    /// When set (World Builder / Training), embedded viewport / websocket lines are mirrored for the map debug overlay.
    var embeddedMapLogHandler: ((String) -> Void)?

    private func logEmbeddedMap(_ line: String) {
        embeddedMapLogHandler?(line)
    }

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
        let footprintHeightM: Double
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

    /// Rebakes `world.sdf` + obstacle meshes from `manifest.json` so Training `.run` loads current obstacles.
    private func refreshTrainingRunWorldSDF(
        package: TrainingEnvironmentPackage,
        worldURL: URL
    ) {
        do {
            try TrainingEnvironmentWorldComposer.writeWorld(
                manifest: package.manifest,
                to: worldURL,
                mode: .trainingRun
            )
        } catch {
            fleetLink?.appendSimulationLog(
                "Gazebo: could not refresh training world for \(package.manifest.displayName) — \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            )
        }
    }

    /// Rewrites on-disk `world.sdf` when an older package still used the shared `guardian_open_field` name.
    private func migrateWorldSDFWorldNameIfNeeded(
        package: TrainingEnvironmentPackage,
        worldURL: URL,
        purpose: GazeboSessionPurpose
    ) {
        let expected = TrainingEnvironmentWorldSDF.worldName(environmentID: package.id)
        guard TrainingEnvironmentWorldSDF.parseWorldName(from: worldURL) != expected else { return }
        let mode: TrainingEnvironmentWorldCompositionMode = purpose == .run ? .trainingRun : .builderSession
        do {
            try TrainingEnvironmentWorldComposer.writeWorld(
                manifest: package.manifest,
                to: worldURL,
                mode: mode
            )
            fleetLink?.appendSimulationLog(
                "Gazebo: updated world name to \(expected) for \(package.manifest.displayName)."
            )
        } catch {
            fleetLink?.appendSimulationLog(
                "Gazebo: could not refresh world.sdf for \(package.manifest.displayName) — \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            )
        }
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
        guard abs(sideM - expected) < 0.001 else { return false }
        let requestedWorldName = TrainingEnvironmentWorldSDF.parseWorldName(from: URL(fileURLWithPath: worldPath))
        guard let requestedWorldName else { return false }
        return requestedWorldName == existing.gazeboSDFWorldName
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
        let footprintHeightM = footprint.metres().heightM
        let modelBase = GazeboVehicleModelSDFWriter.sanitizeModelName("guardian_veh_sysid_\(mavlinkSystemID)")
        await removeOrphanVehicleModelFromWorld(
            worldName: row.gazeboSDFWorldName,
            instanceIndex: row.instanceIndex,
            modelName: modelBase
        )

        do {
            let written = try GazeboVehicleModelSDFWriter.writeTemporaryModel(
                modelName: modelBase,
                params: params,
                footprint: footprint
            )
            try await spawnVehicleProxyModelWithRetry(
                worldName: row.gazeboSDFWorldName,
                instanceIndex: row.instanceIndex,
                written: written,
                params: params,
                footprintHeightM: footprintHeightM
            )
            vehicleVisualsBySystemID[mavlinkSystemID] = GazeboSpawnedVehicleVisual(
                worldID: worldID,
                worldName: row.gazeboSDFWorldName,
                instanceIndex: row.instanceIndex,
                modelName: written.modelName,
                mavlinkSystemID: mavlinkSystemID,
                footprintHeightM: footprintHeightM
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

    /// Moves a spawned training proxy to match live hub pose (ENU in the active `.run` world).
    @discardableResult
    func updateVehicleProxyPose(
        mavlinkSystemID: Int,
        pose: TrainingEnvironmentPose
    ) async -> Bool {
        guard let visual = vehicleVisualsBySystemID[mavlinkSystemID] else { return false }
        guard worlds.first(where: { $0.id == visual.worldID && $0.isAlive }) != nil else {
            return false
        }
        return await GazeboEntityFactoryClient.setModelPose(
            worldName: visual.worldName,
            instanceIndex: visual.instanceIndex,
            modelName: visual.modelName,
            pose: pose,
            footprintHeightM: visual.footprintHeightM
        )
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

    /// Drops a leftover proxy model in gz (registry miss after a prior failed or partial spawn).
    private func removeOrphanVehicleModelFromWorld(
        worldName: String,
        instanceIndex: Int,
        modelName: String
    ) async {
        let live = await GazeboEntityFactoryClient.listWorldModelNames(instanceIndex: instanceIndex)
        guard live.contains(modelName) else { return }
        _ = await GazeboEntityFactoryClient.removeModel(
            worldName: worldName,
            instanceIndex: instanceIndex,
            gazeboModelName: modelName
        )
        fleetLink?.appendSimulationLog("Gazebo: cleared orphan vehicle model \(modelName) before respawn.")
    }

    private func spawnVehicleProxyModelWithRetry(
        worldName: String,
        instanceIndex: Int,
        written: GazeboVehicleModelSDFWriter.WrittenModel,
        params: GazeboVehicleSpawnParams,
        footprintHeightM: Double
    ) async throws {
        var lastError: Error?
        for attempt in 1...2 {
            if attempt > 1 {
                await removeOrphanVehicleModelFromWorld(
                    worldName: worldName,
                    instanceIndex: instanceIndex,
                    modelName: written.modelName
                )
            }
            do {
                try await GazeboEntityFactoryClient.createModel(
                    worldName: worldName,
                    instanceIndex: instanceIndex,
                    sdfURL: written.sdfURL,
                    modelName: written.modelName,
                    pose: params.pose,
                    footprintHeightM: footprintHeightM,
                    modelAppearWaitMS: GazeboEntityFactoryClient.vehicleProxyModelAppearWaitMS
                )
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? GazeboEntityFactoryError.serviceFailed("Vehicle proxy spawn failed.")
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
            if GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: purpose) {
                logEmbeddedMap("spawn blocked — Gazebo runtime not found (run make gazebo-runtime)")
            }
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
            if GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: purpose) {
                logEmbeddedMap("spawn blocked — world.sdf not found")
            }
            return nil
        }

        if let pkg = resolvedPackage {
            migrateWorldSDFWorldNameIfNeeded(package: pkg, worldURL: world, purpose: purpose)
            if purpose == .run {
                refreshTrainingRunWorldSDF(package: pkg, worldURL: world)
            }
        }

        let resolvedFloorSizeLabel = resolvedPackage?.manifest.floorSize ?? floorSizeLabel

        if GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: purpose) {
            GuardianGazeboOrphanBlitz.suppressDuringEmbeddedMapHandoff()
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
            ?? resolvedPackage.map { TrainingEnvironmentWorldSDF.worldName(environmentID: $0.id) }
            ?? TrainingEnvironmentWorldSDF.worldName(environmentID: environmentID ?? "world")

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
            if GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: purpose) {
                self?.logEmbeddedMap("sim: \(line)")
            }
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
            logEmbeddedMap(
                "gz sim started — world \"\(envLabel)\" path \(spec.worldPath) instance \(instance) sdf \"\(sdfWorldName)\""
            )
        }

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
            logEmbeddedMap("websocket bridge ended — \(detail)")
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
            logEmbeddedMap("sim world exited (code \(exitCode)); embedded viewport cleared")
        } else if GazeboSessionLaunchPolicy.usesEmbeddedWebViewport(for: worlds[idx].purpose) {
            logEmbeddedMap("sim world exited (code \(exitCode))")
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
        logEmbeddedMap("embedded viewport starting — port \(port), sdf world \"\(gazeboWorldName)\"")

        guard GazeboLocator.isWebsocketServerPluginAvailable else {
            let message = GazeboLocator.websocketServerPluginInstallHint
            failEmbeddedViewport(worldID: worldID, port: port, gazeboWorldName: gazeboWorldName, message: message)
            fleetLink?.appendSimulationLog("Gazebo: websocket plugin not found — \(message)")
            logEmbeddedMap("websocket plugin missing — \(message)")
            return
        }

        do {
            let launchURL = try GazeboLaunchRecipe.writeWebsocketLaunchFile(port: port, instanceIndex: instanceIndex)
            guard await waitForSimScenePublishing(
                worldID: worldID,
                gazeboWorldName: gazeboWorldName,
                instanceIndex: instanceIndex,
                timeout: 25
            ) else {
                let row = worlds.first(where: { $0.id == worldID })
                let message: String
                if row?.isAlive == false {
                    let code = row?.lastExitCode ?? -1
                    message =
                        "Gazebo simulator exited before the map finished loading (code \(code)). "
                        + "Use Stop Gazebo, wait a moment, then open the world again."
                } else {
                    message =
                        "Simulator did not publish scene information for \"\(gazeboWorldName)\". "
                        + "Confirm SceneBroadcaster is in world.sdf and retry after Stop Gazebo."
                }
                failEmbeddedViewport(
                    worldID: worldID,
                    port: port,
                    gazeboWorldName: gazeboWorldName,
                    message: message
                )
                fleetLink?.appendSimulationLog("Gazebo: \(message)")
                logEmbeddedMap("embedded viewport failed — sim scene not published")
                return
            }
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
            logEmbeddedMap("websocket bridge failed — \(message)")
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
            logTracker.resetForRetry()
            let wsRunner = GazeboProcessRunner()
            wsRunner.onLogLine = { [weak self] line in
                logTracker.consume(line)
                self?.fleetLink?.appendSimulationLog("Gazebo WS: \(line)")
                self?.logEmbeddedMap("WS: \(line)")
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
                timeout: 15
            )

            guard listening, wsRunner.isRunning, !logTracker.serverBindFailed else {
                lastFailure = logTracker.serverBindFailed
                    ? "Websocket server could not bind port \(port) (often a stale gz-launch). Use Stop Gazebo and try again."
                    : "Websocket bridge exited before listening on port \(port)."
                stopWebsocketBridge(worldID: worldID)
                continue
            }

            let sceneReady = await waitForEmbeddedSceneHandshake(
                gazeboWorldName: gazeboWorldName,
                instanceIndex: instanceIndex,
                wsRunner: wsRunner,
                logTracker: logTracker,
                timeout: 22
            )

            guard sceneReady, wsRunner.isRunning, !logTracker.sceneInfoQueryFailed else {
                lastFailure = logTracker.sceneInfoQueryFailed
                    ? "Websocket bridge could not read scene information from the simulator (transport or world name mismatch)."
                    : "Scene information was not available on gz-transport before loading the map."
                logEmbeddedMap(
                    "scene handshake failed — \(lastFailure) (topic \(GazeboTransportSceneReadiness.sceneInfoTopicPath(worldName: gazeboWorldName)))"
                )
                stopWebsocketBridge(worldID: worldID)
                continue
            }

            patchRunningWorldWebsocketPort(worldID: worldID, port: port)
            embeddedViewport = GazeboEmbeddedViewportState(
                worldID: worldID,
                websocketPort: port,
                gazeboWorldName: gazeboWorldName,
                phase: .live
            )
            fleetLink?.appendSimulationLog("Gazebo: websocket bridge listening on port \(port).")
            logEmbeddedMap("embedded viewport live — port \(port), sdf world \"\(gazeboWorldName)\"")
            GuardianGazeboOrphanBlitz.suppressFor(seconds: 8)
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
        logEmbeddedMap("embedded viewport failed — \(message)")
    }

    private func stopWebsocketBridge(worldID: UUID) {
        websocketRunners[worldID]?.stop()
        websocketRunners[worldID] = nil
        if embeddedViewport?.worldID == worldID {
            embeddedViewport = nil
        }
    }

    /// `nil` = still running; non-`nil` = sim row marked dead (exit code, or -1 if unknown).
    private func embeddedSimExitCodeIfTerminated(worldID: UUID) -> Int32? {
        if runners[worldID]?.isRunning == true { return nil }
        guard let row = worlds.first(where: { $0.id == worldID }) else { return -1 }
        if row.isAlive {
            if Date().timeIntervalSince(row.startedAt) < 2.5 { return nil }
            return -1
        }
        return row.lastExitCode ?? -1
    }

    /// Waits for sim scene publish (sim log primary; optional `gz topic -i` cross-check). Does not start websocket until confirmed.
    private func waitForSimScenePublishing(
        worldID: UUID,
        gazeboWorldName: String,
        instanceIndex: Int,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let exitCode = embeddedSimExitCodeIfTerminated(worldID: worldID) {
                logEmbeddedMap("scene publish wait aborted — gz sim exited (code \(exitCode))")
                return false
            }

            if simSceneTrackers[worldID]?.scenePublishing == true {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if await GazeboTransportSceneReadiness.sceneInfoTopicHasPublisher(
                    worldName: gazeboWorldName,
                    instanceIndex: instanceIndex
                ) {
                    logEmbeddedMap("scene publish confirmed — sim log + topic publishers")
                } else {
                    logEmbeddedMap("scene publish confirmed — sim log (topic -i skipped or unavailable)")
                }
                return true
            }

            if await GazeboTransportSceneReadiness.sceneInfoTopicHasPublisher(
                worldName: gazeboWorldName,
                instanceIndex: instanceIndex
            ) {
                logEmbeddedMap("scene publish confirmed — topic publishers (ahead of sim log)")
                return true
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        if simSceneTrackers[worldID]?.scenePublishing == true,
           runners[worldID]?.isRunning == true {
            logEmbeddedMap("scene publish confirmed — sim log after wait deadline")
            return true
        }

        fleetLink?.appendSimulationLog(
            "Gazebo: scene publish not confirmed for \"\(gazeboWorldName)\" before websocket bridge."
        )
        logEmbeddedMap("scene publish not confirmed — websocket bridge will not start")
        return false
    }

    /// After the websocket port is listening, confirm scene info is reachable and no scene query errors appeared.
    private func waitForEmbeddedSceneHandshake(
        gazeboWorldName: String,
        instanceIndex: Int,
        wsRunner: GazeboProcessRunner,
        logTracker: GazeboWebsocketBridgeLogTracker,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastProbeLog = Date.distantPast

        while Date() < deadline {
            if logTracker.sceneInfoQueryFailed || !wsRunner.isRunning {
                return false
            }

            if await GazeboTransportSceneReadiness.sceneInfoTopicHasPublisher(
                worldName: gazeboWorldName,
                instanceIndex: instanceIndex
            ) {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if logTracker.sceneInfoQueryFailed || !wsRunner.isRunning {
                    return false
                }
                logEmbeddedMap("embedded scene handshake ok — topic publishers after websocket listen")
                return true
            }

            if Date().timeIntervalSince(lastProbeLog) >= 2.5 {
                lastProbeLog = Date()
                logEmbeddedMap(
                    "waiting for scene publishers on \(GazeboTransportSceneReadiness.sceneInfoTopicPath(worldName: gazeboWorldName))…"
                )
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        guard !logTracker.sceneInfoQueryFailed, wsRunner.isRunning else { return false }
        return await GazeboTransportSceneReadiness.sceneInfoTopicHasPublisher(
            worldName: gazeboWorldName,
            instanceIndex: instanceIndex
        )
    }
}
