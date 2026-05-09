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
    @ObservedObject var generalSettings: GeneralSettingsStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAddMission = false
    @State private var displayMode: DisplayMode = .list
    @State private var sortMode: SortMode = .newest
    @State private var selectedMissionID: UUID?

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
    }

    private var selectedMission: Mission? {
        guard let selectedMissionID else { return nil }
        return store.missions.first(where: { $0.id == selectedMissionID })
    }

    private var sortedMissions: [Mission] {
        switch sortMode {
        case .newest:
            return store.missions.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return store.missions.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private var missionList: some View {
        VStack(spacing: 0) {
            HStack {
                Button(displayMode == .list ? "Grid View" : "List View") {
                    displayMode = displayMode == .list ? .grid : .list
                }
                .buttonStyle(.bordered)

                Picker("", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()

                Button("Add Mission") {
                    showingAddMission = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(theme.backgroundRaised)

            if sortedMissions.isEmpty {
                VStack {
                    Spacer()
                    Text("No missions yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Use Add Mission to create your first mission template.")
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                }
            } else if displayMode == .list {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedMissions) { mission in
                            Button {
                                selectedMissionID = mission.id
                            } label: {
                                MissionRow(mission: mission)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .cursorOnHover()
                        }
                    }
                    .padding(16)
                }
                .background(theme.backgroundBase)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 320), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(sortedMissions) { mission in
                            Button {
                                selectedMissionID = mission.id
                            } label: {
                                MissionCard(mission: mission)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .cursorOnHover()
                        }
                    }
                    .padding(16)
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
                store.deleteMission(id: missionToDelete.id)
                selectedMissionID = nil
                toastCenter.show("Mission deleted", style: .success)
            },
            persistMission: { updatedMission in
                store.updateMission(updatedMission)
            },
            onToast: { message, style in
                toastCenter.show(message, style: style)
            }
        )
    }
}

private struct RouteTabMapSignature: Equatable {
    let allTasksCoords: [[RouteCoordinate]]
    let selectedWaypoints: [RouteCoordinate]
    let selectedWaypointIndex: Int?
    let headingPreview: HeadingPreview?
    let cameraPreview: CameraPreview?
    let isEditingTask: Bool
}

/// Drives ``View/sheet(item:onDismiss:content:)`` so bulk-edit content is never built as ``EmptyView`` on first open.
private struct BulkWaypointEditorSheetContext: Identifiable {
    let id = UUID()
    let taskIndex: Int
}

private struct MissionWorkspaceView: View {
    enum WorkspaceTab: String, CaseIterable, Identifiable {
        case details = "Details"
        case roster = "Roster"
        case tasks = "Tasks"
        var id: String { rawValue }
    }

    private struct RosterDeviceEditOverlayContext: Equatable {
        let taskIndex: Int
        let deviceId: UUID
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
    @State private var showingDeleteMissionConfirm = false
    @State private var taskRosterDrafts: [UUID: TaskRosterDraft] = [:]
    @State private var bulkWaypointEditorSheetContext: BulkWaypointEditorSheetContext?
    @State private var bulkWaypointDraft = RouteWaypoint()
    @State private var focusedHeadingFieldKey: String?
    @State private var focusedWaypointCameraFieldKey: String?
    @State private var focusedTransitionCameraFieldKey: String?
    @State private var suppressNextMapClick = false
    @State private var detailsDescriptionEditorHeight: CGFloat = 96
    /// Task settings panel hosted **inside** this view so `draft` updates refresh pickers (global ``SidebarOverlay`` does not re-run with mission `@State`).
    @State private var taskSettingsOverlayTaskIndex: Int?
    /// Roster-tab vehicle edit panel (same scrim + slide pattern as task settings).
    @State private var rosterDeviceEditContext: RosterDeviceEditOverlayContext?
    @State private var showingRosterDeleteConfirm = false
    @State private var pendingRosterDelete: RosterDeviceEditOverlayContext?
    /// Coalesces disk writes while typing mission name / description on the Details tab.
    @State private var debouncedPersistMissionTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var sidebarOverlay: SidebarOverlay

    let onBack: () -> Void
    let onDelete: (Mission) -> Void
    /// Writes the mission to persistent storage (no UI feedback).
    let persistMission: (Mission) -> Void
    let onToast: (String, ToastStyle) -> Void

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    /// Matches wingman/reserve “Leader” label + menu footprint so the add row does not jump when Slot changes.
    private static let rosterAddRowSupportsColumnWidth: CGFloat = 264
    /// Leading inset per nesting level for wingmen / reserves under a primary.
    private static let rosterSlotGroupIndentStep: CGFloat = 16

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
                HStack {
                    Picker("", selection: $activeTab) {
                        ForEach(WorkspaceTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360, alignment: .leading)

                    Spacer()

                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "arrow.left")
                            .appIconGlyph()
                    }
                    .buttonStyle(.bordered)
                    .uniformIconButton()

                    Button {
                        showingDeleteMissionConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .appIconGlyph()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .help("Delete Mission")
                    .uniformIconButton()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(theme.backgroundRaised)

                if activeTab == .tasks {
                    tasksTab
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            switch activeTab {
                            case .details:
                                detailsTab
                            case .roster:
                                rosterTab
                            case .tasks:
                                EmptyView()
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
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
                sidebarOverlay.dismiss()
                taskSettingsOverlayTaskIndex = nil
                rosterDeviceEditContext = nil
            }
        }
        .onChange(of: selectedTaskIndex) { _ in
            clearPreviewFocusState()
        }
        .onChange(of: activeTab) { tab in
            if tab != .tasks {
                sidebarOverlay.dismiss()
                taskSettingsOverlayTaskIndex = nil
                clearPreviewFocusState()
            }
            if tab != .roster {
                rosterDeviceEditContext = nil
            }
        }
        .alert("Delete Mission?", isPresented: $showingDeleteMissionConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete(draft)
            }
        } message: {
            Text("This will permanently remove this mission.")
        }
        .alert("Remove vehicle?", isPresented: $showingRosterDeleteConfirm) {
            Button("Cancel", role: .cancel) {
                pendingRosterDelete = nil
            }
            Button("Remove", role: .destructive) {
                if let pending = pendingRosterDelete {
                    performRemoveRosterDeviceFromTask(taskIndex: pending.taskIndex, deviceId: pending.deviceId)
                    pendingRosterDelete = nil
                }
            }
        } message: {
            Text(rosterDeleteConfirmMessage)
        }
        .sheet(item: $bulkWaypointEditorSheetContext) { ctx in
            bulkWaypointEditorSheet(taskIndex: ctx.taskIndex)
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
        Group {
            card("Edit Mission") {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mission Name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        TextField("", text: $draft.name, prompt: Text("Mission name").foregroundColor(theme.textTertiary))
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mission Description")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        AutoGrowingTextEditor(
                            text: $draft.description,
                            measuredHeight: $detailsDescriptionEditorHeight,
                            placeholder: "Description",
                            minHeight: 96,
                            maxHeight: 220
                        )
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Picker("", selection: $draft.type) {
                            Text("mobile").tag(MissionType.mobile)
                            Text("static").tag(MissionType.staticType)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var rosterTab: some View {
        Group {
            VStack(alignment: .leading, spacing: 14) {
                card("Roster") {
                    Text("Vehicles per task")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(
                        "Each mission task lists the vehicles you expect on that route. Use callsigns and slots for planning; "
                            + "you will bind real aircraft in Mission Control."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if draft.routeMacro.tasks.isEmpty {
                    card("Tasks") {
                        Text("No tasks yet. Add tasks on the Tasks tab, then assign vehicles to each task here.")
                            .foregroundStyle(theme.textSecondary)
                    }
                } else {
                    ForEach(Array(draft.routeMacro.tasks.enumerated()), id: \.element.id) { taskIndex, _ in
                        taskRosterCard(taskIndex: taskIndex)
                    }
                }
            }
        }
    }

    private func taskRosterCard(taskIndex: Int) -> some View {
        let path = draft.routeMacro.tasks[taskIndex]
        let taskId = path.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                TextField(
                    "Task name",
                    text: Binding(
                        get: { draft.routeMacro.tasks[taskIndex].name },
                        set: { draft.routeMacro.tasks[taskIndex].name = $0 }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

                Spacer(minLength: 8)

                Button {
                    presentTaskSettingsSidebar(taskIndex: taskIndex)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .appIconGlyph()
                }
                .buttonStyle(.bordered)
                .uniformIconButton()
                .help("Task settings")

                Text("\(path.waypoints.count) waypoints")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundElevated)

            VStack(alignment: .leading, spacing: 10) {
                Text("Vehicles on this task")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)

                if path.rosterDeviceIds.isEmpty {
                    Text("None yet — use the row below.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(taskRosterDisplayRows(for: path)) { row in
                            if let device = draft.rosterDevices.first(where: { $0.id == row.deviceId }) {
                                HStack(alignment: .center, spacing: 8) {
                                    Text(device.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.textPrimary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    rosterDeviceInlineBadges(device: device)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.78)
                                        .layoutPriority(0)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Button {
                                        presentRosterDeviceEdit(taskIndex: taskIndex, deviceId: row.deviceId)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .appIconGlyph()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .uniformIconButton(width: 30, height: 26)
                                    .help("Edit vehicle")

                                    Button {
                                        requestRemoveRosterDevice(taskIndex: taskIndex, deviceId: row.deviceId)
                                    } label: {
                                        Image(systemName: "trash")
                                            .appIconGlyph()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .controlSize(.small)
                                    .uniformIconButton(width: 30, height: 26)
                                    .help("Remove vehicle")
                                }
                                .padding(.leading, CGFloat(row.indentLevel) * Self.rosterSlotGroupIndentStep)
                                .padding(.vertical, 4)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                Divider().overlay(theme.borderSubtle)

                HStack(alignment: .center, spacing: 8) {
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
                    .frame(minWidth: 100, idealWidth: 120, maxWidth: 160, alignment: .leading)
                    .layoutPriority(1)

                    Picker(
                        "Role",
                        selection: Binding(
                            get: { taskRosterDrafts[taskId]?.role ?? .none },
                            set: { v in
                                var d = taskRosterDrafts[taskId] ?? TaskRosterDraft()
                                d.role = v
                                taskRosterDrafts[taskId] = d
                            }
                        )
                    ) {
                        ForEach(RosterRole.allCases) { c in
                            Text(c.rawValue.capitalized).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 148, idealWidth: 168, maxWidth: 220, alignment: .leading)
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
                            HStack(spacing: 8) {
                                Text("Leader")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(theme.textSecondary)
                                    .fixedSize()
                                    .padding(.leading, 4)
                                if primaries.isEmpty {
                                    Text("—")
                                        .font(.system(size: 12))
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

                    Button("Add") {
                        addRosterDeviceToTask(taskIndex: taskIndex)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .layoutPriority(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundElevated)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func rosterDeviceInlineBadges(device: RosterDevice) -> some View {
        HStack(spacing: 6) {
            rosterNeutralCapsuleBadge(device.vehicleClass.classCode)
            rosterSlotSemanticCapsuleBadge(device.slot)
            rosterNeutralCapsuleBadge(rosterBehaviorRoleLabel(device.role))
            if device.slot == .wingman || device.slot == .reserve {
                rosterNeutralCapsuleBadge(rosterLeaderBadgeCaption(device))
            }
        }
    }

    @ViewBuilder
    private func rosterNeutralCapsuleBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(GuardianSemanticColors.neutralBadgeForeground)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
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
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(pair.foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(pair.background)
            .clipShape(Capsule())
    }

    private func rosterBehaviorRoleLabel(_ role: RosterRole) -> String {
        role == .none ? "None" : role.rawValue.capitalized
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
        showingRosterDeleteConfirm = true
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
            SidebarOverlayChrome(title: title, onClose: dismissMissionTaskSettingsOverlay) {
                MissionTaskSettingsSidebar(
                    task: Binding(
                        get: { draft.routeMacro.tasks[taskIndex] },
                        set: { draft.routeMacro.tasks[taskIndex] = $0 }
                    ),
                    onSave: {
                        persistMissionToStoreNow()
                        dismissMissionTaskSettingsOverlay()
                    }
                )
                .padding(16)
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
            SidebarOverlayChrome(title: title, onClose: dismissRosterDeviceEditOverlay) {
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
                    .padding(16)
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

    private var tasksTab: some View {
        GeometryReader { geo in
            let mapWidth = geo.size.width * 0.7
            let listWidth = geo.size.width * 0.3
            HStack(spacing: 0) {
                GuardianMapView(
                        model: mapModel,
                        contextMenuPolicy: GuardianMapContextMenuPolicy(
                            vehicleActions: [],
                            waypointActions: [.deleteWaypoint],
                            homeActions: []
                        ),
                        onMapClick: { lat, lon in
                            if suppressNextMapClick {
                                suppressNextMapClick = false
                                return
                            }

                            guard let taskIndex = editingTaskIndex,
                                  draft.routeMacro.tasks.indices.contains(taskIndex) else { return }

                            draft.routeMacro.tasks[taskIndex].waypoints.append(
                                RouteWaypoint(
                                    coord: RouteCoordinate(lat: lat, lon: lon),
                                    headingPreset: .followCourse
                                )
                            )
                            refreshAutoHeadings(for: taskIndex)
                            selectedTaskIndex = taskIndex
                            selectedWaypointIndex = draft.routeMacro.tasks[taskIndex].waypoints.count - 1
                            onToast("Waypoint added", .success)
                            persistMissionToStoreNow()
                        },
                        onContextAction: { event in
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
                            refreshAutoHeadings(for: taskIndex)
                            selectedTaskIndex = taskIndex
                            selectedWaypointIndex = safeInsert
                            onToast("Waypoint inserted", .success)
                            persistMissionToStoreNow()
                        }
                    )
                    .task(id: routeTabMapSignature) {
                        mapModel.home = nil
                        mapModel.allTasksCoords = allTasksCoords
                        mapModel.selectedTaskWaypoints = selectedTask?.waypoints ?? []
                        mapModel.selectedWaypointIndex = selectedWaypointIndex
                        mapModel.headingPreview = headingPreview
                        mapModel.cameraPreview = cameraPreview
                        mapModel.preserveView = editingTaskIndex != nil
                        mapModel.isEditingTask = editingTaskIndex != nil
                    }
                    .frame(width: mapWidth, height: geo.size.height)
                    .clipped()

                ZStack(alignment: .topTrailing) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Tasks")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Spacer(minLength: 0)
                                Button {
                                    let nextNum = draft.routeMacro.tasks.count + 1
                                    draft.routeMacro.tasks.append(MissionTask(name: "Task \(nextNum)"))
                                    selectedTaskIndex = draft.routeMacro.tasks.count - 1
                                    editingTaskIndex = nil
                                    selectedWaypointIndex = nil
                                } label: {
                                    Image(systemName: "plus")
                                        .appIconGlyph()
                                }
                                .buttonStyle(.bordered)
                                .uniformIconButton()
                            }

                            if draft.routeMacro.tasks.isEmpty {
                                Text("No tasks yet")
                                    .foregroundStyle(theme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(Array(draft.routeMacro.tasks.enumerated()), id: \.offset) { index, path in
                                    HStack {
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
                                        .foregroundStyle(theme.textPrimary)

                                        Text("• \(path.waypoints.count) wp").foregroundStyle(theme.textSecondary)
                                        Text("• \(distanceLabel(for: path))").foregroundStyle(theme.textSecondary)
                                        Text("• \(durationLabel(for: path))").foregroundStyle(theme.textSecondary)
                                        Spacer()

                                        Button {
                                            presentTaskSettingsSidebar(taskIndex: index)
                                        } label: {
                                            Image(systemName: "gearshape.fill")
                                                .appIconGlyph()
                                        }
                                        .buttonStyle(.bordered)
                                        .uniformIconButton()
                                        .help("Task settings")

                                        if editingTaskIndex == index {
                                            Button {
                                                if shouldOfferCloseLoop(path) {
                                                    pendingCloseLoopTaskIndex = index
                                                } else {
                                                    editingTaskIndex = nil
                                                    selectedWaypointIndex = nil
                                                    persistMissionToStoreNow()
                                                    onToast("Task edit mode disabled", .info)
                                                }
                                            } label: {
                                                Image(systemName: "pencil")
                                                    .appIconGlyph()
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.blue)
                                            .uniformIconButton()
                                        } else {
                                            Button {
                                                editingTaskIndex = index
                                                selectedTaskIndex = index
                                                onToast("Task edit mode enabled. Click map to add waypoints.", .info)
                                            } label: {
                                                Image(systemName: "pencil")
                                                    .appIconGlyph()
                                            }
                                            .buttonStyle(.bordered)
                                            .uniformIconButton()
                                        }

                                        Button {
                                            pendingDeleteTaskIndex = index
                                        } label: {
                                            Image(systemName: "trash")
                                                .appIconGlyph()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)
                                        .uniformIconButton()
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedTaskIndex = index }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(theme.backgroundRaised)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        .alert("Delete task?", isPresented: Binding(
                            get: { pendingDeleteTaskIndex != nil },
                            set: { if !$0 { pendingDeleteTaskIndex = nil } }
                        )) {
                            Button("Cancel", role: .cancel) {}
                            Button("Delete", role: .destructive) {
                                if let idx = pendingDeleteTaskIndex,
                                   draft.routeMacro.tasks.indices.contains(idx) {
                                    draft.routeMacro.tasks.remove(at: idx)
                                    if editingTaskIndex == idx {
                                        editingTaskIndex = nil
                                        selectedWaypointIndex = nil
                                    }
                                    if selectedTaskIndex >= draft.routeMacro.tasks.count {
                                        selectedTaskIndex = max(0, draft.routeMacro.tasks.count - 1)
                                    }
                                }
                                pendingDeleteTaskIndex = nil
                                persistMissionToStoreNow()
                            }
                        } message: {
                            Text("This will remove the task and all its waypoints.")
                        }
                        .alert("Close loop for this task?", isPresented: Binding(
                            get: { pendingCloseLoopTaskIndex != nil },
                            set: { if !$0 { pendingCloseLoopTaskIndex = nil } }
                        )) {
                            Button("No", role: .destructive) {
                                editingTaskIndex = nil
                                selectedWaypointIndex = nil
                                pendingCloseLoopTaskIndex = nil
                                persistMissionToStoreNow()
                                onToast("Task edit mode disabled", .info)
                            }
                            Button("Close Loop") {
                                if let idx = pendingCloseLoopTaskIndex,
                                   draft.routeMacro.tasks.indices.contains(idx) {
                                    closeLoop(for: idx)
                                    editingTaskIndex = nil
                                    selectedWaypointIndex = nil
                                    onToast("Loop closed", .success)
                                }
                                pendingCloseLoopTaskIndex = nil
                                persistMissionToStoreNow()
                            }
                        } message: {
                            Text("Add the start waypoint to the end and mark this task as looped?")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)

                    if let taskIndex = editingTaskIndex,
                       draft.routeMacro.tasks.indices.contains(taskIndex) {
                        waypointSidebar(taskIndex: taskIndex)
                            .frame(width: listWidth, height: geo.size.height)
                            .zIndex(1)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .frame(width: listWidth, height: geo.size.height)
                .background(theme.backgroundBase)
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

    /// Equatable signature of every input the route-tab map cares about.
    /// Drives `.task(id:)` so the shared `mapModel` is re-pushed whenever the
    /// tasks/selection/preview/edit-state changes.
    private var routeTabMapSignature: RouteTabMapSignature {
        RouteTabMapSignature(
            allTasksCoords: allTasksCoords,
            selectedWaypoints: selectedTask?.waypoints.map(\.coord) ?? [],
            selectedWaypointIndex: selectedWaypointIndex,
            headingPreview: headingPreview,
            cameraPreview: cameraPreview,
            isEditingTask: editingTaskIndex != nil
        )
    }

    private var selectedTask: MissionTask? {
        guard !draft.routeMacro.tasks.isEmpty else { return nil }
        return draft.routeMacro.tasks[validTaskIndex]
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

    private func closeLoop(for index: Int) {
        guard draft.routeMacro.tasks.indices.contains(index) else { return }
        guard let first = draft.routeMacro.tasks[index].waypoints.first else { return }
        let closingWaypoint = RouteWaypoint(
            coord: first.coord,
            altitude: first.altitude,
            heading: first.heading,
            delaySec: 0,
            action: "none",
            camera: first.camera
        )
        draft.routeMacro.tasks[index].waypoints.append(closingWaypoint)
        draft.routeMacro.tasks[index].loopMode = "loop"
        refreshAutoHeadings(for: index)
    }

    private func waypointSidebar(taskIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Waypoints")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("\(draft.routeMacro.tasks[taskIndex].waypoints.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Button {
                        openBulkWaypointEditor(taskIndex: taskIndex)
                    } label: {
                        Image(systemName: "gearshape")
                            .appIconGlyph()
                    }
                    .buttonStyle(.bordered)
                    .help("Bulk edit all waypoints")
                    .uniformIconButton()
                    Button {
                        finishEditingTaskFromSidebar(taskIndex: taskIndex)
                    } label: {
                        Image(systemName: "checkmark")
                            .appIconGlyph()
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Finish task editing")
                    .uniformIconButton()
                    
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.2))

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(draft.routeMacro.tasks[taskIndex].waypoints.enumerated()), id: \.element.id) { idx, _ in
                            waypointEditorRow(taskIndex: taskIndex, idx: idx)
                                .id("wp-\(idx)")
                                .onTapGesture {
                                    selectedWaypointIndex = idx
                                }
                        }
                    }
                    .padding(12)
                }
                .onChange(of: selectedWaypointIndex) { idx in
                    clearPreviewFocusState()
                    guard let idx else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("wp-\(idx)", anchor: .center)
                    }
                }
                .onChange(of: draft.routeMacro.tasks[taskIndex].waypoints.count) { _ in
                    guard let idx = selectedWaypointIndex else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("wp-\(idx)", anchor: .center)
                    }
                }
            }
        }
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Waypoint \(idx + 1)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if isSelected {
                    Text("Selected")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 8) {
                Text("Altitude")
                    .font(.system(size: 11, weight: .semibold))
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

            HStack(spacing: 8) {
                Text("Heading")
                    .font(.system(size: 11, weight: .semibold))
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

            HStack(spacing: 8) {
                Text("Delay")
                    .font(.system(size: 11, weight: .semibold))
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
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 72)
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Action")
                    .font(.system(size: 11, weight: .semibold))
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

            HStack(spacing: 8) {
                Text("Camera")
                    .font(.system(size: 11, weight: .semibold))
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.gray.opacity(0.9))
                Spacer()
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                Text("Transition")
                    .font(.system(size: 11, weight: .semibold))
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

            HStack(spacing: 8) {
                Text("Cam During")
                    .font(.system(size: 11, weight: .semibold))
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
                .buttonStyle(.borderedProminent)
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
        .padding(10)
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
            role: fields.role,
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Bulk Edit Waypoints")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Cancel") {
                    bulkWaypointEditorSheetContext = nil
                }
                .buttonStyle(.bordered)
                Button("Apply") {
                    applyBulkWaypointValues(taskIndex: taskIndex)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .controlSize(.small)
            .padding(.bottom, 4)

            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
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
                                Text(unit.rawValue).tag(unit)
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
                            .font(.system(size: 14, weight: .semibold))
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
            .padding(.top, 4)
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 520)
        .background(theme.backgroundElevated)
    }

    private func bulkRowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            .frame(width: 132, alignment: .leading)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        card(title, trailing: { EmptyView() }, content: content)
    }

    private func card<Trailing: View, Content: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private struct TaskRosterDraft: Equatable {
        var name: String = ""
        var role: RosterRole = .none
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
    private var fieldRowLabelFont: Font { .system(size: 13) }

    private var slotNeedsLeader: Bool {
        device.slot == .wingman || device.slot == .reserve
    }

    @ViewBuilder
    private func rosterDeviceFieldRow<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(fieldRowLabelFont)
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 12)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
                        Picker("", selection: $device.role) {
                            ForEach(RosterRole.allCases) { r in
                                Text(r.rawValue.capitalized).tag(r)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
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
                    Button("Save") {
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Tasks-tab sidebar: edit ``MissionTask`` fields that are not waypoint geometry.
private struct MissionTaskSettingsSidebar: View {
    @Binding var task: MissionTask
    let onSave: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var showsRepeatCount: Bool {
        task.regularity == .continuous || task.regularity == .continuousWithDelay
    }

    private var showsRegularityDelay: Bool {
        task.regularity == .continuousWithDelay
    }

    private var fieldRowLabelFont: Font { .system(size: 13) }

    @ViewBuilder
    private func missionTaskSettingsFieldRow<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(fieldRowLabelFont)
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 12)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var missionTaskMethodRow: some View {
        missionTaskSettingsFieldRow(label: "Method") {
            Picker("", selection: $task.executionMethod) {
                ForEach(MissionTaskExecutionMethod.allCases) { m in
                    Text(m.displayTitle).tag(m)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
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

    private var missionTaskStartDelayRow: some View {
        missionTaskIntStepperFieldRow(
            label: "Start Delay",
            value: $task.startDelay,
            range: 0...59,
            unitSuffix: "mins"
        )
    }

    private func missionTaskIntStepperFieldRow(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        unitSuffix: String? = nil
    ) -> some View {
        missionTaskSettingsFieldRow(label: label) {
            HStack(spacing: 6) {
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
        missionTaskIntStepperFieldRow(
            label: "Regularity Delay",
            value: $task.regularityDelayMinutes,
            range: 1...60,
            unitSuffix: "mins"
        )
    }

    private var missionTaskRepeatCountRow: some View {
        missionTaskIntStepperFieldRow(
            label: "Repeat Count",
            value: $task.repeatCount,
            range: 0...100,
            unitSuffix: nil
        )
    }

    @ViewBuilder
    private var missionTaskExecutionSettings: some View {
        missionTaskMethodRow
        missionTaskRegularityRow
        missionTaskPatternRow
        missionTaskStartDelayRow
        if showsRegularityDelay {
            missionTaskRegularityDelayRow
        }
        if showsRepeatCount {
            missionTaskRepeatCountRow
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
                    Button("Save") {
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MissionRow: View {
    let mission: Mission
    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mission.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text(mission.type.rawValue.capitalized)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            }
            Text(mission.description.isEmpty ? "No description" : mission.description)
                .foregroundStyle(theme.textSecondary)
            Text("Count: \(mission.count)  Duration: \(mission.duration)")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MissionCard: View {
    let mission: Mission
    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(mission.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text(mission.type.rawValue.capitalized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            }
            Text(mission.description.isEmpty ? "No description" : mission.description)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2)
            Divider().overlay(.gray.opacity(0.25))
            Text("Count: \(mission.count)")
                .foregroundStyle(theme.textSecondary)
            Text("Duration: \(mission.duration)")
                .foregroundStyle(theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct AddMissionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MissionStore
    @EnvironmentObject private var toastCenter: ToastCenter

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
                HStack(spacing: 8) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button("Save Mission") {
                        store.addMission(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                            type: type
                        )
                        toastCenter.show("Mission created", style: .success)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!canSave)
                }
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: 14) {
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

private struct AutoGrowingTextEditor: View {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let placeholder: String
    let minHeight: CGFloat
    let maxHeight: CGFloat

    private var clampedHeight: CGFloat {
        min(max(max(measuredHeight, minHeight), minHeight), maxHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            TextEditor(text: $text)
                .font(.system(size: 14))
                .frame(height: clampedHeight)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .background(
                    Text(text.isEmpty ? " " : text + "\n")
                        .font(.system(size: 14))
                        .foregroundStyle(.clear)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
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
