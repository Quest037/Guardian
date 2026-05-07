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
    @State private var showingAddMission = false
    @State private var displayMode: DisplayMode = .list
    @State private var sortMode: SortMode = .newest
    @State private var selectedMissionID: UUID?

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
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))

            if sortedMissions.isEmpty {
                VStack {
                    Spacer()
                    Text("No missions yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Use Add Mission to create your first mission template.")
                        .foregroundStyle(.gray)
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
                .background(Color(red: 0.07, green: 0.07, blue: 0.08))
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
                .background(Color(red: 0.07, green: 0.07, blue: 0.08))
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
            onSave: { updatedMission in
                store.updateMission(updatedMission)
                toastCenter.show("Mission saved", style: .success)
            },
            onToast: { message, style in
                toastCenter.show(message, style: style)
            }
        )
    }
}

private struct RouteTabMapSignature: Equatable {
    let homeCoord: RouteCoordinate?
    let allPathsCoords: [[RouteCoordinate]]
    let selectedWaypoints: [RouteCoordinate]
    let selectedWaypointIndex: Int?
    let headingPreview: HeadingPreview?
    let cameraPreview: CameraPreview?
    let isEditingPath: Bool
}

private struct MissionWorkspaceView: View {
    enum WorkspaceTab: String, CaseIterable, Identifiable {
        case details = "Details"
        case roster = "Roster"
        case route = "Route"
        var id: String { rawValue }
    }

    @State private var draft: Mission
    @State private var activeTab: WorkspaceTab = .details
    @State private var selectedPathIndex = 0
    @State private var editingPathIndex: Int?
    @State private var selectedWaypointIndex: Int?
    @StateObject private var mapModel: GuardianMapModel
    @State private var setHomeFromMap = false
    @State private var showingDeleteHomeConfirm = false
    @State private var pendingDeletePathIndex: Int?
    @State private var pendingCloseLoopPathIndex: Int?
    @State private var showingDeleteMissionConfirm = false
    @State private var pathRosterDrafts: [UUID: PathRosterDraft] = [:]
    @State private var showingBulkWaypointEditor = false
    @State private var bulkEditPathIndex: Int?
    @State private var bulkWaypointDraft = RouteWaypoint()
    @State private var focusedHeadingFieldKey: String?
    @State private var focusedWaypointCameraFieldKey: String?
    @State private var focusedTransitionCameraFieldKey: String?
    @State private var suppressNextMapClick = false
    @State private var detailsDescriptionEditorHeight: CGFloat = 96

    let onBack: () -> Void
    let onDelete: (Mission) -> Void
    let onSave: (Mission) -> Void
    let onToast: (String, ToastStyle) -> Void

    init(
        mission: Mission,
        defaultMapTileStyle: MapTileStyle,
        onBack: @escaping () -> Void,
        onDelete: @escaping (Mission) -> Void,
        onSave: @escaping (Mission) -> Void,
        onToast: @escaping (String, ToastStyle) -> Void
    ) {
        _draft = State(initialValue: mission)
        _mapModel = StateObject(
            wrappedValue: GuardianMapModel(mapStyle: defaultMapTileStyle)
        )
        self.onBack = onBack
        self.onDelete = onDelete
        self.onSave = onSave
        self.onToast = onToast
    }

    var body: some View {
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
                    if editingPathIndex != nil {
                        onToast("Finish path editing before saving mission", .info)
                        return
                    }
                    onSave(draft)
                } label: {
                    Image(systemName: "externaldrive.fill")
                        .appIconGlyph()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .help("Save Mission")
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
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))

            if activeTab == .route {
                routeTab
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch activeTab {
                        case .details:
                            detailsTab
                        case .roster:
                            rosterTab
                        case .route:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(red: 0.07, green: 0.07, blue: 0.08))
            }
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        .onChange(of: editingPathIndex) { _ in
            clearPreviewFocusState()
        }
        .onChange(of: selectedPathIndex) { _ in
            clearPreviewFocusState()
        }
        .onChange(of: activeTab) { tab in
            if tab != .route {
                clearPreviewFocusState()
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
        .sheet(isPresented: $showingBulkWaypointEditor, onDismiss: {
            bulkEditPathIndex = nil
        }) {
            if let pathIndex = bulkEditPathIndex, draft.routeMacro.paths.indices.contains(pathIndex) {
                bulkWaypointEditorSheet(pathIndex: pathIndex)
            } else {
                EmptyView()
            }
        }
    }

    private var detailsTab: some View {
        Group {
            card("Edit Mission") {
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                AutoGrowingTextEditor(
                    text: $draft.description,
                    measuredHeight: $detailsDescriptionEditorHeight,
                    placeholder: "Description",
                    minHeight: 96,
                    maxHeight: 220
                )
                Picker("Type", selection: $draft.type) {
                    Text("mobile").tag(MissionType.mobile)
                    Text("static").tag(MissionType.staticType)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var rosterTab: some View {
        Group {
            VStack(alignment: .leading, spacing: 14) {
                card("Roster") {
                    Text("Devices per path")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(
                        "Each route path can carry one or more expected devices. Use labels and roles for planning; "
                            + "you will bind real drones or payloads later in Mission Control."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if draft.routeMacro.paths.isEmpty {
                    card("Paths") {
                        Text("No paths yet. Add paths on the Route tab, then assign devices to each path here.")
                            .foregroundStyle(.gray)
                    }
                } else {
                    ForEach(Array(draft.routeMacro.paths.enumerated()), id: \.element.id) { pathIndex, _ in
                        pathRosterCard(pathIndex: pathIndex)
                    }
                }
            }
        }
    }

    private func pathRosterCard(pathIndex: Int) -> some View {
        let path = draft.routeMacro.paths[pathIndex]
        let pathId = path.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                TextField(
                    "Path name",
                    text: Binding(
                        get: { draft.routeMacro.paths[pathIndex].name },
                        set: { draft.routeMacro.paths[pathIndex].name = $0 }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

                Spacer(minLength: 8)

                Text("\(path.waypoints.count) waypoints")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.10, green: 0.10, blue: 0.11))

            VStack(alignment: .leading, spacing: 10) {
                Text("Devices on this path")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gray)

                if path.rosterDeviceIds.isEmpty {
                    Text("None yet — add one below.")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray.opacity(0.9))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(path.rosterDeviceIds, id: \.self) { deviceId in
                            if let device = draft.rosterDevices.first(where: { $0.id == deviceId }) {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text(deviceSubtitle(device))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.gray)
                                    }
                                    Spacer(minLength: 8)
                                    Button {
                                        removeRosterDeviceFromPath(pathIndex: pathIndex, deviceId: deviceId)
                                    } label: {
                                        Image(systemName: "trash")
                                            .appIconGlyph()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .controlSize(.small)
                                    .uniformIconButton(width: 30, height: 26)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                Text("Add device")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gray)

                HStack(spacing: 8) {
                    TextField(
                        "Device label",
                        text: rosterDraftFieldBinding(pathId: pathId, keyPath: \.name)
                    )
                    .textFieldStyle(.roundedBorder)
                    TextField(
                        "Role",
                        text: rosterDraftFieldBinding(pathId: pathId, keyPath: \.role)
                    )
                    .textFieldStyle(.roundedBorder)
                    TextField(
                        "Notes",
                        text: rosterDraftFieldBinding(pathId: pathId, keyPath: \.hint)
                    )
                    .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addRosterDeviceToPath(pathIndex: pathIndex)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.10, green: 0.10, blue: 0.11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func deviceSubtitle(_ device: RosterDevice) -> String {
        let role = device.roleType.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = device.positionHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if role.isEmpty, hint.isEmpty { return "—" }
        if role.isEmpty { return hint }
        if hint.isEmpty { return role }
        return "\(role) · \(hint)"
    }

    private func rosterDraftFieldBinding(pathId: UUID, keyPath: WritableKeyPath<PathRosterDraft, String>) -> Binding<String> {
        Binding(
            get: { (pathRosterDrafts[pathId] ?? PathRosterDraft())[keyPath: keyPath] },
            set: { newValue in
                var draftRow = pathRosterDrafts[pathId] ?? PathRosterDraft()
                draftRow[keyPath: keyPath] = newValue
                pathRosterDrafts[pathId] = draftRow
            }
        )
    }

    private var routeTab: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    GuardianMapView(
                        model: mapModel,
                        onMapClick: { lat, lon in
                            if suppressNextMapClick {
                                suppressNextMapClick = false
                                return
                            }
                            if setHomeFromMap {
                                var home = draft.routeMacro.home ?? RouteHome()
                                home.coord.lat = lat
                                home.coord.lon = lon
                                draft.routeMacro.home = home
                                setHomeFromMap = false
                                onToast("Home saved from map", .success)
                                return
                            }

                            guard let pathIndex = editingPathIndex,
                                  draft.routeMacro.paths.indices.contains(pathIndex) else { return }

                            draft.routeMacro.paths[pathIndex].waypoints.append(
                                RouteWaypoint(
                                    coord: RouteCoordinate(lat: lat, lon: lon),
                                    headingPreset: .followPath
                                )
                            )
                            refreshAutoHeadings(for: pathIndex)
                            selectedPathIndex = pathIndex
                            selectedWaypointIndex = draft.routeMacro.paths[pathIndex].waypoints.count - 1
                            onToast("Waypoint added", .success)
                        },
                        onWaypointClick: { idx in
                            selectedWaypointIndex = idx
                        },
                        onWaypointMoved: { idx, lat, lon in
                            guard let pathIndex = editingPathIndex,
                                  draft.routeMacro.paths.indices.contains(pathIndex),
                                  draft.routeMacro.paths[pathIndex].waypoints.indices.contains(idx) else { return }
                            draft.routeMacro.paths[pathIndex].waypoints[idx].coord.lat = lat
                            draft.routeMacro.paths[pathIndex].waypoints[idx].coord.lon = lon
                            refreshAutoHeadings(for: pathIndex)
                        },
                        onWaypointDelete: { idx in
                            guard let pathIndex = editingPathIndex,
                                  draft.routeMacro.paths.indices.contains(pathIndex),
                                  draft.routeMacro.paths[pathIndex].waypoints.indices.contains(idx) else { return }
                            draft.routeMacro.paths[pathIndex].waypoints.remove(at: idx)
                            refreshAutoHeadings(for: pathIndex)
                            if let selectedWaypointIndex, selectedWaypointIndex == idx {
                                self.selectedWaypointIndex = nil
                            }
                        },
                        onPathInsert: { idx, lat, lon in
                            guard let pathIndex = editingPathIndex,
                                  draft.routeMacro.paths.indices.contains(pathIndex) else { return }
                            suppressNextMapClick = true
                            let waypoint = RouteWaypoint(
                                coord: RouteCoordinate(lat: lat, lon: lon),
                                headingPreset: .followPath
                            )
                            let safeInsert = max(0, min(idx, draft.routeMacro.paths[pathIndex].waypoints.count))
                            draft.routeMacro.paths[pathIndex].waypoints.insert(waypoint, at: safeInsert)
                            refreshAutoHeadings(for: pathIndex)
                            selectedPathIndex = pathIndex
                            selectedWaypointIndex = safeInsert
                            onToast("Waypoint inserted", .success)
                        }
                    )
                    .task(id: routeTabMapSignature) {
                        mapModel.home = draft.routeMacro.home
                        mapModel.allPathsCoords = allPathsCoords
                        mapModel.selectedPathWaypoints = selectedPath?.waypoints ?? []
                        mapModel.selectedWaypointIndex = selectedWaypointIndex
                        mapModel.headingPreview = headingPreview
                        mapModel.cameraPreview = cameraPreview
                        mapModel.preserveView = editingPathIndex != nil
                        mapModel.isEditingPath = editingPathIndex != nil
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 500)

                    if let pathIndex = editingPathIndex,
                       draft.routeMacro.paths.indices.contains(pathIndex) {
                        waypointSidebar(pathIndex: pathIndex)
                            .frame(width: 390, height: 500)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        card("Home") {
                            HStack {
                                HStack(spacing: 10) {
                                    let hasHome = draft.routeMacro.home != nil
                                    Image(systemName: hasHome ? "mappin.circle.fill" : "mappin.slash.circle")
                                        .foregroundStyle(hasHome ? .green : .red)
                                    Text(hasHome ? homeCoordText : "Not set")
                                        .foregroundStyle(.gray)
                                }

                                Spacer(minLength: 0)

                                HStack(spacing: 12) {

                                    Toggle(
                                        "Dockable",
                                        isOn: Binding(
                                            get: { draft.routeMacro.home?.dockAllowed ?? false },
                                            set: { newValue in
                                                if draft.routeMacro.home == nil {
                                                    draft.routeMacro.home = RouteHome(dockAllowed: newValue)
                                                } else {
                                                    draft.routeMacro.home?.dockAllowed = newValue
                                                }
                                            }
                                        )
                                    )
                                    .toggleStyle(.switch)
                                    
                                    if setHomeFromMap {
                                        Button {
                                            setHomeFromMap = false
                                            onToast("Home map-pick canceled", .info)
                                        } label: {
                                            Image(systemName: "pencil")
                                                .appIconGlyph()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.blue)
                                        .uniformIconButton()
                                    } else {
                                        Button {
                                            setHomeFromMap = true
                                            onToast("Click map to save home", .info)
                                        } label: {
                                            Image(systemName: "pencil")
                                                .appIconGlyph()
                                        }
                                        .buttonStyle(.bordered)
                                        .uniformIconButton()
                                    }

                                    if draft.routeMacro.home == nil {
                                        Button {
                                            showingDeleteHomeConfirm = true
                                        } label: {
                                            Image(systemName: "trash")
                                                .appIconGlyph()
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.red)
                                        .disabled(true)
                                        .uniformIconButton()
                                    } else {
                                        Button {
                                            showingDeleteHomeConfirm = true
                                        } label: {
                                            Image(systemName: "trash")
                                                .appIconGlyph()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)
                                        .uniformIconButton()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .alert("Delete Home?", isPresented: $showingDeleteHomeConfirm) {
                            Button("Cancel", role: .cancel) {}
                            Button("Delete", role: .destructive) {
                                draft.routeMacro.home = nil
                            }
                        } message: {
                            Text("This will remove the mission home point.")
                        }

                        card("Paths", trailing: {
                            Button {
                                let nextNum = draft.routeMacro.paths.count + 1
                                draft.routeMacro.paths.append(RoutePath(name: "Path \(nextNum)"))
                                selectedPathIndex = draft.routeMacro.paths.count - 1
                                editingPathIndex = nil
                                selectedWaypointIndex = nil
                            } label: {
                                Image(systemName: "plus")
                                    .appIconGlyph()
                            }
                            .buttonStyle(.bordered)
                            .uniformIconButton()
                        }) {
                            if draft.routeMacro.paths.isEmpty {
                                Text("No paths yet").foregroundStyle(.gray)
                            } else {
                                ForEach(Array(draft.routeMacro.paths.enumerated()), id: \.offset) { index, path in
                                    HStack {
                                        TextField(
                                            "Path Name",
                                            text: Binding(
                                                get: { path.name },
                                                set: { newValue in
                                                    draft.routeMacro.paths[index].name = newValue
                                                }
                                            )
                                        )
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(.white)

                                        Text("• \(path.waypoints.count) wp").foregroundStyle(.gray)
                                        Text("• \(distanceLabel(for: path))").foregroundStyle(.gray)
                                        Text("• \(durationLabel(for: path))").foregroundStyle(.gray)
                                        Spacer()

                                        if editingPathIndex == index {
                                            Button {
                                                if shouldOfferCloseLoop(path) {
                                                    pendingCloseLoopPathIndex = index
                                                } else {
                                                    editingPathIndex = nil
                                                    selectedWaypointIndex = nil
                                                    onToast("Path edit mode disabled", .info)
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
                                                editingPathIndex = index
                                                selectedPathIndex = index
                                                onToast("Path edit mode enabled. Click map to add waypoints.", .info)
                                            } label: {
                                                Image(systemName: "pencil")
                                                    .appIconGlyph()
                                            }
                                            .buttonStyle(.bordered)
                                            .uniformIconButton()
                                        }

                                        Button {
                                            pendingDeletePathIndex = index
                                        } label: {
                                            Image(systemName: "trash")
                                                .appIconGlyph()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)
                                        .uniformIconButton()
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedPathIndex = index }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .alert("Delete Path?", isPresented: Binding(
                            get: { pendingDeletePathIndex != nil },
                            set: { if !$0 { pendingDeletePathIndex = nil } }
                        )) {
                            Button("Cancel", role: .cancel) {}
                            Button("Delete", role: .destructive) {
                                if let idx = pendingDeletePathIndex,
                                   draft.routeMacro.paths.indices.contains(idx) {
                                    draft.routeMacro.paths.remove(at: idx)
                                    if editingPathIndex == idx {
                                        editingPathIndex = nil
                                        selectedWaypointIndex = nil
                                    }
                                    if selectedPathIndex >= draft.routeMacro.paths.count {
                                        selectedPathIndex = max(0, draft.routeMacro.paths.count - 1)
                                    }
                                }
                                pendingDeletePathIndex = nil
                            }
                        } message: {
                            Text("This will remove the path and all its waypoints.")
                        }
                        .alert("Close loop for this path?", isPresented: Binding(
                            get: { pendingCloseLoopPathIndex != nil },
                            set: { if !$0 { pendingCloseLoopPathIndex = nil } }
                        )) {
                            Button("No", role: .destructive) {
                                editingPathIndex = nil
                                selectedWaypointIndex = nil
                                pendingCloseLoopPathIndex = nil
                                onToast("Path edit mode disabled", .info)
                            }
                            Button("Close Loop") {
                                if let idx = pendingCloseLoopPathIndex,
                                   draft.routeMacro.paths.indices.contains(idx) {
                                    closeLoop(for: idx)
                                    editingPathIndex = nil
                                    selectedWaypointIndex = nil
                                    onToast("Loop closed", .success)
                                }
                                pendingCloseLoopPathIndex = nil
                            }
                        } message: {
                            Text("Add the start waypoint to the end and mark this path as looped?")
                        }

                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var validPathIndex: Int {
        guard !draft.routeMacro.paths.isEmpty else { return 0 }
        return min(max(selectedPathIndex, 0), draft.routeMacro.paths.count - 1)
    }

    private var allPathsCoords: [[RouteCoordinate]] {
        draft.routeMacro.paths.map { $0.waypoints.map(\.coord) }
    }

    /// Equatable signature of every input the route-tab map cares about.
    /// Drives `.task(id:)` so the shared `mapModel` is re-pushed whenever the
    /// home/paths/selection/preview/edit-state changes.
    private var routeTabMapSignature: RouteTabMapSignature {
        RouteTabMapSignature(
            homeCoord: draft.routeMacro.home?.coord,
            allPathsCoords: allPathsCoords,
            selectedWaypoints: selectedPath?.waypoints.map(\.coord) ?? [],
            selectedWaypointIndex: selectedWaypointIndex,
            headingPreview: headingPreview,
            cameraPreview: cameraPreview,
            isEditingPath: editingPathIndex != nil
        )
    }

    private var selectedPath: RoutePath? {
        guard !draft.routeMacro.paths.isEmpty else { return nil }
        return draft.routeMacro.paths[validPathIndex]
    }

    private var homeCoordText: String {
        guard let home = draft.routeMacro.home else { return "" }
        return String(format: "%.6f, %.6f", home.coord.lat, home.coord.lon)
    }

    private var headingPreview: HeadingPreview? {
        guard let fieldKey = focusedHeadingFieldKey else { return nil }
        let tokens = fieldKey.split(separator: "-")
        guard tokens.count == 4,
              tokens[0] == "p",
              tokens[2] == "w",
              let pathIndex = Int(tokens[1]),
              let waypointIndex = Int(tokens[3]),
              draft.routeMacro.paths.indices.contains(pathIndex),
              draft.routeMacro.paths[pathIndex].waypoints.indices.contains(waypointIndex) else { return nil }
        let waypoint = draft.routeMacro.paths[pathIndex].waypoints[waypointIndex]
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
                  let pathIndex = Int(tokens[1]),
                  let waypointIndex = Int(tokens[3]),
                  draft.routeMacro.paths.indices.contains(pathIndex),
                  draft.routeMacro.paths[pathIndex].waypoints.indices.contains(waypointIndex) else { return nil }
            let waypoint = draft.routeMacro.paths[pathIndex].waypoints[waypointIndex]
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
                  let pathIndex = Int(tokens[1]),
                  let waypointIndex = Int(tokens[3]),
                  draft.routeMacro.paths.indices.contains(pathIndex),
                  draft.routeMacro.paths[pathIndex].waypoints.indices.contains(waypointIndex),
                  let anchor = transitionAnchorCoordinate(pathIndex: pathIndex, waypointIndex: waypointIndex) else { return nil }
            let waypoint = draft.routeMacro.paths[pathIndex].waypoints[waypointIndex]
            return CameraPreview(
                lat: anchor.lat,
                lon: anchor.lon,
                bearing: normalizeHeading(waypoint.transition.cameraBearing),
                fovDeg: clamp(waypoint.camera.fovDeg, min: 5, max: 170)
            )
        }

        return nil
    }

    private func distanceLabel(for path: RoutePath) -> String {
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

    private func durationLabel(for path: RoutePath) -> String {
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

    private func shouldOfferCloseLoop(_ path: RoutePath) -> Bool {
        guard path.waypoints.count > 2 else { return false }
        guard let first = path.waypoints.first, let last = path.waypoints.last else { return false }
        let distance = CLLocation(latitude: first.coord.lat, longitude: first.coord.lon)
            .distance(from: CLLocation(latitude: last.coord.lat, longitude: last.coord.lon))
        return distance > 2
    }

    private func closeLoop(for index: Int) {
        guard draft.routeMacro.paths.indices.contains(index) else { return }
        guard let first = draft.routeMacro.paths[index].waypoints.first else { return }
        let closingWaypoint = RouteWaypoint(
            coord: first.coord,
            altitude: first.altitude,
            heading: first.heading,
            delaySec: 0,
            action: "none",
            camera: first.camera
        )
        draft.routeMacro.paths[index].waypoints.append(closingWaypoint)
        draft.routeMacro.paths[index].loopMode = "loop"
        refreshAutoHeadings(for: index)
    }

    private func waypointSidebar(pathIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Waypoints")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(draft.routeMacro.paths[pathIndex].waypoints.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.gray)
                    Spacer()
                    Button {
                        openBulkWaypointEditor(pathIndex: pathIndex)
                    } label: {
                        Image(systemName: "gearshape")
                            .appIconGlyph()
                    }
                    .buttonStyle(.bordered)
                    .help("Bulk edit all waypoints")
                    .uniformIconButton()
                    Button {
                        finishEditingPathFromSidebar(pathIndex: pathIndex)
                    } label: {
                        Image(systemName: "checkmark")
                            .appIconGlyph()
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Finish path editing")
                    .uniformIconButton()
                    
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.2))

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(draft.routeMacro.paths[pathIndex].waypoints.enumerated()), id: \.element.id) { idx, _ in
                            waypointEditorRow(pathIndex: pathIndex, idx: idx)
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
                .onChange(of: draft.routeMacro.paths[pathIndex].waypoints.count) { _ in
                    guard let idx = selectedWaypointIndex else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("wp-\(idx)", anchor: .center)
                    }
                }
            }
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.11))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1),
            alignment: .leading
        )
    }

    private func waypointEditorRow(pathIndex: Int, idx: Int) -> some View {
        let waypoint = draft.routeMacro.paths[pathIndex].waypoints[idx]
        let isSelected = selectedWaypointIndex == idx
        let headingKey = headingFieldKey(pathIndex: pathIndex, waypointIndex: idx)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Waypoint \(idx + 1)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
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
                    .foregroundStyle(.gray)
                    .frame(width: 78, alignment: .leading)
                numericInput(
                    value: Binding(
                        get: { waypoint.altitude.value },
                        set: { draft.routeMacro.paths[pathIndex].waypoints[idx].altitude.value = clamp($0, min: 0, max: 100_000) }
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
                        set: { draft.routeMacro.paths[pathIndex].waypoints[idx].altitude.unit = $0 }
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
                        set: { draft.routeMacro.paths[pathIndex].waypoints[idx].altitude.reference = $0 }
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
                    .foregroundStyle(.gray)
                    .frame(width: 78, alignment: .leading)
                Picker(
                    "Preset",
                    selection: Binding<HeadingPreset?>(
                        get: { waypoint.headingPreset },
                        set: { preset in
                            draft.routeMacro.paths[pathIndex].waypoints[idx].headingPreset = preset
                            applyHeadingPreset(pathIndex: pathIndex, waypointIndex: idx)
                        }
                    )
                ) {
                    Text("Manual").tag(HeadingPreset?.none)
                    Text("Follow Path").tag(HeadingPreset?.some(.followPath))
                    if pathIsLooped(pathIndex) {
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
                        set: { draft.routeMacro.paths[pathIndex].waypoints[idx].heading = clamp(normalizeHeading($0), min: 0, max: 359.999) }
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
                    .foregroundStyle(.gray)
                    .frame(width: 78, alignment: .leading)
                numericInput(
                    value: Binding(
                        get: { waypoint.delaySec },
                        set: { draft.routeMacro.paths[pathIndex].waypoints[idx].delaySec = clamp($0, min: 0, max: 100_000) }
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
                        set: { draft.routeMacro.paths[pathIndex].waypoints[idx].delayUnit = $0 }
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
                    .foregroundStyle(.gray)
                    .frame(width: 78, alignment: .leading)
                Picker(
                    "Action",
                    selection: Binding(
                        get: {
                            WaypointActionOption(rawValue: waypoint.action) ?? .none
                        },
                        set: { option in
                            draft.routeMacro.paths[pathIndex].waypoints[idx].action = option.rawValue
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
                    .foregroundStyle(.gray)
                    .frame(width: 78, alignment: .leading)
                Picker(
                    "Camera Mode",
                    selection: Binding(
                        get: { waypoint.camera.mode },
                        set: { mode in
                            draft.routeMacro.paths[pathIndex].waypoints[idx].camera.mode = mode
                            applyCameraMode(pathIndex: pathIndex, waypointIndex: idx)
                        }
                    )
                ) {
                    Text("Follow Heading").tag(CameraMode.followHeading)
                    if pathIsLooped(pathIndex) {
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
                        set: { draft.routeMacro.paths[pathIndex].waypoints[idx].camera.bearing = clamp(normalizeHeading($0), min: 0, max: 359.999) }
                    ),
                    step: 1,
                    min: 0,
                    max: 359.999,
                    onFocusChange: { focused in
                        let key = waypointCameraFieldKey(pathIndex: pathIndex, waypointIndex: idx)
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
                    .foregroundStyle(.gray)
                    .frame(width: 78, alignment: .leading)
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { waypoint.transition.mode },
                        set: { draft.routeMacro.paths[pathIndex].waypoints[idx].transition.mode = $0 }
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
                        set: { draft.routeMacro.paths[pathIndex].waypoints[idx].transition.targetSpeed = clamp($0, min: 0, max: 200) }
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
                        set: { draft.routeMacro.paths[pathIndex].waypoints[idx].transition.speedUnit = $0 }
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
                    .foregroundStyle(.gray)
                    .frame(width: 78, alignment: .leading)
                Picker(
                    "Transition Camera Mode",
                    selection: Binding(
                        get: { waypoint.transition.cameraMode },
                        set: { mode in
                            draft.routeMacro.paths[pathIndex].waypoints[idx].transition.cameraMode = mode
                            applyTransitionCameraMode(pathIndex: pathIndex, waypointIndex: idx)
                        }
                    )
                ) {
                    Text("Hold Current").tag(TransitionCameraMode.holdCurrent)
                    Text("Face Next Waypoint").tag(TransitionCameraMode.faceNextWaypoint)
                    if pathIsLooped(pathIndex) {
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
                        set: { draft.routeMacro.paths[pathIndex].waypoints[idx].transition.cameraBearing = clamp(normalizeHeading($0), min: 0, max: 359.999) }
                    ),
                    step: 1,
                    min: 0,
                    max: 359.999,
                    onFocusChange: { focused in
                        let key = transitionCameraFieldKey(pathIndex: pathIndex, waypointIndex: idx)
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
                    draft.routeMacro.paths[pathIndex].waypoints.remove(at: idx)
                    refreshAutoHeadings(for: pathIndex)
                    if selectedWaypointIndex == idx {
                        selectedWaypointIndex = nil
                    }
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
                applyHeadingPreset(pathIndex: pathIndex, waypointIndex: idx)
            }
            applyCameraMode(pathIndex: pathIndex, waypointIndex: idx)
            applyTransitionCameraMode(pathIndex: pathIndex, waypointIndex: idx)
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

    private func headingFieldKey(pathIndex: Int, waypointIndex: Int) -> String {
        "p-\(pathIndex)-w-\(waypointIndex)"
    }

    private func waypointCameraFieldKey(pathIndex: Int, waypointIndex: Int) -> String {
        "p-\(pathIndex)-w-\(waypointIndex)"
    }

    private func transitionCameraFieldKey(pathIndex: Int, waypointIndex: Int) -> String {
        "p-\(pathIndex)-w-\(waypointIndex)"
    }

    private func applyHeadingPreset(pathIndex: Int, waypointIndex: Int) {
        guard draft.routeMacro.paths.indices.contains(pathIndex),
              draft.routeMacro.paths[pathIndex].waypoints.indices.contains(waypointIndex) else { return }
        guard let preset = draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].headingPreset else { return }
        switch preset {
        case .followPath:
            if let followHeading = followPathHeading(pathIndex: pathIndex, waypointIndex: waypointIndex) {
                draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].heading = followHeading
            }
        case .perimeterOutward:
            if let outwardHeading = perimeterHeading(pathIndex: pathIndex, waypointIndex: waypointIndex, outward: true) {
                draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].heading = outwardHeading
            }
        case .perimeterInward:
            if let inwardHeading = perimeterHeading(pathIndex: pathIndex, waypointIndex: waypointIndex, outward: false) {
                draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].heading = inwardHeading
            }
        case .north:
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].heading = 0
        case .east:
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].heading = 90
        case .south:
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].heading = 180
        case .west:
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].heading = 270
        }
    }

    private func refreshAutoHeadings(for pathIndex: Int) {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return }
        let waypointCount = draft.routeMacro.paths[pathIndex].waypoints.count
        guard waypointCount > 0 else { return }
        for waypointIndex in 0..<waypointCount {
            if draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].headingPreset != nil {
                applyHeadingPreset(pathIndex: pathIndex, waypointIndex: waypointIndex)
            }
        }
        refreshCameraModes(for: pathIndex)
        refreshTransitionCameraModes(for: pathIndex)
    }

    private func applyCameraMode(pathIndex: Int, waypointIndex: Int) {
        guard draft.routeMacro.paths.indices.contains(pathIndex),
              draft.routeMacro.paths[pathIndex].waypoints.indices.contains(waypointIndex) else { return }

        let mode = draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].camera.mode
        switch mode {
        case .followHeading:
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].camera.bearing =
                draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].heading
        case .perimeterOutward:
            if let heading = perimeterHeading(pathIndex: pathIndex, waypointIndex: waypointIndex, outward: true) {
                draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].camera.bearing = heading
            }
        case .perimeterInward:
            if let heading = perimeterHeading(pathIndex: pathIndex, waypointIndex: waypointIndex, outward: false) {
                draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].camera.bearing = heading
            }
        case .manualBearing:
            break
        }

        applyTransitionCameraMode(pathIndex: pathIndex, waypointIndex: waypointIndex)
    }

    private func refreshCameraModes(for pathIndex: Int) {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return }
        let waypointCount = draft.routeMacro.paths[pathIndex].waypoints.count
        guard waypointCount > 0 else { return }
        for waypointIndex in 0..<waypointCount {
            applyCameraMode(pathIndex: pathIndex, waypointIndex: waypointIndex)
        }
    }

    private func applyTransitionCameraMode(pathIndex: Int, waypointIndex: Int) {
        guard draft.routeMacro.paths.indices.contains(pathIndex),
              draft.routeMacro.paths[pathIndex].waypoints.indices.contains(waypointIndex) else { return }

        let cameraMode = draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].transition.cameraMode
        switch cameraMode {
        case .holdCurrent:
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].transition.cameraBearing =
                draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].camera.bearing
        case .faceNextWaypoint:
            if let heading = followPathHeading(pathIndex: pathIndex, waypointIndex: waypointIndex) {
                draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].transition.cameraBearing = heading
            }
        case .perimeterOutward:
            if let heading = perimeterHeading(pathIndex: pathIndex, waypointIndex: waypointIndex, outward: true) {
                draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].transition.cameraBearing = heading
            }
        case .perimeterInward:
            if let heading = perimeterHeading(pathIndex: pathIndex, waypointIndex: waypointIndex, outward: false) {
                draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].transition.cameraBearing = heading
            }
        case .manualBearing:
            break
        }
    }

    private func refreshTransitionCameraModes(for pathIndex: Int) {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return }
        let waypointCount = draft.routeMacro.paths[pathIndex].waypoints.count
        guard waypointCount > 0 else { return }
        for waypointIndex in 0..<waypointCount {
            applyTransitionCameraMode(pathIndex: pathIndex, waypointIndex: waypointIndex)
        }
    }

    private func pathIsLooped(_ pathIndex: Int) -> Bool {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return false }
        let path = draft.routeMacro.paths[pathIndex]
        if path.loopMode == "loop" { return true }
        guard path.waypoints.count > 2,
              let first = path.waypoints.first,
              let last = path.waypoints.last else { return false }
        return CLLocation(latitude: first.coord.lat, longitude: first.coord.lon)
            .distance(from: CLLocation(latitude: last.coord.lat, longitude: last.coord.lon)) <= 2
    }

    private func nextWaypointCoordinate(pathIndex: Int, waypointIndex: Int) -> RouteCoordinate? {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return nil }
        let waypoints = draft.routeMacro.paths[pathIndex].waypoints
        guard waypoints.indices.contains(waypointIndex) else { return nil }
        if waypoints.indices.contains(waypointIndex + 1) {
            return waypoints[waypointIndex + 1].coord
        }
        if pathIsLooped(pathIndex), let first = waypoints.first {
            return first.coord
        }
        return nil
    }

    private func transitionAnchorCoordinate(pathIndex: Int, waypointIndex: Int) -> RouteCoordinate? {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return nil }
        let waypoints = draft.routeMacro.paths[pathIndex].waypoints
        guard waypoints.indices.contains(waypointIndex),
              let nextCoord = nextWaypointCoordinate(pathIndex: pathIndex, waypointIndex: waypointIndex) else { return nil }
        let current = waypoints[waypointIndex].coord
        return RouteCoordinate(
            lat: (current.lat + nextCoord.lat) / 2,
            lon: (current.lon + nextCoord.lon) / 2
        )
    }

    private func followPathHeading(pathIndex: Int, waypointIndex: Int) -> Double? {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return nil }
        let path = draft.routeMacro.paths[pathIndex]
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

    private func perimeterHeading(pathIndex: Int, waypointIndex: Int, outward: Bool) -> Double? {
        guard pathIsLooped(pathIndex) else {
            return followPathHeading(pathIndex: pathIndex, waypointIndex: waypointIndex)
        }
        let waypoints = draft.routeMacro.paths[pathIndex].waypoints
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

    private func openBulkWaypointEditor(pathIndex: Int) {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return }
        guard !draft.routeMacro.paths[pathIndex].waypoints.isEmpty else {
            onToast("No waypoints to edit", .info)
            return
        }
        bulkWaypointDraft = draft.routeMacro.paths[pathIndex].waypoints[0]
        bulkEditPathIndex = pathIndex
        clearPreviewFocusState()
        showingBulkWaypointEditor = true
    }

    private func finishEditingPathFromSidebar(pathIndex: Int) {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return }
        let path = draft.routeMacro.paths[pathIndex]
        if shouldOfferCloseLoop(path) {
            pendingCloseLoopPathIndex = pathIndex
            return
        }
        editingPathIndex = nil
        selectedWaypointIndex = nil
        clearPreviewFocusState()
        onToast("Path edit mode disabled", .info)
    }

    private func applyBulkWaypointValues(pathIndex: Int) {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return }
        guard !draft.routeMacro.paths[pathIndex].waypoints.isEmpty else {
            onToast("No waypoints to update", .info)
            return
        }

        for waypointIndex in draft.routeMacro.paths[pathIndex].waypoints.indices {
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].altitude = bulkWaypointDraft.altitude
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].headingPreset = bulkWaypointDraft.headingPreset
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].heading =
                clamp(normalizeHeading(bulkWaypointDraft.heading), min: 0, max: 359.999)
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].delaySec =
                clamp(bulkWaypointDraft.delaySec, min: 0, max: 100_000)
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].delayUnit = bulkWaypointDraft.delayUnit
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].action = bulkWaypointDraft.action
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].camera = bulkWaypointDraft.camera
            draft.routeMacro.paths[pathIndex].waypoints[waypointIndex].transition = bulkWaypointDraft.transition
        }

        refreshAutoHeadings(for: pathIndex)
        showingBulkWaypointEditor = false
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

    private func addRosterDeviceToPath(pathIndex: Int) {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return }
        let pathId = draft.routeMacro.paths[pathIndex].id
        let fields = pathRosterDrafts[pathId] ?? PathRosterDraft()
        let name = fields.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            onToast("Enter a device label", .info)
            return
        }
        let role = fields.role.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = fields.hint.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = RosterDevice(
            name: name,
            roleType: role.isEmpty ? "device" : role,
            positionHint: hint
        )
        draft.rosterDevices.append(device)
        draft.routeMacro.paths[pathIndex].rosterDeviceIds.append(device.id)
        pathRosterDrafts[pathId] = PathRosterDraft()
        onToast("Device added to path", .success)
    }

    private func removeRosterDeviceFromPath(pathIndex: Int, deviceId: UUID) {
        guard draft.routeMacro.paths.indices.contains(pathIndex) else { return }
        draft.routeMacro.paths[pathIndex].rosterDeviceIds.removeAll { $0 == deviceId }
        let stillReferenced = draft.routeMacro.paths.contains { $0.rosterDeviceIds.contains(deviceId) }
        if !stillReferenced {
            draft.rosterDevices.removeAll { $0.id == deviceId }
        }
    }

    private func bulkWaypointEditorSheet(pathIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Bulk Edit Waypoints")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Cancel") {
                    showingBulkWaypointEditor = false
                }
                .buttonStyle(.bordered)
                Button("Apply") {
                    applyBulkWaypointValues(pathIndex: pathIndex)
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
                            Text("Follow Path").tag(HeadingPreset?.some(.followPath))
                            if pathIsLooped(pathIndex) {
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
                            if pathIsLooped(pathIndex) {
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
                            if pathIsLooped(pathIndex) {
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
        .background(Color(red: 0.10, green: 0.10, blue: 0.11))
    }

    private func bulkRowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.gray)
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
                    .foregroundStyle(.white)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private struct PathRosterDraft: Equatable {
        var name: String = ""
        var role: String = ""
        var hint: String = ""
    }
}

private struct MissionRow: View {
    let mission: Mission

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mission.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(mission.type.rawValue.capitalized)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.gray)
            }
            Text(mission.description.isEmpty ? "No description" : mission.description)
                .foregroundStyle(.gray)
            Text("Count: \(mission.count)  Duration: \(mission.duration)")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MissionCard: View {
    let mission: Mission

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(mission.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(mission.type.rawValue.capitalized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.gray)
            }
            Text(mission.description.isEmpty ? "No description" : mission.description)
                .foregroundStyle(.gray)
                .lineLimit(2)
            Divider().overlay(.gray.opacity(0.25))
            Text("Count: \(mission.count)")
                .foregroundStyle(.gray)
            Text("Duration: \(mission.duration)")
                .foregroundStyle(.gray)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
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
        GuardianModalTemplate(
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
