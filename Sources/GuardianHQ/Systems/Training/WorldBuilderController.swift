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
    /// Timestamped map / gzweb load diagnostics (World Builder debug overlay).
    @Published private(set) var mapDebugLines: [String] = []

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

    var activeZoneMaxRadiusM: Double {
        activeFloorSize.maxZoneRadiusM
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
            logMapObstaclePlace(
                "swift panel open",
                detail: "placementTool=true session=\(sessionMode.rawValue) canEdit=\(canEditScene)"
            )
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
        let maxR = activeZoneMaxRadiusM
        let clamped = min(maxR, max(WorldBuilderZoneState.minRadiusM, radiusM))
        switch zonePlacementKind {
        case .start:
            zones.start.radiusM = clamped
        case .end:
            zones.end.radiusM = clamped
        }
        logMapZones(
            "radius slider",
            detail: "active=\(zonePlacementKind.rawValue) requested=\(formatMapMetres(radiusM)) clamped=\(formatMapMetres(clamped))",
            zones: zones
        )
        let failed = commitZoneManifest(zones, to: &manifest)
        logMapZones(
            "radius commit",
            detail: failed ? "rejected (does not fit)" : "ok",
            zones: zonesSnapshot
        )
        return failed
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
    func applyZonesFromViewport(
        _ zones: WorldBuilderZonesSnapshot,
        jsOutOfBounds: Bool = false
    ) -> Bool {
        guard canEditScene, var manifest = draftManifest else { return false }
        logMapZones(
            "viewport zonesChanged",
            detail: "jsOutOfBounds=\(jsOutOfBounds)",
            zones: zones
        )
        let failed = commitZoneManifest(zones, to: &manifest)
        logMapZones(
            "viewport commit",
            detail: "swiftRejected=\(failed)",
            zones: zonesSnapshot
        )
        return failed
    }

    /// Snaps zones to the map-base square, updates draft manifest, and persists for saved user worlds.
    @discardableResult
    private func commitZoneManifest(
        _ zones: WorldBuilderZonesSnapshot,
        to manifest: inout TrainingEnvironmentManifest
    ) -> Bool {
        var proposed = zones
        let maxZoneR = activeZoneMaxRadiusM
        WorldBuilderZoneManifestSupport.clampZoneRadiiToAllowedRange(&proposed, floorSize: activeFloorSize)
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: activeFloorHalfExtentM)
        let obstacles = manifest.obstacles
        if WorldBuilderZoneBoundsCheck.zonesOverlap(proposed) {
            logMapZones(
                "commit rejected",
                detail: "zones overlap",
                zones: proposed
            )
            bumpZoneEditorRevision()
            return true
        }
        let failed = !WorldBuilderZoneBoundsCheck.snapZonesToFloor(
            &proposed,
            floor: floor,
            maxZoneRadiusM: maxZoneR,
            obstacles: obstacles
        )
        guard !failed else {
            let detail: String
            if WorldBuilderZoneBoundsCheck.zonesOverlap(proposed) {
                detail = "after snap — zones overlap"
            } else if WorldBuilderZoneBoundsCheck.zonesOverlapAnyObstacle(proposed, obstacles: obstacles) {
                detail = "after snap — zone overlaps obstacle"
            } else {
                detail = "after snap — compare centerZM to mapBaseTop=\(WorldBuilderZoneBoundsCheck.mapBaseTopZM)"
            }
            logMapZones(
                "commit rejected",
                detail: detail,
                zones: proposed
            )
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
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: activeFloorHalfExtentM)
        let zones = zonesSnapshot
        guard WorldBuilderObstacleBoundsCheck.fitsPlacement(record, floor: floor, zones: zones) else {
            toastCenter?.show(
                "Model is out of bounds or overlaps a start/end zone.",
                style: .warning
            )
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
        var clamped = WorldBuilderObstacleViewportSyncPolicy.mergingPoseUpdates(
            prior: prior,
            proposed: obstacles
        )
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
        let zones = zonesSnapshot
        let failed = !WorldBuilderObstacleBoundsCheck.snapObstaclesToFloor(&clamped, floor: floor)
            || clamped.contains { WorldBuilderObstacleBoundsCheck.overlapsAnyPlacedZone($0, zones: zones) }
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
        obstacleEditSyncTask?.cancel()
        if let id, let obstacle = obstaclesSnapshot.first(where: { $0.id == id }) {
            let needsRefresh = obstacleSelectedID != id
                || obstaclePlacementDraft.id != id
                || obstaclePlacementDraft != obstacle
            obstaclePlacementDraft = obstacle
            obstacleSelectedID = id
            if needsRefresh {
                bumpObstacleViewportRevision()
            }
        } else {
            obstacleSelectedID = id
            bumpObstacleViewportRevision()
        }
    }

    func placeObstacleAt(centerXM: Double, centerYM: Double) {
        logMapObstaclePlace(
            "swift placeObstacleAt entered",
            detail: obstaclePlaceSwiftContext(centerXM: centerXM, centerYM: centerYM)
        )
        guard canEditScene else {
            logMapObstaclePlace(
                "swift blocked",
                detail: "canEditScene=false sessionMode=\(sessionMode.rawValue) hasWorldFile=\(hasWorldFile) draftIsReadOnly=\(draftIsReadOnly)"
            )
            return
        }
        guard var manifest = draftManifest else {
            logMapObstaclePlace("swift blocked", detail: "draftManifest=nil")
            return
        }
        guard manifest.obstacles.count < TrainingEnvironmentObstacleRecord.maxCount else {
            logMapObstaclePlace("swift blocked", detail: "obstacle limit \(manifest.obstacles.count)/\(TrainingEnvironmentObstacleRecord.maxCount)")
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
            logMapObstaclePlace("swift autoZ", detail: "centerZM=\(record.centerZM)")
        }
        WorldBuilderObstacleManifestSupport.normalizeDimensions(&record)
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: activeFloorHalfExtentM)
        let zones = zonesSnapshot
        guard WorldBuilderObstacleBoundsCheck.fitsPlacement(record, floor: floor, zones: zones) else {
            logMapObstaclePlace(
                "swift blocked",
                detail: "fitsPlacement=false kind=\(record.kind.rawValue) center=(\(centerXM),\(centerYM)) floorHalf=\(activeFloorHalfExtentM)"
            )
            toastCenter?.show(
                "Model is out of bounds or overlaps a start/end zone.",
                style: .warning
            )
            return
        }
        manifest.obstacles.append(record)
        let newCount = manifest.obstacles.count
        obstacleSelectedID = nil
        obstaclePlacementDraft = TrainingEnvironmentObstacleRecord.defaults(for: record.kind)
        logMapObstaclePlace(
            "swift manifest append",
            detail: "id=\(record.id.prefix(8))… count=\(newCount) syncLive=true"
        )
        toastCenter?.show("Adding obstacle to map…", style: .info)
        commitObstacleManifest(&manifest, syncLive: true, bumpViewport: true)
        persistObstacleManifestToDiskNow()
        logMapObstaclePlace("swift placeObstacleAt done", detail: "awaiting live sim spawn")
    }

    func logObstacleEditorViewportPush() {
        let draft = obstaclePlacementDraft
        let footZ = WorldBuilderObstacleManifestSupport.footZM(for: draft)
        logMapObstaclePlace(
            "swift push editor state",
            detail: [
                "editor=\(openSceneToolPanel == .obstacleEditor)",
                "placement=\(obstaclePlacementToolActive)",
                "selected=\(obstacleSelectedID?.prefix(8) ?? "nil")",
                "count=\(obstaclesSnapshot.count)",
                "draft=\(draft.kind.rawValue) footZ=\(String(format: "%.2f", footZ))",
                "floorHalf=\(activeFloorHalfExtentM)",
            ].joined(separator: " ")
        )
    }

    private func obstaclePlaceSwiftContext(centerXM: Double, centerYM: Double) -> String {
        [
            "xy=(\(String(format: "%.2f", centerXM)),\(String(format: "%.2f", centerYM)))",
            "session=\(sessionMode.rawValue)",
            "panel=\(openSceneToolPanel?.rawValue ?? "nil")",
            "placementTool=\(obstaclePlacementToolActive)",
            "manifestObstacles=\(obstaclesSnapshot.count)",
            "gazeboWorld=\(activeGazeboWorldID?.uuidString.prefix(8) ?? "nil")",
        ].joined(separator: " ")
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

    /// Duplicates a placed obstacle at the same pose (new id). Selects the clone on success.
    func cloneObstacle(id: String) {
        guard canEditScene, var manifest = draftManifest else { return }
        guard let source = manifest.obstacles.first(where: { $0.id == id }) else { return }
        guard manifest.obstacles.count < TrainingEnvironmentObstacleRecord.maxCount else {
            toastCenter?.show("Obstacle limit reached (100).", style: .warning)
            return
        }
        flushObstacleEditSyncNow()
        var record = source
        record.id = TrainingEnvironmentObstacleRecord.newID()
        let scene = TrainingEnvironmentSceneType.resolved(from: manifest.sceneType)
        WorldBuilderObstacleManifestSupport.normalizeDimensions(&record)
        if record.usesAutoZ {
            record.centerZM = WorldBuilderObstacleManifestSupport.centerZMForAutoFlush(
                record: record,
                sceneType: scene
            )
        }
        manifest.obstacles.append(record)
        obstacleSelectedID = record.id
        obstaclePlacementDraft = record
        toastCenter?.show("Adding clone to map…", style: .info)
        commitObstacleManifest(&manifest, syncLive: true, bumpViewport: true)
        persistObstacleManifestToDiskNow()
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
        guard let record else {
            logMapObstaclePlace("swift spawnLive", detail: "skipped record=nil")
            return
        }
        guard let worldID = activeGazeboWorldID, let gazebo else {
            logMapObstaclePlace(
                "swift spawnLive blocked",
                detail: "worldID=\(activeGazeboWorldID?.uuidString.prefix(8) ?? "nil") gazebo=\(gazebo != nil)"
            )
            return
        }
        logMapObstaclePlace(
            "swift spawnLive start",
            detail: "id=\(record.id.prefix(8))… world=\(worldID.uuidString.prefix(8))…"
        )
        do {
            let meshDir = try obstacleMeshDirectoryURL()
            let gazeboName = try await gazebo.spawnWorldBuilderObstacle(
                worldID: worldID,
                record: record,
                meshDirectory: meshDir
            )
            registerLiveObstacle(id: record.id, gazeboName: gazeboName)
            logMapObstaclePlace("swift spawnLive ok", detail: "gazeboModel=\(gazeboName)")
            if announceSuccess {
                toastCenter?.show("Obstacle added to map.", style: .success)
            }
        } catch {
            unregisterLiveObstacle(id: record.id)
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = message
            logMapObstaclePlace("swift spawnLive failed", detail: message)
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
        gazebo.embeddedMapLogHandler = { [weak self] line in
            self?.logMap(line)
        }
        reloadCatalogue()
        logMap("World Builder attach — runtimeAvailable=\(gazebo.runtimeAvailable) gzwebInProduct=\(productIncludesGazeboWebViewer)")
        logMap(viewerAssetsLine())
    }

    func logMap(_ message: String) {
        mapDebugLines.append(WorldBuilderMapDebugLog.formattedLine(message))
        if mapDebugLines.count > WorldBuilderMapDebugLog.maxLines {
            mapDebugLines.removeFirst(mapDebugLines.count - WorldBuilderMapDebugLog.maxLines)
        }
    }

    /// Traces gzweb obstacle placement gestures and ``placeObstacleAt(centerXM:centerYM:)`` gates.
    func logMapObstaclePlace(_ step: String, detail: String? = nil) {
        logMap(WorldBuilderMapDebugLog.obstaclePlaceLine(step, detail: detail))
    }

    func logMapZones(
        _ step: String,
        detail: String? = nil,
        zones: WorldBuilderZonesSnapshot
    ) {
        let summary = WorldBuilderMapDebugLog.zoneSnapshotSummary(
            zones: zones,
            floorHalfM: activeFloorHalfExtentM
        )
        let combined: String
        if let detail, !detail.isEmpty {
            combined = "\(detail); \(summary)"
        } else {
            combined = summary
        }
        logMap(WorldBuilderMapDebugLog.zoneOverlayLine(step, detail: combined))
    }

    private func formatMapMetres(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    func clearMapDebugLog() {
        mapDebugLines.removeAll(keepingCapacity: true)
    }

    func noteEmbeddedViewport(_ state: GazeboEmbeddedViewportState?) {
        guard let state else {
            logMap("embedded viewport state: nil")
            logMapEmbeddedViewportGate()
            return
        }
        let phase: String
        switch state.phase {
        case .starting:
            phase = "starting"
        case .live:
            phase = "live"
        case .failed(let detail):
            phase = "failed — \(detail)"
        }
        logMap(
            "embedded viewport — id \(state.worldID.uuidString.prefix(8))… port \(state.websocketPort) sdf \"\(state.gazeboWorldName)\" phase \(phase)"
        )
        logMapEmbeddedViewportGate()
    }

    func logMapEmbeddedViewportGate() {
        reconcileActiveBuilderWorldIfNeeded()
        var parts: [String] = []
        if !hasOpenWorld {
            parts.append("no open world")
        }
        if let gazebo, !gazebo.runtimeAvailable {
            parts.append("runtime unavailable")
        }
        if !productIncludesGazeboWebViewer {
            parts.append("product omits gzweb bundle")
        }
        if GuardianBundledResourceLocator.gazeboWebViewerHTMLURL() == nil {
            parts.append("guardian_viewer.html missing")
        }
        guard let resolvedID = resolvedEmbeddedWorldID else {
            parts.append("no resolved builder world id")
            logMap("map gate: \(parts.joined(separator: "; "))")
            return
        }
        parts.append("resolvedWorldID=\(resolvedID.uuidString.prefix(8))…")
        if let viewport = gazebo?.embeddedViewport {
            if viewport.worldID != resolvedID {
                parts.append("embeddedViewport.worldID mismatch")
            }
            switch viewport.phase {
            case .starting:
                parts.append("phase=starting (spinner)")
            case .live:
                parts.append("phase=live (webview)")
            case .failed(let detail):
                parts.append("phase=failed: \(detail)")
            }
        } else {
            parts.append("embeddedViewport=nil (spinner)")
        }
        if !isEmbeddedViewportLive {
            parts.append("isEmbeddedViewportLive=false")
        }
        logMap("map gate: \(parts.joined(separator: "; "))")
    }

    private func viewerAssetsLine() -> String {
        if let url = GuardianBundledResourceLocator.gazeboWebViewerHTMLURL() {
            let dist = url.deletingLastPathComponent().appendingPathComponent("dist", isDirectory: true)
            let distOK = FileManager.default.fileExists(atPath: dist.path)
            return "viewer assets — \(url.path) dist=\(distOK ? "ok" : "missing")"
        }
        return "viewer assets — guardian_viewer.html missing from bundle"
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
        logMap("syncEmbeddedViewport — sessionMode=\(sessionMode.rawValue) hasWorldFile=\(hasWorldFile)")
        guard GuardianGazeboWebViewerPolicy.guardOnlineOrShowToast(
            productIncludesGazebo: productIncludesGazeboWebViewer,
            toastCenter: toastCenter
        ) else {
            logMap("syncEmbeddedViewport blocked — gzweb not in this product build")
            return
        }
        guard gazebo?.runtimeAvailable == true, hasWorldFile else {
            logMap(
                "syncEmbeddedViewport skipped — runtimeAvailable=\(gazebo?.runtimeAvailable ?? false) hasWorldFile=\(hasWorldFile)"
            )
            return
        }
        if sessionMode == .idle {
            sessionMode = .preview
        }
        await ensureBuilderGazeboRunning()
        noteEmbeddedViewport(gazebo?.embeddedViewport)
    }

    func selectPackage(id: String) {
        Task { await selectPackageAndPrepareViewport(id: id) }
    }

    private func selectPackageAndPrepareViewport(id: String) async {
        logMap("selectPackage — id \(id)")
        flushPendingWorldBuilderPersistence()
        GuardianGazeboOrphanBlitz.suppressDuringEmbeddedMapHandoff()
        await stopGazeboSession()
        loadedGazeboFloorSizeLabel = nil
        resetObstacleEditorState(closePanel: true)
        reloadCatalogue()
        selectedPackageID = id
        isEditingNewDraft = false
        sessionMode = .idle
        loadDraftFromSelection()
        if let url = draftWorldSourceURL ?? selectedPackage?.worldFileURL() {
            logMap("world file — \(url.path)")
        } else {
            logMap("world file — missing after loadDraftFromSelection")
        }
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
        sessionMode = .idle
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
        gazebo?.embeddedMapLogHandler = nil
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

    /// Reuses an already-running preview/build session when the embedded viewport is live but this controller lost `activeGazeboWorldID` (same pattern as Training ``reconcileActiveGazeboRunWorldIfNeeded()``).
    func reconcileActiveBuilderWorldIfNeeded() {
        guard hasOpenWorld, let gazebo else { return }
        if let worldID = activeGazeboWorldID,
           gazebo.isEmbeddedViewportLive(worldID: worldID) || gazebo.isWorldAlive(id: worldID) {
            return
        }
        if let viewport = gazebo.embeddedViewport,
           gazebo.isEmbeddedViewportLive(worldID: viewport.worldID) {
            activeGazeboWorldID = viewport.worldID
            return
        }
        guard let worldURL = draftWorldSourceURL ?? selectedPackage?.worldFileURL() else { return }
        let envID = isEditingNewDraft ? nil : selectedPackageID
        if let id = gazebo.firstAliveBuilderWorldID(
            environmentID: envID,
            worldFilePath: worldURL.path
        ) {
            activeGazeboWorldID = id
        }
    }

    /// True when the World Builder map can show the embedded gzweb viewport (never starts Gazebo here).
    var isBuilderEmbeddedWorldReadyForMap: Bool {
        reconcileActiveBuilderWorldIfNeeded()
        guard let gazebo else { return false }
        if let worldID = activeGazeboWorldID,
           gazebo.isEmbeddedViewportLive(worldID: worldID) {
            return true
        }
        if let viewport = gazebo.embeddedViewport,
           gazebo.isEmbeddedViewportLive(worldID: viewport.worldID) {
            activeGazeboWorldID = viewport.worldID
            return true
        }
        return false
    }

    /// Embedded gzweb state for the map panel after reconciliation (Formation / Training viewport pattern).
    var builderEmbeddedViewportForMap: GazeboEmbeddedViewportState? {
        guard isBuilderEmbeddedWorldReadyForMap,
              let viewport = gazebo?.embeddedViewport
        else { return nil }
        return viewport
    }

    /// Gazebo row id for the open builder world (tracked id or rediscovered alive session).
    var resolvedEmbeddedWorldID: UUID? {
        reconcileActiveBuilderWorldIfNeeded()
        return activeGazeboWorldID
    }

    /// Embedded gzweb viewport is ready for camera and build tools (not still starting).
    var isEmbeddedViewportLive: Bool {
        isBuilderEmbeddedWorldReadyForMap
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
        reconcileActiveBuilderWorldIfNeeded()
        return activeGazeboWorldID
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
            logMap("ensureBuilderGazeboRunning — awaiting in-flight spawn")
            await inFlight.value
            return
        }
        let task = Task { @MainActor in
            defer { ensureBuilderGazeboInFlight = nil }
            if builderEmbeddedSessionMatchesOpenWorld() {
                logMap("ensureBuilderGazeboRunning — reusing embedded session")
                reconcileActiveBuilderWorldIfNeeded()
                await syncBuilderLiveObstacleRegistryIfNeeded()
                return
            }
            logMap("ensureBuilderGazeboRunning — starting new gz sim + websocket bridge")
            await startGazebo()
        }
        ensureBuilderGazeboInFlight = task
        await task.value
    }

    /// Manifest floor size changed — drop the live sim so the next preview reloads `world.sdf`.
    func floorSizeDidChange() {
        loadedGazeboFloorSizeLabel = nil
        reclampDraftZonesToActiveFloorSizeIfNeeded()
        if activeGazeboWorldID != nil {
            Task { await stopGazeboSession() }
        }
    }

    /// Shrinks zone radii when the floor preset lowers the editor max (e.g. micro → 25 m).
    private func reclampDraftZonesToActiveFloorSizeIfNeeded() {
        guard var manifest = draftManifest else { return }
        var zones = WorldBuilderZoneManifestSupport.zones(from: manifest)
        let before = zones
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: activeFloorHalfExtentM)
        let maxR = activeZoneMaxRadiusM
        WorldBuilderZoneManifestSupport.clampZoneRadiiToAllowedRange(&zones, floorSize: activeFloorSize)
        _ = WorldBuilderZoneBoundsCheck.snapZonesToFloor(
            &zones,
            floor: floor,
            maxZoneRadiusM: maxR,
            obstacles: manifest.obstacles
        )
        guard zones != before,
              !WorldBuilderZoneBoundsCheck.zonesOverlap(zones),
              !WorldBuilderZoneBoundsCheck.zonesOverlapAnyObstacle(zones, obstacles: manifest.obstacles)
        else { return }
        WorldBuilderZoneManifestSupport.apply(zones, to: &manifest)
        draftManifest = manifest
        bumpZoneEditorRevision()
    }

    private func builderEmbeddedSessionMatchesOpenWorld() -> Bool {
        guard let gazebo, let id = resolveActiveBuilderWorldID() else {
            logMap("reuse check — no alive builder world id")
            return false
        }
        guard gazebo.isEmbeddedViewportLive(worldID: id) || gazebo.isWorldAlive(id: id) else {
            logMap("reuse check — world \(id.uuidString.prefix(8))… not live in sim or viewport")
            return false
        }
        guard let worldURL = draftWorldSourceURL ?? selectedPackage?.worldFileURL() else {
            logMap("reuse check — no world file URL")
            return false
        }
        guard let row = gazebo.worlds.first(where: { $0.id == id }) else {
            logMap("reuse check — world row missing")
            return false
        }
        let expectedLabel = draftManifest?.floorSize.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !expectedLabel.isEmpty, loadedGazeboFloorSizeLabel == expectedLabel else {
            logMap(
                "reuse check — floor size mismatch (loaded=\(loadedGazeboFloorSizeLabel ?? "nil") expected=\(expectedLabel))"
            )
            return false
        }
        let reuse = GazeboService.canReuseEmbeddedWorld(
            existing: row,
            worldPath: worldURL.path,
            environmentID: isEditingNewDraft ? nil : selectedPackageID,
            floorSizeLabel: expectedLabel
        )
        logMap("reuse check — canReuse=\(reuse)")
        return reuse
    }

    private func startGazebo() async {
        lastError = nil
        guard draftWorldSourceURL != nil || selectedPackage?.worldFileURL() != nil else {
            lastError = "No world file selected."
            logMap("startGazebo aborted — no world file")
            return
        }
        guard let gazebo else {
            logMap("startGazebo aborted — GazeboService not attached")
            return
        }
        if resolveActiveBuilderWorldID() != nil {
            logMap("startGazebo — stopping prior builder session")
            await stopGazeboSession()
        }
        do {
            try persistBuilderSessionWorldSDFSync()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logMap("startGazebo aborted — persist world.sdf failed: \(lastError ?? "")")
            return
        }
        guard let worldURL = draftWorldSourceURL else {
            lastError = "No world file selected."
            logMap("startGazebo aborted — draftWorldSourceURL nil after persist")
            return
        }
        let envID = isEditingNewDraft ? nil : selectedPackageID
        logMap("startGazebo — spawnWorld preview envID=\(envID ?? "draft") path \(worldURL.path)")
        let id = await gazebo.spawnWorld(
            purpose: .preview,
            worldURL: worldURL,
            environmentID: envID,
            floorSizeLabel: draftManifest?.floorSize
        )
        activeGazeboWorldID = id
        if id != nil {
            loadedGazeboFloorSizeLabel = draftManifest?.floorSize
            logMap("startGazebo — spawnWorld returned \(id!.uuidString.prefix(8))…")
            reconcileActiveBuilderWorldIfNeeded()
            await syncManifestObstaclesToLiveSimIfNeeded()
        } else {
            loadedGazeboFloorSizeLabel = nil
            clearLiveObstacleRegistry()
            lastError = gazebo.lastError
            statusText = lastError ?? "Gazebo did not start."
            logMap("startGazebo failed — \(lastError ?? "unknown")")
        }
        noteEmbeddedViewport(gazebo.embeddedViewport)
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
        let savingNewDraftPackage = isEditingNewDraft
        let generateFromFloorSize = savingNewDraftPackage && draftWorldSourceURL == nil
        manifest.displayName = manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if savingNewDraftPackage {
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
                generateFromFloorSize: generateFromFloorSize
            )
            let saved = try TrainingEnvironmentCatalogue.saveUserPackage(
                manifest: manifest,
                worldFileSourceURL: worldSource
            )
            reloadCatalogue()
            isEditingNewDraft = false
            if savingNewDraftPackage {
                selectedPackageID = nil
                draftManifest = nil
                draftWorldSourceURL = nil
                sessionMode = .idle
                statusText = "Saved \(saved.manifest.displayName). Choose it from the library to open."
                Task { await stopGazeboSession() }
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
