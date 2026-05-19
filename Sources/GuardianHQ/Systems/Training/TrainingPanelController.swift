import Foundation
import SwiftUI

/// Skill training lab: spawn one SITL, run autonomous open-loop trials, promote winning segment chains.
@MainActor
final class TrainingPanelController: ObservableObject {
    @Published var vehicleClass: TrainingVehicleClass = .ugvWheeled
    @Published var taskKind: TrainingTaskKind = .reverseIntoSlot
    @Published var forbiddenAxes: Set<TrainingControlAxis> = []
    @Published private(set) var phase: TrainingPanelPhase = .idle
    @Published private(set) var isBusy = false
    @Published private(set) var statusText = "Choose a vehicle class and task, then spawn a simulator."
    @Published private(set) var logLines: [TrainingPanelLogLine] = []
    @Published private(set) var promotedSkill: TrainedVehicleSkill?
    /// When true, a successful promote writes a new catalogue revision under Application Support (no save panel).
    @AppStorage("GuardianTraining.autoExportBrainOnPromote") var autoExportBrainOnPromote = false
    /// Last successful brain pack export for the current promoted skill (`brain_id` for revision exports).
    @Published private(set) var lastExportedBrainId: UUID?
    @Published private(set) var lastExportedBrainVersion: GuardianBrainVersion?
    @Published private(set) var trialsCompleted = 0
    @Published private(set) var trialsTotal = 0
    @Published private(set) var simulatorSlot: FormationsPlaygroundSlotState?
    @Published private(set) var vehicleID: String?
    @Published private(set) var sitlSessionID: UUID?
    /// True only during stop/spawn shell work — not during link wait or preflight.
    var cardActionsLocked: Bool { isBusy }
    @Published private(set) var taskLayout: TrainingTaskLayout?
    /// Planned A→B path for map overlay (Nav2 or geodesic fallback from ROS 2 bridge).
    @Published private(set) var nav2PlannedPath: [RouteCoordinate] = []
    @Published private(set) var nav2PlanPathSource: TrainingNav2PlanPathResponse.Source = .unavailable
    /// Operator-placed target slot on the map (independent of task kind).
    @Published var targetSlot: TrainingTaskPose = TrainingTaskLayoutFactory.defaultTargetSlot(spawn: .default)
    @Published var isTargetSlotMapEditEnabled = false
    @Published private(set) var availableEnvironments: [TrainingEnvironmentPackage] = []
    @Published var selectedEnvironmentID: String = TrainingEnvironmentManifest.defaultBundledID
    @Published private(set) var activeGazeboWorldID: UUID?
    @Published private(set) var gazeboWorldStatusText: String?

    private weak var fleetLink: FleetLinkService?
    private weak var sitl: SitlService?
    private weak var gazebo: GazeboService?
    private weak var toastCenter: ToastCenter?
    private var requiresGazeboRunWorld = false
    private var spawnDefaults: SimSpawnDefaults = .default
    private var simulationPlatform: SimulationPlatform = .ardupilot
    private var teachTask: Task<Void, Never>?
    private var nav2PlanTask: Task<Void, Never>?

    private static let linkWaitTimeoutS: TimeInterval = 60
    private static let preflightSource = "training.panel.preflight"
    private static let resetSource = "training.panel.reset"
    private static let maxLogLines = 200
    private static let maxTeachingTrials = 48

    func attach(
        fleetLink: FleetLinkService,
        sitl: SitlService,
        spawnDefaults: SimSpawnDefaults,
        simulationPlatform: SimulationPlatform,
        gazebo: GazeboService? = nil,
        requiresGazeboRunWorld: Bool = false,
        toastCenter: ToastCenter? = nil
    ) {
        self.fleetLink = fleetLink
        self.sitl = sitl
        self.gazebo = gazebo
        self.toastCenter = toastCenter
        self.requiresGazeboRunWorld = requiresGazeboRunWorld
        self.spawnDefaults = spawnDefaults
        clampVehicleClassToTrainingPanelOptions()
        self.simulationPlatform = SimulationSpawnPolicy.effectivePlatform(
            for: vehicleClass.simulationPreset,
            requested: simulationPlatform
        )
        restoreTargetSlotFromPersistence()
        reloadEnvironmentCatalogue()
        restoreEnvironmentSelectionFromPersistence()
        refreshTaskLayout()
    }

    var selectedEnvironment: TrainingEnvironmentPackage? {
        availableEnvironments.first { $0.id == selectedEnvironmentID }
            ?? TrainingEnvironmentCatalogue.package(id: selectedEnvironmentID)
    }

    func reloadEnvironmentCatalogue() {
        availableEnvironments = TrainingEnvironmentCatalogue.loadAll()
        if !availableEnvironments.contains(where: { $0.id == selectedEnvironmentID }),
           let first = availableEnvironments.first {
            selectedEnvironmentID = first.id
        }
    }

    func restoreEnvironmentSelectionFromPersistence() {
        if let saved = try? TrainingEnvironmentSelectionStore.selectedEnvironmentID(
            task: taskKind,
            vehicleClass: vehicleClass
        ), TrainingEnvironmentCatalogue.package(id: saved) != nil {
            selectedEnvironmentID = saved
            return
        }
        if availableEnvironments.contains(where: { $0.id == TrainingEnvironmentManifest.defaultBundledID }) {
            selectedEnvironmentID = TrainingEnvironmentManifest.defaultBundledID
        } else if let first = availableEnvironments.first {
            selectedEnvironmentID = first.id
        }
    }

    func persistEnvironmentSelection() {
        try? TrainingEnvironmentSelectionStore.setSelectedEnvironmentID(
            selectedEnvironmentID,
            task: taskKind,
            vehicleClass: vehicleClass
        )
    }

    func environmentSelectionDidChange() {
        persistEnvironmentSelection()
        restoreTargetSlotForSelectedEnvironment()
        refreshTaskLayout()
    }

    func trainingTaskOrVehicleDidChange() {
        restoreEnvironmentSelectionFromPersistence()
    }

    /// Load last saved target slot for the selected environment, or seed from manifest / spawn defaults.
    func restoreTargetSlotFromPersistence() {
        restoreTargetSlotForSelectedEnvironment()
    }

    private func restoreTargetSlotForSelectedEnvironment() {
        let envID = selectedEnvironmentID
        if let saved = try? TrainingTargetSlotStore.load(environmentID: envID) {
            targetSlot = saved
            return
        }
        if let pkg = selectedEnvironment {
            targetSlot = TrainingEnvironmentGeodesy.taskPose(
                environmentPose: pkg.manifest.defaultGoal,
                origin: spawnDefaults
            )
        } else {
            targetSlot = TrainingTaskLayoutFactory.defaultTargetSlot(spawn: spawnDefaults)
        }
        persistTargetSlot()
    }

    func spawnDefaultsDidChange() {
        refreshTaskLayout()
    }

    /// Keeps persisted or legacy values on the temporary UGV-only Training Vehicle panel list.
    func clampVehicleClassToTrainingPanelOptions() {
        guard !TrainingVehicleClass.trainingPanelSelectableCases.contains(vehicleClass) else { return }
        vehicleClass = .ugvWheeled
    }

    /// Leaving the Training tab: stop streamed control only (SITL stays in Vehicles).
    func leavePanel() {
        teachTask?.cancel()
        teachTask = nil
        if phase != .teaching {
            isBusy = false
        }
        persistTargetSlot()
        if let vehicleID, let fleetLink {
            Task { await fleetLink.stopTrainingControlStream(vehicleID: vehicleID) }
        }
        if simulatorSlot != nil {
            statusText = "Simulator remains in Vehicles. Run teaching when you return."
        }
    }

    private func persistTargetSlot() {
        try? TrainingTargetSlotStore.save(targetSlot, environmentID: selectedEnvironmentID)
    }

    func syncFromFleetOnAppear(fleetLink: FleetLinkService) {
        reloadEnvironmentCatalogue()
        syncTrainingSimulatorFromRunningSitl(fleetLink: fleetLink)
        refreshSimulatorSlot(fleetLink: fleetLink)
        loadPromotedSkill()
        if simulatorSlot == nil {
            statusText = "Choose a vehicle class and task, then spawn a simulator."
        } else if phase != .teaching {
            let linked = simulatorSlot?.linkReady == true
            let preflight = simulatorSlot?.preflightPassed == true
            statusText = preflight
                ? "Simulator ready in Vehicles. Run autonomous teaching or rerun the task."
                : linked
                    ? "Simulator linked — run preflight or retry from the sim card."
                    : "Simulator in Vehicles — waiting for link or preflight."
        }
    }

    /// Reconcile with a running SITL after returning to Training (session id persisted on spawn).
    func syncTrainingSimulatorFromRunningSitl(fleetLink: FleetLinkService) {
        guard let sitl else { return }

        if let tracked = simulatorSlot?.sitlSessionID,
           let inst = trainingOwnedInstance(id: tracked, sitl: sitl) {
            adoptRunningSimulator(inst, fleetLink: fleetLink, preservePreflightFrom: simulatorSlot)
            return
        }

        if let saved = try? TrainingSimulatorSessionStore.load()?.sitlSessionID,
           let inst = trainingOwnedInstance(id: saved, sitl: sitl) {
            adoptRunningSimulator(inst, fleetLink: fleetLink, preservePreflightFrom: simulatorSlot)
            return
        }

        if simulatorSlot != nil || sitlSessionID != nil {
            clearSimulatorTracking()
        } else {
            try? TrainingSimulatorSessionStore.clear()
        }
    }

    /// Updates link/vehicle id from fleet hub (in-place, same pattern as formation ``refreshSlotRows``).
    func refreshSimulatorSlot(fleetLink: FleetLinkService) {
        guard let sitl, var slot = simulatorSlot else { return }
        let sessionID = slot.sitlSessionID
        guard let row = sitl.instances.first(where: {
            $0.id == sessionID && $0.spawnOwner == .trainingVehicle
        }) else {
            if slot.linkReady || slot.vehicleID != nil {
                slot.linkReady = false
                slot.vehicleID = nil
                applySlot(slot)
            }
            return
        }
        let resolvedVehicleID = resolvedVehicleID(for: row, fleetLink: fleetLink)
        let linkReady = row.isAlive && slotFleetReady(fleetLink: fleetLink, vehicleID: resolvedVehicleID)
        guard slot.vehicleID != resolvedVehicleID || slot.linkReady != linkReady else { return }
        slot.vehicleID = resolvedVehicleID
        slot.linkReady = linkReady
        applySlot(slot)
    }

    func taskKindDidChange() {
        refreshTaskLayout()
    }

    func refreshTaskLayout() {
        if let pkg = selectedEnvironment {
            taskLayout = TrainingGazeboRunOrchestrator.layout(
                environment: pkg,
                targetSlot: targetSlot,
                spawnDefaults: spawnDefaults
            )
        } else {
            let start = TrainingTaskLayoutFactory.startPose(spawn: spawnDefaults)
            taskLayout = Utilities.training.taskLayout(start: start, goal: targetSlot)
        }
        scheduleNav2PlanPathRefresh()
    }

    var usesGazeboTrainingViewport: Bool {
        requiresGazeboRunWorld && gazebo != nil
    }

    /// Re-request Nav2 / geodesic path when layout, vehicle, or ROS bridge changes.
    func scheduleNav2PlanPathRefresh() {
        nav2PlanTask?.cancel()
        nav2PlanTask = Task { [weak self] in
            await self?.refreshNav2PlannedPath()
        }
    }

    /// Debug rail copy for Training path overlay source (Settings → Debug).
    var trainingPathOverlayDebugLine: String {
        switch GuardianAutonomyPlannerRouting.defaultPlannerKind(for: vehicleClass.fleetVehicleType) {
        case .nav2:
            break
        default:
            return "Path overlay: not used for this vehicle class"
        }
        guard let fleetLink else {
            return "Path overlay: none (ROS bridge inactive)"
        }
        if fleetLink.ros2BridgeProcessPhase != .running {
            return "Path overlay: Python fallback (ROS bridge not running — use Training spawn/Replace so this sim is enrolled)"
        }
        let nav2StackReady = fleetLink.nav2TrainingStackReady
        let nav2Status = fleetLink.nav2TrainingStackStatus
        if nav2PlannedPath.count >= 2 {
            return Self.pathOverlayDebugLine(
                source: nav2PlanPathSource,
                nav2StackReady: nav2StackReady,
                nav2StackStatus: nav2Status,
                hasPath: true
            )
        }
        if !nav2StackReady {
            return "Path overlay: none (\(Self.nav2StackStatusPhrase(nav2Status)))"
        }
        return "Path overlay: none"
    }

    /// Operator/debug label for the dashed Training path (Nav2 vs Python geodesic fallback).
    static func pathOverlayDebugLine(
        source: TrainingNav2PlanPathResponse.Source,
        nav2StackReady: Bool,
        nav2StackStatus: String,
        hasPath: Bool
    ) -> String {
        let fallbackStackNote = nav2StackReady ? "" : " — \(nav2StackStatusPhrase(nav2StackStatus))"
        switch source {
        case .nav2:
            return hasPath ? "Path overlay: Nav2" : "Path overlay: none"
        case .geodesicFallback:
            return hasPath
                ? "Path overlay: Python fallback\(fallbackStackNote)"
                : "Path overlay: none\(nav2StackReady ? "" : " (\(nav2StackStatusPhrase(nav2StackStatus)))")"
        case .error:
            return hasPath
                ? "Path overlay: Python fallback (bridge error)\(fallbackStackNote)"
                : "Path overlay: none (bridge error)"
        case .unavailable:
            return nav2StackReady ? "Path overlay: none" : "Path overlay: none (\(nav2StackStatusPhrase(nav2StackStatus)))"
        }
    }

    static func nav2StackStatusPhrase(_ status: String) -> String {
        switch status {
        case "ready":
            return "Nav2 ready"
        case "starting":
            return "Nav2 starting (up to ~2 min)"
        case "restarting":
            return "Nav2 restarting"
        case "timeout":
            return "Nav2 failed — planner service timeout"
        case "unavailable":
            return "Nav2 not in ROS runtime (run make ros2-runtime)"
        case "error":
            return "Nav2 launch error"
        case "stopped":
            return "Nav2 stopped"
        case "inactive":
            return "Nav2 pending (fleet warm-start)"
        default:
            return "Nav2 \(status)"
        }
    }

    private func refreshNav2PlannedPath() async {
        guard !Task.isCancelled else { return }
        guard let layout = taskLayout else {
            nav2PlannedPath = []
            nav2PlanPathSource = .unavailable
            return
        }
        let planner = GuardianAutonomyPlannerRouting.defaultPlannerKind(for: vehicleClass.fleetVehicleType)
        guard planner == .nav2 else {
            nav2PlannedPath = []
            nav2PlanPathSource = .unavailable
            return
        }
        guard let fleetLink, let vehicleID else {
            nav2PlannedPath = []
            nav2PlanPathSource = .unavailable
            return
        }
        let response = await fleetLink.requestTrainingNav2PlanPath(vehicleID: vehicleID, layout: layout)
        guard !Task.isCancelled else { return }
        if response.points.count >= 2 {
            nav2PlannedPath = response.points
            nav2PlanPathSource = response.source
        } else {
            nav2PlannedPath = TrainingGeodesicPathPlanner.plan(start: layout.start, goal: layout.goal)
            nav2PlanPathSource = response.source == .unavailable ? .geodesicFallback : response.source
        }
    }

    func setTargetSlotMapEditEnabled(_ enabled: Bool) {
        guard enabled != isTargetSlotMapEditEnabled else { return }
        isTargetSlotMapEditEnabled = enabled
    }

    /// Leaflet map-edit chrome for the target slot (centroid + heading rim).
    func buildTargetSlotMapEdit() -> GuardianFormationSlotGroupMapEdit? {
        guard isTargetSlotMapEditEnabled else { return nil }
        return GuardianFormationSlotGroupMapEdit(
            centerLat: targetSlot.latitudeDeg,
            centerLon: targetSlot.longitudeDeg,
            headingDeg: targetSlot.headingDeg,
            circleRadiusM: Self.targetSlotMapEditRadiusM
        )
    }

    func moveTargetSlotCenter(latitudeDeg: Double, longitudeDeg: Double) {
        guard isTargetSlotMapEditEnabled else { return }
        targetSlot.latitudeDeg = latitudeDeg
        targetSlot.longitudeDeg = longitudeDeg
        refreshTaskLayout()
        persistTargetSlot()
    }

    func setTargetSlotHeading(headingDeg: Double) {
        guard isTargetSlotMapEditEnabled else { return }
        targetSlot.headingDeg = headingDeg
        refreshTaskLayout()
        persistTargetSlot()
    }

    private static let targetSlotMapEditRadiusM = 6.0

    func loadPromotedSkill() {
        promotedSkill = try? TrainingSkillStore.promoted(task: taskKind, vehicleClass: vehicleClass)
        lastExportedBrainId = nil
        lastExportedBrainVersion = nil
    }

    /// Nav2 / Aerostack2 lab overlay snapshot for brain pack export (ground/surface/aerial classes only).
    func exportPlannerHintsSnapshot() -> GuardianBrainPackPlannerHints? {
        guard let skill = promotedSkill, let layout = taskLayout else { return nil }
        return GuardianBrainPackBuilder.plannerHints(
            from: GuardianBrainPackTrainingPlannerContext(
                vehicleClass: vehicleClass,
                layout: layout,
                segments: skill.segments,
                planPathSource: nav2PlanPathSource,
                nav2StackReady: fleetLink?.nav2TrainingStackReady ?? false,
                nav2StackStatus: fleetLink?.nav2TrainingStackStatus ?? "inactive",
                gazeboEnvironmentId: selectedEnvironmentID,
                planWaypointCount: nav2PlannedPath.count
            )
        )
    }

    /// Writes the promoted skill into the on-disk brain catalogue (Mission import path) without a save panel.
    func autoExportPromotedBrainToCatalogue() {
        guard let skill = promotedSkill else { return }
        do {
            let brainId = lastExportedBrainId ?? skill.id
            let nextVersion = try GuardianBrainCatalogueStore.nextPatchVersion(
                brainId: brainId,
                sessionPeak: lastExportedBrainVersion
            )
            let pack = try GuardianBrainPackBuilder.makePack(
                from: skill,
                brainId: brainId,
                brainVersion: nextVersion,
                displayName: GuardianBrainPackBuilder.defaultDisplayName(for: skill),
                gazeboEnvironmentId: selectedEnvironmentID,
                plannerHints: exportPlannerHintsSnapshot()
            )
            let url = try GuardianBrainCatalogueStore.packFileURL(brainId: brainId, brainVersion: nextVersion)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try GuardianBrainPackCodec.sealedData(for: pack).write(to: url, options: .atomic)
            try GuardianBrainPinDefaultsStore.pin(manifest: pack.manifest)
            lastExportedBrainId = brainId
            lastExportedBrainVersion = nextVersion
            GuardianBrainCatalogueChangeNotification.post(
                displayName: pack.manifest.displayName,
                brainVersion: nextVersion
            )
            appendLog("Auto-exported brain pack \(nextVersion.displayLabel) to catalogue and pinned as default.")
            statusText = "Promoted, exported, and pinned brain \(nextVersion.displayLabel)."
        } catch {
            appendLog("Auto brain export failed: \(error.localizedDescription)")
        }
    }

    /// Export promoted skill as `0.0.1` (subodai line) of a new `brain_id` (defaults to skill id).
    @discardableResult
    func exportPromotedBrainPack(squadProfile: GuardianBrainPackSquadProfile? = nil) -> URL? {
        guard let skill = promotedSkill else { return nil }
        do {
            let brainId = skill.id
            let pack = try GuardianBrainPackBuilder.makePack(
                from: skill,
                brainId: brainId,
                brainVersion: .initial,
                displayName: GuardianBrainPackBuilder.defaultDisplayName(for: skill),
                gazeboEnvironmentId: selectedEnvironmentID,
                plannerHints: exportPlannerHintsSnapshot(),
                squadProfile: squadProfile
            )
            guard let url = GuardianBrainPackExportService.promptSaveToDisk(pack: pack) else { return nil }
            lastExportedBrainId = brainId
            lastExportedBrainVersion = .initial
            appendLog("Exported brain pack \(GuardianBrainVersion.initial.displayLabel) to \(url.lastPathComponent).")
            statusText = "Brain pack exported."
            return url
        } catch {
            appendLog("Brain export failed: \(error.localizedDescription)")
            statusText = "Brain export failed."
            return nil
        }
    }

    /// Export the next **patch** semver for the same `brain_id` as the last export (or skill id).
    @discardableResult
    func exportPromotedBrainPackNewVersion(squadProfile: GuardianBrainPackSquadProfile? = nil) -> URL? {
        guard let skill = promotedSkill else { return nil }
        do {
            let brainId = lastExportedBrainId ?? skill.id
            let nextVersion = try GuardianBrainCatalogueStore.nextPatchVersion(
                brainId: brainId,
                sessionPeak: lastExportedBrainVersion
            )
            let pack = try GuardianBrainPackBuilder.makePack(
                from: skill,
                brainId: brainId,
                brainVersion: nextVersion,
                displayName: GuardianBrainPackBuilder.defaultDisplayName(for: skill),
                gazeboEnvironmentId: selectedEnvironmentID,
                plannerHints: exportPlannerHintsSnapshot(),
                squadProfile: squadProfile
            )
            guard let url = GuardianBrainPackExportService.promptSaveToDisk(pack: pack) else { return nil }
            lastExportedBrainId = brainId
            lastExportedBrainVersion = nextVersion
            appendLog("Exported brain pack \(nextVersion.displayLabel) to \(url.lastPathComponent).")
            statusText = "Brain pack \(nextVersion.displayLabel) exported."
            return url
        } catch {
            appendLog("Brain export failed: \(error.localizedDescription)")
            statusText = "Brain export failed."
            return nil
        }
    }

    func revealLastExportedBrainPack(at url: URL) {
        GuardianBrainPackExportService.revealInFinder(url)
    }

    func canReplaceSlot(_ slot: FormationsPlaygroundSlotState) -> Bool {
        !slot.linkReady || slot.preflightPassed != true
    }

    func shouldOfferSimulatorRetry(slot: FormationsPlaygroundSlotState) -> Bool {
        GuardianSimulatorSlotRecoveryPolicy.shouldOfferRetry(slot: slot)
    }

    func retryButtonTitle(for slot: FormationsPlaygroundSlotState) -> String {
        GuardianSimulatorSlotRecoveryPolicy.formationRetryButtonTitle(
            linkReady: slot.linkReady,
            isConnecting: phase == .connecting || phase == .preflight
        )
    }

    func retrySimulatorConnection(missionControl: MissionControlStore) async {
        guard let fleetLink, let sitl else { return }
        guard var slot = simulatorSlot, let sessionID = sitlSessionID else { return }

        phase = .connecting
        statusText = slot.linkReady ? "Retrying preflight…" : "Reconnecting telemetry…"

        if let vehicleID = slot.vehicleID ?? self.vehicleID {
            await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)
        }

        if !slot.linkReady,
           let inst = trainingOwnedInstance(id: sessionID, sitl: sitl) {
            let reconnected = await bindFleetLinkToTrainingSimulator(
                inst: inst,
                fleetLink: fleetLink,
                sitl: sitl
            )
            if !reconnected {
                slot.preflightPassed = false
                slot.preflightDetail = sitl.lastError ?? "Reconnect failed."
                applySlot(slot)
                statusText = slot.preflightDetail ?? "Reconnect failed."
                phase = .idle
                return
            }
        }

        refreshSimulatorSlot(fleetLink: fleetLink)
        guard let slot = simulatorSlot, let vehicleID = slot.vehicleID ?? self.vehicleID else {
            phase = .idle
            return
        }

        if !slotFleetReady(fleetLink: fleetLink, vehicleID: vehicleID) {
            statusText = "Waiting for live telemetry…"
            guard await waitForLink(fleetLink: fleetLink) else {
                updateSlot {
                    $0.preflightPassed = false
                    $0.preflightDetail = MissionControlStore.preflightProbeNotConnectedDetail
                    $0.linkReady = false
                }
                statusText = "Timed out waiting for telemetry. Try Replace or check SITL logs."
                phase = .idle
                return
            }
        }

        phase = .preflight
        statusText = "Running preflight…"
        let probe = await missionControl.runSingleVehiclePreflightProbe(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl,
            leaveArmed: true,
            allowDuringLiveMission: true,
            preflightAuditSource: Self.preflightSource
        )
        updateSlot {
            $0.preflightPassed = probe.passed
            $0.preflightDetail = probe.detail
            $0.linkReady = true
        }
        phase = .idle
        statusText = probe.passed
            ? "Simulator ready. Run autonomous teaching or rerun the task."
            : "Preflight failed: \(probe.detail)"
    }

    func replaceSimulator(missionControl: MissionControlStore) async {
        guard let fleetLink, let sitl, let old = simulatorSlot else { return }
        guard fleetLink.isSimulateEnabled else {
            statusText = "Turn on Simulate in the top bar before replacing."
            return
        }

        isBusy = true
        phase = .spawning
        guard await startTrainingGazeboRunWorldIfNeeded() else {
            endSpawnShellBusyState()
            phase = .idle
            return
        }
        if let vid = old.vehicleID {
            await fleetLink.stopTrainingControlStream(vehicleID: vid)
        }
        if let oldInst = sitl.instances.first(where: { $0.id == old.sitlSessionID }) {
            fleetLink.unregisterSimulatedVehicle(systemID: oldInst.mavlinkSystemID)
        } else if let vid = old.vehicleID, vid.hasPrefix("sysid:"),
                  let systemID = Int(vid.dropFirst(6)) {
            fleetLink.unregisterSimulatedVehicle(systemID: systemID)
        }
        sitl.stop(id: old.sitlSessionID)
        await sitl.waitForRecentlyReleasedPortsToSettle()

        statusText = "Replacing simulator…"
        let before = Set(sitl.instances.map(\.id))
        sitl.spawn(
            preset: vehicleClass.simulationPreset,
            platform: simulationPlatform,
            defaults: spawnDefaults,
            owner: .trainingVehicle
        )
        guard let row = sitl.instances.first(where: {
            !before.contains($0.id) && $0.spawnOwner == .trainingVehicle
        }) else {
            endSpawnShellBusyState()
            clearSimulatorTracking()
            statusText = sitl.lastError ?? "Could not spawn replacement simulator."
            phase = .idle
            return
        }
        adoptRunningSimulator(row, fleetLink: fleetLink, preservePreflightFrom: nil, freshSpawn: true)
        try? TrainingSimulatorSessionStore.save(row.id)
        endSpawnShellBusyState()
        try? await Task.sleep(nanoseconds: 500_000_000)

        if let inst = trainingSessionInstance(id: row.id, sitl: sitl) {
            _ = await bindFleetLinkToTrainingSimulator(inst: inst, fleetLink: fleetLink, sitl: sitl)
        }
        await finishSpawnLinkAndPreflight(
            missionControl: missionControl,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    func spawnTrainingSim(missionControl: MissionControlStore) async {
        guard let fleetLink, let sitl else { return }
        guard fleetLink.isSimulateEnabled else {
            statusText = "Turn on Simulate in the top bar before spawning."
            return
        }
        teachTask?.cancel()
        teachTask = nil
        clearLogs()
        promotedSkill = nil
        trialsCompleted = 0
        trialsTotal = 0

        isBusy = true
        phase = .spawning
        statusText = "Spawning training simulator…"

        guard await startTrainingGazeboRunWorldIfNeeded() else {
            endSpawnShellBusyState()
            phase = .idle
            return
        }

        await stopPriorTrainingSitlForRespawn()
        let before = Set(sitl.instances.map(\.id))
        sitl.spawn(
            preset: vehicleClass.simulationPreset,
            platform: simulationPlatform,
            defaults: spawnDefaults,
            owner: .trainingVehicle
        )
        guard let row = sitl.instances.first(where: {
            !before.contains($0.id) && $0.spawnOwner == .trainingVehicle
        }) else {
            stopTrainingGazeboRunWorld()
            endSpawnShellBusyState()
            statusText = sitl.lastError ?? "Spawn failed — check SITL logs."
            phase = .idle
            return
        }

        adoptRunningSimulator(row, fleetLink: fleetLink, preservePreflightFrom: nil, freshSpawn: true)
        try? TrainingSimulatorSessionStore.save(row.id)
        endSpawnShellBusyState()
        try? await Task.sleep(nanoseconds: 500_000_000)

        if let inst = trainingSessionInstance(id: row.id, sitl: sitl) {
            _ = await bindFleetLinkToTrainingSimulator(inst: inst, fleetLink: fleetLink, sitl: sitl)
        }
        await finishSpawnLinkAndPreflight(
            missionControl: missionControl,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    func stopSimulator() async {
        teachTask?.cancel()
        teachTask = nil
        isBusy = false
        stopTrainingGazeboRunWorld()
        await stopTrainingStreamAndTrackedSitl()
        statusText = "Spawn a simulator to begin training."
        phase = .idle
    }

    func resetEpisode() async {
        guard let fleetLink, let vehicleID else { return }
        await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)
        await resetToTaskStart(fleetLink: fleetLink)
        statusText = "Reset to task start pose."
    }

    func startAutonomousTeaching() {
        guard let fleetLink, let vehicleID, simulatorSlot?.preflightPassed == true else { return }
        teachTask?.cancel()
        teachTask = Task { [weak self] in
            await self?.runAutonomousTeaching(fleetLink: fleetLink, vehicleID: vehicleID)
        }
    }

    func cancelTeaching() {
        teachTask?.cancel()
        teachTask = nil
        isBusy = false
        if phase == .teaching {
            phase = .idle
            statusText = "Teaching cancelled."
        }
    }

    // MARK: - Spawn helpers

    /// Post-spawn link wait + preflight (SitlService registers MAVSDK on spawn; this waits for live telemetry).
    private func finishSpawnLinkAndPreflight(
        missionControl: MissionControlStore,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) async {
        phase = .connecting
        statusText = "Waiting for fleet link (simulator in Vehicles)…"
        guard vehicleID != nil else {
            statusText = "Simulator not linked."
            phase = .idle
            return
        }
        guard await waitForLink(fleetLink: fleetLink) else {
            statusText =
                "Timed out waiting for simulators to reach live telemetry. Check Vehicles or SITL logs, then retry preflight."
            refreshSimulatorSlot(fleetLink: fleetLink)
            phase = .idle
            return
        }
        refreshSimulatorSlot(fleetLink: fleetLink)
        guard let linkedVehicleID = vehicleID else {
            statusText = "Simulator not linked."
            phase = .idle
            return
        }
        fleetLink.ensurePx4Ros2Sidecar(forVehicleID: linkedVehicleID)
        try? await Task.sleep(nanoseconds: 750_000_000)

        phase = .preflight
        statusText = "Running preflight…"
        let probe = await missionControl.runSingleVehiclePreflightProbe(
            vehicleID: linkedVehicleID,
            fleetLink: fleetLink,
            sitl: sitl,
            leaveArmed: true,
            allowDuringLiveMission: true,
            preflightAuditSource: Self.preflightSource
        )
        updateSlot {
            $0.preflightPassed = probe.passed
            $0.preflightDetail = probe.detail
            $0.linkReady = true
        }
        guard probe.passed else {
            statusText =
                "Preflight failed for the simulator. Use Retry on the card, open Vehicles to inspect, or replace."
            phase = .idle
            appendLog("Preflight: \(probe.detail)")
            return
        }

        await resetToTaskStart(fleetLink: fleetLink)
        phase = .idle
        statusText = "Simulator ready. Run autonomous teaching or rerun the task."
    }

    private func updateSlot(_ mutate: (inout FormationsPlaygroundSlotState) -> Void) {
        guard var slot = simulatorSlot else { return }
        mutate(&slot)
        applySlot(slot)
    }

    private func applySlot(_ slot: FormationsPlaygroundSlotState) {
        let linkBecameReady = simulatorSlot?.linkReady != true && slot.linkReady
        simulatorSlot = slot
        vehicleID = slot.vehicleID
        sitlSessionID = slot.sitlSessionID
        if linkBecameReady, let vehicleID {
            fleetLink?.ensurePx4Ros2Sidecar(forVehicleID: vehicleID)
            scheduleNav2PlanPathRefresh()
        }
    }

    private func endSpawnShellBusyState() {
        isBusy = false
    }

    /// Ensure MAVSDK + ROS sidecar for this training SITL row without tearing down other fleet sims.
    private func bindFleetLinkToTrainingSimulator(
        inst: SitlRunningInstance,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) async -> Bool {
        let vehicleID = resolvedVehicleID(for: inst, fleetLink: fleetLink)
        await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)

        if GuardianSitlFleetLinkReconnectPolicy.simulatorFleetLinkReadyWithMavsdkSession(
            fleetLink: fleetLink,
            vehicleID: vehicleID
        ) {
            fleetLink.ensurePx4Ros2Sidecar(forVehicleID: vehicleID)
            refreshSimulatorSlot(fleetLink: fleetLink)
            return true
        }

        // Stale or missing session (e.g. after Replace): reconnect this sysid only — does not affect other sims.
        fleetLink.unregisterSimulatedVehicle(systemID: inst.mavlinkSystemID)
        try? await Task.sleep(nanoseconds: 350_000_000)
        let ok = await sitl.reconnectFleetLink(sitlSessionID: inst.id, spawnDefaults: spawnDefaults)
        refreshSimulatorSlot(fleetLink: fleetLink)
        if ok {
            fleetLink.ensurePx4Ros2Sidecar(forVehicleID: vehicleID)
        }
        return ok
    }

    private func clearSimulatorTracking() {
        simulatorSlot = nil
        sitlSessionID = nil
        vehicleID = nil
        try? TrainingSimulatorSessionStore.clear()
    }

    /// Row for this panel's session (formation refresh does not require ``SitlRunningInstance/isAlive``).
    private func trainingSessionInstance(id: UUID?, sitl: SitlService) -> SitlRunningInstance? {
        guard let id else { return nil }
        return sitl.instances.first {
            $0.id == id && $0.spawnOwner == .trainingVehicle
        }
    }

    private func trainingOwnedInstance(id: UUID?, sitl: SitlService) -> SitlRunningInstance? {
        guard let row = trainingSessionInstance(id: id, sitl: sitl), row.isAlive else { return nil }
        return row
    }

    private func resolvedVehicleID(for inst: SitlRunningInstance, fleetLink: FleetLinkService) -> String {
        fleetLink.vehicleID(forSystemID: inst.mavlinkSystemID) ?? inst.guardianVehicleStreamKey
    }

    private func adoptRunningSimulator(
        _ inst: SitlRunningInstance,
        fleetLink: FleetLinkService,
        preservePreflightFrom prior: FormationsPlaygroundSlotState?,
        freshSpawn: Bool = false
    ) {
        let vid = resolvedVehicleID(for: inst, fleetLink: fleetLink)
        var preflightPassed = prior?.sitlSessionID == inst.id ? prior?.preflightPassed : nil
        var preflightDetail = prior?.sitlSessionID == inst.id ? prior?.preflightDetail : nil
        if preflightPassed == nil,
           let hub = fleetLink.hubTelemetry(forVehicleID: vid),
           hub.isArmed == true {
            preflightPassed = true
            preflightDetail = "Already armed."
        }
        let linkReady: Bool
        if freshSpawn {
            linkReady = false
        } else if prior?.sitlSessionID == inst.id {
            linkReady = prior?.linkReady ?? slotFleetReady(fleetLink: fleetLink, vehicleID: vid)
        } else {
            linkReady = slotFleetReady(fleetLink: fleetLink, vehicleID: vid)
        }
        applySlot(
            FormationsPlaygroundSlotState(
                sitlSessionID: inst.id,
                vehicleID: vid,
                linkReady: linkReady,
                preflightPassed: preflightPassed,
                preflightDetail: preflightDetail
            )
        )
        try? TrainingSimulatorSessionStore.save(inst.id)
    }

    @discardableResult
    private func startTrainingGazeboRunWorldIfNeeded() async -> Bool {
        guard requiresGazeboRunWorld else { return true }
        guard GuardianGazeboWebViewerPolicy.guardOnlineOrShowToast(
            productIncludesGazebo: true,
            toastCenter: toastCenter
        ) else { return false }
        guard let gazebo else {
            statusText = "Gazebo is not wired for this build."
            return false
        }
        guard let pkg = selectedEnvironment else {
            statusText = "Choose a training environment before spawning."
            return false
        }
        guard gazebo.runtimeAvailable else {
            statusText = "Gazebo is not available. Run make gazebo-runtime after installing Gazebo Harmonic."
            return false
        }

        stopTrainingGazeboRunWorld()
        gazeboWorldStatusText = nil
        statusText = "Starting Gazebo world (\(pkg.manifest.displayName))…"
        let plan = TrainingGazeboRunOrchestrator.spawnPlan(for: pkg)
        let worldID = await gazebo.spawnWorld(purpose: plan.purpose, package: pkg)
        guard let worldID else {
            gazeboWorldStatusText = gazebo.lastError
            statusText = gazebo.lastError ?? "Could not start Gazebo world."
            return false
        }
        activeGazeboWorldID = worldID
        gazeboWorldStatusText = "Gazebo: \(pkg.manifest.displayName) (\(plan.purpose.rawValue))"
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        return true
    }

    private func stopTrainingGazeboRunWorld() {
        guard let gazebo else {
            activeGazeboWorldID = nil
            gazeboWorldStatusText = nil
            return
        }
        if let id = activeGazeboWorldID {
            gazebo.stopWorld(id: id)
        } else {
            gazebo.stopAll(purpose: .run)
        }
        activeGazeboWorldID = nil
        gazeboWorldStatusText = nil
    }

    /// Stops only this panel's training SITL and waits for UDP ports — does not touch formation sims.
    private func stopPriorTrainingSitlForRespawn() async {
        if let fleetLink, let sitl, let id = sitlSessionID {
            if let vehicleID {
                await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)
            }
            sitl.stop(id: id)
        } else if let vehicleID, let fleetLink {
            await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)
        }
        clearSimulatorTracking()
        if let fleetLink, let sitl, !sitl.instances.contains(where: \.isAlive) {
            fleetLink.clearStaleVehicleStateWhenNoSitlAlive()
        }
        if let sitl {
            await sitl.waitForRecentlyReleasedPortsToSettle()
        }
    }

    // MARK: - Teaching loop

    private func runAutonomousTeaching(fleetLink: FleetLinkService, vehicleID: String) async {
        guard let layout = taskLayout else { return }
        isTargetSlotMapEditEnabled = false
        isBusy = true
        phase = .teaching
        GuardianApplicationLifecycle.shared.beginBackgroundLabRun()
        defer {
            GuardianApplicationLifecycle.shared.endBackgroundLabRun()
            isBusy = false
            teachTask = nil
        }

        let vehicleType = vehicleClass.fleetVehicleType
        var queue = Utilities.training.candidates(
            task: taskKind,
            layout: layout,
            vehicleType: vehicleType,
            forbidden: forbiddenAxes
        )
        trialsTotal = min(queue.count, Self.maxTeachingTrials)
        trialsCompleted = 0
        guard !queue.isEmpty else {
            statusText = "No valid trials for this task and forbidden controls."
            phase = .exhausted
            return
        }

        appendLog("Teaching \(taskKind.displayTitle) · up to \(Self.maxTeachingTrials) trials (forbidden: \(forbiddenSummary())).")

        var best: (candidate: TrainingSkillCandidate, score: TrainingSkillScore)?
        var executed = 0

        while !queue.isEmpty, executed < Self.maxTeachingTrials {
            if Task.isCancelled { return }
            let candidate = queue.removeFirst()
            executed += 1
            trialsCompleted = executed
            statusText = "Trial \(executed): \(candidate.summary)"

            await resetToTaskStart(fleetLink: fleetLink)
            try? await Task.sleep(nanoseconds: 400_000_000)

            guard await fleetLink.startTrainingControlStream(vehicleID: vehicleID) else {
                appendLog("Trial \(executed): training stream failed to start.")
                continue
            }

            let episodeStart = Date()
            var violations: Set<TrainingControlAxis> = []
            for segment in candidate.segments {
                if Task.isCancelled { break }
                let segmentViolations = TrainingVehicleControlCapabilities.validateSegment(
                    segment,
                    vehicleType: vehicleType,
                    forbidden: forbiddenAxes
                )
                violations.formUnion(segmentViolations)
                do {
                    try await fleetLink.executeTrainingSegment(vehicleID: vehicleID, segment: segment)
                } catch {
                    appendLog("Trial \(executed): segment error — \(error.localizedDescription)")
                    break
                }
            }
            await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)
            try? await Task.sleep(nanoseconds: 500_000_000)

            let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
            let score = Utilities.training.score(
                hub: hub,
                goal: layout.goal,
                episodeDurationS: Date().timeIntervalSince(episodeStart),
                constraintViolations: violations
            )

            let line = String(
                format: "Trial %d: %@ — pos %.1f m, hdg %.0f°%@",
                executed,
                candidate.summary,
                score.positionErrorM,
                score.headingErrorDeg,
                score.succeeded ? " ✓" : ""
            )
            appendLog(line)

            let improved: Bool
            if let current = best {
                improved = TrainingSkillScorer.sortKey(score) < TrainingSkillScorer.sortKey(current.score)
                if improved { best = (candidate, score) }
            } else {
                improved = true
                best = (candidate, score)
            }

            if improved, !score.succeeded {
                let refinements = TrainingSkillSearcher.variations(
                    around: candidate,
                    layout: layout,
                    vehicleType: vehicleType,
                    forbidden: forbiddenAxes
                )
                queue.append(contentsOf: refinements)
                trialsTotal = min(executed + queue.count, Self.maxTeachingTrials)
            }

            if score.succeeded {
                let skill = TrainedVehicleSkill(
                    taskKind: taskKind,
                    vehicleClass: vehicleClass,
                    segments: candidate.segments,
                    score: score,
                    layout: layout,
                    trialIndex: candidate.trialIndex,
                    summary: candidate.summary
                )
                try? TrainingSkillStore.appendPromoted(skill)
                promotedSkill = skill
                lastExportedBrainId = nil
                lastExportedBrainVersion = nil
                phase = .promoted
                statusText = "Skill promoted — \(candidate.summary)"
                appendLog("Promoted skill for \(taskKind.displayTitle) on \(vehicleClass.displayTitle).")
                if autoExportBrainOnPromote {
                    autoExportPromotedBrainToCatalogue()
                }
                return
            }
        }

        if let best {
            statusText = String(
                format: "No full success; best trial pos %.1f m, hdg %.0f°.",
                best.score.positionErrorM,
                best.score.headingErrorDeg
            )
            appendLog("Best attempt: \(best.candidate.summary)")
        } else {
            statusText = "All trials failed."
        }
        phase = .exhausted
    }

    // MARK: - Link / reset / teardown

    private func waitForLink(fleetLink: FleetLinkService) async -> Bool {
        let deadline = Date().addingTimeInterval(Self.linkWaitTimeoutS)
        while Date() < deadline {
            refreshSimulatorSlot(fleetLink: fleetLink)
            if simulatorSlot?.linkReady == true {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func slotFleetReady(fleetLink: FleetLinkService, vehicleID: String) -> Bool {
        GuardianSitlFleetLinkReconnectPolicy.simulatorFleetLinkReady(
            fleetLink: fleetLink,
            vehicleID: vehicleID
        )
    }

    private func resetToTaskStart(fleetLink: FleetLinkService) async {
        guard let vehicleID, let layout = taskLayout,
              fleetLink.isGuardianManagedSitlStream(vehicleID: vehicleID)
        else { return }
        let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
        let stack = hub?.autopilotStack != .unknown
            ? hub!.autopilotStack
            : FleetAutopilotStack(simulationPlatform: simulationPlatform)
        let pose = layout.start
        let state = FleetSimState(
            latitudeDeg: pose.latitudeDeg,
            longitudeDeg: pose.longitudeDeg,
            absoluteAltitudeM: pose.absoluteAltitudeM,
            yawDeg: Float(pose.headingDeg)
        )
        await fleetLink.applySimState(
            vehicleID: vehicleID,
            state: state,
            autopilotStack: stack,
            source: Self.resetSource
        )
    }

    private func stopTrainingStreamAndTrackedSitl() async {
        if let vehicleID, let fleetLink {
            await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)
        }
        if let id = sitlSessionID, let sitl {
            sitl.stop(id: id)
        }
        clearSimulatorTracking()
        if let fleetLink, let sitl, !sitl.instances.contains(where: \.isAlive) {
            fleetLink.clearStaleVehicleStateWhenNoSitlAlive()
        }
    }

    // MARK: - Logs

    private func appendLog(_ message: String) {
        logLines.insert(TrainingPanelLogLine(message: message), at: 0)
        if logLines.count > Self.maxLogLines {
            logLines.removeLast(logLines.count - Self.maxLogLines)
        }
    }

    private func clearLogs() {
        logLines = []
    }

    private func forbiddenSummary() -> String {
        forbiddenAxes.isEmpty
            ? "none"
            : forbiddenAxes.map(\.displayTitle).sorted().joined(separator: ", ")
    }
}
