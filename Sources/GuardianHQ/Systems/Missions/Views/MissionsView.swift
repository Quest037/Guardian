import SwiftUI
import AppKit
import CoreLocation

struct MissionsView: View {
    enum DisplayMode {
        case list
        case grid
    }

    enum SortMode: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case oldest = "Oldest"
        var id: String { rawValue }
    }

    @ObservedObject var store: MissionStore
    @ObservedObject var missionControlStore: MissionControlStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAddMission = false
    @State private var displayMode: DisplayMode = .list
    @State private var sortMode: SortMode = .newest
    @State private var selectedMissionID: UUID?
    @State private var showArchivedMissions = false
    /// Drives delete confirm ``.sheet(item:)`` so the sheet never opens with an empty payload (avoids the “tiny blank box” first frame).
    private struct MissionListDeleteConfirmContext: Identifiable {
        var id: UUID { mission.id }
        let mission: Mission
    }

    @State private var missionListDeleteConfirm: MissionListDeleteConfirmContext?
    @State private var cloneMissionContext: CloneMissionContext?

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            if let selectedMission {
                missionWorkspace(selectedMission)
            } else {
                missionList
            }
        }
        .sheet(isPresented: $showingAddMission) {
            AddMissionSheet(store: store)
        }
        .sheet(item: $cloneMissionContext) { context in
            CloneMissionSheet(
                sourceMissionName: context.sourceMissionName,
                onCancel: { cloneMissionContext = nil },
                onClone: { newName in
                    guard let cloned = store.cloneMission(id: context.sourceMissionID, newName: newName) else {
                        toastCenter.show("Clone failed", style: .error)
                        return
                    }
                    cloneMissionContext = nil
                    selectedMissionID = cloned.id
                    toastCenter.show("Mission cloned", style: .success)
                }
            )
        }
        .guardianConfirmOverlay(item: $missionListDeleteConfirm) { ctx in
            GuardianConfirmDanger(
                title: "Delete Mission?",
                message: "Delete “\(ctx.mission.name)”? This removes the mission template and non-running Mission Control runs for this mission.",
                cancelTitle: "Cancel",
                confirmTitle: "Delete",
                onCancel: { missionListDeleteConfirm = nil },
                onConfirm: {
                    let mission = ctx.mission
                    missionListDeleteConfirm = nil
                    performDeleteMission(mission)
                }
            )
        }
    }

    private var selectedMission: Mission? {
        guard let selectedMissionID else { return nil }
        return store.missions.first(where: { $0.id == selectedMissionID })
    }

    private var sortedMissions: [Mission] {
        let visible = store.missions.filter { showArchivedMissions || !$0.isArchived }
        switch sortMode {
        case .newest:
            return visible.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return visible.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private var missionList: some View {
        VStack(spacing: 0) {
            HStack(spacing: GuardianSpacing.xs) {
                GuardianThemedButton(
                    title: displayMode == .list ? "Grid View" : "List View",
                    accent: .neutral,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: { displayMode = displayMode == .list ? .grid : .list }
                )

                GuardianThemedButton(
                    title: showArchivedMissions ? "Hide Archived" : "Show Archived",
                    accent: .neutral,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: { showArchivedMissions.toggle() }
                )

                Picker("", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()

                GuardianPrimaryProminentButton(title: "Add Mission") {
                    showingAddMission = true
                }
            }
            .padding(.horizontal, GuardianSpacing.sm)
            .padding(.vertical, GuardianSpacing.xs)
            .frame(maxWidth: .infinity)
            .background(theme.backgroundRaised)

            if sortedMissions.isEmpty {
                VStack {
                    Spacer()
                    Text("No missions yet")
                        .font(GuardianTypography.font(.missionProminentGlyph18Semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Use Add Mission to create your first mission template.")
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                }
            } else if displayMode == .list {
                ScrollView {
                    LazyVStack(spacing: GuardianSpacing.denseGutter) {
                        ForEach(sortedMissions) { mission in
                            MissionRow(
                                mission: mission,
                                onOpen: { selectedMissionID = mission.id },
                                onArchiveToggle: {
                                    store.setMissionArchived(id: mission.id, archived: !mission.isArchived)
                                    toastCenter.show(
                                        mission.isArchived ? "Mission unarchived" : "Mission archived",
                                        style: .success
                                    )
                                },
                                onClone: {
                                    cloneMissionContext = CloneMissionContext(
                                        sourceMissionID: mission.id,
                                        sourceMissionName: mission.name
                                    )
                                },
                                onDelete: {
                                    requestDeleteMission(mission)
                                }
                            )
                        }
                    }
                    .padding(GuardianSpacing.md)
                }
                .background(theme.backgroundBase)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: GuardianSpacing.sm),
                            GridItem(.flexible(), spacing: GuardianSpacing.sm),
                            GridItem(.flexible(), spacing: GuardianSpacing.sm),
                            GridItem(.flexible(), spacing: GuardianSpacing.sm),
                        ],
                        spacing: GuardianSpacing.sm
                    ) {
                        ForEach(sortedMissions) { mission in
                            MissionCard(
                                mission: mission,
                                onOpen: { selectedMissionID = mission.id },
                                onArchiveToggle: {
                                    store.setMissionArchived(id: mission.id, archived: !mission.isArchived)
                                    toastCenter.show(
                                        mission.isArchived ? "Mission unarchived" : "Mission archived",
                                        style: .success
                                    )
                                },
                                onClone: {
                                    cloneMissionContext = CloneMissionContext(
                                        sourceMissionID: mission.id,
                                        sourceMissionName: mission.name
                                    )
                                },
                                onDelete: {
                                    requestDeleteMission(mission)
                                }
                            )
                        }
                    }
                    .padding(GuardianSpacing.md)
                }
                .background(theme.backgroundBase)
            }
        }
    }

    private func missionWorkspace(_ mission: Mission) -> some View {
        MissionWorkspaceView(
            mission: mission,
            defaultMapTileStyle: generalSettings.defaultMapTileStyle,
            onBack: { selectedMissionID = nil },
            onDelete: { missionToDelete in
                performConfirmedDeleteMission(missionToDelete)
            },
            persistMission: { updatedMission in
                store.updateMission(updatedMission)
            },
            onToast: { message, style in
                toastCenter.show(message, style: style)
            }
        )
    }

    private func requestDeleteMission(_ mission: Mission) {
        if missionControlStore.hasLiveRun(forMissionID: mission.id) {
            toastCenter.show("Cannot delete a mission with a live Mission Control run.", style: .error)
            return
        }
        missionListDeleteConfirm = MissionListDeleteConfirmContext(mission: mission)
    }

    private func performConfirmedDeleteMission(_ mission: Mission) {
        if missionControlStore.hasLiveRun(forMissionID: mission.id) {
            toastCenter.show("Cannot delete a mission with a live Mission Control run.", style: .error)
            return
        }
        performDeleteMission(mission)
    }

    private func performDeleteMission(_ mission: Mission) {
        missionControlStore.deleteNonLiveRuns(forMissionID: mission.id)
        store.deleteMission(id: mission.id)
        if selectedMissionID == mission.id {
            selectedMissionID = nil
        }
        toastCenter.show("Mission deleted", style: .success)
    }
}

private struct CloneMissionContext: Identifiable {
    let id = UUID()
    let sourceMissionID: UUID
    let sourceMissionName: String
}

private struct RouteTabMissionPointRowSig: Equatable {
    let id: UUID
    let lat: Double
    let lon: Double
    let chip: String
    let kind: MissionPointKind
    let closed: Bool
}

/// Segmented control inside the mission workspace **Tasks** tab: route tasks vs map points.
private enum MissionWorkspaceTasksInnerTab: String, CaseIterable, Identifiable {
    case routes
    case points
    case geofences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routes: "Tasks"
        case .points: "Points"
        case .geofences: "Fences"
        }
    }
}

private struct RouteTabMapSignature: Equatable {
    let allTasksCoords: [[RouteCoordinate]]
    let taskPathIDs: [UUID]
    let selectedWaypoints: [RouteCoordinate]
    let selectedWaypointIndex: Int?
    let headingPreview: HeadingPreview?
    let cameraPreview: CameraPreview?
    let isEditingTask: Bool
    let missionPointRows: [RouteTabMissionPointRowSig]
    let selectedMissionPointID: UUID?
    let missionPointPlacementArmed: Bool
    let tasksInnerTab: MissionWorkspaceTasksInnerTab
    let geofenceChecksum: String
}

/// Drives ``View/sheet(item:onDismiss:content:)`` so bulk-edit content is never built as ``EmptyView`` on first open.
private struct BulkWaypointEditorSheetContext: Identifiable {
    let id = UUID()
    let taskIndex: Int
}

private struct MissionWorkspaceView: View {
    enum WorkspaceTab: String, CaseIterable, Identifiable {
        case details = "Details"
        case tasks = "Tasks"
        case roster = "Roster"
        var id: String { rawValue }
    }

    private struct RosterDeviceEditOverlayContext: Equatable {
        let taskIndex: Int
        let deviceId: UUID
    }

    private enum MissionWorkspacePresentedConfirm: String, Identifiable, Equatable {
        case deleteMission
        case removeRosterDevice
        case deleteTask
        case closeLoop
        var id: String { rawValue }
    }

    private struct MissionPointDeleteCandidate: Identifiable, Equatable {
        let id: UUID
    }

    /// One row in the Roster tab vehicle list (order may differ from ``MissionTask/rosterDeviceIds`` for grouped display).
    private struct TaskRosterDisplayRow: Identifiable {
        let deviceId: UUID
        /// `0` = primary (or ungrouped slot); `1` = wingman / reserve shown under a primary.
        let indentLevel: Int
        var id: UUID { deviceId }
    }

    @State private var draft: Mission
    @State private var activeTab: WorkspaceTab = .details
    @State private var selectedTaskIndex = 0
    @State private var editingTaskIndex: Int?
    @State private var selectedWaypointIndex: Int?
    @StateObject private var mapModel: GuardianMapModel
    @State private var pendingDeleteTaskIndex: Int?
    @State private var pendingCloseLoopTaskIndex: Int?
    @State private var missionWorkspacePresentedConfirm: MissionWorkspacePresentedConfirm?
    @State private var taskRosterDrafts: [UUID: TaskRosterDraft] = [:]
    @State private var bulkWaypointEditorSheetContext: BulkWaypointEditorSheetContext?
    @State private var bulkWaypointDraft = RouteWaypoint()
    @State private var focusedHeadingFieldKey: String?
    @State private var focusedWaypointCameraFieldKey: String?
    @State private var focusedTransitionCameraFieldKey: String?
    @State private var suppressNextMapClick = false
    @State private var selectedMissionPointID: UUID?
    @State private var selectedGeofenceID: UUID?
    /// Non-`nil` when ``AppDrawer`` is showing ``MissionWorkspaceMissionPointEditDrawer`` for that point (only opened via sidebar pencil).
    @State private var missionPointDrawerEditingID: UUID?
    @State private var geofenceDrawerEditingID: UUID?
    @State private var missionPointPlacementArmed = false
    @State private var missionPointDeleteCandidate: MissionPointDeleteCandidate?
    @State private var tasksInnerTab: MissionWorkspaceTasksInnerTab = .routes
    /// After **Add point**, scroll this row into view in the Tasks sidebar list.
    @State private var missionWorkspaceMapPointsListScrollEpoch: UInt = 0
    @State private var missionWorkspaceMapPointsListScrollTargetRow: UUID?
    @State private var missionWorkspaceGeofencesListScrollEpoch: UInt = 0
    @State private var missionWorkspaceGeofencesListScrollTargetRow: UUID?
    @State private var mapViewportCenter: RouteCoordinate?
    @State private var detailsDescriptionEditorHeight: CGFloat = 96
    /// Task settings panel hosted **inside** this view so `draft` updates refresh pickers (global ``AppDrawer`` does not re-run with mission `@State`).
    @State private var taskSettingsOverlayTaskIndex: Int?
    /// Roster-tab vehicle edit panel (same scrim + slide pattern as task settings).
    @State private var rosterDeviceEditContext: RosterDeviceEditOverlayContext?
    @State private var pendingRosterDelete: RosterDeviceEditOverlayContext?
    /// Coalesces disk writes while typing mission name / description on the Details tab.
    @State private var debouncedPersistMissionTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appDrawer: AppDrawer
    @EnvironmentObject private var osmRoutingService: OSMRoutingService

    /// Outgoing leg mode for the **next** map click when extending the path.
    @State private var pendingOutgoingSegmentKind: RouteSegmentKind = .direct

    let onBack: () -> Void
    let onDelete: (Mission) -> Void
    /// Writes the mission to persistent storage (no UI feedback).
    let persistMission: (Mission) -> Void
    let onToast: (String, ToastStyle) -> Void

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    /// Shown in the workspace sub-bar after Back (uses live `draft.name`).
    private var missionWorkspaceToolbarTitle: String {
        let t = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled mission" : t
    }

    /// Matches system ``TextField`` / `.roundedBorder` fill (light: white; dark: field dark).
    private static var missionFormTextFieldBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    /// Matches wingman/reserve “Leader” label + menu footprint so the add row does not jump when Slot changes.
    private static let rosterAddRowSupportsColumnWidth: CGFloat = 264
    /// Leading inset per nesting level for wingmen / reserves under a primary.
    private static let rosterSlotGroupIndentStep: CGFloat = GuardianSpacing.md

    private var missionTaskSettingsSidebarAnimation: Animation {
        .spring(response: 0.36, dampingFraction: 0.88)
    }

    init(
        mission: Mission,
        defaultMapTileStyle: MapTileStyle,
        onBack: @escaping () -> Void,
        onDelete: @escaping (Mission) -> Void,
        persistMission: @escaping (Mission) -> Void,
        onToast: @escaping (String, ToastStyle) -> Void
    ) {
        _draft = State(initialValue: mission)
        _mapModel = StateObject(
            wrappedValue: GuardianMapModel(mapStyle: defaultMapTileStyle)
        )
        self.onBack = onBack
        self.onDelete = onDelete
        self.persistMission = persistMission
        self.onToast = onToast
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: GuardianSpacing.denseGutter) {
                    HStack(spacing: GuardianSpacing.denseGutter) {
                        GuardianThemedButton(
                            accent: .neutral,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            contentSizing: .squareToolbarCell,
                            action: onBack,
                            label: {
                                Image(systemName: "arrow.left")
                                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                            }
                        )
                        .help("Back to missions")

                        Text(missionWorkspaceToolbarTitle)
                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(minWidth: 0, maxWidth: 100, alignment: .leading)

                        Picker("", selection: $activeTab) {
                            ForEach(WorkspaceTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 420)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: GuardianSpacing.sm)

                    GuardianThemedButton(
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: { missionWorkspacePresentedConfirm = .deleteMission },
                        label: {
                            Image(systemName: "trash")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Delete Mission")
                }
                .padding(.horizontal, GuardianSpacing.sm)
                .padding(.vertical, GuardianSpacing.xs)
                .frame(maxWidth: .infinity)
                .background(theme.backgroundRaised)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.borderSubtle)
                        .frame(height: 1)
                }

                if activeTab == .tasks {
                    tasksTab
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                            switch activeTab {
                            case .details:
                                detailsTab
                            case .roster:
                                rosterTab
                            case .tasks:
                                EmptyView()
                            }
                        }
                        .padding(.horizontal, GuardianSpacing.lg)
                        .padding(.vertical, GuardianSpacing.md)
                        .frame(maxWidth: .infinity)
                    }
                    .background(theme.backgroundBase)
                }
            }
            .background(theme.backgroundBase)

            if taskSettingsOverlayValidatedIndex != nil {
                theme.overlayScrim
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissMissionTaskSettingsOverlay() }
                    .transition(.opacity)
                    .zIndex(49)
            }
            if let taskIndex = taskSettingsOverlayValidatedIndex {
                missionTaskSettingsOverlayPanel(taskIndex: taskIndex)
                    .transition(.move(edge: .trailing))
                    .zIndex(50)
            }

            if rosterDeviceEditValidatedContext != nil {
                theme.overlayScrim
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissRosterDeviceEditOverlay() }
                    .transition(.opacity)
                    .zIndex(51)
            }
            if let ctx = rosterDeviceEditValidatedContext {
                missionRosterDeviceEditOverlayPanel(context: ctx)
                    .transition(.move(edge: .trailing))
                    .zIndex(52)
            }
        }
        .animation(missionTaskSettingsSidebarAnimation, value: taskSettingsOverlayTaskIndex)
        .animation(missionTaskSettingsSidebarAnimation, value: rosterDeviceEditContext)
        .onChange(of: editingTaskIndex) { newIndex in
            clearPreviewFocusState()
            if newIndex != nil {
                missionPointPlacementArmed = false
                appDrawer.dismiss()
                missionPointDrawerEditingID = nil
                geofenceDrawerEditingID = nil
                taskSettingsOverlayTaskIndex = nil
                rosterDeviceEditContext = nil
            }
        }
        .onChange(of: selectedTaskIndex) { _ in
            clearPreviewFocusState()
        }
        .onChange(of: activeTab) { tab in
            if tab != .tasks {
                appDrawer.dismiss()
                missionPointDrawerEditingID = nil
                geofenceDrawerEditingID = nil
                taskSettingsOverlayTaskIndex = nil
                clearPreviewFocusState()
                missionPointPlacementArmed = false
                selectedMissionPointID = nil
                selectedGeofenceID = nil
                tasksInnerTab = .routes
            }
            if tab != .roster {
                rosterDeviceEditContext = nil
            }
        }
        .guardianConfirmOverlay(item: $missionPointDeleteCandidate, dialog: { candidate in
            GuardianConfirmDanger(
                title: "Delete map point?",
                message: "This removes the point from the mission template.",
                cancelTitle: "Cancel",
                confirmTitle: "Delete",
                onCancel: { missionPointDeleteCandidate = nil },
                onConfirm: {
                    draft.missionPoints.removeAll { $0.id == candidate.id }
                    if selectedMissionPointID == candidate.id {
                        selectedMissionPointID = nil
                    }
                    if missionPointDrawerEditingID == candidate.id {
                        missionPointDrawerEditingID = nil
                        appDrawer.dismiss()
                    }
                    draft.renumberMissionPointSlugsByListOrder()
                    missionPointDeleteCandidate = nil
                    persistMissionToStoreNow()
                }
            )
        })
        .guardianConfirmOverlay(item: $missionWorkspacePresentedConfirm, onDismiss: {
            pendingRosterDelete = nil
            pendingDeleteTaskIndex = nil
            pendingCloseLoopTaskIndex = nil
        }, dialog: missionWorkspaceConfirmOverlayContent)
        .sheet(item: $bulkWaypointEditorSheetContext) { ctx in
            bulkWaypointEditorSheet(taskIndex: ctx.taskIndex)
        }
        .onChange(of: tasksInnerTab) { newTab in
            if newTab == .points {
                editingTaskIndex = nil
                selectedWaypointIndex = nil
                appDrawer.dismiss()
                geofenceDrawerEditingID = nil
            }
            if newTab == .routes {
                missionPointPlacementArmed = false
                appDrawer.dismiss()
                missionPointDrawerEditingID = nil
                geofenceDrawerEditingID = nil
            }
            if newTab == .geofences {
                editingTaskIndex = nil
                selectedWaypointIndex = nil
                missionPointPlacementArmed = false
                appDrawer.dismiss()
                missionPointDrawerEditingID = nil
                geofenceDrawerEditingID = nil
            }
        }
        .onChange(of: appDrawer.presented?.id) { newDrawerID in
            if newDrawerID == nil {
                missionPointDrawerEditingID = nil
                geofenceDrawerEditingID = nil
            }
        }
        .onChange(of: draft.name) { _ in scheduleDebouncedPersistMission() }
        .onChange(of: draft.description) { _ in scheduleDebouncedPersistMission() }
        .onChange(of: draft.type) { _ in persistMissionToStoreNow() }
        .onDisappear {
            debouncedPersistMissionTask?.cancel()
            debouncedPersistMissionTask = nil
            persistMission(draft)
        }
    }

    private func scheduleDebouncedPersistMission() {
        debouncedPersistMissionTask?.cancel()
        debouncedPersistMissionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            persistMission(draft)
        }
    }

    private func persistMissionToStoreNow() {
        debouncedPersistMissionTask?.cancel()
        debouncedPersistMissionTask = nil
        persistMission(draft)
    }

    private var detailsTab: some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianCardLayout.defaultBodyPadding
            ),
            header: {
                Text("Edit Mission")
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            },
            body: {
                VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                    GuardianLabeledFormField(label: "Mission name") {
                        TextField("", text: $draft.name, prompt: Text("Mission name").foregroundColor(theme.textTertiary))
                            .textFieldStyle(.roundedBorder)
                            .guardianFormControlSizing()
                    }
                    GuardianLabeledFormField(label: "Mission description") {
                        AutoGrowingTextEditor(
                            text: $draft.description,
                            measuredHeight: $detailsDescriptionEditorHeight,
                            placeholder: "Description",
                            minHeight: 96,
                            maxHeight: 220,
                            fieldBackground: Self.missionFormTextFieldBackground
                        )
                    }
                    GuardianLabeledFormField(label: "Type") {
                        Picker("", selection: $draft.type) {
                            Text("mobile").tag(MissionType.mobile)
                            Text("static").tag(MissionType.staticType)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280, alignment: .leading)
                        .guardianFormControlSizing()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    private var rosterTab: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.md) {
            GuardianCard(
                configuration: GuardianCardConfiguration(
                    border: .subtle,
                    cornerRadius: GuardianCardLayout.cornerRadius,
                    bodyPadding: GuardianCardLayout.defaultBodyPadding
                ),
                header: {
                    Text("Roster")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                },
                body: {
                    VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                        Text("Vehicles per task")
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(
                            "Each mission task lists the vehicles you expect on that route. Use callsigns and slots for planning; "
                                + "you will bind real aircraft in Mission Control."
                        )
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            )

            if draft.routeMacro.tasks.isEmpty {
                GuardianCard(
                    configuration: GuardianCardConfiguration(
                        border: .subtle,
                        cornerRadius: GuardianCardLayout.cornerRadius,
                        bodyPadding: GuardianCardLayout.defaultBodyPadding
                    ),
                    body: {
                        Text("No tasks yet. Add tasks on the Tasks tab, then assign vehicles to each task here.")
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
            } else {
                ForEach(Array(draft.routeMacro.tasks.enumerated()), id: \.element.id) { taskIndex, _ in
                    taskRosterCard(taskIndex: taskIndex)
                }
            }
        }
    }

    private func taskRosterCard(taskIndex: Int) -> some View {
        let path = draft.routeMacro.tasks[taskIndex]
        let taskId = path.id
        return GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianCardLayout.defaultBodyPadding
            ),
            header: {
                HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xs) {
                    TextField(
                        "Task name",
                        text: Binding(
                            get: { draft.routeMacro.tasks[taskIndex].name },
                            set: { draft.routeMacro.tasks[taskIndex].name = $0 }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                    .foregroundStyle(theme.textPrimary)

                    Spacer(minLength: GuardianSpacing.xs)

                    GuardianThemedButton(
                        accent: .neutral,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: { presentTaskSettingsSidebar(taskIndex: taskIndex) },
                        label: {
                            Image(systemName: "gearshape.fill")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Task settings")

                    Text("\(path.waypoints.count) waypoints")
                        .font(GuardianTypography.font(.inlineNoticeDetail))
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            body: {
                VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                    Text("Vehicles on this task")
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(theme.textSecondary)

                    if path.rosterDeviceIds.isEmpty {
                        Text("None yet — use the row below.")
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textTertiary)
                    } else {
                        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                            ForEach(taskRosterDisplayRows(for: path)) { row in
                                if let device = draft.rosterDevices.first(where: { $0.id == row.deviceId }) {
                                    HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                                        Text(device.name)
                                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                                            .foregroundStyle(theme.textPrimary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)

                                        rosterDeviceInlineBadges(device: device)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.78)
                                            .layoutPriority(0)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        GuardianThemedButton(
                                            accent: .primary,
                                            surface: .outline,
                                            size: .small,
                                            shape: .cornered,
                                            contentSizing: .squareToolbarCell,
                                            action: { presentRosterDeviceEdit(taskIndex: taskIndex, deviceId: row.deviceId) },
                                            label: {
                                                Image(systemName: "pencil")
                                                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                                            }
                                        )
                                        .help("Edit vehicle")

                                        GuardianThemedButton(
                                            accent: .danger,
                                            surface: .outline,
                                            size: .small,
                                            shape: .cornered,
                                            contentSizing: .squareToolbarCell,
                                            action: { requestRemoveRosterDevice(taskIndex: taskIndex, deviceId: row.deviceId) },
                                            label: {
                                                Image(systemName: "trash")
                                                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                                            }
                                        )
                                        .help("Remove vehicle")
                                    }
                                    .padding(.leading, CGFloat(row.indentLevel) * Self.rosterSlotGroupIndentStep)
                                    .padding(.vertical, GuardianSpacing.xxs)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }

                    Divider().overlay(theme.borderSubtle)

                    HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                        TextField(
                            "Callsign",
                            text: Binding(
                                get: { taskRosterDrafts[taskId]?.name ?? "" },
                                set: { v in
                                    var d = taskRosterDrafts[taskId] ?? TaskRosterDraft()
                                    d.name = v
                                    taskRosterDrafts[taskId] = d
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(0)

                        Picker(
                            "Class",
                            selection: Binding(
                                get: { taskRosterDrafts[taskId]?.vehicleClass ?? .unknown },
                                set: { v in
                                    var d = taskRosterDrafts[taskId] ?? TaskRosterDraft()
                                    d.vehicleClass = v
                                    taskRosterDrafts[taskId] = d
                                }
                            )
                        ) {
                            ForEach(FleetVehicleType.allCases, id: \.self) { t in
                                Text(t.classCode).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 100, idealWidth: 120, maxWidth: 160, alignment: .leading)
                        .layoutPriority(1)

                        HStack(spacing: GuardianSpacing.xxs) {
                            Picker(
                                "Role",
                                selection: Binding(
                                    get: { taskRosterDrafts[taskId]?.behaviorRoleID ?? RosterRole.none.rawValue },
                                    set: { v in
                                        var d = taskRosterDrafts[taskId] ?? TaskRosterDraft()
                                        d.behaviorRoleID = v
                                        taskRosterDrafts[taskId] = d
                                    }
                                )
                            ) {
                                ForEach(RosterRoleCatalog.missionUIPickerBehaviorRoleIDs(), id: \.self) { rid in
                                    Text(RosterRoleCatalog.displayName(forBehaviorRoleID: rid)).tag(rid)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .help("Optional behavior role for Mission Control / Paladin (see roster catalog).")

                            GuardianThemedButton(
                                accent: .neutral,
                                surface: .outline,
                                size: .small,
                                shape: .cornered,
                                contentSizing: .squareToolbarCell,
                                action: { presentRosterBehaviorRolesCatalogDrawer() },
                                label: {
                                    Image(systemName: "info.circle")
                                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                                }
                            )
                            .help("Open reference for all behavior roles")
                        }
                        .frame(minWidth: 160, idealWidth: 196, maxWidth: 260, alignment: .leading)
                        .layoutPriority(1)

                        Picker(
                            "Slot",
                            selection: Binding(
                                get: { taskRosterDrafts[taskId]?.slot ?? .primary },
                                set: { v in
                                    var d = taskRosterDrafts[taskId] ?? TaskRosterDraft()
                                    d.slot = v
                                    if v != .wingman && v != .reserve { d.leaderRosterDeviceId = nil }
                                    taskRosterDrafts[taskId] = d
                                }
                            )
                        ) {
                            ForEach(MissionRosterSlotRole.allCases) { r in
                                Text(r.rawValue.capitalized).tag(r)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(minWidth: 148, idealWidth: 168, maxWidth: 220, alignment: .leading)
                        .layoutPriority(1)

                        // Reserve width so switching Slot away from wingman/reserve does not collapse or jump the row.
                        Group {
                            let slotNeedsLeader = {
                                let s = taskRosterDrafts[taskId]?.slot ?? .primary
                                return s == .wingman || s == .reserve
                            }()
                            let primaries = primaryRosterDevices(on: path)
                            if slotNeedsLeader {
                                HStack(spacing: GuardianSpacing.xs) {
                                    Text("Leader")
                                        .font(GuardianTypography.font(.formFieldLabel))
                                        .foregroundStyle(theme.textSecondary)
                                        .fixedSize()
                                        .padding(.leading, GuardianSpacing.xxs)
                                    if primaries.isEmpty {
                                        Text("—")
                                            .font(GuardianTypography.font(.denseCaption12Regular))
                                            .foregroundStyle(theme.textTertiary)
                                            .lineLimit(1)
                                    } else {
                                        Picker(
                                            "Leader",
                                            selection: Binding(
                                                get: { taskRosterDrafts[taskId]?.leaderRosterDeviceId },
                                                set: { v in
                                                    var d = taskRosterDrafts[taskId] ?? TaskRosterDraft()
                                                    d.leaderRosterDeviceId = v
                                                    taskRosterDrafts[taskId] = d
                                                }
                                            )
                                        ) {
                                            Text("Auto").tag(UUID?.none)
                                            ForEach(primaries) { p in
                                                Text(p.name).tag(Optional(p.id))
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                        .controlSize(.small)
                                        .frame(minWidth: 120, idealWidth: 140, maxWidth: 200, alignment: .leading)
                                        .accessibilityLabel("Leader")
                                    }
                                }
                            } else {
                                Color.clear
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(width: Self.rosterAddRowSupportsColumnWidth, alignment: .leading)
                        .layoutPriority(1)

                        GuardianPrimaryProminentButton(title: "Add") {
                            addRosterDeviceToTask(taskIndex: taskIndex)
                        }
                        .layoutPriority(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rosterDeviceInlineBadges(device: RosterDevice) -> some View {
        HStack(spacing: GuardianSpacing.xsTight) {
            rosterNeutralCapsuleBadge(device.vehicleClass.classCode)
            rosterSlotSemanticCapsuleBadge(device.slot)
            rosterNeutralCapsuleBadge(rosterBehaviorRoleLabel(device.behaviorRoleID))
            if device.slot == .wingman || device.slot == .reserve {
                rosterNeutralCapsuleBadge(rosterLeaderBadgeCaption(device))
            }
        }
    }

    @ViewBuilder
    private func rosterNeutralCapsuleBadge(_ title: String) -> some View {
        Text(title)
            .font(GuardianTypography.font(.denseCaption10Semibold))
            .foregroundStyle(GuardianSemanticColors.neutralBadgeForeground)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, GuardianSpacing.chromeTightInset)
            .padding(.vertical, GuardianSpacing.titleStackTight)
            .background(GuardianSemanticColors.neutralBadgeBackground)
            .clipShape(Capsule())
    }

    private func rosterSlotSemanticColors(_ slot: MissionRosterSlotRole) -> (background: Color, foreground: Color) {
        switch slot {
        case .primary:
            return (GuardianSemanticColors.infoBackground, GuardianSemanticColors.infoForeground)
        case .wingman:
            return (GuardianSemanticColors.successBackground, GuardianSemanticColors.successForeground)
        case .reserve:
            return (GuardianSemanticColors.warningBackground, GuardianSemanticColors.warningForeground)
        }
    }

    @ViewBuilder
    private func rosterSlotSemanticCapsuleBadge(_ slot: MissionRosterSlotRole) -> some View {
        let pair = rosterSlotSemanticColors(slot)
        Text(slot.rawValue.capitalized)
            .font(GuardianTypography.font(.denseCaption10Semibold))
            .foregroundStyle(pair.foreground)
            .lineLimit(1)
            .padding(.horizontal, GuardianSpacing.chromeTightInset)
            .padding(.vertical, GuardianSpacing.titleStackTight)
            .background(pair.background)
            .clipShape(Capsule())
    }

    private func rosterBehaviorRoleLabel(_ behaviorRoleID: String) -> String {
        RosterRoleCatalog.displayName(forBehaviorRoleID: behaviorRoleID)
    }

    /// App-wide drawer: catalog copy for every behavior role id (add-slot row info control).
    private func presentRosterBehaviorRolesCatalogDrawer() {
        appDrawer.present(
            title: "Behavior roles",
            preferredWidth: 420,
            scrimTapDismisses: true
        ) {
            RosterBehaviorRolesCatalogDrawerContent()
        }
    }

    private func rosterLeaderBadgeCaption(_ device: RosterDevice) -> String {
        if let pid = device.leaderRosterDeviceId,
           let leader = draft.rosterDevices.first(where: { $0.id == pid }) {
            return leader.name
        }
        return "Auto"
    }

    private func primaryRosterDevices(on path: MissionTask) -> [RosterDevice] {
        path.rosterDeviceIds.compactMap { id in draft.rosterDevices.first { $0.id == id } }
            .filter { $0.slot == .primary }
    }

    /// Primaries in mission roster order, then each primary’s wingmen and reserves (by roster order); trailing slots are supports without a matching primary leader or other edge cases.
    private func taskRosterDisplayRows(for path: MissionTask) -> [TaskRosterDisplayRow] {
        let ids = path.rosterDeviceIds
        func device(for rosterId: UUID) -> RosterDevice? {
            draft.rosterDevices.first { $0.id == rosterId }
        }

        var emitted = Set<UUID>()
        var rows: [TaskRosterDisplayRow] = []

        let primaryIds = ids.filter { device(for: $0)?.slot == .primary }
        for pid in primaryIds {
            guard device(for: pid)?.slot == .primary else { continue }
            rows.append(TaskRosterDisplayRow(deviceId: pid, indentLevel: 0))
            emitted.insert(pid)

            let wingmanIds = ids.filter {
                guard let d = device(for: $0), d.slot == .wingman, d.leaderRosterDeviceId == pid else { return false }
                return true
            }
            let reserveIds = ids.filter {
                guard let d = device(for: $0), d.slot == .reserve, d.leaderRosterDeviceId == pid else { return false }
                return true
            }
            for wid in wingmanIds {
                rows.append(TaskRosterDisplayRow(deviceId: wid, indentLevel: 1))
                emitted.insert(wid)
            }
            for rid in reserveIds {
                rows.append(TaskRosterDisplayRow(deviceId: rid, indentLevel: 1))
                emitted.insert(rid)
            }
        }

        for id in ids where !emitted.contains(id) {
            let d = device(for: id)
            let indent = (d?.slot == .wingman || d?.slot == .reserve) ? 1 : 0
            rows.append(TaskRosterDisplayRow(deviceId: id, indentLevel: indent))
            emitted.insert(id)
        }

        return rows
    }

    private func presentTaskSettingsSidebar(taskIndex: Int) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return }
        withAnimation(missionTaskSettingsSidebarAnimation) {
            rosterDeviceEditContext = nil
            taskSettingsOverlayTaskIndex = taskIndex
        }
    }

    private func dismissMissionTaskSettingsOverlay() {
        withAnimation(missionTaskSettingsSidebarAnimation) {
            taskSettingsOverlayTaskIndex = nil
        }
    }

    private func presentRosterDeviceEdit(taskIndex: Int, deviceId: UUID) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex),
              draft.rosterDevices.contains(where: { $0.id == deviceId }) else { return }
        withAnimation(missionTaskSettingsSidebarAnimation) {
            taskSettingsOverlayTaskIndex = nil
            rosterDeviceEditContext = RosterDeviceEditOverlayContext(taskIndex: taskIndex, deviceId: deviceId)
        }
    }

    private func dismissRosterDeviceEditOverlay() {
        withAnimation(missionTaskSettingsSidebarAnimation) {
            rosterDeviceEditContext = nil
        }
    }

    /// Index for the task-settings overlay when it is allowed to show (avoids duplicate `if` guard drift).
    private var taskSettingsOverlayValidatedIndex: Int? {
        guard let i = taskSettingsOverlayTaskIndex,
              draft.routeMacro.tasks.indices.contains(i) else { return nil }
        return i
    }

    private var rosterDeviceEditValidatedContext: RosterDeviceEditOverlayContext? {
        guard let ctx = rosterDeviceEditContext,
              draft.routeMacro.tasks.indices.contains(ctx.taskIndex),
              draft.rosterDevices.contains(where: { $0.id == ctx.deviceId }) else { return nil }
        return ctx
    }

    @ViewBuilder
    private func missionWorkspaceConfirmOverlayContent(_ kind: MissionWorkspacePresentedConfirm) -> some View {
        Group {
            switch kind {
                case .deleteMission:
                    GuardianConfirmDanger(
                        title: "Delete mission?",
                        message: "This will permanently remove this mission.",
                        cancelTitle: "Cancel",
                        confirmTitle: "Delete",
                        onCancel: { missionWorkspacePresentedConfirm = nil },
                        onConfirm: {
                            missionWorkspacePresentedConfirm = nil
                            onDelete(draft)
                        }
                    )
                case .removeRosterDevice:
                    GuardianConfirmDanger(
                        title: "Remove vehicle?",
                        message: rosterDeleteConfirmMessage,
                        cancelTitle: "Cancel",
                        confirmTitle: "Remove",
                        onCancel: {
                            pendingRosterDelete = nil
                            missionWorkspacePresentedConfirm = nil
                        },
                        onConfirm: {
                            if let pending = pendingRosterDelete {
                                performRemoveRosterDeviceFromTask(taskIndex: pending.taskIndex, deviceId: pending.deviceId)
                            }
                            pendingRosterDelete = nil
                            missionWorkspacePresentedConfirm = nil
                        }
                    )
                case .deleteTask:
                    GuardianConfirmDanger(
                        title: "Delete task?",
                        message: "This will remove the task and all its waypoints.",
                        cancelTitle: "Cancel",
                        confirmTitle: "Delete",
                        onCancel: {
                            pendingDeleteTaskIndex = nil
                            missionWorkspacePresentedConfirm = nil
                        },
                        onConfirm: {
                            if let idx = pendingDeleteTaskIndex,
                               draft.routeMacro.tasks.indices.contains(idx) {
                                let removedTaskID = draft.routeMacro.tasks[idx].id
                                draft.routeMacro.tasks.remove(at: idx)
                                draft.removeMissionPoints(forRemovedTaskID: removedTaskID)
                                if editingTaskIndex == idx {
                                    editingTaskIndex = nil
                                    selectedWaypointIndex = nil
                                }
                                if selectedTaskIndex >= draft.routeMacro.tasks.count {
                                    selectedTaskIndex = max(0, draft.routeMacro.tasks.count - 1)
                                }
                                if let sid = selectedMissionPointID,
                                   !draft.missionPoints.contains(where: { $0.id == sid }) {
                                    selectedMissionPointID = nil
                                }
                            }
                            pendingDeleteTaskIndex = nil
                            missionWorkspacePresentedConfirm = nil
                            persistMissionToStoreNow()
                        }
                    )
                case .closeLoop:
                    GuardianConfirm(
                        title: "Close loop for this task?",
                        message: "Add the start waypoint to the end and mark this task as looped?",
                        cancelTitle: "No",
                        confirmTitle: "Close Loop",
                        onCancel: {
                            editingTaskIndex = nil
                            selectedWaypointIndex = nil
                            pendingCloseLoopTaskIndex = nil
                            missionWorkspacePresentedConfirm = nil
                            persistMissionToStoreNow()
                            onToast("Task edit mode disabled", .info)
                        },
                        onConfirm: {
                            guard let idx = pendingCloseLoopTaskIndex,
                                  draft.routeMacro.tasks.indices.contains(idx) else {
                                pendingCloseLoopTaskIndex = nil
                                missionWorkspacePresentedConfirm = nil
                                persistMissionToStoreNow()
                                return
                            }
                            Task { @MainActor in
                                await closeLoop(for: idx)
                                editingTaskIndex = nil
                                selectedWaypointIndex = nil
                                onToast("Loop closed", .success)
                                pendingCloseLoopTaskIndex = nil
                                missionWorkspacePresentedConfirm = nil
                                persistMissionToStoreNow()
                            }
                        }
                    )
                }
        }
    }

    private var rosterDeleteConfirmMessage: String {
        guard let pending = pendingRosterDelete,
              draft.routeMacro.tasks.indices.contains(pending.taskIndex) else {
            return "This removes the vehicle from this task roster."
        }
        var parts = ["This removes the vehicle from this task roster."]
        if let d = draft.rosterDevices.first(where: { $0.id == pending.deviceId }), d.slot == .primary {
            let n = dependentLeaderSlotCount(primaryId: pending.deviceId, taskIndex: pending.taskIndex)
            if n > 0 {
                parts.append(
                    "It will also remove \(n) wingman or reserve slot(s) on this task that follow this primary."
                )
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private func dependentLeaderSlotCount(primaryId: UUID, taskIndex: Int) -> Int {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return 0 }
        let taskIds = draft.routeMacro.tasks[taskIndex].rosterDeviceIds
        return taskIds.filter { did in
            guard did != primaryId,
                  let d = draft.rosterDevices.first(where: { $0.id == did }) else { return false }
            return (d.slot == .wingman || d.slot == .reserve) && d.leaderRosterDeviceId == primaryId
        }.count
    }

    private func requestRemoveRosterDevice(taskIndex: Int, deviceId: UUID) {
        pendingRosterDelete = RosterDeviceEditOverlayContext(taskIndex: taskIndex, deviceId: deviceId)
        missionWorkspacePresentedConfirm = .removeRosterDevice
    }

    private func performRemoveRosterDeviceFromTask(taskIndex: Int, deviceId: UUID) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return }
        var idsToRemove: Set<UUID> = [deviceId]
        if let device = draft.rosterDevices.first(where: { $0.id == deviceId }), device.slot == .primary {
            let taskIds = draft.routeMacro.tasks[taskIndex].rosterDeviceIds
            for did in taskIds where did != deviceId {
                guard let d = draft.rosterDevices.first(where: { $0.id == did }) else { continue }
                if (d.slot == .wingman || d.slot == .reserve), d.leaderRosterDeviceId == deviceId {
                    idsToRemove.insert(did)
                }
            }
        }
        draft.routeMacro.tasks[taskIndex].rosterDeviceIds.removeAll { idsToRemove.contains($0) }
        for id in idsToRemove {
            let stillReferenced = draft.routeMacro.tasks.contains { $0.rosterDeviceIds.contains(id) }
            if !stillReferenced {
                draft.rosterDevices.removeAll { $0.id == id }
            }
        }
        if let ctx = rosterDeviceEditContext, idsToRemove.contains(ctx.deviceId) {
            rosterDeviceEditContext = nil
        }
        persistMissionToStoreNow()
    }

    /// Trailing task-settings column only. The scrim is a **sibling** view in the workspace `ZStack` so each layer’s
    /// ``View/transition(_:)`` is a separate insertion root — nested transitions under one inserted `ZStack` do not animate reliably.
    @ViewBuilder
    private func missionTaskSettingsOverlayPanel(taskIndex: Int) -> some View {
        let path = draft.routeMacro.tasks[taskIndex]
        let trimmedName = path.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedName.isEmpty ? "Task settings" : "Task settings — \(trimmedName)"
        let panelWidth = CGFloat(min(560, max(260, 400)))
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            AppDrawerChrome(title: title, onClose: dismissMissionTaskSettingsOverlay) {
                MissionTaskSettingsSidebar(
                    task: Binding(
                        get: { draft.routeMacro.tasks[taskIndex] },
                        set: { draft.routeMacro.tasks[taskIndex] = $0 }
                    ),
                    rosterDevices: draft.rosterDevices,
                    onSave: {
                        persistMissionToStoreNow()
                        dismissMissionTaskSettingsOverlay()
                    }
                )
                .padding(GuardianSpacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: panelWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(theme.backgroundElevated)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(theme.borderSubtle)
                    .frame(width: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .onExitCommand { dismissMissionTaskSettingsOverlay() }
    }

    @ViewBuilder
    private func missionRosterDeviceEditOverlayPanel(context: RosterDeviceEditOverlayContext) -> some View {
        let taskIndex = context.taskIndex
        let deviceId = context.deviceId
        let path = draft.routeMacro.tasks[taskIndex]
        let deviceName = draft.rosterDevices.first(where: { $0.id == deviceId })?.name ?? ""
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Vehicle" : "Vehicle — \(trimmed)"
        let panelWidth = CGFloat(min(560, max(260, 400)))
        let primaries = primaryRosterDevices(on: path)
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            AppDrawerChrome(title: title, onClose: dismissRosterDeviceEditOverlay) {
                if let deviceIndex = draft.rosterDevices.firstIndex(where: { $0.id == deviceId }) {
                    MissionRosterDeviceSettingsSidebar(
                        device: Binding(
                            get: { draft.rosterDevices[deviceIndex] },
                            set: { draft.rosterDevices[deviceIndex] = $0 }
                        ),
                        primariesOnTask: primaries,
                        onSave: {
                            persistMissionToStoreNow()
                            dismissRosterDeviceEditOverlay()
                        }
                    )
                    .padding(GuardianSpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(width: panelWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(theme.backgroundElevated)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(theme.borderSubtle)
                    .frame(width: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .onExitCommand { dismissRosterDeviceEditOverlay() }
    }

    @MainActor
    private func handleTaskMapClickAddWaypoint(lat: Double, lon: Double) async {
        guard let taskIndex = editingTaskIndex,
              draft.routeMacro.tasks.indices.contains(taskIndex) else { return }

        let coord = RouteCoordinate(lat: lat, lon: lon)
        var wps = draft.routeMacro.tasks[taskIndex].waypoints

        if wps.isEmpty {
            wps.append(RouteWaypoint(coord: coord, headingPreset: .followCourse))
        } else {
            guard let anchorIdx = wps.lastIndex(where: { $0.pathRole == .anchor }) else {
                wps.append(RouteWaypoint(coord: coord, headingPreset: .followCourse))
                draft.routeMacro.tasks[taskIndex].waypoints = wps
                refreshAutoHeadings(for: taskIndex)
                selectedTaskIndex = taskIndex
                selectedWaypointIndex = wps.count - 1
                onToast("Waypoint added", .success)
                persistMissionToStoreNow()
                return
            }

            switch pendingOutgoingSegmentKind {
            case .direct:
                MissionTaskPathSegmentEditing.appendDirectLeg(
                    waypoints: &wps,
                    coordinate: coord,
                    outgoingKind: .direct
                )
            case .followRoads:
                let from = wps[anchorIdx].coord
                do {
                    let dense = try await osmRoutingService.routeDrivingCoordinates(from: from, to: coord)
                    MissionTaskPathSegmentEditing.appendFollowRoadLeg(
                        waypoints: &wps,
                        templateIndex: anchorIdx,
                        coordinate: coord,
                        denseCoords: dense
                    )
                } catch {
                    MissionTaskPathSegmentEditing.appendDirectLeg(
                        waypoints: &wps,
                        coordinate: coord,
                        outgoingKind: .direct
                    )
                    onToast("Road routing unavailable; added direct leg.", .info)
                }
            }
        }

        draft.routeMacro.tasks[taskIndex].waypoints = wps
        refreshAutoHeadings(for: taskIndex)
        selectedTaskIndex = taskIndex
        selectedWaypointIndex = draft.routeMacro.tasks[taskIndex].waypoints.count - 1
        onToast("Waypoint added", .success)
        persistMissionToStoreNow()
    }

    // MARK: - Geofences (mission template)

    /// Applies a geofence-affecting mutation when the result satisfies ``MissionTemplateGeofenceUtilities/inclusionConstraintViolationMessage`` (inclusion limits and exclusion–inclusion pairing).
    @discardableResult
    private func applyGeofenceTemplateMutation(successToast: String?, _ body: (inout Mission) -> Void) -> Bool {
        var copy = draft
        body(&copy)
        if let msg = Utilities.mission.templateGeofences.inclusionConstraintViolationMessage(for: copy) {
            onToast(msg, .error)
            return false
        }
        draft = copy
        persistMissionToStoreNow()
        if let successToast {
            onToast(successToast, .success)
        }
        return true
    }

    private func addMissionGeofencePolygon() {
        let n = draft.missionGeofences.count + 1
        let boundary = Utilities.mission.templateGeofences.defaultBoundaryForNewMissionWideFence(in: draft)
        let fence = MissionGeofence.newPolygon(
            name: "Mission fence \(n)",
            around: missionGeofenceDefaultCenter,
            boundary: boundary
        )
        guard applyGeofenceTemplateMutation(successToast: "Fence added — drag vertices or the square handle on the map to adjust", { $0.missionGeofences.append(fence) }) else { return }
        selectedGeofenceID = fence.id
        missionWorkspaceGeofencesListScrollTargetRow = fence.id
        missionWorkspaceGeofencesListScrollEpoch &+= 1
    }

    private func addMissionGeofenceCircle() {
        let n = draft.missionGeofences.count + 1
        let boundary = Utilities.mission.templateGeofences.defaultBoundaryForNewMissionWideFence(in: draft)
        let fence = MissionGeofence.newCircle(
            name: "Mission fence \(n)",
            center: missionGeofenceDefaultCenter,
            boundary: boundary
        )
        guard applyGeofenceTemplateMutation(successToast: "Fence added — drag the center and rim on the map to adjust", { $0.missionGeofences.append(fence) }) else { return }
        selectedGeofenceID = fence.id
        missionWorkspaceGeofencesListScrollTargetRow = fence.id
        missionWorkspaceGeofencesListScrollEpoch &+= 1
    }

    private func removeGeofence(id: UUID) {
        var copy = draft
        copy.missionGeofences.removeAll { $0.id == id }
        for ti in copy.routeMacro.tasks.indices {
            copy.routeMacro.tasks[ti].geofences.removeAll { $0.id == id }
        }
        if let msg = Utilities.mission.templateGeofences.inclusionConstraintViolationMessage(for: copy) {
            onToast(msg, .error)
            return
        }
        draft = copy
        if selectedGeofenceID == id {
            selectedGeofenceID = nil
        }
        if geofenceDrawerEditingID == id {
            geofenceDrawerEditingID = nil
            appDrawer.dismiss()
        }
        persistMissionToStoreNow()
    }

    private func duplicateGeofence(id: UUID) {
        if let i = draft.missionGeofences.firstIndex(where: { $0.id == id }) {
            var dup = draft.missionGeofences[i].duplicatedForClonedMission()
            dup.name = dup.name + " copy"
            dup.boundary = Utilities.mission.templateGeofences.defaultBoundaryForNewMissionWideFence(in: draft)
            guard applyGeofenceTemplateMutation(successToast: nil, { $0.missionGeofences.append(dup) }) else { return }
            selectedGeofenceID = dup.id
            missionWorkspaceGeofencesListScrollTargetRow = dup.id
            missionWorkspaceGeofencesListScrollEpoch &+= 1
            return
        }
        for ti in draft.routeMacro.tasks.indices {
            if let i = draft.routeMacro.tasks[ti].geofences.firstIndex(where: { $0.id == id }) {
                var dup = draft.routeMacro.tasks[ti].geofences[i].duplicatedForClonedMission()
                dup.name = dup.name + " copy"
                let taskID = draft.routeMacro.tasks[ti].id
                dup.boundary = Utilities.mission.templateGeofences.defaultBoundaryForNewTaskScopedFence(taskID: taskID, in: draft)
                guard applyGeofenceTemplateMutation(successToast: nil, { $0.routeMacro.tasks[ti].geofences.append(dup) }) else { return }
                selectedGeofenceID = dup.id
                missionWorkspaceGeofencesListScrollTargetRow = dup.id
                missionWorkspaceGeofencesListScrollEpoch &+= 1
                return
            }
        }
    }

    private func mutateMissionGeofenceFromMap(id: UUID, _ update: (inout MissionGeofence) -> Void) {
        applyGeofenceTemplateMutation(successToast: nil) { mission in
            if let i = mission.missionGeofences.firstIndex(where: { $0.id == id }) {
                update(&mission.missionGeofences[i])
                return
            }
            for ti in mission.routeMacro.tasks.indices {
                if let fi = mission.routeMacro.tasks[ti].geofences.firstIndex(where: { $0.id == id }) {
                    update(&mission.routeMacro.tasks[ti].geofences[fi])
                    return
                }
            }
        }
    }

    private func moveGeofenceTemplateToPlacement(fenceID: UUID, target: MissionGeofenceTemplatePlacement) {
        applyGeofenceTemplateMutation(successToast: nil) { mission in
            var fence: MissionGeofence?
            if let i = mission.missionGeofences.firstIndex(where: { $0.id == fenceID }) {
                fence = mission.missionGeofences.remove(at: i)
            } else {
                for ti in mission.routeMacro.tasks.indices {
                    if let fi = mission.routeMacro.tasks[ti].geofences.firstIndex(where: { $0.id == fenceID }) {
                        fence = mission.routeMacro.tasks[ti].geofences.remove(at: fi)
                        break
                    }
                }
            }
            guard let f = fence else { return }
            switch target {
            case .missionWide:
                mission.missionGeofences.append(f)
            case .taskScoped(let taskUUID):
                if let ti = mission.routeMacro.tasks.firstIndex(where: { $0.id == taskUUID }) {
                    mission.routeMacro.tasks[ti].geofences.append(f)
                } else {
                    mission.missionGeofences.append(f)
                }
            }
        }
    }

    private func openGeofenceEditDrawer(fenceID: UUID) {
        let exists = draft.missionGeofences.contains(where: { $0.id == fenceID })
            || draft.routeMacro.tasks.contains { $0.geofences.contains { $0.id == fenceID } }
        guard exists else { return }
        selectedGeofenceID = fenceID
        geofenceDrawerEditingID = fenceID
        appDrawer.present(title: "Edit fence", preferredWidth: 400, scrimTapDismisses: true) {
            MissionWorkspaceGeofenceEditDrawer(
                fenceID: fenceID,
                mission: Binding(
                    get: { draft },
                    set: { newValue in
                        if let msg = Utilities.mission.templateGeofences.inclusionConstraintViolationMessage(for: newValue) {
                            onToast(msg, .error)
                            return
                        }
                        draft = newValue
                        persistMissionToStoreNow()
                    }
                ),
                onMovePlacement: { placement in moveGeofenceTemplateToPlacement(fenceID: fenceID, target: placement) },
                persist: { persistMissionToStoreNow() }
            )
        }
    }

    private func toggleGeofenceEditDrawer(fenceID: UUID) {
        let exists = draft.missionGeofences.contains(where: { $0.id == fenceID })
            || draft.routeMacro.tasks.contains { $0.geofences.contains { $0.id == fenceID } }
        guard exists else { return }
        if geofenceDrawerEditingID == fenceID {
            geofenceDrawerEditingID = nil
            appDrawer.dismiss()
            return
        }
        openGeofenceEditDrawer(fenceID: fenceID)
    }

    private func addMissionPointAtMap(lat: Double, lon: Double) {
        let p = MissionPoint(
            pointId: "rally.0",
            label: "",
            kind: .rally,
            coordinate: RouteCoordinate(lat: lat, lon: lon),
            taskID: nil
        )
        draft.missionPoints.append(p)
        draft.renumberMissionPointSlugsByListOrder()
        selectedMissionPointID = p.id
        missionWorkspaceMapPointsListScrollTargetRow = p.id
        missionWorkspaceMapPointsListScrollEpoch &+= 1
        missionPointPlacementArmed = false
        persistMissionToStoreNow()
        onToast("Map point added — drag the pin on the map to move it", .success)
    }

    private func appendMissionPointAtViewportCenter() {
        let coord = mapViewportCenter ?? RouteCoordinate()
        let p = MissionPoint(
            pointId: "rally.0",
            label: "",
            kind: .rally,
            coordinate: coord,
            taskID: nil
        )
        draft.missionPoints.append(p)
        draft.renumberMissionPointSlugsByListOrder()
        selectedMissionPointID = p.id
        missionWorkspaceMapPointsListScrollTargetRow = p.id
        missionWorkspaceMapPointsListScrollEpoch &+= 1
        persistMissionToStoreNow()
        onToast("Map point added — drag the pin on the map to move it", .success)
    }

    /// Presents the edit drawer (sidebar pencil only). Map marker / list row taps use ``toggleMissionPointMapSelection`` instead.
    private func openMissionPointEditDrawer(missionPointID: UUID) {
        guard draft.missionPoints.contains(where: { $0.id == missionPointID }) else { return }
        selectedMissionPointID = missionPointID
        missionPointDrawerEditingID = missionPointID
        appDrawer.present(title: "Edit map point", preferredWidth: 400, scrimTapDismisses: true) {
            MissionWorkspaceMissionPointEditDrawer(
                missionPointID: missionPointID,
                mission: $draft,
                onStructuralChange: {
                    draft.renumberMissionPointSlugsByListOrder()
                },
                persist: {
                    persistMissionToStoreNow()
                }
            )
        }
    }

    /// Sidebar pencil only: open drawer for this point, or close if already editing this point.
    private func toggleMissionPointEditDrawer(missionPointID: UUID) {
        guard draft.missionPoints.contains(where: { $0.id == missionPointID }) else { return }
        if missionPointDrawerEditingID == missionPointID {
            missionPointDrawerEditingID = nil
            appDrawer.dismiss()
            return
        }
        openMissionPointEditDrawer(missionPointID: missionPointID)
    }

    /// Map marker or sidebar row: select/deselect only; never opens the edit drawer.
    private func toggleMissionPointMapSelection(missionPointID: UUID) {
        guard draft.missionPoints.contains(where: { $0.id == missionPointID }) else { return }
        if selectedMissionPointID == missionPointID {
            selectedMissionPointID = nil
            if missionPointDrawerEditingID == missionPointID {
                missionPointDrawerEditingID = nil
                appDrawer.dismiss()
            }
        } else {
            if missionPointDrawerEditingID != nil {
                appDrawer.dismiss()
                missionPointDrawerEditingID = nil
            }
            selectedMissionPointID = missionPointID
        }
    }

    /// Geofences tab: map polygon/circle tap selects the matching sidebar card and scrolls it into view.
    private func toggleGeofenceMapSelection(fenceID: UUID) {
        let onMission = draft.missionGeofences.contains { $0.id == fenceID }
        let onTask = draft.routeMacro.tasks.contains { $0.geofences.contains { $0.id == fenceID } }
        guard onMission || onTask else { return }
        if selectedGeofenceID == fenceID {
            selectedGeofenceID = nil
            if geofenceDrawerEditingID == fenceID {
                geofenceDrawerEditingID = nil
                appDrawer.dismiss()
            }
        } else {
            if geofenceDrawerEditingID != nil {
                appDrawer.dismiss()
                geofenceDrawerEditingID = nil
            }
            selectedGeofenceID = fenceID
            missionWorkspaceGeofencesListScrollTargetRow = fenceID
            missionWorkspaceGeofencesListScrollEpoch &+= 1
        }
    }

    @MainActor
    private func maybeRebuildFollowRoadAfterWaypointMove(taskIndex: Int, movedIndex: Int) async {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return }
        var wps = draft.routeMacro.tasks[taskIndex].waypoints
        guard wps.indices.contains(movedIndex) else { return }
        guard let prevAnchor = MissionTaskPathSegmentEditing.indexOfPreviousAnchor(in: wps, before: movedIndex) else { return }
        guard wps[prevAnchor].outgoingSegmentKind == .followRoads else { return }
        guard let nextIdx = MissionTaskPathSegmentEditing.indexOfNextAnchor(in: wps, after: prevAnchor) else { return }
        let from = wps[prevAnchor].coord
        let to = wps[nextIdx].coord
        do {
            let dense = try await osmRoutingService.routeDrivingCoordinates(from: from, to: to)
            MissionTaskPathSegmentEditing.rebuildFollowRoadInterior(
                waypoints: &wps,
                anchorFromIndex: prevAnchor,
                denseCoords: dense
            )
            draft.routeMacro.tasks[taskIndex].waypoints = wps
            refreshAutoHeadings(for: taskIndex)
            persistMissionToStoreNow()
        } catch {
            onToast("Could not refresh road leg after move.", .info)
        }
    }

    private func waypointPathRoleLabel(_ waypoint: RouteWaypoint) -> String {
        switch waypoint.pathRole {
        case .segmentInterior:
            return "Road segment sample"
        case .anchor:
            if let out = waypoint.outgoingSegmentKind {
                return out == .direct ? "Anchor · next leg: direct" : "Anchor · next leg: follow roads"
            }
            return "Anchor · path end"
        }
    }

    private var tasksTab: some View {
        GeometryReader { geo in
            let mapWidth = geo.size.width * 0.7
            let listWidth = geo.size.width * 0.3
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    GuardianMapView(
                        model: mapModel,
                        toolbar: GuardianMapToolbarOptions(
                            extraButtons: tasksInnerTab == .points
                                ? [
                                    GuardianMapToolbarButton(
                                        id: "missionPointDrop",
                                        systemImage: missionPointPlacementArmed ? "mappin.circle.fill" : "mappin.and.ellipse",
                                        help: missionPointPlacementArmed
                                            ? "Cancel placing a map point"
                                            : "Place map point — tap map (exits route edit)",
                                        action: {
                                            missionPointPlacementArmed.toggle()
                                            if missionPointPlacementArmed {
                                                editingTaskIndex = nil
                                                selectedWaypointIndex = nil
                                            }
                                        }
                                    ),
                                ]
                                : []
                        ),
                        contextMenuPolicy: GuardianMapContextMenuPolicy(
                            vehicleActions: [],
                            waypointActions: [.deleteWaypoint],
                            homeActions: [],
                            missionPointActions: [.deleteMissionPoint]
                        ),
                        onMapClick: { lat, lon in
                            if suppressNextMapClick {
                                suppressNextMapClick = false
                                return
                            }
                            if missionPointPlacementArmed, editingTaskIndex == nil {
                                addMissionPointAtMap(lat: lat, lon: lon)
                                return
                            }
                            if tasksInnerTab != .routes {
                                return
                            }
                            Task { @MainActor in
                                await handleTaskMapClickAddWaypoint(lat: lat, lon: lon)
                            }
                        },
                        onContextAction: { event in
                            if event.markerType == .missionPoint, event.action == .deleteMissionPoint,
                               let raw = event.markerID, let uuid = UUID(uuidString: raw) {
                                missionPointDeleteCandidate = MissionPointDeleteCandidate(id: uuid)
                                return
                            }
                            guard event.markerType == .waypoint,
                                  event.action == .deleteWaypoint,
                                  let markerID = event.markerID,
                                  let idx = Int(markerID),
                                  let taskIndex = editingTaskIndex,
                                  draft.routeMacro.tasks.indices.contains(taskIndex),
                                  draft.routeMacro.tasks[taskIndex].waypoints.indices.contains(idx)
                            else { return }
                            draft.routeMacro.tasks[taskIndex].waypoints.remove(at: idx)
                            refreshAutoHeadings(for: taskIndex)
                            if let selectedWaypointIndex, selectedWaypointIndex == idx {
                                self.selectedWaypointIndex = nil
                            }
                            persistMissionToStoreNow()
                        },
                        onWaypointClick: { idx in
                            selectedWaypointIndex = idx
                        },
                        onWaypointMoved: { idx, lat, lon in
                            guard let taskIndex = editingTaskIndex,
                                  draft.routeMacro.tasks.indices.contains(taskIndex),
                                  draft.routeMacro.tasks[taskIndex].waypoints.indices.contains(idx) else { return }
                            draft.routeMacro.tasks[taskIndex].waypoints[idx].coord.lat = lat
                            draft.routeMacro.tasks[taskIndex].waypoints[idx].coord.lon = lon
                            refreshAutoHeadings(for: taskIndex)
                            persistMissionToStoreNow()
                            Task { @MainActor in
                                await maybeRebuildFollowRoadAfterWaypointMove(taskIndex: taskIndex, movedIndex: idx)
                            }
                        },
                        onWaypointDelete: { idx in
                            guard let taskIndex = editingTaskIndex,
                                  draft.routeMacro.tasks.indices.contains(taskIndex),
                                  draft.routeMacro.tasks[taskIndex].waypoints.indices.contains(idx) else { return }
                            draft.routeMacro.tasks[taskIndex].waypoints.remove(at: idx)
                            refreshAutoHeadings(for: taskIndex)
                            if let selectedWaypointIndex, selectedWaypointIndex == idx {
                                self.selectedWaypointIndex = nil
                            }
                            persistMissionToStoreNow()
                        },
                        onTaskMapInsert: { idx, lat, lon in
                            guard let taskIndex = editingTaskIndex,
                                  draft.routeMacro.tasks.indices.contains(taskIndex) else { return }
                            suppressNextMapClick = true
                            let waypoint = RouteWaypoint(
                                coord: RouteCoordinate(lat: lat, lon: lon),
                                headingPreset: .followCourse
                            )
                            let safeInsert = max(0, min(idx, draft.routeMacro.tasks[taskIndex].waypoints.count))
                            draft.routeMacro.tasks[taskIndex].waypoints.insert(waypoint, at: safeInsert)

                            var wps = draft.routeMacro.tasks[taskIndex].waypoints
                            if let pa = MissionTaskPathSegmentEditing.indexOfPreviousAnchor(in: wps, before: safeInsert),
                               let na = MissionTaskPathSegmentEditing.indexOfNextAnchor(in: wps, after: safeInsert),
                               na > pa + 1 {
                                for i in stride(from: na - 1, through: pa + 1, by: -1) where wps.indices.contains(i) {
                                    if wps[i].pathRole == .segmentInterior {
                                        wps.remove(at: i)
                                    }
                                }
                                if pa < wps.count {
                                    wps[pa].outgoingSegmentKind = .direct
                                }
                            }
                            draft.routeMacro.tasks[taskIndex].waypoints = wps

                            refreshAutoHeadings(for: taskIndex)
                            selectedTaskIndex = taskIndex
                            selectedWaypointIndex = safeInsert
                            onToast("Waypoint inserted", .success)
                            persistMissionToStoreNow()
                        },
                        onMissionPointClick: { id in
                            toggleMissionPointMapSelection(missionPointID: id)
                        },
                        onMissionPointMoved: { id, lat, lon in
                            guard let idx = draft.missionPoints.firstIndex(where: { $0.id == id }) else { return }
                            draft.missionPoints[idx].coordinate.lat = lat
                            draft.missionPoints[idx].coordinate.lon = lon
                            persistMissionToStoreNow()
                        },
                        onTaskPathTap: { event in
                            if let idx = draft.routeMacro.tasks.firstIndex(where: { $0.id == event.taskPathID }) {
                                selectedTaskIndex = idx
                            }
                        },
                        onViewportCenterChanged: { lat, lon in
                            mapViewportCenter = RouteCoordinate(lat: lat, lon: lon)
                        },
                        onGeofenceClick: { id in
                            guard tasksInnerTab == .geofences else { return }
                            toggleGeofenceMapSelection(fenceID: id)
                        },
                        onGeofenceCircleCenterMoved: { id, lat, lon in
                            guard tasksInnerTab == .geofences else { return }
                            mutateMissionGeofenceFromMap(id: id) { $0.circleCenter.lat = lat; $0.circleCenter.lon = lon }
                        },
                        onGeofenceCircleRadiusMoved: { id, radiusM in
                            guard tasksInnerTab == .geofences else { return }
                            mutateMissionGeofenceFromMap(id: id) { $0.circleRadiusMeters = max(1, radiusM) }
                        },
                        onGeofencePolygonVertexMoved: { id, idx, lat, lon in
                            guard tasksInnerTab == .geofences else { return }
                            mutateMissionGeofenceFromMap(id: id) { g in
                                guard g.shape == .polygon, g.polygonVertices.indices.contains(idx) else { return }
                                g.polygonVertices[idx].lat = lat
                                g.polygonVertices[idx].lon = lon
                            }
                        },
                        onGeofencePolygonTranslated: { id, dLat, dLon in
                            guard tasksInnerTab == .geofences else { return }
                            mutateMissionGeofenceFromMap(id: id) { g in
                                guard g.shape == .polygon else { return }
                                for i in g.polygonVertices.indices {
                                    g.polygonVertices[i].lat += dLat
                                    g.polygonVertices[i].lon += dLon
                                }
                            }
                        },
                        onGeofencePolygonEdgeInsert: { id, afterIndex, lat, lon in
                            guard tasksInnerTab == .geofences else { return }
                            mutateMissionGeofenceFromMap(id: id) { g in
                                guard g.shape == .polygon else { return }
                                var v = g.polygonVertices
                                let n = v.count
                                guard n >= 3, afterIndex >= 0, afterIndex < n else { return }
                                let insertAt = afterIndex + 1
                                let coord = RouteCoordinate(lat: lat, lon: lon)
                                if insertAt >= n {
                                    v.append(coord)
                                } else {
                                    v.insert(coord, at: insertAt)
                                }
                                g.polygonVertices = v
                            }
                        },
                        onGeofencePolygonVertexDelete: { id, idx in
                            guard tasksInnerTab == .geofences else { return }
                            let vertexCount: Int = {
                                if let i = draft.missionGeofences.firstIndex(where: { $0.id == id }) {
                                    return draft.missionGeofences[i].polygonVertices.count
                                }
                                for ti in draft.routeMacro.tasks.indices {
                                    if let fi = draft.routeMacro.tasks[ti].geofences.firstIndex(where: { $0.id == id }) {
                                        return draft.routeMacro.tasks[ti].geofences[fi].polygonVertices.count
                                    }
                                }
                                return 0
                            }()
                            guard vertexCount > 3 else {
                                onToast("A polygon fence needs at least three markers.", .warning)
                                return
                            }
                            mutateMissionGeofenceFromMap(id: id) { g in
                                guard g.shape == .polygon, g.polygonVertices.count > 3, g.polygonVertices.indices.contains(idx) else { return }
                                g.polygonVertices.remove(at: idx)
                            }
                            onToast("Marker removed", .success)
                        }
                    )
                    .task(id: routeTabMapSignature) {
                        mapModel.routeGeometry = GuardianRouteMapGeometry(
                            home: nil,
                            allTasksCoords: allTasksCoords,
                            taskPathIDs: allTaskPathIDs,
                            selectedTaskWaypoints: selectedTask?.waypoints ?? [],
                            selectedWaypointIndex: selectedWaypointIndex,
                            headingPreview: headingPreview,
                            cameraPreview: cameraPreview,
                            preserveView: editingTaskIndex != nil,
                            isEditingTask: editingTaskIndex != nil,
                            missionPointMarkers: missionPointMapMarkers,
                            missionPointPlacementArmed: missionPointPlacementArmed,
                            mcsReservePoolHomePlacementArmed: false,
                            geofenceOverlays: draft.allGuardianGeofenceMapOverlays(
                                mapSelectionFenceID: tasksInnerTab == .geofences ? selectedGeofenceID : nil
                            ),
                            geofenceMapLayerPointerSelectsFence: tasksInnerTab == .geofences
                        )
                    }
                    .frame(width: mapWidth)
                    .frame(maxHeight: .infinity)
                    .clipped()
                }
                .frame(width: mapWidth, height: geo.size.height, alignment: .top)

                Rectangle()
                    .fill(theme.borderSubtle)
                    .frame(width: 1)
                    .frame(height: geo.size.height)

                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                            HStack(spacing: GuardianSpacing.denseGutter) {
                                Picker("", selection: $tasksInnerTab) {
                                    ForEach(MissionWorkspaceTasksInnerTab.allCases) { tab in
                                        Text(tab.title).tag(tab)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 360)
                            }
                            .fixedSize(horizontal: true, vertical: false)

                            Spacer(minLength: GuardianSpacing.sm)

                            Group {
                                if tasksInnerTab == .routes {
                                    GuardianPrimaryProminentButton(title: "Add task") {
                                        let nextNum = draft.routeMacro.tasks.count + 1
                                        draft.routeMacro.tasks.append(MissionTask(name: "Task \(nextNum)"))
                                        selectedTaskIndex = draft.routeMacro.tasks.count - 1
                                        editingTaskIndex = nil
                                        selectedWaypointIndex = nil
                                    }
                                    .guardianPointerOnHover()
                                } else if tasksInnerTab == .points {
                                    GuardianPrimaryProminentButton(title: "Add point") {
                                        appendMissionPointAtViewportCenter()
                                    }
                                    .guardianPointerOnHover()
                                } else {
                                    HStack(spacing: GuardianSpacing.xs) {
                                        GuardianPrimaryProminentButton(title: "Polygon") {
                                            addMissionGeofencePolygon()
                                        }
                                        .guardianPointerOnHover()
                                        GuardianPrimaryProminentButton(title: "Circle") {
                                            addMissionGeofenceCircle()
                                        }
                                        .guardianPointerOnHover()
                                    }
                                    .fixedSize()
                                }
                            }
                        }
                        .padding(.horizontal, GuardianSpacing.md)
                        .padding(.vertical, GuardianSpacing.sm)

                        Rectangle()
                            .fill(theme.borderSubtle)
                            .frame(height: 1)

                        ScrollViewReader { proxy in
                        ScrollView {
                            Group {
                                if tasksInnerTab == .routes {
                                    VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                                        if draft.routeMacro.tasks.isEmpty {
                                            Text("No tasks yet")
                                                .font(GuardianTypography.font(.denseCaption12Regular))
                                                .foregroundStyle(theme.textSecondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        } else {
                                            ForEach(Array(draft.routeMacro.tasks.enumerated()), id: \.offset) { index, path in
                                                GuardianCard(
                                                    configuration: GuardianCardConfiguration(
                                                        border: .subtle,
                                                        cornerRadius: GuardianCardLayout.cornerRadius,
                                                        bodyPadding: GuardianSpacing.cardBodyInset
                                                    ),
                                                    body: {
                                                        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                                                            VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                                                                TextField(
                                                                    "Task name",
                                                                    text: Binding(
                                                                        get: { path.name },
                                                                        set: { newValue in
                                                                            draft.routeMacro.tasks[index].name = newValue
                                                                        }
                                                                    )
                                                                )
                                                                .textFieldStyle(.plain)
                                                                .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                                                                .foregroundStyle(theme.textPrimary)

                                                                VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                                                                    Text("\(path.waypoints.count) wp")
                                                                        .foregroundStyle(theme.textSecondary)
                                                                    Text(distanceLabel(for: path))
                                                                        .foregroundStyle(theme.textSecondary)
                                                                    Text(durationLabel(for: path))
                                                                        .foregroundStyle(theme.textSecondary)
                                                                }
                                                                .font(GuardianTypography.font(.denseCaption12Medium))
                                                            }
                                                            .frame(maxWidth: .infinity, alignment: .leading)

                                                            HStack(spacing: GuardianSpacing.xs) {
                                                                GuardianThemedButton(
                                                                    accent: .neutral,
                                                                    surface: .outline,
                                                                    size: .small,
                                                                    shape: .cornered,
                                                                    contentSizing: .squareToolbarCell,
                                                                    action: { presentTaskSettingsSidebar(taskIndex: index) },
                                                                    label: {
                                                                        Image(systemName: "gearshape.fill")
                                                                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                                                                    }
                                                                )
                                                                .help("Task settings")

                                                                if editingTaskIndex == index {
                                                                    GuardianThemedButton(
                                                                        accent: .primary,
                                                                        surface: .solid,
                                                                        size: .small,
                                                                        shape: .cornered,
                                                                        contentSizing: .squareToolbarCell,
                                                                        action: {
                                                                            missionPointPlacementArmed = false
                                                                            if shouldOfferCloseLoop(path) {
                                                                                pendingCloseLoopTaskIndex = index
                                                                            } else {
                                                                                editingTaskIndex = nil
                                                                                selectedWaypointIndex = nil
                                                                                persistMissionToStoreNow()
                                                                                onToast("Task edit mode disabled", .info)
                                                                            }
                                                                        },
                                                                        label: {
                                                                            Image(systemName: "pencil")
                                                                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                                                                        }
                                                                    )
                                                                    .help("Exit task edit mode")
                                                                } else {
                                                                    GuardianThemedButton(
                                                                        accent: .primary,
                                                                        surface: .outline,
                                                                        size: .small,
                                                                        shape: .cornered,
                                                                        contentSizing: .squareToolbarCell,
                                                                        action: {
                                                                            missionPointPlacementArmed = false
                                                                            editingTaskIndex = index
                                                                            selectedTaskIndex = index
                                                                            pendingOutgoingSegmentKind = .direct
                                                                            onToast("Task edit mode enabled. Click map to add waypoints.", .info)
                                                                        },
                                                                        label: {
                                                                            Image(systemName: "pencil")
                                                                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                                                                        }
                                                                    )
                                                                    .help("Edit route on map")
                                                                }

                                                                GuardianThemedButton(
                                                                    accent: .danger,
                                                                    surface: .outline,
                                                                    size: .small,
                                                                    shape: .cornered,
                                                                    contentSizing: .squareToolbarCell,
                                                                    action: {
                                                                        pendingDeleteTaskIndex = index
                                                                        missionWorkspacePresentedConfirm = .deleteTask
                                                                    },
                                                                    label: {
                                                                        Image(systemName: "trash")
                                                                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                                                                    }
                                                                )
                                                                .help("Delete task")
                                                            }
                                                        }
                                                    }
                                                )
                                                .contentShape(Rectangle())
                                                .onTapGesture { selectedTaskIndex = index }
                                                .overlay {
                                                    if selectedTaskIndex == index {
                                                        RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                                                            .strokeBorder(GuardianSemanticColors.infoForeground.opacity(0.45), lineWidth: 2)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } else if tasksInnerTab == .points {
                                    missionPointsListScrollContent
                                } else {
                                    missionGeofencesListScrollContent
                                }
                            }
                            .padding(.horizontal, GuardianSpacing.md)
                            .padding(.vertical, GuardianSpacing.sm)
                        }
                        .onChange(of: missionWorkspaceMapPointsListScrollEpoch) { _ in
                            guard let id = missionWorkspaceMapPointsListScrollTargetRow else { return }
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.22)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                        .onChange(of: missionWorkspaceGeofencesListScrollEpoch) { _ in
                            guard let id = missionWorkspaceGeofencesListScrollTargetRow else { return }
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.22)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: listWidth, height: geo.size.height)
                    .background(theme.backgroundElevated)

                    if tasksInnerTab == .routes,
                       let taskIndex = editingTaskIndex,
                       draft.routeMacro.tasks.indices.contains(taskIndex) {
                        waypointSidebar(taskIndex: taskIndex)
                            .frame(width: listWidth, height: geo.size.height)
                            .zIndex(1)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .frame(width: listWidth, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.22), value: editingTaskIndex)
        .onChange(of: draft.routeMacro.tasks) { _ in
            guard editingTaskIndex != nil else { return }
            scheduleDebouncedPersistMission()
        }
    }

    private var validTaskIndex: Int {
        guard !draft.routeMacro.tasks.isEmpty else { return 0 }
        return min(max(selectedTaskIndex, 0), draft.routeMacro.tasks.count - 1)
    }

    private var allTasksCoords: [[RouteCoordinate]] {
        draft.routeMacro.tasks.map { $0.waypoints.map(\.coord) }
    }

    private var allTaskPathIDs: [UUID] {
        draft.routeMacro.tasks.map(\.id)
    }

    private var routeTabMissionPointRowSigs: [RouteTabMissionPointRowSig] {
        draft.missionPoints.map {
            RouteTabMissionPointRowSig(
                id: $0.id,
                lat: $0.coordinate.lat,
                lon: $0.coordinate.lon,
                chip: $0.mapChipLabel,
                kind: $0.kind,
                closed: $0.isClosed
            )
        }
    }

    private var missionPointMapMarkers: [GuardianMissionPointMapMarker] {
        draft.missionPoints.map { mp in
            GuardianMissionPointMapMarker(
                id: mp.id,
                lat: mp.coordinate.lat,
                lon: mp.coordinate.lon,
                mapLabelCompact: mp.mapGlyphDigit,
                mapLabelFull: mp.mapChipLabel,
                kindRaw: mp.kind.rawValue,
                isClosed: mp.isClosed,
                isSelected: mp.id == selectedMissionPointID
            )
        }
    }

    /// Drives map overlay updates when geofence geometry changes (nested under ``draft``).
    private var geofenceRouteTabChecksum: String {
        var parts: [String] = []
        for g in draft.missionGeofences {
            parts.append(
                "m:\(g.id.uuidString);\(g.shape.rawValue);\(g.boundary.rawValue);\(g.polygonVertices.count);\(g.circleCenter.lat),\(g.circleCenter.lon);\(g.circleRadiusMeters)"
            )
            for v in g.polygonVertices {
                parts.append("\(v.lat),\(v.lon)")
            }
        }
        for t in draft.routeMacro.tasks {
            for g in t.geofences {
                parts.append(
                    "t:\(t.id.uuidString);\(g.id.uuidString);\(g.shape.rawValue);\(g.boundary.rawValue);\(g.polygonVertices.count);\(g.circleCenter.lat),\(g.circleCenter.lon);\(g.circleRadiusMeters)"
                )
                for v in g.polygonVertices {
                    parts.append("\(v.lat),\(v.lon)")
                }
            }
        }
        if tasksInnerTab == .geofences {
            parts.append("gfsel:\(selectedGeofenceID?.uuidString ?? "nil")")
        }
        return parts.joined(separator: "|")
    }

    private var missionGeofenceDefaultCenter: RouteCoordinate {
        mapViewportCenter ?? RouteCoordinate(lat: -27.4689, lon: 153.0235)
    }

    /// Equatable signature of every input the route-tab map cares about.
    /// Drives `.task(id:)` so the shared `mapModel` is re-pushed whenever the
    /// tasks/selection/preview/edit-state changes.
    private var routeTabMapSignature: RouteTabMapSignature {
        RouteTabMapSignature(
            allTasksCoords: allTasksCoords,
            taskPathIDs: allTaskPathIDs,
            selectedWaypoints: selectedTask?.waypoints.map(\.coord) ?? [],
            selectedWaypointIndex: selectedWaypointIndex,
            headingPreview: headingPreview,
            cameraPreview: cameraPreview,
            isEditingTask: editingTaskIndex != nil,
            missionPointRows: routeTabMissionPointRowSigs,
            selectedMissionPointID: selectedMissionPointID,
            missionPointPlacementArmed: missionPointPlacementArmed,
            tasksInnerTab: tasksInnerTab,
            geofenceChecksum: geofenceRouteTabChecksum
        )
    }

    private var selectedTask: MissionTask? {
        guard !draft.routeMacro.tasks.isEmpty else { return nil }
        return draft.routeMacro.tasks[validTaskIndex]
    }

    private func geofenceTaskScopeLabel(for task: MissionTask) -> String {
        let n = task.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Task" : n
    }

    /// Geofences sub-tab: single list of every template fence (mission-wide, then each task in order).
    private var missionGeofencesListScrollContent: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.md) {
            let hasAnyFence = !draft.missionGeofences.isEmpty
                || draft.routeMacro.tasks.contains { !$0.geofences.isEmpty }
            if !hasAnyFence {
                Text("No fences yet.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textTertiary)
            } else {
                ForEach(draft.missionGeofences) { fence in
                    geofenceListRow(scopeLabel: "Mission", fence: fence)
                        .id(fence.id)
                }
                ForEach(draft.routeMacro.tasks) { task in
                    ForEach(task.geofences) { fence in
                        geofenceListRow(scopeLabel: geofenceTaskScopeLabel(for: task), fence: fence)
                            .id(fence.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func geofenceListRow(scopeLabel: String, fence: MissionGeofence) -> some View {
        let fenceID = fence.id
        let isSelected = selectedGeofenceID == fenceID
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianSpacing.cardBodyInset
            ),
            body: {
                HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                    VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                        Text(fence.name.isEmpty ? "Untitled fence" : fence.name)
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2)
                        HStack(spacing: GuardianSpacing.xs) {
                            Text(scopeLabel)
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(theme.textTertiary)
                            Text("·")
                                .foregroundStyle(theme.textTertiary)
                            Text(fence.shape.displayTitle)
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(theme.textSecondary)
                            Text("·")
                                .foregroundStyle(theme.textTertiary)
                            Text(fence.boundary.displayTitle)
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GuardianThemedButton(
                        accent: .primary,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: { toggleGeofenceEditDrawer(fenceID: fenceID) },
                        label: {
                            Image(systemName: "pencil")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Open or close edit drawer")

                    GuardianThemedButton(
                        accent: .primary,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: { duplicateGeofence(id: fenceID) },
                        label: {
                            Image(systemName: "doc.on.doc")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Duplicate fence")

                    GuardianThemedButton(
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: { removeGeofence(id: fenceID) },
                        label: {
                            Image(systemName: "trash")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Delete fence")
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            toggleGeofenceMapSelection(fenceID: fenceID)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                    .strokeBorder(GuardianSemanticColors.infoForeground.opacity(0.45), lineWidth: 2)
            }
        }
    }

    /// Map points sub-tab scroll body (header with tabs + Add lives in ``tasksTab`` sidebar chrome).
    private var missionPointsListScrollContent: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            if draft.missionPoints.isEmpty {
                Text("No map points yet.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textTertiary)
            } else {
                ForEach(Array(draft.missionPoints.enumerated()), id: \.element.id) { _, mp in
                    missionPointListRow(mp: mp)
                        .id(mp.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func missionPointListRow(mp: MissionPoint) -> some View {
        let sel = mp.id == selectedMissionPointID
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianSpacing.cardBodyInset
            ),
            body: {
                HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                    VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                        Text(mp.mapChipLabel)
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(mp.isClosed ? theme.textTertiary : theme.textPrimary)
                            .strikethrough(mp.isClosed)
                        Text(mp.kind.rawValue.capitalized)
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GuardianThemedButton(
                        accent: .primary,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: { toggleMissionPointEditDrawer(missionPointID: mp.id) },
                        label: {
                            Image(systemName: "pencil")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Open or close edit drawer")

                    GuardianThemedButton(
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: { missionPointDeleteCandidate = MissionPointDeleteCandidate(id: mp.id) },
                        label: {
                            Image(systemName: "trash")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Delete map point")
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            toggleMissionPointMapSelection(missionPointID: mp.id)
        }
        .overlay {
            if sel {
                RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                    .strokeBorder(GuardianSemanticColors.infoForeground.opacity(0.45), lineWidth: 2)
            }
        }
    }

    private var headingPreview: HeadingPreview? {
        guard let fieldKey = focusedHeadingFieldKey else { return nil }
        let tokens = fieldKey.split(separator: "-")
        guard tokens.count == 4,
              tokens[0] == "p",
              tokens[2] == "w",
              let taskIndex = Int(tokens[1]),
              let waypointIndex = Int(tokens[3]),
              draft.routeMacro.tasks.indices.contains(taskIndex),
              draft.routeMacro.tasks[taskIndex].waypoints.indices.contains(waypointIndex) else { return nil }
        let waypoint = draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex]
        return HeadingPreview(
            lat: waypoint.coord.lat,
            lon: waypoint.coord.lon,
            heading: normalizeHeading(waypoint.heading)
        )
    }

    private var cameraPreview: CameraPreview? {
        if let fieldKey = focusedWaypointCameraFieldKey {
            let tokens = fieldKey.split(separator: "-")
            guard tokens.count == 4,
                  tokens[0] == "p",
                  tokens[2] == "w",
                  let taskIndex = Int(tokens[1]),
                  let waypointIndex = Int(tokens[3]),
                  draft.routeMacro.tasks.indices.contains(taskIndex),
                  draft.routeMacro.tasks[taskIndex].waypoints.indices.contains(waypointIndex) else { return nil }
            let waypoint = draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex]
            return CameraPreview(
                lat: waypoint.coord.lat,
                lon: waypoint.coord.lon,
                bearing: normalizeHeading(waypoint.camera.bearing),
                fovDeg: clamp(waypoint.camera.fovDeg, min: 5, max: 170)
            )
        }

        if let fieldKey = focusedTransitionCameraFieldKey {
            let tokens = fieldKey.split(separator: "-")
            guard tokens.count == 4,
                  tokens[0] == "p",
                  tokens[2] == "w",
                  let taskIndex = Int(tokens[1]),
                  let waypointIndex = Int(tokens[3]),
                  draft.routeMacro.tasks.indices.contains(taskIndex),
                  draft.routeMacro.tasks[taskIndex].waypoints.indices.contains(waypointIndex),
                  let anchor = transitionAnchorCoordinate(taskIndex: taskIndex, waypointIndex: waypointIndex) else { return nil }
            let waypoint = draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex]
            return CameraPreview(
                lat: anchor.lat,
                lon: anchor.lon,
                bearing: normalizeHeading(waypoint.transition.cameraBearing),
                fovDeg: clamp(waypoint.camera.fovDeg, min: 5, max: 170)
            )
        }

        return nil
    }

    private func distanceLabel(for path: MissionTask) -> String {
        guard path.waypoints.count > 1 else { return "0 m" }
        var totalMeters: Double = 0
        for idx in 1..<path.waypoints.count {
            let a = path.waypoints[idx - 1].coord
            let b = path.waypoints[idx].coord
            totalMeters += CLLocation(
                latitude: a.lat,
                longitude: a.lon
            ).distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
        }
        if totalMeters < 1000 {
            return "\(Int(totalMeters.rounded())) m"
        }
        return String(format: "%.2f km", totalMeters / 1000)
    }

    private func durationLabel(for path: MissionTask) -> String {
        let totalDelaySeconds = path.waypoints.reduce(0.0) { partial, waypoint in
            partial + delaySeconds(for: waypoint)
        }

        guard path.waypoints.count > 1 else {
            return formatDuration(totalDelaySeconds)
        }

        var transitSeconds = 0.0
        for idx in 1..<path.waypoints.count {
            let start = path.waypoints[idx - 1]
            let end = path.waypoints[idx]
            let legDistanceMeters = CLLocation(
                latitude: start.coord.lat,
                longitude: start.coord.lon
            ).distance(from: CLLocation(latitude: end.coord.lat, longitude: end.coord.lon))
            let speedMetersPerSecond = metersPerSecond(
                value: start.transition.targetSpeed,
                unit: start.transition.speedUnit
            )
            if speedMetersPerSecond > 0 {
                transitSeconds += legDistanceMeters / speedMetersPerSecond
            }
        }

        return formatDuration(totalDelaySeconds + transitSeconds)
    }

    private func delaySeconds(for waypoint: RouteWaypoint) -> Double {
        switch waypoint.delayUnit {
        case .secs:
            return waypoint.delaySec
        case .mins:
            return waypoint.delaySec * 60
        case .hrs:
            return waypoint.delaySec * 3600
        }
    }

    private func metersPerSecond(value: Double, unit: SpeedUnit) -> Double {
        switch unit {
        case .metersPerSecond:
            return value
        case .kilometersPerHour:
            return value / 3.6
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        let hours = rounded / 3600
        let minutes = (rounded % 3600) / 60
        let remainingSeconds = rounded % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, remainingSeconds)
        }
        return "\(remainingSeconds)s"
    }

    private func shouldOfferCloseLoop(_ path: MissionTask) -> Bool {
        guard path.waypoints.count > 2 else { return false }
        guard let first = path.waypoints.first, let last = path.waypoints.last else { return false }
        let distance = CLLocation(latitude: first.coord.lat, longitude: first.coord.lon)
            .distance(from: CLLocation(latitude: last.coord.lat, longitude: last.coord.lon))
        return distance > 2
    }

    /// Closes the path back to the first anchor; respects ``pendingOutgoingSegmentKind`` for the closing leg.
    private func closeLoop(for index: Int) async {
        guard draft.routeMacro.tasks.indices.contains(index) else { return }
        guard let first = draft.routeMacro.tasks[index].waypoints.first else { return }
        var wps = draft.routeMacro.tasks[index].waypoints
        guard let lastAnchorIdx = MissionTaskPathSegmentEditing.anchorFlatIndices(in: wps).last else { return }

        switch pendingOutgoingSegmentKind {
        case .direct:
            if wps.indices.contains(lastAnchorIdx) {
                wps[lastAnchorIdx].outgoingSegmentKind = .direct
            }
            let closingWaypoint = RouteWaypoint(
                coord: first.coord,
                altitude: first.altitude,
                heading: first.heading,
                headingPreset: first.headingPreset,
                delaySec: first.delaySec,
                delayUnit: first.delayUnit,
                action: first.action,
                camera: first.camera,
                transition: first.transition
            )
            wps.append(closingWaypoint)
        case .followRoads:
            let fromCoord = wps[lastAnchorIdx].coord
            let toCoord = first.coord
            do {
                let dense = try await osmRoutingService.routeDrivingCoordinates(from: fromCoord, to: toCoord)
                MissionTaskPathSegmentEditing.appendFollowRoadLeg(
                    waypoints: &wps,
                    templateIndex: lastAnchorIdx,
                    coordinate: toCoord,
                    denseCoords: dense
                )
                if let li = wps.indices.last {
                    let closingId = wps[li].id
                    wps[li] = RouteWaypoint(
                        id: closingId,
                        coord: first.coord,
                        altitude: first.altitude,
                        heading: first.heading,
                        headingPreset: first.headingPreset,
                        delaySec: first.delaySec,
                        delayUnit: first.delayUnit,
                        action: first.action,
                        camera: first.camera,
                        transition: first.transition,
                        pathSegmentId: nil,
                        pathRole: .anchor,
                        pathSegmentKind: .direct,
                        outgoingSegmentKind: nil
                    )
                }
            } catch {
                if wps.indices.contains(lastAnchorIdx) {
                    wps[lastAnchorIdx].outgoingSegmentKind = .direct
                }
                let closingWaypoint = RouteWaypoint(
                    coord: first.coord,
                    altitude: first.altitude,
                    heading: first.heading,
                    headingPreset: first.headingPreset,
                    delaySec: first.delaySec,
                    delayUnit: first.delayUnit,
                    action: first.action,
                    camera: first.camera,
                    transition: first.transition
                )
                wps.append(closingWaypoint)
                onToast("Road routing unavailable; closed loop with a direct leg.", .info)
            }
        }

        draft.routeMacro.tasks[index].waypoints = wps
        draft.routeMacro.tasks[index].loopMode = "loop"
        refreshAutoHeadings(for: index)
    }

    private func sanitizeSelectedWaypointToAnchorIfNeeded(taskIndex: Int) {
        guard let sel = selectedWaypointIndex,
              draft.routeMacro.tasks[taskIndex].waypoints.indices.contains(sel) else { return }
        guard draft.routeMacro.tasks[taskIndex].waypoints[sel].pathRole != .anchor else { return }
        let wps = draft.routeMacro.tasks[taskIndex].waypoints
        if let next = MissionTaskPathSegmentEditing.indexOfNextAnchor(in: wps, after: sel) {
            selectedWaypointIndex = next
        } else if let prev = MissionTaskPathSegmentEditing.indexOfPreviousAnchor(in: wps, before: sel) {
            selectedWaypointIndex = prev
        } else if let firstAnchor = MissionTaskPathSegmentEditing.anchorFlatIndices(in: wps).first {
            selectedWaypointIndex = firstAnchor
        }
    }

    private func waypointSidebar(taskIndex: Int) -> some View {
        let waypoints = draft.routeMacro.tasks[taskIndex].waypoints
        let anchorCount = waypoints.filter { $0.pathRole == .anchor }.count
        let interiorCount = waypoints.filter { $0.pathRole == .segmentInterior }.count
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                    Text("Waypoints")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("\(anchorCount)")
                        .font(GuardianTypography.font(.missionRowKicker12Bold))
                        .foregroundStyle(theme.textSecondary)
                    if interiorCount > 0 {
                        Text("· +\(interiorCount) road")
                            .font(GuardianTypography.font(.formFieldLabel))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer(minLength: GuardianSpacing.xsTight)
                    Picker("", selection: $pendingOutgoingSegmentKind) {
                        Text("Direct").tag(RouteSegmentKind.direct)
                        Text("Road").tag(RouteSegmentKind.followRoads)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 148)
                    GuardianThemedButton(
                        accent: .neutral,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: { openBulkWaypointEditor(taskIndex: taskIndex) },
                        label: {
                            Image(systemName: "gearshape")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Bulk edit all waypoints")
                    GuardianThemedButton(
                        accent: .primary,
                        surface: .solid,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: { finishEditingTaskFromSidebar(taskIndex: taskIndex) },
                        label: {
                            Image(systemName: "checkmark")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Finish task editing")
                }
                .padding(.horizontal, GuardianSpacing.sm)
                .padding(.vertical, GuardianSpacing.denseGutter)
                .frame(maxWidth: .infinity)
                .background(theme.backgroundRaised)

                Rectangle()
                    .fill(theme.borderSubtle)
                    .frame(height: 1)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                        ForEach(MissionTaskPathSegmentEditing.anchorFlatIndices(in: draft.routeMacro.tasks[taskIndex].waypoints), id: \.self) { idx in
                            waypointEditorRow(taskIndex: taskIndex, idx: idx)
                                .id("wp-\(idx)")
                                .onTapGesture {
                                    selectedWaypointIndex = idx
                                }
                        }
                    }
                    .padding(GuardianSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onAppear {
                    sanitizeSelectedWaypointToAnchorIfNeeded(taskIndex: taskIndex)
                }
                .onChange(of: draft.routeMacro.tasks[taskIndex].waypoints.count) { _ in
                    sanitizeSelectedWaypointToAnchorIfNeeded(taskIndex: taskIndex)
                }
                .onChange(of: selectedWaypointIndex) { idx in
                    clearPreviewFocusState()
                    guard let idx else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("wp-\(idx)", anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.backgroundElevated)
        .overlay(
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(width: 1),
            alignment: .leading
        )
    }

    private func waypointEditorRow(taskIndex: Int, idx: Int) -> some View {
        let waypoint = draft.routeMacro.tasks[taskIndex].waypoints[idx]
        let isSelected = selectedWaypointIndex == idx
        let headingKey = headingFieldKey(taskIndex: taskIndex, waypointIndex: idx)
        let anchorOrdinal = draft.routeMacro.tasks[taskIndex].waypoints[...idx].filter { $0.pathRole == .anchor }.count
        let rowTitle = waypoint.pathRole == .anchor ? "Anchor \(anchorOrdinal)" : "Road sample \(idx + 1)"
        return VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            HStack {
                Text(rowTitle)
                    .font(GuardianTypography.font(.missionCardEmphasis13Bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if isSelected {
                    Text("Selected")
                        .font(GuardianTypography.font(.missionMicro10Bold))
                        .foregroundStyle(GuardianSemanticColors.infoForeground)
                }
            }
            Text(waypointPathRoleLabel(waypoint))
                .font(GuardianTypography.font(.denseCaption10Medium))
                .foregroundStyle(theme.textTertiary)

            HStack(spacing: GuardianSpacing.xs) {
                Text("Altitude")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 78, alignment: .leading)
                numericInput(
                    value: Binding(
                        get: { waypoint.altitude.value },
                        set: { draft.routeMacro.tasks[taskIndex].waypoints[idx].altitude.value = clamp($0, min: 0, max: 100_000) }
                    ),
                    step: 1,
                    min: 0,
                    max: 100_000
                )
                .frame(width: 86)
                Picker(
                    "Alt Unit",
                    selection: Binding(
                        get: { waypoint.altitude.unit },
                        set: { draft.routeMacro.tasks[taskIndex].waypoints[idx].altitude.unit = $0 }
                    )
                ) {
                    ForEach(AltitudeUnit.allCases) { unit in
                        Text(unit.rawValue.uppercased()).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 80)

                Picker(
                    "Alt Ref",
                    selection: Binding(
                        get: { waypoint.altitude.reference },
                        set: { draft.routeMacro.tasks[taskIndex].waypoints[idx].altitude.reference = $0 }
                    )
                ) {
                    ForEach(AltitudeReference.allCases) { reference in
                        Text(reference.rawValue).tag(reference)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 96)
            }

            HStack(spacing: GuardianSpacing.xs) {
                Text("Heading")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 78, alignment: .leading)
                Picker(
                    "Preset",
                    selection: Binding<HeadingPreset?>(
                        get: { waypoint.headingPreset },
                        set: { preset in
                            draft.routeMacro.tasks[taskIndex].waypoints[idx].headingPreset = preset
                            applyHeadingPreset(taskIndex: taskIndex, waypointIndex: idx)
                        }
                    )
                ) {
                    Text("Manual").tag(HeadingPreset?.none)
                    Text("Along route").tag(HeadingPreset?.some(.followCourse))
                    if taskIsLooped(taskIndex) {
                        Text("Perimeter Outward").tag(HeadingPreset?.some(.perimeterOutward))
                        Text("Perimeter Inward").tag(HeadingPreset?.some(.perimeterInward))
                    }
                    Text("North").tag(HeadingPreset?.some(.north))
                    Text("East").tag(HeadingPreset?.some(.east))
                    Text("South").tag(HeadingPreset?.some(.south))
                    Text("West").tag(HeadingPreset?.some(.west))
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 104)

                numericInput(
                    value: Binding(
                        get: { waypoint.heading },
                        set: { draft.routeMacro.tasks[taskIndex].waypoints[idx].heading = clamp(normalizeHeading($0), min: 0, max: 359.999) }
                    ),
                    step: 1,
                    min: 0,
                    max: 359.999,
                    onFocusChange: { isFocused in
                        if isFocused {
                            focusedHeadingFieldKey = headingKey
                        } else if focusedHeadingFieldKey == headingKey {
                            focusedHeadingFieldKey = nil
                        }
                    }
                )
                .frame(maxWidth: .infinity)
                .disabled(waypoint.headingPreset != nil)
            }

            HStack(spacing: GuardianSpacing.xs) {
                Text("Delay")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 78, alignment: .leading)
                numericInput(
                    value: Binding(
                        get: { waypoint.delaySec },
                        set: { draft.routeMacro.tasks[taskIndex].waypoints[idx].delaySec = clamp($0, min: 0, max: 100_000) }
                    ),
                    step: 1,
                    min: 0,
                    max: 100_000
                )
                .frame(width: 96)
                Picker(
                    "Delay Unit",
                    selection: Binding(
                        get: { waypoint.delayUnit },
                        set: { draft.routeMacro.tasks[taskIndex].waypoints[idx].delayUnit = $0 }
                    )
                ) {
                    ForEach(DelayUnit.allCases) { unit in
                        Text(unit.missionDelayMenuLabel).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 72)
                Spacer()
            }

            HStack(spacing: GuardianSpacing.xs) {
                Text("Action")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 78, alignment: .leading)
                Picker(
                    "Action",
                    selection: Binding(
                        get: {
                            WaypointActionOption(rawValue: waypoint.action) ?? .none
                        },
                        set: { option in
                            draft.routeMacro.tasks[taskIndex].waypoints[idx].action = option.rawValue
                        }
                    )
                ) {
                    ForEach(WaypointActionOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: GuardianSpacing.xs) {
                Text("Camera")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 78, alignment: .leading)
                Picker(
                    "Camera Mode",
                    selection: Binding(
                        get: { waypoint.camera.mode },
                        set: { mode in
                            draft.routeMacro.tasks[taskIndex].waypoints[idx].camera.mode = mode
                            applyCameraMode(taskIndex: taskIndex, waypointIndex: idx)
                        }
                    )
                ) {
                    Text("Follow Heading").tag(CameraMode.followHeading)
                    if taskIsLooped(taskIndex) {
                        Text("Perimeter Outward").tag(CameraMode.perimeterOutward)
                        Text("Perimeter Inward").tag(CameraMode.perimeterInward)
                    }
                    Text("Manual Bearing").tag(CameraMode.manualBearing)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 132)

                numericInput(
                    value: Binding(
                        get: { waypoint.camera.bearing },
                        set: { draft.routeMacro.tasks[taskIndex].waypoints[idx].camera.bearing = clamp(normalizeHeading($0), min: 0, max: 359.999) }
                    ),
                    step: 1,
                    min: 0,
                    max: 359.999,
                    onFocusChange: { focused in
                        let key = waypointCameraFieldKey(taskIndex: taskIndex, waypointIndex: idx)
                        if focused {
                            focusedWaypointCameraFieldKey = key
                            focusedTransitionCameraFieldKey = nil
                        } else if focusedWaypointCameraFieldKey == key {
                            focusedWaypointCameraFieldKey = nil
                        }
                    }
                )
                .frame(width: 88)
                .disabled(waypoint.camera.mode != .manualBearing)
                Spacer()
            }

            HStack {
                Text("Transition (to next waypoint)")
                    .font(GuardianTypography.font(.denseCaption10Semibold))
                    .foregroundStyle(.gray.opacity(0.9))
                Spacer()
            }
            .padding(.top, GuardianSpacing.xxs)

            HStack(spacing: GuardianSpacing.xs) {
                Text("Transition")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 78, alignment: .leading)
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { waypoint.transition.mode },
                        set: { draft.routeMacro.tasks[taskIndex].waypoints[idx].transition.mode = $0 }
                    )
                ) {
                    ForEach(TransitionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 102)
                numericInput(
                    value: Binding(
                        get: { waypoint.transition.targetSpeed },
                        set: { draft.routeMacro.tasks[taskIndex].waypoints[idx].transition.targetSpeed = clamp($0, min: 0, max: 200) }
                    ),
                    step: 1,
                    min: 0,
                    max: 200
                )
                .frame(width: 86)
                Picker(
                    "Speed Unit",
                    selection: Binding(
                        get: { waypoint.transition.speedUnit },
                        set: { draft.routeMacro.tasks[taskIndex].waypoints[idx].transition.speedUnit = $0 }
                    )
                ) {
                    ForEach(SpeedUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 82)
            }

            HStack(spacing: GuardianSpacing.xs) {
                Text("Cam During")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 78, alignment: .leading)
                Picker(
                    "Transition Camera Mode",
                    selection: Binding(
                        get: { waypoint.transition.cameraMode },
                        set: { mode in
                            draft.routeMacro.tasks[taskIndex].waypoints[idx].transition.cameraMode = mode
                            applyTransitionCameraMode(taskIndex: taskIndex, waypointIndex: idx)
                        }
                    )
                ) {
                    Text("Hold Current").tag(TransitionCameraMode.holdCurrent)
                    Text("Face Next Waypoint").tag(TransitionCameraMode.faceNextWaypoint)
                    if taskIsLooped(taskIndex) {
                        Text("Perimeter Outward").tag(TransitionCameraMode.perimeterOutward)
                        Text("Perimeter Inward").tag(TransitionCameraMode.perimeterInward)
                    }
                    Text("Manual Bearing").tag(TransitionCameraMode.manualBearing)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 170)

                numericInput(
                    value: Binding(
                        get: { waypoint.transition.cameraBearing },
                        set: { draft.routeMacro.tasks[taskIndex].waypoints[idx].transition.cameraBearing = clamp(normalizeHeading($0), min: 0, max: 359.999) }
                    ),
                    step: 1,
                    min: 0,
                    max: 359.999,
                    onFocusChange: { focused in
                        let key = transitionCameraFieldKey(taskIndex: taskIndex, waypointIndex: idx)
                        if focused {
                            focusedTransitionCameraFieldKey = key
                            focusedWaypointCameraFieldKey = nil
                        } else if focusedTransitionCameraFieldKey == key {
                            focusedTransitionCameraFieldKey = nil
                        }
                    }
                )
                .frame(width: 88)
                .disabled(waypoint.transition.cameraMode != .manualBearing)
                Spacer()
            }

            HStack {
                Spacer()
                Button {
                    draft.routeMacro.tasks[taskIndex].waypoints.remove(at: idx)
                    refreshAutoHeadings(for: taskIndex)
                    if selectedWaypointIndex == idx {
                        selectedWaypointIndex = nil
                    }
                    persistMissionToStoreNow()
                } label: {
                    Image(systemName: "trash")
                        .appIconGlyph()
                }
                .buttonStyle(.borderedProminent).guardianPointerOnHover()
                .tint(.red)
                .uniformIconButton()
            }
        }
        .onAppear {
            if waypoint.headingPreset != nil {
                applyHeadingPreset(taskIndex: taskIndex, waypointIndex: idx)
            }
            applyCameraMode(taskIndex: taskIndex, waypointIndex: idx)
            applyTransitionCameraMode(taskIndex: taskIndex, waypointIndex: idx)
        }
        .textFieldStyle(.roundedBorder)
        .padding(GuardianSpacing.denseGutter)
        .background(isSelected ? Color.blue.opacity(0.12) : Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func headingFieldKey(taskIndex: Int, waypointIndex: Int) -> String {
        "p-\(taskIndex)-w-\(waypointIndex)"
    }

    private func waypointCameraFieldKey(taskIndex: Int, waypointIndex: Int) -> String {
        "p-\(taskIndex)-w-\(waypointIndex)"
    }

    private func transitionCameraFieldKey(taskIndex: Int, waypointIndex: Int) -> String {
        "p-\(taskIndex)-w-\(waypointIndex)"
    }

    private func applyHeadingPreset(taskIndex: Int, waypointIndex: Int) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex),
              draft.routeMacro.tasks[taskIndex].waypoints.indices.contains(waypointIndex) else { return }
        guard let preset = draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].headingPreset else { return }
        switch preset {
        case .followCourse:
            if let followHeading = followCourseHeading(taskIndex: taskIndex, waypointIndex: waypointIndex) {
                draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].heading = followHeading
            }
        case .perimeterOutward:
            if let outwardHeading = perimeterHeading(taskIndex: taskIndex, waypointIndex: waypointIndex, outward: true) {
                draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].heading = outwardHeading
            }
        case .perimeterInward:
            if let inwardHeading = perimeterHeading(taskIndex: taskIndex, waypointIndex: waypointIndex, outward: false) {
                draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].heading = inwardHeading
            }
        case .north:
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].heading = 0
        case .east:
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].heading = 90
        case .south:
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].heading = 180
        case .west:
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].heading = 270
        }
    }

    private func refreshAutoHeadings(for taskIndex: Int) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return }
        let waypointCount = draft.routeMacro.tasks[taskIndex].waypoints.count
        guard waypointCount > 0 else { return }
        for waypointIndex in 0..<waypointCount {
            if draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].headingPreset != nil {
                applyHeadingPreset(taskIndex: taskIndex, waypointIndex: waypointIndex)
            }
        }
        refreshCameraModes(for: taskIndex)
        refreshTransitionCameraModes(for: taskIndex)
    }

    private func applyCameraMode(taskIndex: Int, waypointIndex: Int) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex),
              draft.routeMacro.tasks[taskIndex].waypoints.indices.contains(waypointIndex) else { return }

        let mode = draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].camera.mode
        switch mode {
        case .followHeading:
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].camera.bearing =
                draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].heading
        case .perimeterOutward:
            if let heading = perimeterHeading(taskIndex: taskIndex, waypointIndex: waypointIndex, outward: true) {
                draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].camera.bearing = heading
            }
        case .perimeterInward:
            if let heading = perimeterHeading(taskIndex: taskIndex, waypointIndex: waypointIndex, outward: false) {
                draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].camera.bearing = heading
            }
        case .manualBearing:
            break
        }

        applyTransitionCameraMode(taskIndex: taskIndex, waypointIndex: waypointIndex)
    }

    private func refreshCameraModes(for taskIndex: Int) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return }
        let waypointCount = draft.routeMacro.tasks[taskIndex].waypoints.count
        guard waypointCount > 0 else { return }
        for waypointIndex in 0..<waypointCount {
            applyCameraMode(taskIndex: taskIndex, waypointIndex: waypointIndex)
        }
    }

    private func applyTransitionCameraMode(taskIndex: Int, waypointIndex: Int) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex),
              draft.routeMacro.tasks[taskIndex].waypoints.indices.contains(waypointIndex) else { return }

        let cameraMode = draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].transition.cameraMode
        switch cameraMode {
        case .holdCurrent:
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].transition.cameraBearing =
                draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].camera.bearing
        case .faceNextWaypoint:
            if let heading = followCourseHeading(taskIndex: taskIndex, waypointIndex: waypointIndex) {
                draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].transition.cameraBearing = heading
            }
        case .perimeterOutward:
            if let heading = perimeterHeading(taskIndex: taskIndex, waypointIndex: waypointIndex, outward: true) {
                draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].transition.cameraBearing = heading
            }
        case .perimeterInward:
            if let heading = perimeterHeading(taskIndex: taskIndex, waypointIndex: waypointIndex, outward: false) {
                draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].transition.cameraBearing = heading
            }
        case .manualBearing:
            break
        }
    }

    private func refreshTransitionCameraModes(for taskIndex: Int) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return }
        let waypointCount = draft.routeMacro.tasks[taskIndex].waypoints.count
        guard waypointCount > 0 else { return }
        for waypointIndex in 0..<waypointCount {
            applyTransitionCameraMode(taskIndex: taskIndex, waypointIndex: waypointIndex)
        }
    }

    private func taskIsLooped(_ taskIndex: Int) -> Bool {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return false }
        let path = draft.routeMacro.tasks[taskIndex]
        if path.loopMode == "loop" { return true }
        guard path.waypoints.count > 2,
              let first = path.waypoints.first,
              let last = path.waypoints.last else { return false }
        return CLLocation(latitude: first.coord.lat, longitude: first.coord.lon)
            .distance(from: CLLocation(latitude: last.coord.lat, longitude: last.coord.lon)) <= 2
    }

    private func nextWaypointCoordinate(taskIndex: Int, waypointIndex: Int) -> RouteCoordinate? {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return nil }
        let waypoints = draft.routeMacro.tasks[taskIndex].waypoints
        guard waypoints.indices.contains(waypointIndex) else { return nil }
        if waypoints.indices.contains(waypointIndex + 1) {
            return waypoints[waypointIndex + 1].coord
        }
        if taskIsLooped(taskIndex), let first = waypoints.first {
            return first.coord
        }
        return nil
    }

    private func transitionAnchorCoordinate(taskIndex: Int, waypointIndex: Int) -> RouteCoordinate? {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return nil }
        let waypoints = draft.routeMacro.tasks[taskIndex].waypoints
        guard waypoints.indices.contains(waypointIndex),
              let nextCoord = nextWaypointCoordinate(taskIndex: taskIndex, waypointIndex: waypointIndex) else { return nil }
        let current = waypoints[waypointIndex].coord
        return RouteCoordinate(
            lat: (current.lat + nextCoord.lat) / 2,
            lon: (current.lon + nextCoord.lon) / 2
        )
    }

    private func followCourseHeading(taskIndex: Int, waypointIndex: Int) -> Double? {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return nil }
        let path = draft.routeMacro.tasks[taskIndex]
        guard path.waypoints.indices.contains(waypointIndex) else { return nil }

        if path.waypoints.indices.contains(waypointIndex + 1) {
            let from = path.waypoints[waypointIndex].coord
            let to = path.waypoints[waypointIndex + 1].coord
            return bearingDegrees(from: from, to: to)
        }
        if waypointIndex > 0 && path.waypoints.indices.contains(waypointIndex - 1) {
            let from = path.waypoints[waypointIndex - 1].coord
            let to = path.waypoints[waypointIndex].coord
            return bearingDegrees(from: from, to: to)
        }
        return nil
    }

    private func perimeterHeading(taskIndex: Int, waypointIndex: Int, outward: Bool) -> Double? {
        guard taskIsLooped(taskIndex) else {
            return followCourseHeading(taskIndex: taskIndex, waypointIndex: waypointIndex)
        }
        let waypoints = draft.routeMacro.tasks[taskIndex].waypoints
        guard waypoints.count > 2, waypoints.indices.contains(waypointIndex) else { return nil }

        let prevIndex = (waypointIndex - 1 + waypoints.count) % waypoints.count
        let nextIndex = (waypointIndex + 1) % waypoints.count
        let prevCoord = waypoints[prevIndex].coord
        let nextCoord = waypoints[nextIndex].coord
        let tangent = bearingDegrees(from: prevCoord, to: nextCoord)

        let winding = polygonWinding(waypoints.map(\.coord))
        let isCCW = winding > 0
        let outwardOffset: Double = isCCW ? 90 : -90
        let inwardOffset: Double = -outwardOffset
        return normalizeHeading(tangent + (outward ? outwardOffset : inwardOffset))
    }

    private func polygonWinding(_ coords: [RouteCoordinate]) -> Double {
        guard coords.count > 2 else { return 0 }
        var area2 = 0.0
        for i in 0..<coords.count {
            let j = (i + 1) % coords.count
            area2 += (coords[i].lon * coords[j].lat) - (coords[j].lon * coords[i].lat)
        }
        return area2
    }

    private func bearingDegrees(from: RouteCoordinate, to: RouteCoordinate) -> Double {
        let lat1 = from.lat * .pi / 180
        let lat2 = to.lat * .pi / 180
        let dLon = (to.lon - from.lon) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        return normalizeHeading(radians * 180 / .pi)
    }

    private func normalizeHeading(_ heading: Double) -> Double {
        let mod = heading.truncatingRemainder(dividingBy: 360)
        return mod >= 0 ? mod : (mod + 360)
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private func clearPreviewFocusState() {
        focusedHeadingFieldKey = nil
        focusedWaypointCameraFieldKey = nil
        focusedTransitionCameraFieldKey = nil
    }

    private func openBulkWaypointEditor(taskIndex: Int) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return }
        guard !draft.routeMacro.tasks[taskIndex].waypoints.isEmpty else {
            onToast("No waypoints to edit", .info)
            return
        }
        bulkWaypointDraft = draft.routeMacro.tasks[taskIndex].waypoints[0]
        clearPreviewFocusState()
        bulkWaypointEditorSheetContext = BulkWaypointEditorSheetContext(taskIndex: taskIndex)
    }

    private func finishEditingTaskFromSidebar(taskIndex: Int) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return }
        let path = draft.routeMacro.tasks[taskIndex]
        if shouldOfferCloseLoop(path) {
            pendingCloseLoopTaskIndex = taskIndex
            missionWorkspacePresentedConfirm = .closeLoop
            return
        }
        editingTaskIndex = nil
        selectedWaypointIndex = nil
        clearPreviewFocusState()
        persistMissionToStoreNow()
        onToast("Task edit mode disabled", .info)
    }

    private func applyBulkWaypointValues(taskIndex: Int) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return }
        guard !draft.routeMacro.tasks[taskIndex].waypoints.isEmpty else {
            onToast("No waypoints to update", .info)
            return
        }

        for waypointIndex in draft.routeMacro.tasks[taskIndex].waypoints.indices {
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].altitude = bulkWaypointDraft.altitude
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].headingPreset = bulkWaypointDraft.headingPreset
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].heading =
                clamp(normalizeHeading(bulkWaypointDraft.heading), min: 0, max: 359.999)
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].delaySec =
                clamp(bulkWaypointDraft.delaySec, min: 0, max: 100_000)
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].delayUnit = bulkWaypointDraft.delayUnit
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].action = bulkWaypointDraft.action
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].camera = bulkWaypointDraft.camera
            draft.routeMacro.tasks[taskIndex].waypoints[waypointIndex].transition = bulkWaypointDraft.transition
        }

        refreshAutoHeadings(for: taskIndex)
        bulkWaypointEditorSheetContext = nil
        persistMissionToStoreNow()
        onToast("Applied bulk waypoint settings", .success)
    }

    private func numericInput(
        value: Binding<Double>,
        step: Double,
        min: Double,
        max: Double,
        onFocusChange: ((Bool) -> Void)? = nil
    ) -> some View {
        StrictNumberField(
            value: value,
            step: step,
            min: min,
            max: max,
            onFocusChange: onFocusChange
        )
    }

    private func addRosterDeviceToTask(taskIndex: Int) {
        guard draft.routeMacro.tasks.indices.contains(taskIndex) else { return }
        let taskId = draft.routeMacro.tasks[taskIndex].id
        let path = draft.routeMacro.tasks[taskIndex]
        let fields = taskRosterDrafts[taskId] ?? TaskRosterDraft()
        let name = fields.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            onToast("Enter a vehicle callsign", .info)
            return
        }
        var leaderId = fields.leaderRosterDeviceId
        if fields.slot != .wingman && fields.slot != .reserve {
            leaderId = nil
        } else if let lid = leaderId {
            let primaryIds = Set(primaryRosterDevices(on: path).map(\.id))
            if !primaryIds.contains(lid) { leaderId = nil }
        }
        let device = RosterDevice(
            name: name,
            behaviorRoleID: fields.behaviorRoleID,
            slot: fields.slot,
            vehicleClass: fields.vehicleClass,
            leaderRosterDeviceId: leaderId
        )
        draft.rosterDevices.append(device)
        draft.routeMacro.tasks[taskIndex].rosterDeviceIds.append(device.id)
        taskRosterDrafts[taskId] = TaskRosterDraft()
        persistMissionToStoreNow()
    }

    private func bulkWaypointEditorSheet(taskIndex: Int) -> some View {
        Modal(
            title: "Bulk Edit Waypoints",
            headerActions: {
                HStack(spacing: GuardianSpacing.xs) {
                    GuardianThemedButton(
                        title: "Cancel",
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        action: { bulkWaypointEditorSheetContext = nil }
                    )
                    GuardianPrimaryProminentButton(title: "Apply") {
                        applyBulkWaypointValues(taskIndex: taskIndex)
                    }
                }
            },
            bodyContent: {
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: GuardianSpacing.denseGutter, verticalSpacing: GuardianSpacing.denseGutter) {
                    GridRow {
                        bulkRowLabel("Altitude")
                        numericInput(
                            value: Binding(
                                get: { bulkWaypointDraft.altitude.value },
                                set: { bulkWaypointDraft.altitude.value = clamp($0, min: 0, max: 100_000) }
                            ),
                            step: 1,
                            min: 0,
                            max: 100_000
                        )
                        .frame(maxWidth: .infinity)
                        Picker(
                            "Alt Unit",
                            selection: Binding(
                                get: { bulkWaypointDraft.altitude.unit },
                                set: { bulkWaypointDraft.altitude.unit = $0 }
                            )
                        ) {
                            ForEach(AltitudeUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .labelsHidden()
                        
                        Picker(
                            "Alt Ref",
                            selection: Binding(
                                get: { bulkWaypointDraft.altitude.reference },
                                set: { bulkWaypointDraft.altitude.reference = $0 }
                            )
                        ) {
                            ForEach(AltitudeReference.allCases) { reference in
                                Text(reference.rawValue).tag(reference)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    GridRow {
                        bulkRowLabel("Heading")
                        Picker(
                            "Preset",
                            selection: Binding<HeadingPreset?>(
                                get: { bulkWaypointDraft.headingPreset },
                                set: { bulkWaypointDraft.headingPreset = $0 }
                            )
                        ) {
                            Text("Manual").tag(HeadingPreset?.none)
                            Text("Along route").tag(HeadingPreset?.some(.followCourse))
                            if taskIsLooped(taskIndex) {
                                Text("Perimeter Outward").tag(HeadingPreset?.some(.perimeterOutward))
                                Text("Perimeter Inward").tag(HeadingPreset?.some(.perimeterInward))
                            }
                            Text("North").tag(HeadingPreset?.some(.north))
                            Text("East").tag(HeadingPreset?.some(.east))
                            Text("South").tag(HeadingPreset?.some(.south))
                            Text("West").tag(HeadingPreset?.some(.west))
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        numericInput(
                            value: Binding(
                                get: { bulkWaypointDraft.heading },
                                set: { bulkWaypointDraft.heading = clamp(normalizeHeading($0), min: 0, max: 359.999) }
                            ),
                            step: 1,
                            min: 0,
                            max: 359.999
                        )
                        .disabled(bulkWaypointDraft.headingPreset != nil)
                        Color.clear
                    }

                    GridRow {
                        bulkRowLabel("Delay")
                        numericInput(
                            value: Binding(
                                get: { bulkWaypointDraft.delaySec },
                                set: { bulkWaypointDraft.delaySec = clamp($0, min: 0, max: 100_000) }
                            ),
                            step: 1,
                            min: 0,
                            max: 100_000
                        )
                        Picker(
                            "Delay Unit",
                            selection: Binding(
                                get: { bulkWaypointDraft.delayUnit },
                                set: { bulkWaypointDraft.delayUnit = $0 }
                            )
                        ) {
                            ForEach(DelayUnit.allCases) { unit in
                                Text(unit.missionDelayMenuLabel).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        Color.clear
                    }

                    GridRow {
                        bulkRowLabel("Action")
                        Picker(
                            "Action",
                            selection: Binding(
                                get: { WaypointActionOption(rawValue: bulkWaypointDraft.action) ?? .none },
                                set: { bulkWaypointDraft.action = $0.rawValue }
                            )
                        ) {
                            ForEach(WaypointActionOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        Color.clear
                        Color.clear
                    }

                    GridRow {
                        bulkRowLabel("Camera")
                        Picker(
                            "Camera Mode",
                            selection: Binding(
                                get: { bulkWaypointDraft.camera.mode },
                                set: { bulkWaypointDraft.camera.mode = $0 }
                            )
                        ) {
                            Text("Follow Heading").tag(CameraMode.followHeading)
                            if taskIsLooped(taskIndex) {
                                Text("Perimeter Outward").tag(CameraMode.perimeterOutward)
                                Text("Perimeter Inward").tag(CameraMode.perimeterInward)
                            }
                            Text("Manual Bearing").tag(CameraMode.manualBearing)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        numericInput(
                            value: Binding(
                                get: { bulkWaypointDraft.camera.bearing },
                                set: { bulkWaypointDraft.camera.bearing = clamp(normalizeHeading($0), min: 0, max: 359.999) }
                            ),
                            step: 1,
                            min: 0,
                            max: 359.999
                        )
                        .disabled(bulkWaypointDraft.camera.mode != .manualBearing)
                        Color.clear
                    }

                    GridRow {
                        Text("Transition (to next waypoint)")
                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                            .foregroundStyle(.gray.opacity(0.9))
                            .gridCellColumns(4)
                    }

                    GridRow {
                        bulkRowLabel("Transition")
                        Picker(
                            "Mode",
                            selection: Binding(
                                get: { bulkWaypointDraft.transition.mode },
                                set: { bulkWaypointDraft.transition.mode = $0 }
                            )
                        ) {
                            ForEach(TransitionMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        numericInput(
                            value: Binding(
                                get: { bulkWaypointDraft.transition.targetSpeed },
                                set: { bulkWaypointDraft.transition.targetSpeed = clamp($0, min: 0, max: 200) }
                            ),
                            step: 1,
                            min: 0,
                            max: 200
                        )
                        Picker(
                            "Speed Unit",
                            selection: Binding(
                                get: { bulkWaypointDraft.transition.speedUnit },
                                set: { bulkWaypointDraft.transition.speedUnit = $0 }
                            )
                        ) {
                            ForEach(SpeedUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    GridRow {
                        bulkRowLabel("Cam During")
                        Picker(
                            "Transition Camera Mode",
                            selection: Binding(
                                get: { bulkWaypointDraft.transition.cameraMode },
                                set: { bulkWaypointDraft.transition.cameraMode = $0 }
                            )
                        ) {
                            Text("Hold Current").tag(TransitionCameraMode.holdCurrent)
                            Text("Face Next Waypoint").tag(TransitionCameraMode.faceNextWaypoint)
                            if taskIsLooped(taskIndex) {
                                Text("Perimeter Outward").tag(TransitionCameraMode.perimeterOutward)
                                Text("Perimeter Inward").tag(TransitionCameraMode.perimeterInward)
                            }
                            Text("Manual Bearing").tag(TransitionCameraMode.manualBearing)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        numericInput(
                            value: Binding(
                                get: { bulkWaypointDraft.transition.cameraBearing },
                                set: { bulkWaypointDraft.transition.cameraBearing = clamp(normalizeHeading($0), min: 0, max: 359.999) }
                            ),
                            step: 1,
                            min: 0,
                            max: 359.999
                        )
                        .disabled(bulkWaypointDraft.transition.cameraMode != .manualBearing)
                        Color.clear
                    }
                    }
                    .textFieldStyle(.roundedBorder)
                }
            }
        )
        .frame(minWidth: 700, minHeight: 520)
    }

    private func bulkRowLabel(_ text: String) -> some View {
        Text(text)
            .font(GuardianTypography.font(.formFieldLabel))
                .foregroundStyle(theme.textSecondary)
            .frame(width: 132, alignment: .leading)
    }

    private struct TaskRosterDraft: Equatable {
        var name: String = ""
        var behaviorRoleID: String = RosterRole.none.rawValue
        var slot: MissionRosterSlotRole = .primary
        var vehicleClass: FleetVehicleType = .unknown
        var leaderRosterDeviceId: UUID?
    }
}

/// Roster-tab sidebar: edit one ``RosterDevice`` on a task (mirrors task settings overlay pattern).
private struct MissionRosterDeviceSettingsSidebar: View {
    @Binding var device: RosterDevice
    let primariesOnTask: [RosterDevice]
    let onSave: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }
    private var fieldRowLabelFont: Font { GuardianTypography.font(.denseSubsection13Regular) }

    private var slotNeedsLeader: Bool {
        device.slot == .wingman || device.slot == .reserve
    }

    @ViewBuilder
    private func rosterDeviceFieldRow<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
            Text(label)
                .font(fieldRowLabelFont)
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: GuardianSpacing.sm)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                rosterSettingsSection("Callsign") {
                    TextField("Callsign", text: $device.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                rosterSettingsSection("Configuration") {
                    rosterDeviceFieldRow(label: "Class") {
                        Picker("", selection: $device.vehicleClass) {
                            ForEach(FleetVehicleType.allCases, id: \.self) { t in
                                Text(t.classCode).tag(t)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    rosterDeviceFieldRow(label: "Role") {
                        Picker("", selection: $device.behaviorRoleID) {
                            ForEach(RosterRoleCatalog.missionUIPickerBehaviorRoleIDs(), id: \.self) { rid in
                                Text(RosterRoleCatalog.displayName(forBehaviorRoleID: rid)).tag(rid)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .help(
                            RosterRoleCatalog.blurb(forBehaviorRoleID: device.behaviorRoleID)
                                ?? "Optional behavior role for Mission Control / Paladin."
                        )
                    }
                    rosterDeviceFieldRow(label: "Slot") {
                        Picker("", selection: $device.slot) {
                            ForEach(MissionRosterSlotRole.allCases) { r in
                                Text(r.rawValue.capitalized).tag(r)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    .onChange(of: device.slot) { newSlot in
                        if newSlot != .wingman && newSlot != .reserve {
                            device.leaderRosterDeviceId = nil
                        }
                    }

                    if slotNeedsLeader {
                        rosterDeviceFieldRow(label: "Leader") {
                            if primariesOnTask.isEmpty {
                                Text("—")
                                    .font(fieldRowLabelFont)
                                    .foregroundStyle(theme.textSecondary)
                            } else {
                                Picker("", selection: $device.leaderRosterDeviceId) {
                                    Text("Auto").tag(UUID?.none)
                                    ForEach(primariesOnTask) { p in
                                        Text(p.name).tag(Optional(p.id))
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .fixedSize()
                            }
                        }
                    }
                }

                HStack {
                    GuardianPrimaryProminentButton(title: "Save", action: onSave)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func rosterSettingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            Text(title)
                .font(GuardianTypography.font(.subsectionTitleSemibold))
                .foregroundStyle(theme.textPrimary)
            VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Tasks-tab sidebar: edit ``MissionTask`` fields that are not waypoint geometry.
private struct MissionTaskSettingsSidebar: View {
    @Binding var task: MissionTask
    let rosterDevices: [RosterDevice]
    let onSave: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var taskHasSquadWingmen: Bool {
        MissionControlSquadFollowBindingUtilities.taskHasWingmen(
            rosterDevices: rosterDevices,
            task: task
        )
    }

    private func enforceConvoyPatternWhenWingmenPresent() {
        if taskHasSquadWingmen, task.pattern != .convoy {
            task.pattern = .convoy
        }
    }

    private var showsCycles: Bool {
        task.regularity == .continuous || task.regularity == .continuousWithDelay
    }

    private var showsRegularityDelay: Bool {
        task.regularity == .continuousWithDelay
    }

    private var fieldRowLabelFont: Font { GuardianTypography.font(.denseSubsection13Regular) }

    @ViewBuilder
    private func missionTaskSettingsFieldRow<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
            Text(label)
                .font(fieldRowLabelFont)
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: GuardianSpacing.sm)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var missionTaskStaggerTriggerRow: some View {
        missionTaskSettingsFieldRow(label: "Squad stagger") {
            Picker("", selection: $task.staggerTrigger) {
                ForEach(MissionTaskStaggerTrigger.allCases) { trigger in
                    Text(trigger.displayTitle).tag(trigger)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .help("How the first launch wave spaces each primary squad on this task.")
    }

    private var missionTaskStaggerIntervalRow: some View {
        missionTaskSettingsFieldRow(label: "Stagger interval") {
            MissionDelayValueUnitEditor(
                label: "",
                value: $task.staggerIntervalValue,
                unit: $task.staggerIntervalUnit,
                minimumTotalSeconds: 1,
                numericFieldWidth: 96,
                secondaryLabelColor: theme.textSecondary
            )
        }
        .help("Time between each primary's first launch when stagger is fixed interval.")
    }

    private var missionTaskStaggerWaypointRow: some View {
        missionTaskIntStepperFieldRow(
            label: "Stagger waypoint",
            value: Binding(
                get: { task.staggerWaypointIndex + 1 },
                set: { task.staggerWaypointIndex = max(0, $0 - 1) }
            ),
            range: 1...max(1, task.waypoints.count),
            unitSuffix: "on path"
        )
        .help("Each primary after the first launches when the lead reaches this path waypoint.")
    }

    private var missionTaskRegularityRow: some View {
        missionTaskSettingsFieldRow(label: "Regularity") {
            Picker("", selection: $task.regularity) {
                ForEach(MissionTaskRegularity.allCases) { r in
                    Text(r.displayTitle).tag(r)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var missionTaskPatternRow: some View {
        missionTaskSettingsFieldRow(label: "Pattern") {
            if taskHasSquadWingmen {
                Text(MissionTaskPattern.convoy.displayTitle)
                    .font(fieldRowLabelFont)
                    .foregroundStyle(theme.textSecondary)
            } else {
                Picker("", selection: $task.pattern) {
                    ForEach(MissionTaskPattern.allCases) { p in
                        Text(p.displayTitle).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .help(
            taskHasSquadWingmen
                ? "Convoy formation is required when this task includes squad wingmen."
                : "Mission pattern for this task."
        )
    }

    private var missionTaskStartDelayRow: some View {
        missionTaskSettingsFieldRow(label: "Start Delay") {
            MissionDelayValueUnitEditor(
                label: "",
                value: $task.startDelayValue,
                unit: $task.startDelayUnit,
                minimumTotalSeconds: 0,
                numericFieldWidth: 96,
                secondaryLabelColor: theme.textSecondary
            )
        }
    }

    private func missionTaskIntStepperFieldRow(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        unitSuffix: String? = nil
    ) -> some View {
        missionTaskSettingsFieldRow(label: label) {
            HStack(spacing: GuardianSpacing.xsTight) {
                Stepper(value: value, in: range) {
                    Text(String(value.wrappedValue))
                        .font(fieldRowLabelFont)
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .frame(minWidth: 28, alignment: .trailing)
                }
                if let unitSuffix {
                    Text(unitSuffix)
                        .font(fieldRowLabelFont)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .fixedSize()
        }
    }

    private var missionTaskRegularityDelayRow: some View {
        missionTaskSettingsFieldRow(label: "Regularity Delay") {
            MissionDelayValueUnitEditor(
                label: "",
                value: $task.regularityDelayValue,
                unit: $task.regularityDelayUnit,
                minimumTotalSeconds: 1,
                numericFieldWidth: 96,
                secondaryLabelColor: theme.textSecondary
            )
        }
    }

    private var missionTaskCyclesRow: some View {
        missionTaskIntStepperFieldRow(
            label: "Cycles",
            value: $task.cycles,
            range: 0...100,
            unitSuffix: nil
        )
    }

    private var missionTaskBetweenCyclesRow: some View {
        missionTaskSettingsFieldRow(label: "Between cycles") {
            Picker("Between cycles", selection: $task.betweenCycles) {
                ForEach(MissionTaskBetweenCyclesAction.allCases) { action in
                    Text(action.displayTitle).tag(action)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel("Between cycles")
        }
        .help("When this task repeats, what the squad does in the gap before the next cycle starts.")
    }

    @ViewBuilder
    private var missionTaskExecutionSettings: some View {
        missionTaskStaggerTriggerRow
        if task.staggerTrigger == .fixedInterval {
            missionTaskStaggerIntervalRow
        }
        if task.staggerTrigger == .waypointReached, !task.waypoints.isEmpty {
            missionTaskStaggerWaypointRow
        }
        missionTaskRegularityRow
        missionTaskPatternRow
        missionTaskStartDelayRow
        if showsRegularityDelay {
            missionTaskRegularityDelayRow
        }
        if showsCycles {
            missionTaskCyclesRow
            missionTaskBetweenCyclesRow
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                settingsSection("") {
                    missionTaskSettingsFieldRow(label: "Name") {
                        TextField("Task name", text: $task.name)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                settingsSection("") {
                    missionTaskExecutionSettings
                }

                HStack {
                    GuardianPrimaryProminentButton(title: "Save", action: onSave)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear(perform: enforceConvoyPatternWhenWingmenPresent)
        .onChange(of: task.rosterDeviceIds) { _ in
            enforceConvoyPatternWhenWingmenPresent()
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            Text(title)
                .font(GuardianTypography.font(.subsectionTitleSemibold))
                .foregroundStyle(theme.textPrimary)
            VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Mission list / grid cards (shared chrome)

private struct MissionCardMetricBadges: View {
    let taskCount: Int
    let vehicleCount: Int

    var body: some View {
        HStack(spacing: GuardianSpacing.xsTight) {
            GuardianBadge(
                text: "\(taskCount) tasks",
                accent: .secondary,
                paint: .outline,
                size: .small,
                shape: .cornered
            )
            GuardianBadge(
                text: "\(vehicleCount) vehicles",
                accent: .secondary,
                paint: .outline,
                size: .small,
                shape: .cornered
            )
        }
    }
}

private struct MissionCardActionButtons: View {
    let isArchived: Bool
    let onArchiveToggle: () -> Void
    let onClone: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: GuardianSpacing.xsTight) {
            GuardianThemedButton(
                accent: .neutral,
                surface: .outline,
                size: .small,
                shape: .cornered,
                contentSizing: .squareToolbarCell,
                action: onArchiveToggle,
                label: {
                    Image(systemName: isArchived ? "archivebox.fill" : "archivebox")
                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                }
            )
            .help(isArchived ? "Unarchive mission" : "Archive mission")

            GuardianThemedButton(
                accent: .primary,
                surface: .outline,
                size: .small,
                shape: .cornered,
                contentSizing: .squareToolbarCell,
                action: onClone,
                label: {
                    Image(systemName: "doc.on.doc")
                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                }
            )
            .help("Clone mission")

            GuardianThemedButton(
                accent: .danger,
                surface: .outline,
                size: .small,
                shape: .cornered,
                contentSizing: .squareToolbarCell,
                action: onDelete,
                label: {
                    Image(systemName: "trash")
                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                }
            )
            .help("Delete mission")
        }
    }
}

/// Static (success) vs mobile (info) — shared by list and grid mission cards.
private struct MissionTypeCapsuleBadge: View {
    let type: MissionType

    var body: some View {
        let bg: Color
        let fg: Color
        switch type {
        case .staticType:
            bg = GuardianSemanticColors.successBackground
            fg = GuardianSemanticColors.successForeground
        case .mobile:
            bg = GuardianSemanticColors.infoBackground
            fg = GuardianSemanticColors.infoForeground
        }
        return Text(type.rawValue.capitalized)
            .font(GuardianTypography.font(.formFieldLabel))
            .foregroundStyle(fg)
            .lineLimit(1)
            .padding(.horizontal, GuardianSpacing.xs)
            .padding(.vertical, GuardianSpacing.xxs)
            .background(bg)
            .clipShape(Capsule())
    }
}

private struct MissionRow: View {
    let mission: Mission
    let onOpen: () -> Void
    let onArchiveToggle: () -> Void
    let onClone: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var taskCount: Int { mission.routeMacro.tasks.count }
    private var vehicleCount: Int { mission.rosterDevices.count }

    var body: some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(border: .subtle, cornerRadius: 10, bodyPadding: GuardianSpacing.sm),
            body: {
                HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                    MissionCardThumbnailView(mission: mission, fixedLength: 52)

                    VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                        Text(mission.name)
                            .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)

                        Text(mission.description.isEmpty ? "No description" : mission.description)
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)

                        HStack(spacing: GuardianSpacing.xsTight) {
                            if mission.isArchived {
                                GuardianBadge(
                                    text: "Archived",
                                    accent: .neutral,
                                    paint: .light,
                                    size: .small,
                                    shape: .pill
                                )
                            }
                            MissionTypeCapsuleBadge(type: mission.type)
                            MissionCardMetricBadges(taskCount: taskCount, vehicleCount: vehicleCount)
                        }
                    }

                    Spacer(minLength: GuardianSpacing.xsTight)

                    MissionCardActionButtons(
                        isArchived: mission.isArchived,
                        onArchiveToggle: onArchiveToggle,
                        onClone: onClone,
                        onDelete: onDelete
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
        .cursorOnHover()
    }
}

private struct MissionCard: View {
    let mission: Mission
    let onOpen: () -> Void
    let onArchiveToggle: () -> Void
    let onClone: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var taskCount: Int { mission.routeMacro.tasks.count }
    private var vehicleCount: Int { mission.rosterDevices.count }

    var body: some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(border: .subtle, cornerRadius: 10, bodyPadding: GuardianSpacing.cardBodyInset),
            media: {
                MissionCardThumbnailView(mission: mission, gridBannerBarHeight: 120, gridThumbnailSide: 100)
            },
            body: {
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    Text(mission.name)
                        .font(GuardianTypography.font(.windowHeading16Semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .center, spacing: GuardianSpacing.xsTight) {
                        if mission.isArchived {
                            GuardianBadge(
                                text: "Archived",
                                accent: .neutral,
                                paint: .light,
                                size: .small,
                                shape: .pill
                            )
                        }
                        MissionTypeCapsuleBadge(type: mission.type)
                        MissionCardMetricBadges(taskCount: taskCount, vehicleCount: vehicleCount)
                        Spacer(minLength: GuardianSpacing.xxs)
                        MissionCardActionButtons(
                            isArchived: mission.isArchived,
                            onArchiveToggle: onArchiveToggle,
                            onClone: onClone,
                            onDelete: onDelete
                        )
                    }

                    Text(mission.description.isEmpty ? "No description" : mission.description)
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
        .cursorOnHover()
    }
}

private struct AddMissionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MissionStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    @State private var name = ""
    @State private var description = ""
    @State private var type: MissionType = .mobile
    @State private var descriptionEditorHeight: CGFloat = 96

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Modal(
            title: "New Mission",
            headerActions: {
                HStack(spacing: GuardianSpacing.xs) {
                    GuardianThemedButton(
                        title: "Cancel",
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        action: { dismiss() }
                    )
                    GuardianThemedButton(
                        title: "Save Mission",
                        accent: .primary,
                        surface: .solid,
                        size: .small,
                        shape: .cornered,
                        isEnabled: canSave,
                        action: {
                            store.addMission(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                                type: type
                            )
                            toastCenter.show("Mission created", style: .success)
                            dismiss()
                        }
                    )
                }
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    AutoGrowingTextEditor(
                        text: $description,
                        measuredHeight: $descriptionEditorHeight,
                        placeholder: "Description",
                        minHeight: 96,
                        maxHeight: 220
                    )

                    Picker("Type", selection: $type) {
                        Text("mobile").tag(MissionType.mobile)
                        Text("static").tag(MissionType.staticType)
                    }
                    .pickerStyle(.segmented)
                }
            }
        )
        .frame(width: 460)
    }
}

private struct CloneMissionSheet: View {
    let sourceMissionName: String
    let onCancel: () -> Void
    let onClone: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    @State private var cloneName: String

    init(sourceMissionName: String, onCancel: @escaping () -> Void, onClone: @escaping (String) -> Void) {
        self.sourceMissionName = sourceMissionName
        self.onCancel = onCancel
        self.onClone = onClone
        _cloneName = State(initialValue: "\(sourceMissionName) Copy")
    }

    private var canClone: Bool {
        !cloneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Modal(
            title: "Clone Mission",
            headerActions: {
                HStack(spacing: GuardianSpacing.xs) {
                    GuardianThemedButton(
                        title: "Cancel",
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        action: onCancel
                    )
                    GuardianThemedButton(
                        title: "Clone Mission",
                        accent: .primary,
                        surface: .solid,
                        size: .small,
                        shape: .cornered,
                        isEnabled: canClone,
                        action: { onClone(cloneName) }
                    )
                }
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                    Text("Source mission")
                        .font(GuardianTypography.font(.inlineNoticeTitle))
                        .foregroundStyle(theme.textSecondary)
                    Text(sourceMissionName)
                        .font(GuardianTypography.relativeFixed(size: 14, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(theme.textPrimary)

                    Text("New mission name")
                        .font(GuardianTypography.font(.inlineNoticeTitle))
                        .foregroundStyle(theme.textSecondary)
                    TextField("Mission name", text: $cloneName)
                        .textFieldStyle(.roundedBorder)
                }
            }
        )
        .frame(width: 460)
    }
}

private struct AutoGrowingTextEditor: View {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let placeholder: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    /// Match adjacent `TextField` / `.roundedBorder` fill (`NSColor.textBackgroundColor`).
    var fieldBackground: Color = Color(nsColor: .textBackgroundColor)

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var clampedHeight: CGFloat {
        min(max(max(measuredHeight, minHeight), minHeight), maxHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, GuardianSpacing.xs)
                    .padding(.vertical, GuardianSpacing.xs)
            }
            TextEditor(text: $text)
                .font(GuardianTypography.relativeFixed(size: 14, weight: .regular, relativeTo: .callout))
                .foregroundStyle(theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(height: clampedHeight)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fieldBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
                .background(
                    Text(text.isEmpty ? " " : text + "\n")
                        .font(GuardianTypography.relativeFixed(size: 14, weight: .regular, relativeTo: .callout))
                        .foregroundStyle(.clear)
                        .padding(.horizontal, GuardianSpacing.sm)
                        .padding(.vertical, GuardianSpacing.xs)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: AutoGrowingEditorHeightKey.self,
                                    value: proxy.size.height
                                )
                            }
                        )
                        .hidden()
                )
                .onPreferenceChange(AutoGrowingEditorHeightKey.self) { nextHeight in
                    measuredHeight = nextHeight
                }
        }
    }
}

private struct AutoGrowingEditorHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 96

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Roster behavior roles reference (drawer)

private struct RosterBehaviorRolesCatalogDrawerContent: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                ForEach(RosterRoleCatalog.behaviorRoleReferenceOrderedIDs(), id: \.self) { rid in
                    GuardianCard(
                        configuration: GuardianCardConfiguration(
                            border: .subtle,
                            cornerRadius: GuardianCardLayout.cornerRadius,
                            bodyPadding: GuardianCardLayout.defaultBodyPadding
                        ),
                        body: {
                            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                                Text(RosterRoleCatalog.displayName(forBehaviorRoleID: rid))
                                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                                    .foregroundStyle(theme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(Self.blurb(forBehaviorRoleID: rid))
                                    .font(GuardianTypography.font(.denseCaption12Regular))
                                    .foregroundStyle(theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    )
                }
            }
            .padding(GuardianSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func blurb(forBehaviorRoleID id: String) -> String {
        if id == RosterRole.none.rawValue {
            return "Neutral — no behavior-role catalog row is applied. Mission Control and Paladin treat this slot without role-specific tags or weights."
        }
        if let b = RosterRoleCatalog.blurb(forBehaviorRoleID: id), !b.isEmpty { return b }
        return "No description in catalog."
    }
}

private struct PointerOnHoverModifier: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside && !hovering {
                hovering = true
                NSCursor.pointingHand.push()
            } else if !inside && hovering {
                hovering = false
                NSCursor.pop()
            }
        }
    }
}

private enum WaypointActionOption: String, CaseIterable, Identifiable {
    case none

    var id: String { rawValue }
}

private extension View {
    func cursorOnHover() -> some View {
        modifier(PointerOnHoverModifier())
    }
}
