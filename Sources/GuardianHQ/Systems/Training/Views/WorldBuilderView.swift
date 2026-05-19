import SwiftUI

/// World Builder — sub-bar, full-width Gazebo viewport, choose/new/edit in app drawers.
struct WorldBuilderView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var gazebo: GazeboService
    @StateObject private var builder = WorldBuilderController()
    @StateObject private var viewportCamera = GazeboWebViewportCameraBridge()

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
            if builder.hasOpenWorld {
                Task { await builder.syncEmbeddedViewport() }
            }
        }
        .onDisappear {
            builder.leavePanel()
            appDrawer.dismiss()
        }
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
        .disabled(!gazebo.runtimeAvailable || !builder.hasWorldFile || builder.draftIsReadOnly)
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
        gazebo.embeddedViewport?.worldID == builder.activeGazeboWorldID
            && gazebo.embeddedViewport?.phase == .live
    }

    private var viewportCameraControls: some View {
        HStack(spacing: GuardianSpacing.xs) {
            subBarIconButton(
                systemImage: "view.3d",
                accessibilityLabel: "Default view",
                action: { viewportCamera.trigger(.defaultView) }
            )
            .disabled(!isViewportCameraLive)
            subBarIconButton(
                systemImage: "view.2d",
                accessibilityLabel: "Bird's-eye view",
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
        GuardianChromeSize.small.controlOuterHeight
    }

    /// Swift spinner until the web viewer is mounted; gzweb HTML overlay handles load after that.
    private var showsEmbeddedViewportSpinner: Bool {
        guard builder.hasOpenWorld else { return false }
        guard let viewport = gazebo.embeddedViewport,
              viewport.worldID == builder.activeGazeboWorldID else {
            return true
        }
        return false
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
                        canInteract: builder.canEditScene
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
    }

    private var embeddedViewportStack: some View {
        Group {
            if let viewport = gazebo.embeddedViewport,
               viewport.worldID == builder.activeGazeboWorldID {
                GazeboWebViewportView(
                    websocketPort: viewport.websocketPort,
                    gazeboWorldName: viewport.gazeboWorldName,
                    phase: viewport.phase,
                    cameraBridge: viewportCamera,
                    cameraCommandTick: viewportCamera.tick,
                    showsCameraDebugHUD: fleetLink.isDebugEnabled,
                    groundHalfExtentM: builder.activeFloorHalfExtentM
                )
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

private struct WorldBuilderChooseDrawerContent: View {
    @ObservedObject var builder: WorldBuilderController
    let onSelect: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if builder.packages.isEmpty {
                    Text("No environments installed.")
                        .font(GuardianTypography.Scale.body.font())
                        .foregroundStyle(theme.textSecondary)
                        .padding(GuardianSpacing.md)
                } else {
                    ForEach(builder.packages) { pkg in
                        chooseRow(pkg)
                        if pkg.id != builder.packages.last?.id {
                            Divider()
                                .overlay(theme.borderSubtle)
                        }
                    }
                }
            }
        }
    }

    private func chooseRow(_ pkg: TrainingEnvironmentPackage) -> some View {
        Button {
            onSelect(pkg.id)
        } label: {
            HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pkg.manifest.displayName)
                        .font(GuardianTypography.Scale.body.font(weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Text(pkg.source == .bundled ? "Bundled" : "Yours")
                        .font(GuardianTypography.Scale.caption.font())
                        .foregroundStyle(theme.textTertiary)
                    if !pkg.manifest.description.isEmpty {
                        Text(pkg.manifest.description)
                            .font(GuardianTypography.Scale.caption.font())
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if builder.selectedPackageID == pkg.id {
                    Image(systemName: "checkmark")
                        .font(GuardianTypography.Scale.caption.font(weight: .semibold))
                        .foregroundStyle(GuardianSemanticColors.infoForeground)
                }
            }
            .padding(GuardianSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
        .guardianPointerOnHover()
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

    var body: some View {
        VStack(spacing: GuardianSpacing.xs) {
            toolButton(systemImage: "plus", accessibilityLabel: "Add model")
            toolButton(systemImage: "arrow.up.and.down.and.arrow.left.and.right", accessibilityLabel: "Move")
            toolButton(systemImage: "trash", accessibilityLabel: "Delete", accent: .danger)
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

    private func toolButton(
        systemImage: String,
        accessibilityLabel: String,
        accent: GuardianThemeAccent = .neutral
    ) -> some View {
        GuardianThemedButton(
            accent: accent,
            surface: .outline,
            size: .small,
            shape: .cornered,
            contentSizing: .squareToolbarCell,
            action: {},
            label: {
                Image(systemName: systemImage)
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
            }
        )
        .disabled(!canInteract)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .guardianPointerOnHover()
    }
}
