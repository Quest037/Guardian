import Foundation
import SwiftUI

enum WorldBuilderSessionMode: String, Equatable, Sendable {
    case idle
    case preview
    case build
}

/// Autosave cadence for ``TrainingEnvironmentManifest/obstacles`` (single source of truth).
enum WorldBuilderObstaclePersistence {
    static let manifestAutosaveIntervalNs: UInt64 = 60_000_000_000
}

/// World Builder: catalogue, manifest editing, Gazebo preview/build sessions.
@MainActor
final class WorldBuilderController: ObservableObject {
    @Published private(set) var packages: [TrainingEnvironmentPackage] = []
    @Published var selectedPackageID: String?
    @Published var draftManifest: TrainingEnvironmentManifest?
    @Published private(set) var isEditingNewDraft = false

    var isEditingNewDraftPackage: Bool { isEditingNewDraft }
    /// Guardian-only UI gate: preview inspects the scene; build allows scene edits.
    @Published private(set) var sessionMode: WorldBuilderSessionMode = .idle
    @Published private(set) var activeGazeboWorldID: UUID?
    @Published private(set) var statusText = "Select a world or create a new one."
    @Published private(set) var lastError: String?

    private weak var gazebo: GazeboService?
    private weak var toastCenter: ToastCenter?
    private var productIncludesGazeboWebViewer = false
    private var draftWorldSourceURL: URL?
    /// Isolates unsaved draft `world.sdf` / `manifest.json` from bundled or saved user packages.
    private var builderDraftSessionID = UUID()
    /// Manifest `floorSize` label last loaded into the live Gazebo sim (e.g. `micro`).
    private var loadedGazeboFloorSizeLabel: String?

    /// When true, World Builder may add or edit objects in the 3D scene (build mode only).
    var canEditScene: Bool {
        sessionMode == .build && hasWorldFile && !draftIsReadOnly
    }

    var selectedPackage: TrainingEnvironmentPackage? {
        guard let id = selectedPackageID else { return nil }
        return packages.first { $0.id == id }
    }

    var draftIsReadOnly: Bool {
        guard let pkg = selectedPackage, !isEditingNewDraft else { return false }
        return pkg.source == .bundled
    }

    var hasWorldFile: Bool {
        draftWorldSourceURL != nil || selectedPackage != nil
    }

    /// Title for the builder sub-bar when a world is open.
    var subBarTitle: String {
        if isEditingNewDraft {
            let name = draftManifest?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "New world" : name
        }
        if let pkg = selectedPackage {
            return pkg.manifest.displayName
        }
        return "World Builder"
    }

    /// A saved or bundled world is open in the builder (not an unsaved new-world drawer draft).
    var hasOpenWorld: Bool {
        selectedPackageID != nil
    }

    private var activeFloorSize: TrainingEnvironmentFloorSize {
        let floorRaw = selectedPackage?.manifest.floorSize ?? draftManifest?.floorSize
        return TrainingEnvironmentFloorSize.resolved(from: floorRaw)
    }

    /// Half side length (m) of the open world's square floor for gzweb birdseye framing.
    var activeFloorHalfExtentM: Double {
        activeFloorSize.floorSideM / 2
    }

    /// Closest orbit zoom (m) for the embedded gzweb viewport on this world's floor size.
    var activeOrbitMinDistanceM: Double {
        activeFloorSize.orbitMinDistanceM
    }

    /// Foot height limits (m) relative to map-base top (z = 0) for the obstacle toolbar.
    var obstacleFootZLimitsM: (min: Double, max: Double) {
        let scene = TrainingEnvironmentSceneType.resolved(from: draftManifest?.sceneType)
        return WorldBuilderObstacleManifestSupport.footZLimitsM(
            sceneType: scene,
            floorSideM: activeFloorSize.floorSideM
        )
    }

    var canEditManifestInDrawer: Bool {
        draftManifest != nil && !draftIsReadOnly
    }

    var zonesSnapshot: WorldBuilderZonesSnapshot {
        guard let manifest = draftManifest else { return .empty }
        return WorldBuilderZoneManifestSupport.zones(from: manifest)
    }

    @Published var openSceneToolPanel: WorldBuilderSceneToolPanel?

    func toggleZoneEditorPanel() {
        guard canEditScene else { return }
        if openSceneToolPanel == .zoneEditor {
            closeSceneToolPanel()
        } else {
            closeObstacleEditorPanel()
            openSceneToolPanel = .zoneEditor
            zonePlacementToolActive = true
            bumpZoneEditorRevision()
        }
    }

    /// Opens zone editing from a viewport tap on a placed zone (start/end).
    func openZoneEditorFromViewport(kind: WorldBuilderZoneKind) {
        guard canEditScene else { return }
        guard openSceneToolPanel != .obstacleEditor else { return }
        if openSceneToolPanel != .zoneEditor {
            closeObstacleEditorPanel()
            openSceneToolPanel = .zoneEditor
        }
        zonePlacementKind = kind
        zonePlacementToolActive = true
        bumpZoneEditorRevision()
    }

    func requestDeleteZone(kind: WorldBuilderZoneKind) {
        guard canEditScene, openSceneToolPanel == .zoneEditor, zonePlacementToolActive else { return }
        pendingZoneDeleteKind = kind
    }

    func confirmDeleteZone(kind: WorldBuilderZoneKind) {
        guard canEditScene, var manifest = draftManifest else { return }
        var zones = WorldBuilderZoneManifestSupport.zones(from: manifest)
        switch kind {
        case .start:
            let preserved = zones.start
            zones.start = WorldBuilderZoneState.unplaced(shape: preserved.shape)
            zones.start.radiusM = preserved.radiusM
        case .end:
            let preserved = zones.end
            zones.end = WorldBuilderZoneState.unplaced(shape: preserved.shape)
            zones.end.radiusM = preserved.radiusM
        }
        pendingZoneDeleteKind = nil
        _ = commitZoneManifest(zones, to: &manifest)
    }

    func toggleObstacleEditorPanel() {
        guard canEditScene else { return }
        if openSceneToolPanel == .obstacleEditor {
            closeSceneToolPanel()
        } else {
            closeZoneEditorOnly()
            openSceneToolPanel = .obstacleEditor
            obstaclePlacementToolActive = true
            resetObstaclePlacementPrototype()
            bumpObstacleViewportRevision()
            Task {
                _ = try? ensureDraftWorldFileURL()
                if activeGazeboWorldID == nil {
                    await syncEmbeddedViewport()
                }
                await stripOrphanLiveObstaclesIfNeeded()
                await syncManifestObstaclesToLiveSimIfNeeded()
            }
        }
    }

    func closeSceneToolPanel() {
        let wasObstacleEditor = openSceneToolPanel == .obstacleEditor
        openSceneToolPanel = nil
        zonePlacementToolActive = false
        obstaclePlacementToolActive = false
        obstacleSelectedID = nil
        pendingZoneDeleteKind = nil
        pendingObstacleDeleteID = nil
        bumpZoneEditorRevision()
        bumpObstacleViewportRevision()
        if wasObstacleEditor {
            persistObstacleManifestToDiskNow()
        }
    }

    private func closeZoneEditorOnly() {
        zonePlacementToolActive = false
        bumpZoneEditorRevision()
    }

    private func closeObstacleEditorPanel() {
        obstaclePlacementToolActive = false
        obstacleSelectedID = nil
        bumpObstacleViewportRevision()
    }

    func setZonePlacementKind(_ kind: WorldBuilderZoneKind) {
        guard canEditScene else { return }
        zonePlacementKind = kind
        bumpZoneEditorRevision()
    }

    func setActiveZoneShape(_ shape: TrainingEnvironmentZoneShape) {
        guard canEditScene, var manifest = draftManifest else { return }
        var zones = WorldBuilderZoneManifestSupport.zones(from: manifest)
        switch zonePlacementKind {
        case .start:
            zones.start.shape = shape
        case .end:
            zones.end.shape = shape
        }
        commitZoneManifest(zones, to: &manifest)
    }

    @discardableResult
    func setActiveZoneRadiusM(_ radiusM: Double) -> Bool {
        guard canEditScene, var manifest = draftManifest else { return false }
        var zones = WorldBuilderZoneManifestSupport.zones(from: manifest)
        let clamped = min(WorldBuilderZoneState.maxRadiusM, max(WorldBuilderZoneState.minRadiusM, radiusM))
        switch zonePlacementKind {
        case .start:
            zones.start.radiusM = clamped
        case .end:
            zones.end.radiusM = clamped
        }
        return commitZoneManifest(zones, to: &manifest)
    }

    var activeZoneRadiusM: Double {
        let zones = zonesSnapshot
        switch zonePlacementKind {
        case .start: return zones.start.radiusM
        case .end: return zones.end.radiusM
        }
    }

    var activeZoneShape: TrainingEnvironmentZoneShape {
        let zones = zonesSnapshot
        switch zonePlacementKind {
        case .start: return zones.start.shape
        case .end: return zones.end.shape
        }
    }

    /// Applies snapped zone geometry from the viewport. Returns `true` when a zone cannot fit on the map.
    @discardableResult
    func applyZonesFromViewport(_ zones: WorldBuilderZonesSnapshot) -> Bool {
        guard canEditScene, var manifest = draftManifest else { return false }
        return commitZoneManifest(zones, to: &manifest)
    }

    /// Snaps zones to the map-base square, updates draft manifest, and persists for saved user worlds.
    @discardableResult
    private func commitZoneManifest(
        _ zones: WorldBuilderZonesSnapshot,
        to manifest: inout TrainingEnvironmentManifest
    ) -> Bool {
        var proposed = zones
        WorldBuilderZoneManifestSupport.clampZoneRadiiToAllowedRange(&proposed)
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: activeFloorHalfExtentM)
        let failed = !WorldBuilderZoneBoundsCheck.snapZonesToFloor(&proposed, floor: floor)
        guard !failed else {
            bumpZoneEditorRevision()
            return true
        }
        WorldBuilderZoneManifestSupport.apply(proposed, to: &manifest)
        draftManifest = manifest
        persistDraftManifestToDiskIfPossible(manifest)
        bumpZoneEditorRevision()
        return false
    }

    private func persistDraftManifestToDiskIfPossible(_ manifest: TrainingEnvironmentManifest) {
        guard !draftIsReadOnly, let packageRoot = obstaclePersistencePackageRoot() else { return }
        do {
            try TrainingEnvironmentStore.saveManifest(manifest, packageRoot: packageRoot)
            if !isEditingNewDraft, let pkg = selectedPackage {
                if let index = packages.firstIndex(where: { $0.id == pkg.id }) {
                    packages[index] = TrainingEnvironmentPackage(
                        manifest: manifest,
                        packageRootURL: pkg.packageRootURL,
                        source: pkg.source
                    )
                }
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// User package root for a saved world, or a staging folder while editing an unsaved draft.
    private func obstaclePersistencePackageRoot() -> URL? {
        if draftIsReadOnly { return nil }
        if isEditingNewDraft {
            return try? builderDraftPackageRootURL()
        }
        guard let pkg = selectedPackage, pkg.source != .bundled else { return nil }
        return pkg.packageRootURL
    }

    private func builderDraftPackageRootURL() throws -> URL {
        let trimmedID = draftManifest?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let folderName = trimmedID.isEmpty ? builderDraftSessionID.uuidString : trimmedID
        return try TrainingEnvironmentStore.builderDraftPackageRoot(folderName: folderName)
    }

    private func resetBuilderDraftSession() {
        builderDraftSessionID = UUID()
    }

    private func seedDraftWorldFileInStagingIfNeeded(copyFrom sourceWorld: URL?) throws {
        let root = try builderDraftPackageRootURL()
        let worldName = draftManifest?.worldFile ?? "world.sdf"
        let dest = root.appendingPathComponent(worldName, isDirectory: false)
        if FileManager.default.isReadableFile(atPath: dest.path) {
            draftWorldSourceURL = dest
            return
        }
        if let sourceWorld, FileManager.default.isReadableFile(atPath: sourceWorld.path) {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceWorld, to: dest)
        } else if let manifest = draftManifest {
            try TrainingEnvironmentWorldComposer.writeWorld(
                manifest: manifest,
                to: dest,
                mode: .builderSession
            )
        }
        draftWorldSourceURL = dest
    }

    private func bumpZoneEditorRevision() {
        zoneEditorRevision = UUID()
    }

    /// When true, the gzweb viewport accepts clicks to place the active start/end zone.
    @Published private(set) var zonePlacementToolActive = false
    @Published var zonePlacementKind: WorldBuilderZoneKind = .start
    @Published private(set) var zoneEditorRevision = UUID()

    // MARK: - Obstacle editor

    @Published private(set) var obstaclePlacementToolActive = false
    /// Single edit buffer for the Models panel and the next map placement (Mission-style one binding).
    @Published var obstaclePlacementDraft = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
    @Published private(set) var obstacleSelectedID: String?
    /// Bumps when the gzweb obstacle editor state should refresh (not used for SwiftUI panel identity).
    @Published private(set) var obstacleViewportRevision = UUID()
    @Published private(set) var isObstacleMapRepairInFlight = false
    /// Obstacle currently being removed from Gazebo (viewport fade + no selection).
    @Published private(set) var obstacleDeletingID: String?
    @Published var pendingObstacleDeleteID: String?
    @Published var pendingZoneDeleteKind: WorldBuilderZoneKind?

    /// Obstacle ids currently present in the running Gazebo world.
    private var liveObstacleIDs: Set<String> = []
    /// Exact Gazebo model name per obstacle id (`allow_renaming: false` at spawn).
    private var liveObstacleGazeboNames: [String: String] = [:]
    private var obstacleViewportPushTask: Task<Void, Never>?
    private var obstacleManifestPersistTask: Task<Void, Never>?
    private var obstacleEditSyncTask: Task<Void, Never>?
    private var ensureBuilderGazeboInFlight: Task<Void, Never>?

    /// Models toolbar is active (blue) in build mode.
    var isObstacleEditorActive: Bool {
        openSceneToolPanel == .obstacleEditor
    }

    private var canPersistObstaclesToDisk: Bool {
        !draftIsReadOnly && obstaclePersistencePackageRoot() != nil
    }

    var obstaclesSnapshot: [TrainingEnvironmentObstacleRecord] {
        draftManifest?.obstacles ?? []
    }

    /// Toolbar + placement both use ``obstaclePlacementDraft``; selection syncs into/out of the manifest.
    func obstacleEditingBinding() -> Binding<TrainingEnvironmentObstacleRecord> {
        Binding(
            get: { self.obstaclePlacementDraft },
            set: { newValue in
                self.obstaclePlacementDraft = newValue
                self.commitObstacleEditToManifestAndViewport()
                self.scheduleDebouncedObstacleLiveSimSync()
            }
        )
    }

    private func normalizedObstacleEditBuffer() -> TrainingEnvironmentObstacleRecord {
        guard let manifest = draftManifest else { return obstaclePlacementDraft }
        var record = obstaclePlacementDraft
        let scene = TrainingEnvironmentSceneType.resolved(from: manifest.sceneType)
        WorldBuilderObstacleManifestSupport.normalizeRecord(
            &record,
            floorHalfM: activeFloorHalfExtentM,
            sceneType: scene
        )
        return record
    }

    @discardableResult
    private func applyNormalizedObstacleEditBuffer() -> TrainingEnvironmentObstacleRecord? {
        let record = normalizedObstacleEditBuffer()
        obstaclePlacementDraft = record
        guard var manifest = draftManifest else {
            bumpObstacleViewportRevision()
            return nil
        }
        guard let id = obstacleSelectedID,
              let index = manifest.obstacles.firstIndex(where: { $0.id == id }) else {
            bumpObstacleViewportRevision()
            return nil
        }
        manifest.obstacles[index] = record
        commitObstacleManifest(&manifest, syncLive: false, bumpViewport: false)
        return record
    }

    /// Writes toolbar edits into the manifest and refreshes the gzweb editor state immediately.
    private func commitObstacleEditToManifestAndViewport() {
        _ = applyNormalizedObstacleEditBuffer()
        bumpObstacleViewportRevision()
    }

    /// Re-spawns the selected obstacle in Gazebo after toolbar edits settle (geometry / pose).
    private func scheduleDebouncedObstacleLiveSimSync() {
        obstacleEditSyncTask?.cancel()
        obstacleEditSyncTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            guard let id = obstacleSelectedID,
                  let record = obstaclesSnapshot.first(where: { $0.id == id }) else { return }
            await syncSelectedObstacleToLiveSim(record)
        }
    }

    private func flushObstacleEditSyncNow() {
        obstacleEditSyncTask?.cancel()
        guard let record = applyNormalizedObstacleEditBuffer() else { return }
        bumpObstacleViewportRevision()
        Task { await syncSelectedObstacleToLiveSim(record) }
    }

    /// Re-spawns the selected obstacle in the running Gazebo world so toolbar edits appear in the sim.
    private func syncSelectedObstacleToLiveSim(_ record: TrainingEnvironmentObstacleRecord) async {
        guard canEditScene,
              obstacleSelectedID == record.id,
              activeGazeboWorldID != nil,
              gazebo != nil else { return }
        await refreshLiveObstacle(record)
    }

    @discardableResult
    func applyObstaclesFromViewport(_ obstacles: [TrainingEnvironmentObstacleRecord], selectedID: String?) -> Bool {
        guard canEditScene, var manifest = draftManifest else { return false }
        let prior = manifest.obstacles
        guard WorldBuilderObstacleViewportSyncPolicy.acceptsViewportObstacleList(
            prior: prior,
            proposed: obstacles
        ) else {
            obstacleSelectedID = selectedID
            bumpObstacleViewportRevision()
            return false
        }
        var clamped = obstacles
        let floorHalfM = activeFloorHalfExtentM
        let scene = TrainingEnvironmentSceneType.resolved(from: manifest.sceneType)
        for index in clamped.indices {
            WorldBuilderObstacleManifestSupport.normalizeDimensions(&clamped[index])
            if clamped[index].usesAutoZ {
                WorldBuilderObstacleManifestSupport.reclampAutoZ(
                    &clamped[index],
                    floorHalfM: floorHalfM,
                    sceneType: scene
                )
            } else {
                WorldBuilderObstacleManifestSupport.clampFootZM(
                    &clamped[index],
                    sceneType: scene,
                    floorSideM: floorHalfM * 2
                )
            }
        }
        clamped = Array(clamped.prefix(TrainingEnvironmentObstacleRecord.maxCount))
        let selectionOnly = clamped == prior
        if selectionOnly {
            obstacleSelectedID = selectedID
            return false
        }
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: activeFloorHalfExtentM)
        let failed = !WorldBuilderObstacleBoundsCheck.snapObstaclesToFloor(&clamped, floor: floor)
        guard !failed else {
            obstacleSelectedID = selectedID
            bumpObstacleViewportRevision()
            return true
        }
        manifest.obstacles = clamped
        if let id = selectedID, let record = clamped.first(where: { $0.id == id }) {
            obstaclePlacementDraft = record
        }
        commitObstacleManifest(&manifest, syncLive: false, bumpViewport: true)
        obstacleSelectedID = selectedID
        let priorByID = Dictionary(uniqueKeysWithValues: prior.map { ($0.id, $0) })
        let changedIDs = Set(clamped.compactMap { record -> String? in
            guard let old = priorByID[record.id], record != old else { return nil }
            return record.id
        })
        if !changedIDs.isEmpty {
            Task {
                for record in clamped where changedIDs.contains(record.id) {
                    if let old = priorByID[record.id], copiesObstacleGeometry(old, record) {
                        await repositionLiveObstacle(record)
                    } else {
                        await refreshLiveObstacle(record)
                    }
                }
            }
        }
        return false
    }

    private func copiesObstacleGeometry(
        _ a: TrainingEnvironmentObstacleRecord,
        _ b: TrainingEnvironmentObstacleRecord
    ) -> Bool {
        var lhs = a
        var rhs = b
        lhs.centerXM = 0
        lhs.centerYM = 0
        lhs.centerZM = 0
        lhs.yawDeg = 0
        rhs.centerXM = 0
        rhs.centerYM = 0
        rhs.centerZM = 0
        rhs.yawDeg = 0
        return lhs == rhs
    }

    private func repositionLiveObstacle(_ record: TrainingEnvironmentObstacleRecord) async {
        guard let worldID = activeGazeboWorldID, let gazebo else { return }
        let gazeboName = liveObstacleGazeboNames[record.id] ?? record.gazeboModelName
        let moved = await gazebo.repositionWorldBuilderObstacle(
            worldID: worldID,
            record: record,
            gazeboModelName: gazeboName
        )
        if !moved {
            await refreshLiveObstacle(record)
        }
    }

    func selectObstacleFromViewport(id: String?) {
        guard canEditScene else { return }
        if let id, id == obstacleDeletingID { return }
        guard obstacleSelectedID != id else { return }
        obstacleEditSyncTask?.cancel()
        if let id, let obstacle = obstaclesSnapshot.first(where: { $0.id == id }) {
            obstaclePlacementDraft = obstacle
        }
        obstacleSelectedID = id
        bumpObstacleViewportRevision()
    }

    func placeObstacleAt(centerXM: Double, centerYM: Double) {
        guard canEditScene, var manifest = draftManifest else { return }
        guard manifest.obstacles.count < TrainingEnvironmentObstacleRecord.maxCount else {
            toastCenter?.show("Obstacle limit reached (100).", style: .warning)
            return
        }
        flushObstacleEditSyncNow()
        var record = obstaclePlacementDraft
        record.id = TrainingEnvironmentObstacleRecord.newID()
        record.centerXM = centerXM
        record.centerYM = centerYM
        let scene = TrainingEnvironmentSceneType.resolved(from: manifest.sceneType)
        if record.usesAutoZ {
            record.centerZM = WorldBuilderObstacleManifestSupport.centerZMForAutoFlush(
                record: record,
                sceneType: scene
            )
        }
        WorldBuilderObstacleManifestSupport.normalizeDimensions(&record)
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: activeFloorHalfExtentM)
        guard WorldBuilderObstacleBoundsCheck.fitsOnFloor(record, floor: floor) else {
            toastCenter?.show("Model does not fit on the map.", style: .warning)
            return
        }
        manifest.obstacles.append(record)
        obstacleSelectedID = nil
        obstaclePlacementDraft = TrainingEnvironmentObstacleRecord.defaults(for: record.kind)
        toastCenter?.show("Adding obstacle to map…", style: .info)
        commitObstacleManifest(&manifest, syncLive: true, bumpViewport: true)
        persistObstacleManifestToDiskNow()
    }

    func confirmDeleteObstacle(id: String) async {
        guard canEditScene, var manifest = draftManifest else { return }
        guard manifest.obstacles.contains(where: { $0.id == id }) else { return }
        let record = manifest.obstacles.first { $0.id == id }
        pendingObstacleDeleteID = nil

        if obstacleSelectedID == id {
            obstacleSelectedID = nil
            obstaclePlacementDraft = TrainingEnvironmentObstacleRecord.defaults(for: obstaclePlacementDraft.kind)
        }
        obstacleDeletingID = id
        bumpObstacleViewportRevision()

        var removedFromSim = true
        if let worldID = activeGazeboWorldID, let record, let gazebo {
            let gazeboName = liveObstacleGazeboNames[record.id] ?? record.gazeboModelName
            removedFromSim = await gazebo.removeWorldBuilderObstacle(
                worldID: worldID,
                gazeboModelName: gazeboName,
                obstacleID: record.id
            )
        }

        obstacleDeletingID = nil

        guard removedFromSim else {
            bumpObstacleViewportRevision()
            toastCenter?.show("Could not remove model from the map.", style: .warning)
            return
        }

        unregisterLiveObstacle(id: id)
        manifest.obstacles.removeAll { $0.id == id }
        commitObstacleManifest(&manifest, syncLive: false, bumpViewport: true)
        persistObstacleManifestToDiskNow()
    }

    func requestDeleteObstacle(id: String) {
        pendingObstacleDeleteID = id
    }

    private func commitObstacleManifest(
        _ manifest: inout TrainingEnvironmentManifest,
        syncLive: Bool,
        bumpViewport: Bool = false
    ) {
        WorldBuilderObstacleManifestSupport.apply(manifest.obstacles, to: &manifest)
        draftManifest = manifest
        scheduleObstacleManifestPersist()
        if bumpViewport {
            scheduleDebouncedObstacleViewportPush()
        }
        if syncLive, let record = manifest.obstacles.last {
            Task { await spawnLiveObstacle(record, announceSuccess: true) }
        }
    }

    /// Merges toolbar edits and writes `manifest.json` (not the baked Training `world.sdf`).
    private func persistObstacleManifestToDiskNow() {
        obstacleManifestPersistTask?.cancel()
        obstacleEditSyncTask?.cancel()
        _ = applyNormalizedObstacleEditBuffer()
        guard var manifest = draftManifest else { return }
        WorldBuilderObstacleManifestSupport.apply(manifest.obstacles, to: &manifest)
        draftManifest = manifest
        guard canPersistObstaclesToDisk else { return }
        persistDraftManifestToDiskIfPossible(manifest)
    }

    private func scheduleObstacleManifestPersist() {
        guard canPersistObstaclesToDisk else { return }
        obstacleManifestPersistTask?.cancel()
        obstacleManifestPersistTask = Task {
            try? await Task.sleep(nanoseconds: WorldBuilderObstaclePersistence.manifestAutosaveIntervalNs)
            guard !Task.isCancelled else { return }
            persistObstacleManifestToDiskNow()
        }
    }

    private func scheduleDebouncedObstacleViewportPush() {
        obstacleViewportPushTask?.cancel()
        obstacleViewportPushTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            bumpObstacleViewportRevision()
        }
    }

    private func registerLiveObstacle(id: String, gazeboName: String) {
        liveObstacleIDs.insert(id)
        liveObstacleGazeboNames[id] = gazeboName
    }

    private func unregisterLiveObstacle(id: String) {
        liveObstacleIDs.remove(id)
        liveObstacleGazeboNames.removeValue(forKey: id)
    }

    private func clearLiveObstacleRegistry() {
        liveObstacleIDs = []
        liveObstacleGazeboNames = [:]
    }

    private func bumpObstacleViewportRevision() {
        obstacleViewportRevision = UUID()
    }

    private func obstacleMeshDirectoryURL() throws -> URL {
        let worldURL = try ensureDraftWorldFileURL()
        return worldURL.deletingLastPathComponent()
            .appendingPathComponent("obstacle_meshes", isDirectory: true)
    }

    /// Floor-only `world.sdf` for the open Builder Gazebo session (obstacles stay live-spawned).
    private func persistBuilderSessionWorldSDFSync() throws {
        guard let manifest = draftManifest else { return }
        let worldURL = try ensureDraftWorldFileURL()
        try TrainingEnvironmentWorldComposer.writeWorld(
            manifest: manifest,
            to: worldURL,
            mode: .builderSession
        )
        draftWorldSourceURL = worldURL
    }

    /// Bakes ``draftManifest/obstacles`` into one Training model in on-disk `world.sdf`.
    private func bakeObstaclesForTrainingWorld() {
        guard canPersistObstaclesToDisk else { return }
        obstacleManifestPersistTask?.cancel()
        obstacleEditSyncTask?.cancel()
        _ = applyNormalizedObstacleEditBuffer()
        guard var manifest = draftManifest else { return }
        WorldBuilderObstacleManifestSupport.apply(manifest.obstacles, to: &manifest)
        draftManifest = manifest
        persistDraftManifestToDiskIfPossible(manifest)
        do {
            let worldURL = try trainingWorldFileURLForPersistence()
            try TrainingEnvironmentWorldComposer.writeWorld(
                manifest: manifest,
                to: worldURL,
                mode: .trainingRun
            )
            if !isEditingNewDraft, selectedPackage != nil {
                draftWorldSourceURL = worldURL
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func trainingWorldFileURLForPersistence() throws -> URL {
        if isEditingNewDraft {
            return try ensureDraftWorldFileURL()
        }
        if let pkg = selectedPackage {
            return pkg.worldFileURL()
        }
        return try ensureDraftWorldFileURL()
    }

    /// Manifest autosave during editing; baked Training `world.sdf` on map/panel exit only.
    private func flushPendingWorldBuilderPersistence() {
        persistObstacleManifestToDiskNow()
        bakeObstaclesForTrainingWorld()
    }

    private func needsObstacleReconcile() -> Bool {
        Set(obstaclesSnapshot.map(\.id)) != liveObstacleIDs
    }

    /// Drops every `guardian_obstacle_*` model in the live sim, then re-inserts manifest obstacles.
    @discardableResult
    private func reconcileLiveObstaclesWithManifest(force: Bool = false) async -> Int {
        guard let worldID = activeGazeboWorldID, let gazebo else { return 0 }
        if !force, !needsObstacleReconcile() { return 0 }

        let manifest = obstaclesSnapshot
        let (_, orphanCount) = await gazebo.stripAllGuardianObstacleModelsFromLiveSim(
            worldID: worldID,
            manifest: manifest
        )
        clearLiveObstacleRegistry()

        let meshDir: URL
        do {
            meshDir = try obstacleMeshDirectoryURL()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return orphanCount
        }
        for record in manifest {
            do {
                let gazeboName = try await gazebo.spawnWorldBuilderObstacle(
                    worldID: worldID,
                    record: record,
                    meshDirectory: meshDir
                )
                registerLiveObstacle(id: record.id, gazeboName: gazeboName)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                toastCenter?.show("Could not show \(record.kind.displayName) on map: \(message)", style: .warning)
            }
        }

        do {
            try persistBuilderSessionWorldSDFSync()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        bumpObstacleViewportRevision()
        return orphanCount
    }

    /// Operator repair when the viewport and obstacle list disagree.
    func repairObstacleMapAlignment() async {
        guard canEditScene, !isObstacleMapRepairInFlight else { return }
        isObstacleMapRepairInFlight = true
        defer { isObstacleMapRepairInFlight = false }
        let orphans = await reconcileLiveObstaclesWithManifest(force: true)
        if orphans > 0 {
            toastCenter?.show(
                "Removed \(orphans) stray model(s) and synced obstacles to the list.",
                style: .info
            )
        } else {
            toastCenter?.show("Obstacle models synced to the list.", style: .success)
        }
    }

    private func spawnLiveObstacle(
        _ record: TrainingEnvironmentObstacleRecord?,
        announceSuccess: Bool
    ) async {
        guard let record, let worldID = activeGazeboWorldID, let gazebo else { return }
        do {
            let meshDir = try obstacleMeshDirectoryURL()
            let gazeboName = try await gazebo.spawnWorldBuilderObstacle(
                worldID: worldID,
                record: record,
                meshDirectory: meshDir
            )
            registerLiveObstacle(id: record.id, gazeboName: gazeboName)
            if announceSuccess {
                toastCenter?.show("Obstacle added to map.", style: .success)
            }
        } catch {
            unregisterLiveObstacle(id: record.id)
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = message
            toastCenter?.show(message, style: .error)
        }
    }

    private func refreshLiveObstacle(_ record: TrainingEnvironmentObstacleRecord) async {
        guard let worldID = activeGazeboWorldID,
              let gazebo,
              let row = gazebo.worlds.first(where: { $0.id == worldID && $0.isAlive }) else { return }
        let liveNames = await GazeboEntityFactoryClient.listWorldModelNames(instanceIndex: row.instanceIndex)
        let gazeboName = liveObstacleGazeboNames[record.id] ?? record.gazeboModelName
        _ = await gazebo.removeWorldBuilderObstacle(
            worldID: worldID,
            gazeboModelName: gazeboName,
            obstacleID: record.id,
            knownLiveModelNames: liveNames
        )
        unregisterLiveObstacle(id: record.id)
        await spawnLiveObstacle(record, announceSuccess: false)
    }

    /// Aligns live sim obstacles with the manifest (repairs drift / phantom models).
    func syncManifestObstaclesToLiveSimIfNeeded() async {
        guard sessionMode != .idle, activeGazeboWorldID != nil, gazebo != nil else { return }
        if needsObstacleReconcile() {
            guard !isObstacleMapRepairInFlight else { return }
            isObstacleMapRepairInFlight = true
            defer { isObstacleMapRepairInFlight = false }
            let orphans = await reconcileLiveObstaclesWithManifest(force: true)
            if orphans > 0 {
                toastCenter?.show(
                    "Repaired obstacle models on the map (\(orphans) stray removed).",
                    style: .info
                )
            }
            return
        }
        guard let worldID = activeGazeboWorldID, let gazebo else { return }
        let meshDir: URL
        do {
            meshDir = try obstacleMeshDirectoryURL()
        } catch {
            return
        }
        for record in obstaclesSnapshot where !liveObstacleIDs.contains(record.id) {
            do {
                let gazeboName = try await gazebo.spawnWorldBuilderObstacle(
                    worldID: worldID,
                    record: record,
                    meshDirectory: meshDir
                )
                registerLiveObstacle(id: record.id, gazeboName: gazeboName)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                toastCenter?.show("Could not show \(record.kind.displayName) on map: \(message)", style: .warning)
            }
        }
    }

    private func ensureDraftWorldFileURL() throws -> URL {
        if isEditingNewDraft {
            try seedDraftWorldFileInStagingIfNeeded(copyFrom: draftWorldSourceURL)
            if let url = draftWorldSourceURL, FileManager.default.isReadableFile(atPath: url.path) {
                return url
            }
        }
        if let pkg = selectedPackage {
            let packageWorld = pkg.worldFileURL()
            draftWorldSourceURL = packageWorld
            return packageWorld
        }
        if let url = draftWorldSourceURL, FileManager.default.isReadableFile(atPath: url.path) {
            return url
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-draft-world-\(UUID().uuidString).sdf")
        draftWorldSourceURL = url
        if let manifest = draftManifest {
            try TrainingEnvironmentWorldComposer.writeWorld(
                manifest: manifest,
                to: url,
                mode: .builderSession
            )
        }
        return url
    }

    func attach(gazebo: GazeboService, toastCenter: ToastCenter, productIncludesGazeboWebViewer: Bool) {
        self.gazebo = gazebo
        self.toastCenter = toastCenter
        self.productIncludesGazeboWebViewer = productIncludesGazeboWebViewer
        reloadCatalogue()
    }

    func reloadCatalogue() {
        packages = TrainingEnvironmentCatalogue.loadAll()
        if let id = selectedPackageID, !packages.contains(where: { $0.id == id }) {
            closeCurrentWorld()
        }
    }

    /// Clears the open world and stops all preview/build Gazebo sessions (sub-bar close control).
    func closeCurrentWorld() {
        Task { await closeCurrentWorldAsync() }
    }

    private func closeCurrentWorldAsync() async {
        resetObstacleEditorState(closePanel: true)
        flushPendingWorldBuilderPersistence()
        await stopAllBuilderGazeboSessions()
        clearLiveObstacleRegistry()
        selectedPackageID = nil
        isEditingNewDraft = false
        draftManifest = nil
        draftWorldSourceURL = nil
        lastError = nil
        statusText = "Select a world or create a new one."
    }

    /// Starts headless sim + websocket bridge for the embedded World Builder viewport.
    func syncEmbeddedViewport() async {
        guard GuardianGazeboWebViewerPolicy.guardOnlineOrShowToast(
            productIncludesGazebo: productIncludesGazeboWebViewer,
            toastCenter: toastCenter
        ) else { return }
        guard gazebo?.runtimeAvailable == true, hasWorldFile else { return }
        if sessionMode == .idle {
            sessionMode = .preview
        }
        await ensureBuilderGazeboRunning()
    }

    func selectPackage(id: String) {
        Task { await selectPackageAndPrepareViewport(id: id) }
    }

    private func selectPackageAndPrepareViewport(id: String) async {
        flushPendingWorldBuilderPersistence()
        await stopGazeboSession()
        loadedGazeboFloorSizeLabel = nil
        resetObstacleEditorState(closePanel: true)
        reloadCatalogue()
        selectedPackageID = id
        isEditingNewDraft = false
        sessionMode = .idle
        loadDraftFromSelection()
        await syncEmbeddedViewport()
    }

    /// Prepares an unsaved world for the New drawer only — does not open Gazebo or the main viewport.
    func prepareNewDraftInDrawer() {
        Task { await stopGazeboSession() }
        resetObstacleEditorState(closePanel: true)
        resetBuilderDraftSession()
        isEditingNewDraft = true
        selectedPackageID = nil
        draftWorldSourceURL = nil
        draftManifest = TrainingEnvironmentAuthoring.newDraftManifest()
        lastError = nil
        statusText = ""
    }

    func duplicateSelectedAsNewDraft() {
        guard let pkg = selectedPackage else { return }
        Task { await duplicateSelectedAsNewDraftAsync(pkg: pkg) }
    }

    private func duplicateSelectedAsNewDraftAsync(pkg: TrainingEnvironmentPackage) async {
        await stopGazeboSession()
        resetObstacleEditorState(closePanel: true)
        resetBuilderDraftSession()
        isEditingNewDraft = true
        selectedPackageID = nil
        var manifest = pkg.manifest
        manifest.displayName = "\(manifest.displayName) copy"
        let occupied = occupiedEnvironmentIDs()
        manifest.id = TrainingEnvironmentAuthoring.uniqueEnvironmentID(
            slug: TrainingEnvironmentAuthoring.slugFromDisplayName(manifest.displayName),
            occupiedIDs: occupied
        )
        draftManifest = manifest
        draftWorldSourceURL = nil
        do {
            try seedDraftWorldFileInStagingIfNeeded(copyFrom: pkg.worldFileURL())
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        statusText = "Duplicated as a new draft. Save to write a user copy."
    }

    func loadDraftFromSelection() {
        guard !isEditingNewDraft, let pkg = selectedPackage else {
            if !isEditingNewDraft {
                draftManifest = nil
                draftWorldSourceURL = nil
            }
            return
        }
        draftManifest = pkg.manifest
        draftWorldSourceURL = pkg.worldFileURL()
        lastError = nil
        statusText = pkg.source == .bundled
            ? "Bundled world — preview only, or duplicate to edit."
            : "User world — edit and save, or preview in Gazebo."
    }

    func leavePanel() {
        Task { await stopAllBuilderGazeboSessions() }
    }

    /// Stops every embedded Gazebo sim used by World Builder and waits for Harmonic processes to exit.
    func stopAllBuilderGazeboSessions() async {
        flushPendingWorldBuilderPersistence()
        await gazebo?.stopAllEmbeddedViewportWorldsCompletely()
        activeGazeboWorldID = nil
        loadedGazeboFloorSizeLabel = nil
        clearLiveObstacleRegistry()
        obstacleViewportPushTask?.cancel()
        obstacleManifestPersistTask?.cancel()
        obstacleEditSyncTask?.cancel()
        sessionMode = .idle
    }

    func stopGazeboSession() async {
        await stopAllBuilderGazeboSessions()
    }

    /// Preview mode — same Gazebo session as build; UI/scene-edit gate only.
    func enterPreviewMode() async {
        guard GuardianGazeboWebViewerPolicy.guardOnlineOrShowToast(
            productIncludesGazebo: productIncludesGazeboWebViewer,
            toastCenter: toastCenter
        ) else { return }
        let wasBuild = sessionMode == .build
        if applyBuilderSessionModeWithoutRespawn(.preview) {
            return
        }
        sessionMode = .preview
        await ensureBuilderGazeboRunning()
        if wasBuild {
            persistObstacleManifestToDiskNow()
        }
        if activeGazeboWorldID != nil {
            statusText = ""
        }
    }

    /// Build mode — same Gazebo session as preview; UI/scene-edit gate only.
    func enterBuildMode() async {
        guard GuardianGazeboWebViewerPolicy.guardOnlineOrShowToast(
            productIncludesGazebo: productIncludesGazeboWebViewer,
            toastCenter: toastCenter
        ) else { return }
        if applyBuilderSessionModeWithoutRespawn(.build) {
            return
        }
        await ensureBuilderGazeboRunning()
        guard isEmbeddedViewportLive else { return }
        sessionMode = .build
        statusText = ""
    }

    /// Gazebo row id for the open builder world (tracked id or rediscovered alive session).
    var resolvedEmbeddedWorldID: UUID? {
        resolveActiveBuilderWorldID()
    }

    /// Embedded gzweb viewport is ready for camera and build tools (not still starting).
    var isEmbeddedViewportLive: Bool {
        gazebo?.isEmbeddedViewportLive(worldID: resolvedEmbeddedWorldID) ?? false
    }

    /// Flips preview/build when the embedded sim + gzweb are already live — no `spawnWorld`.
    @discardableResult
    private func applyBuilderSessionModeWithoutRespawn(_ mode: WorldBuilderSessionMode) -> Bool {
        guard let id = resolveActiveBuilderWorldID() else { return false }
        activeGazeboWorldID = id
        guard isEmbeddedViewportLive else { return false }
        let wasBuild = sessionMode == .build
        sessionMode = mode
        if wasBuild, mode == .preview {
            persistObstacleManifestToDiskNow()
        }
        statusText = ""
        return true
    }

    /// Resolves the alive Gazebo row for the open builder world (manifest id or world file path).
    private func resolveActiveBuilderWorldID() -> UUID? {
        if let id = activeGazeboWorldID, gazebo?.isWorldAlive(id: id) == true {
            return id
        }
        guard let gazebo, let worldURL = draftWorldSourceURL ?? selectedPackage?.worldFileURL() else {
            return nil
        }
        let envID = isEditingNewDraft ? nil : selectedPackageID
        return gazebo.firstAliveBuilderWorldID(
            environmentID: envID,
            worldFilePath: worldURL.path
        )
    }

    private func syncBuilderLiveObstacleRegistryIfNeeded() async {
        if needsObstacleReconcile() {
            await syncManifestObstaclesToLiveSimIfNeeded()
        } else if obstaclesSnapshot.isEmpty {
            await stripOrphanLiveObstaclesIfNeeded()
        }
    }

    /// One headless sim per open world; preview/build toggles do not respawn unless the floor footprint changed.
    private func ensureBuilderGazeboRunning() async {
        if let inFlight = ensureBuilderGazeboInFlight {
            await inFlight.value
            return
        }
        let task = Task { @MainActor in
            defer { ensureBuilderGazeboInFlight = nil }
            if builderEmbeddedSessionMatchesOpenWorld() {
                if let id = resolveActiveBuilderWorldID() {
                    activeGazeboWorldID = id
                }
                await syncBuilderLiveObstacleRegistryIfNeeded()
                return
            }
            await startGazebo()
        }
        ensureBuilderGazeboInFlight = task
        await task.value
    }

    /// Manifest floor size changed — drop the live sim so the next preview reloads `world.sdf`.
    func floorSizeDidChange() {
        loadedGazeboFloorSizeLabel = nil
        if activeGazeboWorldID != nil {
            Task { await stopGazeboSession() }
        }
    }

    private func builderEmbeddedSessionMatchesOpenWorld() -> Bool {
        guard let gazebo, let id = resolveActiveBuilderWorldID() else { return false }
        guard gazebo.isEmbeddedViewportLive(worldID: id) || gazebo.isWorldAlive(id: id) else { return false }
        guard let worldURL = draftWorldSourceURL ?? selectedPackage?.worldFileURL() else { return false }
        guard let row = gazebo.worlds.first(where: { $0.id == id }) else { return false }
        let expectedLabel = draftManifest?.floorSize.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !expectedLabel.isEmpty, loadedGazeboFloorSizeLabel == expectedLabel else { return false }
        return GazeboService.canReuseEmbeddedWorld(
            existing: row,
            worldPath: worldURL.path,
            environmentID: isEditingNewDraft ? nil : selectedPackageID,
            floorSizeLabel: expectedLabel
        )
    }

    private func startGazebo() async {
        lastError = nil
        guard draftWorldSourceURL != nil || selectedPackage?.worldFileURL() != nil else {
            lastError = "No world file selected."
            return
        }
        guard let gazebo else { return }
        if resolveActiveBuilderWorldID() != nil {
            await stopGazeboSession()
        }
        do {
            try persistBuilderSessionWorldSDFSync()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        guard let worldURL = draftWorldSourceURL else {
            lastError = "No world file selected."
            return
        }
        let envID = isEditingNewDraft ? nil : selectedPackageID
        let id = await gazebo.spawnWorld(
            purpose: .preview,
            worldURL: worldURL,
            environmentID: envID,
            floorSizeLabel: draftManifest?.floorSize
        )
        activeGazeboWorldID = id
        if id != nil {
            loadedGazeboFloorSizeLabel = draftManifest?.floorSize
            await syncManifestObstaclesToLiveSimIfNeeded()
        } else {
            loadedGazeboFloorSizeLabel = nil
            clearLiveObstacleRegistry()
            lastError = gazebo.lastError
            statusText = lastError ?? "Gazebo did not start."
        }
    }

    /// Clears selection/delete UI and refreshes the placement prototype (not a placed model).
    private func resetObstacleEditorState(closePanel: Bool) {
        obstacleDeletingID = nil
        pendingObstacleDeleteID = nil
        obstacleSelectedID = nil
        obstacleEditSyncTask?.cancel()
        resetObstaclePlacementPrototype()
        if closePanel, openSceneToolPanel == .obstacleEditor {
            closeSceneToolPanel()
        } else {
            bumpObstacleViewportRevision()
        }
    }

    private func resetObstaclePlacementPrototype() {
        obstaclePlacementDraft = TrainingEnvironmentObstacleRecord.defaults(for: obstaclePlacementDraft.kind)
    }

    /// Removes `guardian_obstacle_*` models from the live sim when the manifest list is empty.
    private func stripOrphanLiveObstaclesIfNeeded() async {
        guard obstaclesSnapshot.isEmpty, let worldID = activeGazeboWorldID, let gazebo else { return }
        _ = await gazebo.stripAllGuardianObstacleModelsFromLiveSim(worldID: worldID, manifest: [])
        clearLiveObstacleRegistry()
        bumpObstacleViewportRevision()
    }

    func saveDraft() {
        lastError = nil
        guard var manifest = draftManifest else { return }
        if draftIsReadOnly {
            lastError = TrainingEnvironmentAuthoringError.bundledReadOnly.errorDescription
            return
        }
        let wasBlankNewWorld = isEditingNewDraft && draftWorldSourceURL == nil
        manifest.displayName = manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEditingNewDraft {
            let slug = TrainingEnvironmentAuthoring.slugFromDisplayName(manifest.displayName)
            manifest.id = TrainingEnvironmentAuthoring.uniqueEnvironmentID(
                slug: slug,
                occupiedIDs: occupiedEnvironmentIDs()
            )
        } else {
            manifest.id = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            try TrainingEnvironmentAuthoring.validateManifest(manifest)
            let worldSource = try resolveWorldFileForSave(
                manifest: manifest,
                generateFromFloorSize: wasBlankNewWorld
            )
            let saved = try TrainingEnvironmentCatalogue.saveUserPackage(
                manifest: manifest,
                worldFileSourceURL: worldSource
            )
            reloadCatalogue()
            isEditingNewDraft = false
            if wasBlankNewWorld {
                selectedPackageID = nil
                draftManifest = nil
                draftWorldSourceURL = nil
                statusText = "Saved \(saved.manifest.displayName). Choose it from the library to open."
            } else {
                selectedPackageID = saved.id
                draftWorldSourceURL = saved.worldFileURL()
                draftManifest = saved.manifest
                statusText = "Saved \(saved.manifest.displayName)."
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Save failed."
        }
    }

    private func resolveWorldFileForSave(
        manifest: TrainingEnvironmentManifest,
        generateFromFloorSize: Bool
    ) throws -> URL {
        if generateFromFloorSize {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("guardian-new-world-\(UUID().uuidString).sdf")
            try TrainingEnvironmentWorldComposer.writeWorld(
                manifest: manifest,
                to: url,
                mode: .trainingRun
            )
            return url
        }
        guard let worldSource = draftWorldSourceURL else {
            throw TrainingEnvironmentAuthoringError.missingTemplateWorld
        }
        try TrainingEnvironmentWorldComposer.writeWorld(
            manifest: manifest,
            to: worldSource,
            mode: .trainingRun
        )
        return worldSource
    }

    func importFromDisk() {
        guard let imported = TrainingEnvironmentImportExportService.promptImportFolder() else { return }
        reloadCatalogue()
        selectPackage(id: imported.id)
        statusText = "Imported \(imported.manifest.displayName)."
    }

    func exportSelected() {
        guard let pkg = selectedPackage else { return }
        TrainingEnvironmentImportExportService.promptExportFolder(package: pkg)
    }

    @discardableResult
    func deleteUserPackage(id: String) -> Bool {
        lastError = nil
        let displayName = packages.first { $0.id == id }?.manifest.displayName ?? id
        do {
            try TrainingEnvironmentCatalogue.deleteUserPackage(environmentID: id)
            if selectedPackageID == id {
                closeCurrentWorld()
            }
            reloadCatalogue()
            statusText = "Deleted \(displayName)."
            toastCenter?.show("Deleted \(displayName).", style: .success)
            return true
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            toastCenter?.show(lastError ?? "Could not delete world.", style: .error)
            return false
        }
    }

    private func occupiedEnvironmentIDs() -> Set<String> {
        Set(packages.map(\.id))
    }
}
