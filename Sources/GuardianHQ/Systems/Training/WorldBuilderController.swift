import Foundation
import SwiftUI

enum WorldBuilderSessionMode: String, Equatable, Sendable {
    case idle
    case preview
    case build
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

    /// Half side length (m) of the open world's square floor for gzweb birdseye framing.
    var activeFloorHalfExtentM: Double {
        let floorRaw = selectedPackage?.manifest.floorSize ?? draftManifest?.floorSize
        let floor = TrainingEnvironmentFloorSize.resolved(from: floorRaw)
        return floor.floorSideM / 2
    }

    var canEditManifestInDrawer: Bool {
        draftManifest != nil && !draftIsReadOnly
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
        stopAllBuilderGazeboSessions()
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
        stopGazeboSession()
        selectedPackageID = id
        isEditingNewDraft = false
        sessionMode = .idle
        loadDraftFromSelection()
        Task { await syncEmbeddedViewport() }
    }

    /// Prepares an unsaved world for the New drawer only — does not open Gazebo or the main viewport.
    func prepareNewDraftInDrawer() {
        stopGazeboSession()
        isEditingNewDraft = true
        selectedPackageID = nil
        draftWorldSourceURL = nil
        draftManifest = TrainingEnvironmentAuthoring.newDraftManifest()
        lastError = nil
        statusText = ""
    }

    func duplicateSelectedAsNewDraft() {
        guard let pkg = selectedPackage else { return }
        stopGazeboSession()
        isEditingNewDraft = true
        selectedPackageID = nil
        draftWorldSourceURL = pkg.worldFileURL()
        var manifest = pkg.manifest
        manifest.displayName = "\(manifest.displayName) copy"
        let occupied = occupiedEnvironmentIDs()
        manifest.id = TrainingEnvironmentAuthoring.uniqueEnvironmentID(
            slug: TrainingEnvironmentAuthoring.slugFromDisplayName(manifest.displayName),
            occupiedIDs: occupied
        )
        draftManifest = manifest
        lastError = nil
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
        stopAllBuilderGazeboSessions()
    }

    /// Stops every World Builder preview/build sim (not Training `.run` sessions).
    func stopAllBuilderGazeboSessions() {
        gazebo?.stopAllPreviewAndBuildWorlds()
        activeGazeboWorldID = nil
        sessionMode = .idle
    }

    func stopGazeboSession() {
        stopAllBuilderGazeboSessions()
    }

    /// Preview mode — same Gazebo session as build; UI/scene-edit gate only.
    func enterPreviewMode() async {
        guard GuardianGazeboWebViewerPolicy.guardOnlineOrShowToast(
            productIncludesGazebo: productIncludesGazeboWebViewer,
            toastCenter: toastCenter
        ) else { return }
        sessionMode = .preview
        await ensureBuilderGazeboRunning()
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
        sessionMode = .build
        await ensureBuilderGazeboRunning()
        if activeGazeboWorldID != nil {
            statusText = ""
        }
    }

    /// One headless sim per open world; preview/build toggles do not respawn.
    private func ensureBuilderGazeboRunning() async {
        if let id = activeGazeboWorldID, gazebo?.isWorldAlive(id: id) == true {
            return
        }
        activeGazeboWorldID = nil
        await startGazebo()
    }

    private func startGazebo() async {
        lastError = nil
        guard let worldURL = draftWorldSourceURL ?? selectedPackage?.worldFileURL() else {
            lastError = "No world file selected."
            return
        }
        guard let gazebo else { return }
        let envID = isEditingNewDraft ? nil : selectedPackageID
        let id = await gazebo.spawnWorld(
            purpose: .preview,
            worldURL: worldURL,
            environmentID: envID
        )
        activeGazeboWorldID = id
        if id == nil {
            lastError = gazebo.lastError
            statusText = lastError ?? "Gazebo did not start."
        }
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
            let floor = TrainingEnvironmentFloorSize.resolved(from: manifest.floorSize)
            let scene = TrainingEnvironmentSceneType.resolved(from: manifest.sceneType)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("guardian-new-world-\(UUID().uuidString).sdf")
            try TrainingEnvironmentAuthoring.writeNewWorldFile(floorSize: floor, sceneType: scene, to: url)
            return url
        }
        guard let worldSource = draftWorldSourceURL else {
            throw TrainingEnvironmentAuthoringError.missingTemplateWorld
        }
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

    private func occupiedEnvironmentIDs() -> Set<String> {
        Set(packages.map(\.id))
    }
}
