import SwiftUI
import AppKit

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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(red: 0.14, green: 0.14, blue: 0.15))

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
                List(sortedMissions) { mission in
                    Button {
                        selectedMissionID = mission.id
                    } label: {
                        MissionRow(mission: mission)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .cursorOnHover()
                    .listRowBackground(Color(red: 0.12, green: 0.12, blue: 0.13))
                }
                .listStyle(.inset)
                .padding(.horizontal, 16)
                .scrollContentBackground(.hidden)
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
            onBack: { selectedMissionID = nil },
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
    @State private var mapStyle: MapTileStyle = .standard
    @State private var setHomeFromMap = false
    @State private var showingDeleteHomeConfirm = false
    @State private var pendingDeletePathIndex: Int?
    @State private var newSpaceName = ""
    @State private var newSpaceRoleType = ""
    @State private var newSpacePositionHint = ""

    let onBack: () -> Void
    let onSave: (Mission) -> Void
    let onToast: (String, ToastStyle) -> Void

    init(
        mission: Mission,
        onBack: @escaping () -> Void,
        onSave: @escaping (Mission) -> Void,
        onToast: @escaping (String, ToastStyle) -> Void
    ) {
        _draft = State(initialValue: mission)
        self.onBack = onBack
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
                }
                .buttonStyle(.bordered)

                Button("Save Mission") {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
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
    }

    private var detailsTab: some View {
        Group {
            card("Edit Mission") {
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                TextField("Description", text: $draft.description)
                    .textFieldStyle(.roundedBorder)
                Picker("Type", selection: $draft.type) {
                    Text("mobile").tag(MissionType.mobile)
                    Text("static").tag(MissionType.staticType)
                }
                .pickerStyle(.segmented)
            }

            card("Mission Runtime") {
                HStack {
                    Stepper("Count: \(draft.count)", value: $draft.count, in: 0...10_000)
                    Spacer()
                    Stepper("Duration: \(draft.duration)", value: $draft.duration, in: 0...100_000)
                }
            }
        }
    }

    private var rosterTab: some View {
        Group {
            card("Mission Device Spaces") {
                Text("Create slots/spaces now; assign actual drones later in Mission Control.")
                    .foregroundStyle(.gray)
                HStack {
                    TextField("Space Name", text: $newSpaceName).textFieldStyle(.roundedBorder)
                    TextField("Role Type", text: $newSpaceRoleType).textFieldStyle(.roundedBorder)
                    TextField("Position Hint", text: $newSpacePositionHint).textFieldStyle(.roundedBorder)
                    Button("Add Space") { addSpace() }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            card("Configured Spaces") {
                if draft.spaces.isEmpty {
                    Text("No spaces yet. Add a space for each expected device position.")
                        .foregroundStyle(.gray)
                } else {
                    ForEach(draft.spaces) { space in
                        HStack {
                            Text(space.name).foregroundStyle(.white)
                            Spacer()
                            Text(space.roleType).foregroundStyle(.gray)
                            Text(space.positionHint).foregroundStyle(.gray)
                            Button {
                                draft.spaces.removeAll { $0.id == space.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                }
            }
        }
    }

    private var routeTab: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    OSMMapView(
                        home: draft.routeMacro.home,
                        allPathCoords: allPathCoords,
                        selectedPathWaypoints: selectedPath?.waypoints ?? [],
                        mapStyle: mapStyle
                    ) { lat, lon in
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
                            RouteWaypoint(coord: RouteCoordinate(lat: lat, lon: lon))
                        )
                        selectedPathIndex = pathIndex
                        selectedWaypointIndex = draft.routeMacro.paths[pathIndex].waypoints.count - 1
                        onToast("Waypoint added", .success)
                    } onWaypointClick: { idx in
                        selectedWaypointIndex = idx
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 500)

                    Button {
                        mapStyle = mapStyle == .standard ? .satellite : .standard
                    } label: {
                        Image(systemName: mapStyle == .standard ? "map" : "globe.americas.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.top, 10)
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
                                    if setHomeFromMap {
                                        Button {
                                            setHomeFromMap = false
                                            onToast("Home map-pick canceled", .info)
                                        } label: {
                                            Image(systemName: "pencil")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.blue)
                                    } else {
                                        Button {
                                            setHomeFromMap = true
                                            onToast("Click map to save home", .info)
                                        } label: {
                                            Image(systemName: "pencil")
                                        }
                                        .buttonStyle(.bordered)
                                    }

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

                                    if draft.routeMacro.home == nil {
                                        Button {
                                            showingDeleteHomeConfirm = true
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.red)
                                        .disabled(true)
                                    } else {
                                        Button {
                                            showingDeleteHomeConfirm = true
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)
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
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.bordered)
                        }) {
                            if draft.routeMacro.paths.isEmpty {
                                Text("No paths yet").foregroundStyle(.gray)
                            } else {
                                ForEach(Array(draft.routeMacro.paths.enumerated()), id: \.offset) { index, path in
                                    HStack {
                                        Text(path.name).foregroundStyle(.white)
                                        Text("• \(path.waypoints.count) wp").foregroundStyle(.gray)
                                        Spacer()

                                        if editingPathIndex == index {
                                            Button {
                                                editingPathIndex = nil
                                                onToast("Path edit mode disabled", .info)
                                            } label: {
                                                Image(systemName: "pencil")
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.blue)
                                        } else {
                                            Button {
                                                editingPathIndex = index
                                                selectedPathIndex = index
                                                onToast("Path edit mode enabled. Click map to add waypoints.", .info)
                                            } label: {
                                                Image(systemName: "pencil")
                                            }
                                            .buttonStyle(.bordered)
                                        }

                                        Button {
                                            pendingDeletePathIndex = index
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)
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
                                    if editingPathIndex == idx { editingPathIndex = nil }
                                    if selectedPathIndex >= draft.routeMacro.paths.count {
                                        selectedPathIndex = max(0, draft.routeMacro.paths.count - 1)
                                    }
                                }
                                pendingDeletePathIndex = nil
                            }
                        } message: {
                            Text("This will remove the path and all its waypoints.")
                        }

                        card("Schedule") {
                            TextField(
                                "Comma-separated schedule entries",
                                text: Binding(
                                    get: { draft.schedule.joined(separator: ", ") },
                                    set: { newValue in
                                        draft.schedule = newValue
                                            .split(separator: ",")
                                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                            .filter { !$0.isEmpty }
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                }
            }

            if let idx = selectedWaypointIndex,
               let selectedPath,
               idx < selectedPath.waypoints.count {
                waypointOverlay(idx: idx)
                    .transition(.move(edge: .trailing))
                    .padding(.trailing, 12)
            }
        }
    }

    private var validPathIndex: Int {
        guard !draft.routeMacro.paths.isEmpty else { return 0 }
        return min(max(selectedPathIndex, 0), draft.routeMacro.paths.count - 1)
    }

    private var allPathCoords: [RouteCoordinate] {
        draft.routeMacro.paths.flatMap { $0.waypoints.map(\.coord) }
    }

    private var selectedPath: RoutePath? {
        guard !draft.routeMacro.paths.isEmpty else { return nil }
        return draft.routeMacro.paths[validPathIndex]
    }

    private var homeCoordText: String {
        guard let home = draft.routeMacro.home else { return "" }
        return String(format: "%.6f, %.6f", home.coord.lat, home.coord.lon)
    }

    @ViewBuilder
    private func waypointOverlay(idx: Int) -> some View {
        if let selectedPath, idx < selectedPath.waypoints.count {
            let waypoint = selectedPath.waypoints[idx]
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Waypoint \(idx + 1)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        selectedWaypointIndex = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                Group {
                    TextField(
                        "Latitude",
                        value: Binding(
                            get: { waypoint.coord.lat },
                            set: { draft.routeMacro.paths[validPathIndex].waypoints[idx].coord.lat = $0 }
                        ),
                        format: .number
                    )
                    TextField(
                        "Longitude",
                        value: Binding(
                            get: { waypoint.coord.lon },
                            set: { draft.routeMacro.paths[validPathIndex].waypoints[idx].coord.lon = $0 }
                        ),
                        format: .number
                    )
                    TextField(
                        "Altitude",
                        value: Binding(
                            get: { waypoint.altitude.value },
                            set: { draft.routeMacro.paths[validPathIndex].waypoints[idx].altitude.value = $0 }
                        ),
                        format: .number
                    )
                    TextField(
                        "Heading",
                        value: Binding(
                            get: { waypoint.heading },
                            set: { draft.routeMacro.paths[validPathIndex].waypoints[idx].heading = $0 }
                        ),
                        format: .number
                    )
                    TextField(
                        "Delay (s)",
                        value: Binding(
                            get: { waypoint.delaySec },
                            set: { draft.routeMacro.paths[validPathIndex].waypoints[idx].delaySec = $0 }
                        ),
                        format: .number
                    )
                    TextField(
                        "Action",
                        text: Binding(
                            get: { waypoint.action },
                            set: { draft.routeMacro.paths[validPathIndex].waypoints[idx].action = $0 }
                        )
                    )
                }
                .textFieldStyle(.roundedBorder)

                Button("Remove Waypoint", role: .destructive) {
                    draft.routeMacro.paths[validPathIndex].waypoints.remove(at: idx)
                    selectedWaypointIndex = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(14)
            .frame(width: 340)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func addSpace() {
        let name = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let role = newSpaceRoleType.trimmingCharacters(in: .whitespacesAndNewlines)
        let position = newSpacePositionHint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        draft.spaces.append(
            MissionSpace(
                name: name,
                roleType: role.isEmpty ? "general" : role,
                positionHint: position
            )
        )
        newSpaceName = ""
        newSpaceRoleType = ""
        newSpacePositionHint = ""
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
            Text("Count: \(mission.count)  Duration: \(mission.duration)  Schedules: \(mission.schedule.count)")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
        }
        .padding(.vertical, 6)
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
            Text("Schedules: \(mission.schedule.count)")
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

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Mission")
                .font(.title2.bold())

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description", text: $description)
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: $type) {
                Text("mobile").tag(MissionType.mobile)
                Text("static").tag(MissionType.staticType)
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
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
        }
        .padding(20)
        .frame(width: 460)
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

private extension View {
    func cursorOnHover() -> some View {
        modifier(PointerOnHoverModifier())
    }
}
