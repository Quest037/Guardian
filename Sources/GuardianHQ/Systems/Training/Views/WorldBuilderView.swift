import SwiftUI

/// World Builder — sub-bar, full-width Gazebo viewport for **world authoring** (terrain, obstacles, zones).
/// Uses ``GazeboSessionPurpose/build`` or ``preview`` — **no vehicle proxies**; sized SITL blocks spawn only from
/// Training / Formation ``.run`` sessions (see ``GazeboService/spawnVehicleProxy``).
struct WorldBuilderView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var gazebo: GazeboService
    @StateObject private var builder = WorldBuilderController()
    @StateObject private var viewportCamera = GazeboWebViewportCameraBridge()
    @StateObject private var viewportZones = GazeboWebViewportZoneBridge()
    @StateObject private var viewportObstacles = GazeboWebViewportObstacleBridge()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.guardianAppProduct) private var appProduct
    @EnvironmentObject private var appDrawer: AppDrawer
    @EnvironmentObject private var toastCenter: ToastCenter

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            subBar
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)
            viewportColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundBase)
        .onAppear {
            builder.attach(
                gazebo: gazebo,
                toastCenter: toastCenter,
                productIncludesGazeboWebViewer: appProduct.includesGazeboSimulation
            )
            pushViewportZoneState()
            pushViewportObstacleState()
            if builder.hasOpenWorld {
                Task { await builder.syncEmbeddedViewport() }
            }
        }
        .onDisappear {
            builder.leavePanel()
            appDrawer.dismiss()
        }
        .onChange(of: builder.draftManifest?.id) { _ in
            pushViewportZoneState()
            pushViewportObstacleState()
        }
        .onChange(of: builder.openSceneToolPanel) { _ in
            pushViewportZoneState()
            pushViewportObstacleState()
        }
        .onChange(of: builder.zonePlacementKind) { _ in
            pushViewportZoneState()
        }
        .onChange(of: builder.zoneEditorRevision) { _ in
            pushViewportZoneState()
        }
        .onChange(of: builder.obstacleViewportRevision) { _ in
            pushViewportObstacleState()
        }
        .onChange(of: builder.obstacleSelectedID) { _ in
            pushViewportObstacleState()
        }
        .onChange(of: builder.obstacleDeletingID) { _ in
            pushViewportObstacleState()
        }
        .onChange(of: isViewportCameraLive) { live in
            if live {
                pushViewportZoneState()
                pushViewportObstacleState()
            }
        }
        .guardianConfirmOverlay(item: obstacleDeleteBinding) { candidate in
            GuardianConfirmDanger(
                title: "Delete model?",
                message: "Remove this obstacle from the world?",
                cancelTitle: "Cancel",
                confirmTitle: "Delete",
                onCancel: { builder.pendingObstacleDeleteID = nil },
                onConfirm: { Task { await builder.confirmDeleteObstacle(id: candidate.id) } }
            )
        }
        .guardianConfirmOverlay(item: zoneDeleteBinding) { kind in
            GuardianConfirmDanger(
                title: "Delete zone?",
                message: "Remove the \(kind.displayName.lowercased()) zone from this world?",
                cancelTitle: "Cancel",
                confirmTitle: "Delete",
                onCancel: { builder.pendingZoneDeleteKind = nil },
                onConfirm: {
                    builder.confirmDeleteZone(kind: kind)
                    pushViewportZoneState()
                }
            )
        }
        .onChange(of: builder.sessionMode) { mode in
            if mode != .build {
                builder.closeSceneToolPanel()
            }
        }
    }

    private func pushViewportZoneState() {
        let zones = builder.draftManifest.map(WorldBuilderZoneManifestSupport.zones(from:))
            ?? .empty
        viewportZones.pushEditorState(
            placementActive: builder.zonePlacementToolActive,
            tapToEditEnabled: builder.canEditScene && builder.openSceneToolPanel != .obstacleEditor,
            placementKind: builder.zonePlacementKind,
            zones: zones,
            mapHalfExtentM: builder.activeFloorHalfExtentM
        )
    }

    private func pushViewportObstacleState() {
        let obstacles = builder.obstaclesSnapshot
        viewportObstacles.pushEditorState(
            editorActive: builder.openSceneToolPanel == .obstacleEditor,
            placementActive: builder.obstaclePlacementToolActive,
            selectedID: builder.obstacleSelectedID,
            draft: builder.obstaclePlacementDraft,
            obstacles: obstacles,
            mapHalfExtentM: builder.activeFloorHalfExtentM,
            deletingID: builder.obstacleDeletingID
        )
    }

    private var obstacleDeleteBinding: Binding<WorldBuilderObstacleDeleteCandidate?> {
        Binding(
            get: {
                builder.pendingObstacleDeleteID.map(WorldBuilderObstacleDeleteCandidate.init(id:))
            },
            set: { builder.pendingObstacleDeleteID = $0?.id }
        )
    }

    private var zoneDeleteBinding: Binding<WorldBuilderZoneKind?> {
        Binding(
            get: { builder.pendingZoneDeleteKind },
            set: { builder.pendingZoneDeleteKind = $0 }
        )
    }

    // MARK: - Sub-bar

    private var subBar: some View {
        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            HStack(spacing: GuardianSpacing.sm) {
                if builder.hasOpenWorld {
                    backWorldButton
                    Text(builder.subBarTitle)
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 220, alignment: .leading)
                    if showsViewportCameraControls {
                        viewportCameraControls
                    }
                } else {
                    Text("World Builder")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textPrimary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: GuardianSpacing.sm)

            HStack(spacing: GuardianSpacing.xs) {
                if builder.hasOpenWorld {
                    worldLoadedSubBarActions
                } else {
                    idleSubBarActions
                }
            }
        }
        .padding(.horizontal, GuardianSpacing.md)
        .padding(.vertical, GuardianSpacing.sm)
        .background(theme.backgroundRaised)
    }

    private var idleSubBarActions: some View {
        Group {
            subBarIconButton(
                systemImage: "plus",
                accessibilityLabel: "New",
                accent: .primary,
                surface: .solid,
                action: { openNewWorldDrawer() }
            )
            .disabled(!gazebo.runtimeAvailable)
            subBarIconButton(
                systemImage: "list.bullet",
                accessibilityLabel: "Choose",
                action: { presentChooseDrawer() }
            )
            subBarIconButton(
                systemImage: "arrow.down.circle",
                accessibilityLabel: "Import",
                action: { builder.importFromDisk() }
            )
        }
    }

    private var previewModeButton: some View {
        subBarIconButton(
            systemImage: "binoculars",
            accessibilityLabel: "Preview",
            accent: builder.sessionMode == .preview ? .primary : .neutral,
            surface: builder.sessionMode == .preview ? .solid : .outline,
            action: { Task { await builder.enterPreviewMode() } }
        )
        .disabled(!gazebo.runtimeAvailable || !builder.hasWorldFile)
    }

    private var buildModeButton: some View {
        subBarIconButton(
            systemImage: "hammer",
            accessibilityLabel: "Build",
            accent: builder.sessionMode == .build ? .primary : .neutral,
            surface: builder.sessionMode == .build ? .solid : .outline,
            action: { Task { await builder.enterBuildMode() } }
        )
        .disabled(!gazebo.runtimeAvailable || !builder.hasWorldFile || builder.draftIsReadOnly || !isViewportCameraLive)
        .help(isViewportCameraLive ? "Build" : "Wait for the map to finish loading")
    }

    private var worldLoadedSubBarActions: some View {
        Group {
            if builder.canEditManifestInDrawer {
                subBarIconButton(
                    systemImage: "pencil",
                    accessibilityLabel: "Edit",
                    action: { presentEditDrawer() }
                )
            }
            previewModeButton
            buildModeButton

            if builder.sessionMode != .idle {
                subBarIconButton(
                    systemImage: "xmark",
                    accessibilityLabel: "Stop Gazebo",
                    accent: .danger,
                    surface: .outline,
                    action: {
                        builder.stopGazeboSession()
                        builder.loadDraftFromSelection()
                    }
                )
            }

            if builder.selectedPackage != nil {
                subBarIconButton(
                    systemImage: "doc.on.doc",
                    accessibilityLabel: "Duplicate",
                    action: {
                        builder.duplicateSelectedAsNewDraft()
                        presentNewDrawer()
                    }
                )
                subBarIconButton(
                    systemImage: "arrow.up.circle",
                    accessibilityLabel: "Export",
                    action: { builder.exportSelected() }
                )
            }
        }
    }

    private var showsViewportCameraControls: Bool {
        builder.hasOpenWorld && builder.sessionMode != .idle
    }

    private var isViewportCameraLive: Bool {
        builder.isEmbeddedViewportLive
    }

    private var viewportCameraControls: some View {
        HStack(spacing: GuardianSpacing.xs) {
            subBarIconButton(
                systemImage: "view.3d",
                accessibilityLabel: "Oblique view preset",
                action: { viewportCamera.trigger(.defaultView) }
            )
            .disabled(!isViewportCameraLive)
            subBarIconButton(
                systemImage: "view.2d",
                accessibilityLabel: "Top-down view preset",
                action: { viewportCamera.trigger(.birdseye) }
            )
            .disabled(!isViewportCameraLive)
        }
    }

    private var backWorldButton: some View {
        subBarIconButton(
            systemImage: "chevron.left",
            accessibilityLabel: "Back",
            action: { builder.closeCurrentWorld() }
        )
    }

    private func subBarIconButton(
        systemImage: String,
        accessibilityLabel: String,
        accent: GuardianThemeAccent = .neutral,
        surface: GuardianChromeSurface = .outline,
        action: @escaping () -> Void
    ) -> some View {
        GuardianThemedButton(
            accent: accent,
            surface: surface,
            size: .small,
            shape: .cornered,
            contentSizing: .squareToolbarCell,
            action: action,
            label: {
                Image(systemName: systemImage)
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
            }
        )
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .guardianPointerOnHover()
    }

    // MARK: - Viewport

    private var viewportColumn: some View {
        Group {
            if !builder.hasOpenWorld {
                emptyViewportPrompt
            } else if !gazebo.runtimeAvailable {
                runtimeMissingViewport
                    .padding(GuardianSpacing.lg)
            } else {
                gazeboViewportWithBuildRail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var buildToolbarRailVisible: Bool {
        builder.sessionMode == .build && builder.hasWorldFile
    }

    private var buildToolbarRailWidth: CGFloat {
        GuardianChromeSize.small.controlOuterHeight * 1.5
    }

    /// Swift spinner until the web viewer is mounted; gzweb HTML overlay handles load after that.
    private var showsEmbeddedViewportSpinner: Bool {
        guard builder.hasOpenWorld else { return false }
        guard let worldID = builder.resolvedEmbeddedWorldID,
              let viewport = gazebo.embeddedViewport,
              viewport.worldID == worldID else {
            return true
        }
        if case .live = viewport.phase { return false }
        return true
    }

    private var gazeboViewportWithBuildRail: some View {
        ZStack {
            HStack(alignment: .top, spacing: 0) {
                embeddedViewportStack
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if buildToolbarRailVisible {
                    WorldBuilderBuildToolbarRail(
                        theme: theme,
                        railWidth: buildToolbarRailWidth,
                        canInteract: builder.canEditScene,
                        zoneToolActive: builder.openSceneToolPanel == .zoneEditor,
                        obstacleToolActive: builder.openSceneToolPanel == .obstacleEditor,
                        onToggleZoneTool: { builder.toggleZoneEditorPanel() },
                        onToggleObstacleTool: { builder.toggleObstacleEditorPanel() }
                    )
                    .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .animation(GuardianMotion.drawerSlide, value: builder.sessionMode)

            if showsEmbeddedViewportSpinner {
                viewportLoadingOverlay
            }
        }
        .overlay(alignment: .topLeading) {
            sceneToolPanelOverlay
        }
        .animation(GuardianMotion.drawerSlide, value: builder.openSceneToolPanel)
    }

    @ViewBuilder
    private var sceneToolPanelOverlay: some View {
        if builder.openSceneToolPanel == .obstacleEditor, builder.canEditScene {
            WorldBuilderObstacleToolBar(
                record: builder.obstacleEditingBinding(),
                theme: theme,
                isEditingPlaced: builder.obstacleSelectedID != nil,
                obstacleCount: builder.obstaclesSnapshot.count,
                isSyncInFlight: builder.isObstacleMapRepairInFlight,
                onRepairMap: {
                    Task { await builder.repairObstacleMapAlignment() }
                },
                onClose: { builder.closeSceneToolPanel() }
            )
            .padding(.leading, GuardianSpacing.sm)
            .padding(.top, GuardianSpacing.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if builder.openSceneToolPanel == .zoneEditor, builder.canEditScene {
            WorldBuilderSceneToolBar(
                theme: theme,
                placementKind: builder.zonePlacementKind,
                zoneShape: builder.activeZoneShape,
                zoneRadiusM: builder.activeZoneRadiusM,
                onSelectPlacementKind: { builder.setZonePlacementKind($0) },
                onSelectZoneShape: { builder.setActiveZoneShape($0) },
                onZoneRadiusChange: { radius in
                    if builder.setActiveZoneRadiusM(radius) {
                        toastCenter.show("Zone does not fit on the map", style: .error)
                    }
                    pushViewportZoneState()
                },
                onClose: { builder.closeSceneToolPanel() }
            )
            .padding(.leading, GuardianSpacing.sm)
            .padding(.top, GuardianSpacing.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var embeddedViewportStack: some View {
        Group {
            if let viewport = gazebo.embeddedViewport,
               let worldID = builder.resolvedEmbeddedWorldID,
               viewport.worldID == worldID {
                GazeboWebViewportView(
                    websocketPort: viewport.websocketPort,
                    gazeboWorldName: viewport.gazeboWorldName,
                    phase: viewport.phase,
                    cameraBridge: viewportCamera,
                    cameraCommandTick: viewportCamera.tick,
                    zoneBridge: viewportZones,
                    zoneCommandTick: viewportZones.tick,
                    obstacleBridge: viewportObstacles,
                    obstacleCommandTick: viewportObstacles.tick,
                    showsCameraDebugHUD: fleetLink.isDebugEnabled,
                    groundHalfExtentM: builder.activeFloorHalfExtentM,
                    onZonesChanged: { zones, jsZoneFailed in
                        let swiftFailed = builder.applyZonesFromViewport(zones)
                        if jsZoneFailed || swiftFailed {
                            toastCenter.show("Zone does not fit on the map", style: .error)
                        }
                        viewportZones.pushZones(builder.zonesSnapshot)
                    },
                    onZoneEditRequest: { kind in
                        builder.openZoneEditorFromViewport(kind: kind)
                        pushViewportZoneState()
                    },
                    onZoneDeleteRequest: { kind in
                        builder.requestDeleteZone(kind: kind)
                    },
                    onObstaclesChanged: { obstacles, selectedID, jsOutOfBounds in
                        let prior = builder.obstaclesSnapshot
                        let sameIDs = obstacles.map(\.id) == prior.map(\.id)
                        if sameIDs {
                            if obstacles == prior {
                                builder.selectObstacleFromViewport(id: selectedID)
                                pushViewportObstacleState()
                                return
                            }
                            let swiftOutOfBounds = builder.applyObstaclesFromViewport(
                                obstacles,
                                selectedID: selectedID
                            )
                            if jsOutOfBounds || swiftOutOfBounds {
                                toastCenter.show("Out of bounds", style: .warning)
                            }
                            pushViewportObstacleState()
                            return
                        }
                        let swiftOutOfBounds = builder.applyObstaclesFromViewport(
                            obstacles,
                            selectedID: selectedID
                        )
                        if jsOutOfBounds || swiftOutOfBounds {
                            toastCenter.show("Out of bounds", style: .warning)
                        }
                        pushViewportObstacleState()
                    },
                    onObstacleDeleteRequest: { id in
                        builder.requestDeleteObstacle(id: id)
                    },
                    onObstaclePlaceRequest: { x, y in
                        builder.placeObstacleAt(centerXM: x, centerYM: y)
                        pushViewportObstacleState()
                    }
                )
                .id(worldID)
            } else {
                viewportPreparingSurface
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var viewportPreparingSurface: some View {
        Color.black
    }

    private var viewportLoadingOverlay: some View {
        ZStack {
            theme.backgroundRaised.opacity(0.92)
            VStack(spacing: GuardianSpacing.md) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading scene…")
                    .font(GuardianTypography.Scale.body.font())
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(GuardianSpacing.lg)
        }
    }

    private var runtimeMissingViewport: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            Text("Gazebo is not available")
                .font(GuardianTypography.font(.sectionHeadingSemibold))
                .foregroundStyle(theme.textPrimary)
            Text("Run make gazebo-runtime after installing Gazebo Harmonic, then rebuild.")
                .font(GuardianTypography.Scale.body.font())
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var emptyViewportPrompt: some View {
        GuardianEmptyState(
            systemImage: "globe",
            title: "No World Open",
            detail: "Choose an environment from your library, import a package, or create a new world.",
            primaryTitle: gazebo.runtimeAvailable ? "New World" : nil,
            primaryAction: gazebo.runtimeAvailable ? { openNewWorldDrawer() } : nil,
            secondaryTitle: "Choose",
            secondaryAction: { presentChooseDrawer() }
        )
    }

    // MARK: - Drawers

    private func presentChooseDrawer() {
        appDrawer.present(title: "Choose world", preferredWidth: 360) {
            WorldBuilderChooseDrawerContent(
                builder: builder,
                onSelect: { id in
                    builder.selectPackage(id: id)
                    appDrawer.dismiss()
                }
            )
        }
    }

    private func openNewWorldDrawer() {
        builder.prepareNewDraftInDrawer()
        presentNewDrawer()
    }

    private func presentNewDrawer() {
        appDrawer.present(title: "New world", preferredWidth: 400) {
            WorldBuilderManifestDrawerContent(
                builder: builder,
                onSaved: { appDrawer.dismiss() }
            )
        }
    }

    private func presentEditDrawer() {
        appDrawer.present(title: "Environment", preferredWidth: 400) {
            WorldBuilderManifestDrawerContent(
                builder: builder,
                onSaved: { appDrawer.dismiss() }
            )
        }
    }
}

// MARK: - Choose drawer

private struct WorldBuilderObstacleDeleteCandidate: Identifiable, Equatable {
    let id: String
}

private struct WorldBuilderDeleteEnvironmentCandidate: Identifiable, Equatable {
    let id: String
    let displayName: String
}

private struct WorldBuilderChooseDrawerContent: View {
    @ObservedObject var builder: WorldBuilderController
    let onSelect: (String) -> Void

    @State private var deleteConfirmCandidate: WorldBuilderDeleteEnvironmentCandidate?

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                if builder.packages.isEmpty {
                    Text("No environments installed.")
                        .font(GuardianTypography.Scale.body.font())
                        .foregroundStyle(theme.textSecondary)
                } else {
                    ForEach(builder.packages) { pkg in
                        WorldBuilderEnvironmentChooseCard(
                            package: pkg,
                            isSelected: builder.selectedPackageID == pkg.id,
                            onOpen: { onSelect(pkg.id) },
                            onDelete: pkg.source == .bundled
                                ? nil
                                : {
                                    deleteConfirmCandidate = WorldBuilderDeleteEnvironmentCandidate(
                                        id: pkg.id,
                                        displayName: pkg.manifest.displayName
                                    )
                                }
                        )
                    }
                }
            }
            .padding(GuardianSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .guardianConfirmOverlay(item: $deleteConfirmCandidate) { candidate in
            GuardianConfirmDanger(
                title: "Delete world?",
                message: "Delete “\(candidate.displayName)”? This removes the world package from your library.",
                cancelTitle: "Cancel",
                confirmTitle: "Delete",
                onCancel: { deleteConfirmCandidate = nil },
                onConfirm: {
                    let id = candidate.id
                    deleteConfirmCandidate = nil
                    _ = builder.deleteUserPackage(id: id)
                }
            )
        }
    }

}

// MARK: - Choose drawer card

private struct WorldBuilderEnvironmentChooseCard: View {
    let package: TrainingEnvironmentPackage
    let isSelected: Bool
    let onOpen: () -> Void
    let onDelete: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var sceneType: TrainingEnvironmentSceneType {
        TrainingEnvironmentSceneType.resolved(from: package.manifest.sceneType)
    }

    private var sourceLabel: String {
        package.source == .bundled ? "Bundled" : "Yours"
    }

    var body: some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: isSelected ? .primary : .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianSpacing.cardBodyInset
            ),
            body: {
                HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                    VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                        Text(package.manifest.displayName)
                            .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: GuardianSpacing.xsTight) {
                            GuardianBadge(
                                text: sourceLabel,
                                accent: .neutral,
                                paint: .light,
                                size: .small,
                                shape: .pill
                            )
                            GuardianBadge(
                                text: sceneType.displayName,
                                accent: .neutral,
                                paint: .light,
                                size: .small,
                                shape: .pill
                            )
                        }
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(GuardianSemanticColors.infoForeground)
                            .accessibilityHidden(true)
                    }

                    if let onDelete {
                        GuardianThemedButton(
                            accent: .danger,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            contentSizing: .squareToolbarCell,
                            action: onDelete,
                            label: {
                                Image(systemName: "trash")
                                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                            }
                        )
                        .help("Delete world")
                        .accessibilityLabel("Delete world")
                        .guardianPointerOnHover()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .guardianPointerOnHover()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens this world in World Builder")
    }

    private var accessibilitySummary: String {
        var parts = [package.manifest.displayName, sourceLabel, sceneType.displayName]
        if isSelected {
            parts.append("Selected")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - New / edit drawer (manifest form)

private struct WorldBuilderManifestDrawerContent: View {
    @ObservedObject var builder: WorldBuilderController
    let onSaved: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                if builder.draftManifest == nil {
                    Text("Could not load the world form.")
                        .font(GuardianTypography.Scale.body.font())
                        .foregroundStyle(theme.textSecondary)
                } else {
                    WorldBuilderManifestForm(builder: builder)
                }

                if let err = builder.lastError {
                    Text(err)
                        .font(GuardianTypography.Scale.caption.font())
                        .foregroundStyle(GuardianSemanticColors.dangerForeground)
                }

                HStack(spacing: GuardianSpacing.sm) {
                    GuardianPrimaryProminentButton(title: "Save") {
                        builder.saveDraft()
                        if builder.lastError == nil {
                            onSaved()
                        }
                    }
                    .disabled(builder.draftManifest == nil || builder.draftIsReadOnly)
                }
            }
            .padding(GuardianSpacing.md)
        }
    }
}

// MARK: - Manifest form fields

private struct WorldBuilderManifestForm: View {
    @ObservedObject var builder: WorldBuilderController

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Group {
            labelledField("Display name") {
                TextField("Name", text: displayNameBinding)
                    .textFieldStyle(.roundedBorder)
                    .disabled(builder.draftIsReadOnly)
            }
            if builder.isEditingNewDraftPackage || builder.draftManifest?.id.isEmpty == false {
                labelledField("Environment id") {
                    Text(builder.draftManifest?.id ?? "")
                        .font(GuardianTypography.Scale.body.font())
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            labelledField("Description") {
                TextField("Description", text: manifestString(\.description), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .disabled(builder.draftIsReadOnly)
            }
            if builder.isEditingNewDraftPackage {
                labelledField("Size") {
                    Picker("Size", selection: floorSizeBinding) {
                        ForEach(TrainingEnvironmentFloorSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                labelledField("Scene type") {
                    Picker("Scene type", selection: sceneTypeBinding) {
                        ForEach(TrainingEnvironmentSceneType.allCases) { scene in
                            Text(scene.displayName).tag(scene)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var floorSizeBinding: Binding<TrainingEnvironmentFloorSize> {
        Binding(
            get: {
                TrainingEnvironmentFloorSize.resolved(from: builder.draftManifest?.floorSize)
            },
            set: { newValue in
                guard var manifest = builder.draftManifest else { return }
                manifest.floorSize = newValue.rawValue
                builder.draftManifest = manifest
            }
        )
    }

    private var sceneTypeBinding: Binding<TrainingEnvironmentSceneType> {
        Binding(
            get: {
                TrainingEnvironmentSceneType.resolved(from: builder.draftManifest?.sceneType)
            },
            set: { newValue in
                guard var manifest = builder.draftManifest else { return }
                manifest.sceneType = newValue.rawValue
                builder.draftManifest = manifest
            }
        )
    }

    private var displayNameBinding: Binding<String> {
        Binding(
            get: { builder.draftManifest?.displayName ?? "" },
            set: { newValue in
                guard var manifest = builder.draftManifest else { return }
                manifest.displayName = newValue
                if builder.isEditingNewDraftPackage {
                    manifest.id = TrainingEnvironmentAuthoring.slugFromDisplayName(newValue)
                }
                builder.draftManifest = manifest
            }
        )
    }

    private func manifestString(_ keyPath: WritableKeyPath<TrainingEnvironmentManifest, String>) -> Binding<String> {
        Binding(
            get: { builder.draftManifest?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard var manifest = builder.draftManifest else { return }
                manifest[keyPath: keyPath] = newValue
                builder.draftManifest = manifest
            }
        )
    }

    private func labelledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            Text(title)
                .font(GuardianTypography.Scale.caption.font(weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            content()
        }
    }
}

// MARK: - Build toolbar rail

/// Trailing strip beside the Gazebo viewport in World Builder **build** mode (not preview).
private struct WorldBuilderBuildToolbarRail: View {
    let theme: GuardianThemePalette
    let railWidth: CGFloat
    let canInteract: Bool
    let zoneToolActive: Bool
    let obstacleToolActive: Bool
    let onToggleZoneTool: () -> Void
    let onToggleObstacleTool: () -> Void

    var body: some View {
        VStack(spacing: GuardianSpacing.xs) {
            GuardianThemedButton(
                accent: zoneToolActive ? .primary : .neutral,
                surface: zoneToolActive ? .solid : .outline,
                size: .small,
                shape: .cornered,
                contentSizing: .squareToolbarCell,
                action: onToggleZoneTool,
                label: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                }
            )
            .disabled(!canInteract)
            .accessibilityLabel("Start and end zones")
            .help("Add start and end zones on the map")
            .guardianPointerOnHover()

            GuardianThemedButton(
                accent: obstacleToolActive ? .primary : .neutral,
                surface: obstacleToolActive ? .solid : .outline,
                size: .small,
                shape: .cornered,
                contentSizing: .squareToolbarCell,
                action: onToggleObstacleTool,
                label: {
                    Image(systemName: "cube")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                }
            )
            .disabled(!canInteract)
            .accessibilityLabel("Obstacle models")
            .help("Place static obstacle models on the map")
            .guardianPointerOnHover()

            Spacer(minLength: 0)
        }
        .padding(.vertical, GuardianSpacing.xs)
        .frame(width: railWidth)
        .frame(maxHeight: .infinity)
        .background(theme.backgroundRaised)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(width: 1)
        }
    }
}

// MARK: - Scene tool bar (viewport overlay)

/// Optional toolbar over the top-right of the Gazebo viewport (opened from the build rail).
private struct WorldBuilderSceneToolBar: View {
    let theme: GuardianThemePalette
    let placementKind: WorldBuilderZoneKind
    let zoneShape: TrainingEnvironmentZoneShape
    let zoneRadiusM: Double
    let onSelectPlacementKind: (WorldBuilderZoneKind) -> Void
    let onSelectZoneShape: (TrainingEnvironmentZoneShape) -> Void
    let onZoneRadiusChange: (Double) -> Void
    let onClose: () -> Void

    private static let radiusRangeM = WorldBuilderZoneState.minRadiusM ... WorldBuilderZoneState.maxRadiusM

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            HStack(spacing: GuardianSpacing.xs) {
                Text("Zones")
                    .font(GuardianTypography.Scale.caption.font(weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(GuardianTypography.Scale.caption.font(weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .accessibilityLabel("Close zone tools")
            }

            sceneToolPicker(
                title: "Type",
                selection: placementKind,
                options: WorldBuilderZoneKind.allCases,
                label: { $0.displayName },
                onSelect: onSelectPlacementKind
            )

            sceneToolPicker(
                title: "Shape",
                selection: zoneShape,
                options: TrainingEnvironmentZoneShape.allCases,
                label: { $0 == .circle ? "Circle" : "Square" },
                onSelect: onSelectZoneShape
            )

            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                HStack {
                    Text("Radius")
                        .font(GuardianTypography.Scale.caption.font())
                        .foregroundStyle(theme.textTertiary)
                    Spacer(minLength: 0)
                    Text("\(Int(zoneRadiusM.rounded())) m")
                        .font(GuardianTypography.Scale.caption.font(weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { zoneRadiusM },
                        set: { onZoneRadiusChange($0) }
                    ),
                    in: Self.radiusRangeM,
                    step: 5
                )
            }

            Text("Click map to place. Drag zone to move. Shift+drag pans, drag rotates.")
                .font(GuardianTypography.Scale.caption.font())
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(GuardianSpacing.sm)
        .frame(width: 200)
        .background(theme.backgroundRaised, in: RoundedRectangle(cornerRadius: GuardianSpacing.xs, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GuardianSpacing.xs, style: .continuous)
                .stroke(theme.borderSubtle, lineWidth: 1)
        )
    }

    private func sceneToolPicker<T: Hashable>(
        title: String,
        selection: T,
        options: [T],
        label: @escaping (T) -> String,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
            Text(title)
                .font(GuardianTypography.Scale.caption.font())
                .foregroundStyle(theme.textTertiary)
            Picker(title, selection: Binding(
                get: { selection },
                set: { onSelect($0) }
            )) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
