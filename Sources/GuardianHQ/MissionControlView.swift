import SwiftUI

/// Spacing and widths for mission setup / roster prep.
/// Tune here when adding sim battery, pre-place coordinates, staging waypoints, or other per-slot controls.
private enum MissionRunPrepLayout {
    static let setupScrollPaddingH: CGFloat = 36
    static let setupScrollPaddingV: CGFloat = 28
    static let setupBlockSpacing: CGFloat = 22
    static let pathCardPadding: CGFloat = 22
    static let pathCardInnerSpacing: CGFloat = 18
    static let pathsOuterSpacing: CGFloat = 22
    /// Former default ~200pt; +50% for wider prep columns.
    static let rosterGridMinWidth: CGFloat = 300
    static let rosterGridSpacing: CGFloat = 18
    static let scheduleCardPadding: CGFloat = 20
    static let scheduleCardSpacing: CGFloat = 16
    static let rosterSlotPadding: CGFloat = 20
    static let rosterSlotStackSpacing: CGFloat = 16
    static let rosterSlotIconSize: CGFloat = 58
    static let rosterSlotIconRowSpacing: CGFloat = 12
    static let rosterTitleStackSpacing: CGFloat = 5
    static let rosterSlotCornerRadius: CGFloat = 14
    static let pathCardCornerRadius: CGFloat = 12
}

struct MissionControlView: View {
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var controlStore: MissionControlStore
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var generalSettings: GeneralSettingsStore

    @State private var selectedRunID: UUID?
    @State private var showingAddRunSheet = false

    private let bgMain = Color(red: 0.07, green: 0.07, blue: 0.08)

    var body: some View {
        Group {
            if !fleetLink.isRunning {
                serverOfflineMessage
            } else if let run = selectedRun {
                MissionRunDetailView(
                    run: run,
                    missionStore: missionStore,
                    fleetLink: fleetLink,
                    sitl: sitl,
                    controlStore: controlStore,
                    defaultLiveMapStyle: generalSettings.defaultMapTileStyle,
                    onBack: { selectedRunID = nil },
                    onUpdate: { controlStore.updateRun($0) },
                    onStart: {
                        controlStore.updateRun($0)
                        controlStore.startRun(id: $0.id)
                    },
                    onDelete: { controlStore.deleteRun(id: $0) }
                )
            } else {
                missionRunGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgMain)
        .sheet(isPresented: $showingAddRunSheet) {
            AddMissionRunSheet(
                missionStore: missionStore,
                onCreateRun: { mission in
                    let run = controlStore.createRun(from: mission)
                    selectedRunID = run.id
                }
            )
        }
    }

    private var serverOfflineMessage: some View {
        centeredEmptyStateBlock(
            systemImage: "antenna.radiowaves.left.and.right.slash",
            title: "Server isn’t running",
            subtitle: {
                Text("Turn on ")
                    + Text("Server").fontWeight(.semibold)
                    + Text(" in the top bar to bring up MAVSDK and listen for vehicles.")
            }
        )
    }

    /// Same layout as Vehicles (`DevicesView.centeredEmptyStateBlock`): icon 44pt medium gray, title 20pt semibold white, subtitle 14pt gray, max 480pt, padding 32, centered in the pane.
    private func centeredEmptyStateBlock(
        systemImage: String,
        title: String,
        @ViewBuilder subtitle: () -> Text
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.gray)
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                subtitle()
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            .padding(32)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedRun: MissionRun? {
        guard let selectedRunID else { return nil }
        return controlStore.runs.first(where: { $0.id == selectedRunID })
    }

    private var missionRunGrid: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mission Runs")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Add Run") {
                    showingAddRunSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))

            if controlStore.runs.isEmpty {
                centeredEmptyStateBlock(
                    systemImage: "slider.horizontal.3",
                    title: "No mission running",
                    subtitle: {
                        Text("Add a run from a mission template to begin.")
                    }
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(controlStore.runs) { run in
                            Button {
                                selectedRunID = run.id
                            } label: {
                                MissionRunCard(run: run)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .background(Color(red: 0.07, green: 0.07, blue: 0.08))
            }
        }
    }
}

private struct MissionRunStatusBadge: View {
    let status: MissionRunStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.system(size: 10, weight: .heavy))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch status {
        case .running:
            return GuardianSemanticColors.successBackground
        case .setup:
            return GuardianSemanticColors.warningBackground
        case .paused, .completed:
            return GuardianSemanticColors.neutralBadgeBackground
        }
    }

    private var foreground: Color {
        switch status {
        case .running:
            return GuardianSemanticColors.successForeground
        case .setup:
            return GuardianSemanticColors.warningForeground
        case .paused, .completed:
            return GuardianSemanticColors.neutralBadgeForeground
        }
    }
}

private struct MissionRunCard: View {
    let run: MissionRun

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(run.missionName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                MissionRunStatusBadge(status: run.status)
            }
            Text("Schedule: \(run.scheduleMode.rawValue)")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
            Text("Slots: \(run.assignments.count)")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Roster slot card: role + vehicle from fleet picker (Vehicles tab inventory).
private struct MissionControlRosterSlotCard: View {
    let title: String
    let subtitle: String
    let assignedVehicleTitle: String?
    /// `nil` when unassigned or legacy free-text only; `false` = live MAVLink, `true` = built-in sim.
    let assignedFleetIsSimulation: Bool?
    let simulationImageBasenames: [String]?
    let onChooseVehicle: () -> Void
    let onRemoveVehicle: () -> Void

    private var isAttached: Bool {
        assignedVehicleTitle != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterSlotStackSpacing) {
            HStack(alignment: .center, spacing: MissionRunPrepLayout.rosterSlotIconRowSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.07, green: 0.12, blue: 0.14),
                                    Color(red: 0.05, green: 0.07, blue: 0.09)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    slotLeadingGlyph
                }
                .frame(width: MissionRunPrepLayout.rosterSlotIconSize, height: MissionRunPrepLayout.rosterSlotIconSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterTitleStackSpacing) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let assignedVehicleTitle {
                Group {
                    if let isSim = assignedFleetIsSimulation {
                        HStack(alignment: .center, spacing: 10) {
                            FleetLiveSimBadge(isSimulation: isSim)
                            Text(assignedVehicleTitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(assignedVehicleTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("No vehicle assigned")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }

            HStack(spacing: 12) {
                Button {
                    onChooseVehicle()
                } label: {
                    if isAttached {
                        Text("Change")
                    } else {
                        Label("Choose", systemImage: "plus.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(.blue)
                .controlSize(.small)

                Spacer()

                if isAttached {
                    Button {
                        onRemoveVehicle()
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .labelStyle(.titleAndIcon)
                }
            }
            .padding(.top, 4)
        }
        .padding(MissionRunPrepLayout.rosterSlotPadding)
        .background(Color(red: 0.10, green: 0.10, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.rosterSlotCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MissionRunPrepLayout.rosterSlotCornerRadius)
                .strokeBorder(
                    isAttached ? Color.green.opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: isAttached ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: isAttached ? 6 : 2, y: isAttached ? 2 : 1)
    }

    @ViewBuilder
    private var slotLeadingGlyph: some View {
        if let names = simulationImageBasenames, !names.isEmpty {
            SimulationDeviceThumbnail(imageBasenames: names)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(4)
        } else {
            Image(systemName: "fanblades")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan.opacity(0.9), .teal.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .symbolRenderingMode(.hierarchical)
        }
    }
}

private struct MissionRunDetailView: View {
    @State var run: MissionRun
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var controlStore: MissionControlStore
    let onBack: () -> Void
    let onUpdate: (MissionRun) -> Void
    let onStart: (MissionRun) -> Void
    let onDelete: (UUID) -> Void

    @State private var confirmDeleteRun = false
    @State private var rosterPickerAssignmentId: UUID?
    @State private var liveConsoleMapStyle: MapTileStyle

    init(
        run: MissionRun,
        missionStore: MissionStore,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        controlStore: MissionControlStore,
        defaultLiveMapStyle: MapTileStyle,
        onBack: @escaping () -> Void,
        onUpdate: @escaping (MissionRun) -> Void,
        onStart: @escaping (MissionRun) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        _run = State(initialValue: run)
        self.missionStore = missionStore
        self.fleetLink = fleetLink
        self.sitl = sitl
        self.controlStore = controlStore
        self.onBack = onBack
        self.onUpdate = onUpdate
        self.onStart = onStart
        self.onDelete = onDelete
        _confirmDeleteRun = State(initialValue: false)
        _rosterPickerAssignmentId = State(initialValue: nil)
        _liveConsoleMapStyle = State(initialValue: defaultLiveMapStyle)
    }

    private var rosterPickerSpring: Animation {
        .spring(response: 0.36, dampingFraction: 0.88)
    }

    private func syncRunFromStore() {
        if let r = controlStore.runs.first(where: { $0.id == run.id }) {
            run = r
        }
    }

    private func applyStopImmediate() {
        controlStore.stopRunImmediate(id: run.id)
        syncRunFromStore()
    }

    private func applyStopAfterCycle() {
        controlStore.stopRunAfterCurrentCycle(id: run.id)
        syncRunFromStore()
    }

    private func applyResetToSetup() {
        controlStore.resetRunToSetup(id: run.id)
        syncRunFromStore()
    }

    private var resolvedMission: Mission? {
        missionStore.missions.first { $0.id == run.missionId }
    }

    private var allRosterFilled: Bool {
        run.assignments.allSatisfy(\.hasFleetOrLegacyAssignment)
    }

    private var canStart: Bool {
        guard allRosterFilled else { return false }
        if run.scheduleMode == .loop {
            return run.loopIntervalMinutes > 0
        }
        return true
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            onBack()
                        } label: {
                            Image(systemName: "arrow.left")
                                .appIconGlyph()
                        }
                        .buttonStyle(.bordered)
                        .uniformIconButton()

                        Text(run.missionName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()

                        if run.status == .setup {
                            HStack(spacing: 10) {
                                Button("Start Run") {
                                    run.status = .running
                                    onStart(run)
                                    syncRunFromStore()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .disabled(!canStart)

                                Button("Delete Run") {
                                    confirmDeleteRun = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        } else if run.status == .running || run.status == .paused {
                            Menu {
                                Button("Immediate", role: .destructive) {
                                    applyStopImmediate()
                                }
                                Button("Finish loop", role: .destructive) {
                                    applyStopAfterCycle()
                                }
                            } label: {
                                Text("Stop run")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .menuStyle(.button)
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.regular)
                        } else if run.status == .completed {
                            Button("Back to setup") {
                                applyResetToSetup()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .controlSize(.regular)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.12, green: 0.12, blue: 0.13))

                    if run.pendingGracefulCycleStop, run.status == .running || run.status == .paused {
                        gracefulStopPendingBanner
                    }
                }

                if run.status == .setup {
                    ScrollView {
                        VStack(alignment: .leading, spacing: MissionRunPrepLayout.setupBlockSpacing) {
                            scheduleSetupCard
                            rosterPathsSetupSection
                        }
                        .padding(.horizontal, MissionRunPrepLayout.setupScrollPaddingH)
                        .padding(.vertical, MissionRunPrepLayout.setupScrollPaddingV)
                        .frame(maxWidth: .infinity)
                    }
                } else if run.status == .completed {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            completedSummaryCard
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    missionLiveConsole
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if run.status == .setup, rosterPickerAssignmentId != nil {
                Color.black.opacity(0.45)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(rosterPickerSpring) {
                            rosterPickerAssignmentId = nil
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
            if run.status == .setup, let aid = rosterPickerAssignmentId {
                MissionRosterVehiclePickerSidebar(
                    vehicles: buildMissionPickableVehicles(fleetLink: fleetLink, sitl: sitl),
                    rowIsEnabled: { rosterPickDisabledReason($0, assignmentId: aid) == nil },
                    rowDisabledReason: { rosterPickDisabledReason($0, assignmentId: aid) },
                    onSelect: { v in
                        applyFleetVehicle(v, assignmentId: aid)
                        withAnimation(rosterPickerSpring) {
                            rosterPickerAssignmentId = nil
                        }
                    },
                    onClose: {
                        withAnimation(rosterPickerSpring) {
                            rosterPickerAssignmentId = nil
                        }
                    }
                )
                .frame(width: 420)
                .frame(maxHeight: .infinity)
                .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        .confirmationDialog(
            "Delete “\(run.missionName)”?",
            isPresented: $confirmDeleteRun,
            titleVisibility: .visible
        ) {
            Button("Delete Run", role: .destructive) {
                let id = run.id
                onDelete(id)
                onBack()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the run from Mission Control. The mission template is not deleted.")
        }
        .onAppear {
            syncRunFromStore()
        }
        .onDisappear {
            onUpdate(run)
        }
    }

    private var gracefulStopPendingBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GuardianSemanticColors.warningForeground)
            Text(
                "Finishing the current run — when it completes, this mission stops. No further loop or continuous cycles will be scheduled."
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.gray)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GuardianSemanticColors.warningBackground.opacity(0.5))
    }

    private let liveConsoleCardFill = Color(red: 0.10, green: 0.10, blue: 0.11)
    private let liveConsoleCardStroke = Color.white.opacity(0.06)

    /// Running / paused: loop strip, camera | 3D, per-vehicle status, log — placeholders only (no section headings).
    private var missionLiveConsole: some View {
        VStack(spacing: 12) {
            missionLiveLoopStrip
            HStack(spacing: 12) {
                missionLiveCameraPlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                missionLiveOverviewMap
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 220)
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
            missionLiveVehicleStatusRow
            missionLiveLogPlaceholder
        }
    }

    private var missionLiveLoopStrip: some View {
        HStack(spacing: 12) {
            ProgressView(value: 0.34)
                .progressViewStyle(.linear)
                .tint(.cyan.opacity(0.85))
                .frame(maxWidth: .infinity)
            Text("0 / —")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.gray)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(liveConsoleCardStroke, lineWidth: 1)
        )
    }

    private var missionLiveCameraPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(liveConsoleCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(liveConsoleCardStroke, lineWidth: 1)
            )
    }

    /// Same Leaflet/OSM stack and bbox logic as Missions route tab: home marker + path polylines from the mission template.
    private var missionLiveOverviewMap: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let mission = resolvedMission {
                    OSMMapView(
                        home: mission.routeMacro.home,
                        allPathsCoords: mission.routeMacro.paths.map { $0.waypoints.map(\.coord) },
                        selectedPathWaypoints: [],
                        selectedWaypointIndex: nil,
                        mapStyle: liveConsoleMapStyle,
                        recenterNonce: 0,
                        headingPreview: nil,
                        cameraPreview: nil,
                        preserveView: false,
                        isEditingPath: false,
                        onMapClick: { _, _ in },
                        onWaypointClick: { _ in },
                        onWaypointMoved: { _, _, _ in },
                        onWaypointDelete: { _ in },
                        onPathInsert: { _, _, _ in }
                    )
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(liveConsoleCardFill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(liveConsoleCardStroke, lineWidth: 1)
            )

            if resolvedMission != nil {
                Button {
                    liveConsoleMapStyle = liveConsoleMapStyle == .standard ? .satellite : .standard
                } label: {
                    Image(systemName: liveConsoleMapStyle == .standard ? "map" : "globe.americas.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 33, height: 33)
                }
                .buttonStyle(.plain)
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.12))
                        .frame(height: 1),
                    alignment: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.leading, 10)
                .padding(.top, 85)
                .help(liveConsoleMapStyle == .standard ? "Show satellite imagery" : "Show street map")
            }
        }
    }

    private var missionLiveVehicleStatusRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if run.assignments.isEmpty {
                    MissionLiveVehicleHealthCard(
                        slotTitle: "—",
                        rosterSubtitle: "—",
                        vehicleID: nil,
                        simulationImageBasenames: nil,
                        hub: fleetLink.hubTelemetry
                    )
                } else {
                    ForEach(run.assignments) { assignment in
                        let device = resolvedMission.flatMap { m in
                            m.rosterDevices.first { $0.id == assignment.rosterDeviceId }
                        }
                        let vehicleID = telemetryVehicleID(for: assignment)
                        MissionLiveVehicleHealthCard(
                            slotTitle: assignment.slotName,
                            rosterSubtitle: rosterRoleSubtitle(device),
                            vehicleID: vehicleID,
                            simulationImageBasenames: simulationImageBasenamesForAssignment(assignment, sitl: sitl),
                            hub: vehicleID.flatMap(fleetLink.hubTelemetry(forVehicleID:))
                        )
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 140)
    }

    private var missionLiveLogPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(liveConsoleCardFill)
            .frame(minHeight: 120, maxHeight: 200)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(liveConsoleCardStroke, lineWidth: 1)
            )
    }

    private var completedSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mission completed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                MissionRunStatusBadge(status: .completed)
            }
            if let completedAt = run.completedAt {
                Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var scheduleSetupCard: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.scheduleCardSpacing) {
            Text("Schedule")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Picker("Mode", selection: $run.scheduleMode) {
                ForEach(MissionRunScheduleMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if run.scheduleMode == .oneOff {
                DatePicker(
                    "Start At",
                    selection: $run.oneOffStartAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
            } else if run.scheduleMode == .loop {
                Stepper(
                    "Loop every \(run.loopIntervalMinutes) minutes",
                    value: $run.loopIntervalMinutes,
                    in: 1...1440
                )
            } else {
                Text("Runs without a fixed start time or repeat interval. Continue until you pause or complete the run.")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MissionRunPrepLayout.scheduleCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.pathCardCornerRadius))
    }

    private var rosterPathsSetupSection: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.pathsOuterSpacing) {
            if run.assignments.isEmpty {
                Text("No roster slots on this mission template.")
                    .foregroundStyle(.gray)
            } else if let mission = resolvedMission {
                ForEach(mission.routeMacro.paths) { path in
                    pathRosterCard(path: path, mission: mission)
                }
                legacyPathlessRosterCard(mission: mission)
            } else {
                missionMissingTemplateRosterFallback
            }
        }
    }

    private var legacyUnassignedIndices: [Int] {
        run.assignments.indices.filter { run.assignments[$0].pathId == nil }
    }

    private func pathRosterCard(path: RoutePath, mission: Mission) -> some View {
        let indices = run.assignments.indices.filter { run.assignments[$0].pathId == path.id }
        return VStack(alignment: .leading, spacing: MissionRunPrepLayout.pathCardInnerSpacing) {
            Text(path.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            if indices.isEmpty {
                Text("No roster slots linked to this path. Link devices to the path in Missions → Roster.")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: MissionRunPrepLayout.rosterGridMinWidth),
                            spacing: MissionRunPrepLayout.rosterGridSpacing,
                            alignment: .top
                        ),
                    ],
                    spacing: MissionRunPrepLayout.rosterGridSpacing
                ) {
                    ForEach(indices, id: \.self) { idx in
                        rosterSlotCard(assignmentIndex: idx, mission: mission)
                    }
                }
            }
        }
        .padding(MissionRunPrepLayout.pathCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.pathCardCornerRadius))
    }

    @ViewBuilder
    private func legacyPathlessRosterCard(mission: Mission) -> some View {
        let indices = legacyUnassignedIndices
        if !indices.isEmpty {
            VStack(alignment: .leading, spacing: MissionRunPrepLayout.pathCardInnerSpacing) {
                Text("Mission roster")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: MissionRunPrepLayout.rosterGridMinWidth),
                            spacing: MissionRunPrepLayout.rosterGridSpacing,
                            alignment: .top
                        ),
                    ],
                    spacing: MissionRunPrepLayout.rosterGridSpacing
                ) {
                    ForEach(indices, id: \.self) { idx in
                        rosterSlotCard(assignmentIndex: idx, mission: mission)
                    }
                }
            }
            .padding(MissionRunPrepLayout.pathCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.pathCardCornerRadius))
        }
    }

    private var missionMissingTemplateRosterFallback: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.pathCardInnerSpacing) {
            Text("Roster")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text("Mission template not found — roster slots are frozen from when the run was created.")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: MissionRunPrepLayout.rosterGridMinWidth),
                        spacing: MissionRunPrepLayout.rosterGridSpacing,
                        alignment: .top
                    ),
                ],
                spacing: MissionRunPrepLayout.rosterGridSpacing
            ) {
                ForEach(run.assignments.indices, id: \.self) { idx in
                    rosterSlotCard(assignmentIndex: idx, mission: nil)
                }
            }
        }
        .padding(MissionRunPrepLayout.pathCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: MissionRunPrepLayout.pathCardCornerRadius))
    }

    private func rosterSlotCard(assignmentIndex: Int, mission: Mission?) -> some View {
        let a = run.assignments[assignmentIndex]
        let device = mission.flatMap { m in m.rosterDevices.first { $0.id == a.rosterDeviceId } }
        let label = resolvedRosterVehicleLabel(assignment: a, fleetLink: fleetLink, sitl: sitl)
        let basenames = simulationImageBasenamesForAssignment(a, sitl: sitl)
        let assignmentId = a.id
        return MissionControlRosterSlotCard(
            title: a.slotName,
            subtitle: rosterRoleSubtitle(device),
            assignedVehicleTitle: label,
            assignedFleetIsSimulation: rosterAssignmentFleetIsSimulation(a),
            simulationImageBasenames: basenames,
            onChooseVehicle: {
                withAnimation(rosterPickerSpring) {
                    rosterPickerAssignmentId = assignmentId
                }
            },
            onRemoveVehicle: {
                clearFleetVehicle(assignmentId: assignmentId)
            }
        )
    }

    private func rosterRoleSubtitle(_ device: RosterDevice?) -> String {
        guard let device else { return "—" }
        let hint = device.positionHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if hint.isEmpty { return device.roleType }
        return "\(device.roleType) · \(hint)"
    }

    /// `nil` when there is no fleet token (unassigned or legacy typed label only).
    private func rosterAssignmentFleetIsSimulation(_ assignment: MissionRunAssignment) -> Bool? {
        guard let key = assignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: key)
        else { return nil }
        switch token {
        case .live: return false
        case .sitl: return true
        }
    }

    private func applyFleetVehicle(_ vehicle: MissionPickableFleetVehicle, assignmentId: UUID) {
        guard let idx = run.assignments.firstIndex(where: { $0.id == assignmentId }) else { return }
        run.assignments[idx].attachedFleetVehicleToken = vehicle.token.storageKey
        run.assignments[idx].attachedDevice = vehicle.title
    }

    private func clearFleetVehicle(assignmentId: UUID) {
        guard let idx = run.assignments.firstIndex(where: { $0.id == assignmentId }) else { return }
        run.assignments[idx].attachedFleetVehicleToken = nil
        run.assignments[idx].attachedDevice = ""
    }

    private func rosterPickDisabledReason(_ vehicle: MissionPickableFleetVehicle, assignmentId: UUID) -> String? {
        let key = vehicle.token.storageKey
        if run.assignments.first(where: { $0.id == assignmentId })?.attachedFleetVehicleToken == key {
            return nil
        }
        if controlStore.isFleetVehicleLockedByOtherLiveMission(tokenKey: key, excludingRunId: run.id) {
            return "In use by another live mission"
        }
        if controlStore.isFleetVehicleUsedOnOtherSlotInRun(tokenKey: key, run: run, assignmentId: assignmentId) {
            return "Already assigned in this mission"
        }
        return nil
    }

    /// Bridge vehicle stream key for a roster assignment (`sysid:<id>` for SITL).
    private func telemetryVehicleID(for assignment: MissionRunAssignment) -> String? {
        guard let key = assignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: key)
        else { return nil }
        switch token {
        case .sitl(let uuid):
            guard let inst = sitl.instances.first(where: { $0.id == uuid }) else { return nil }
            // SITL instance indices are expected as MAVLink system ids `instance + 1`,
            // but we resolve through the bridge runtime map in case key format changes.
            let expectedSystemID = inst.stackInstanceIndex + 1
            return fleetLink.vehicleID(forSystemID: expectedSystemID) ?? "sysid:\(expectedSystemID)"
        case .live:
            return nil
        }
    }


}

/// One vehicle column in Mission Control: vehicle-type thumbnail + slot title / roster role subtitle, battery/GPS, MAVSDK health. Top-trailing reserved for a future cog menu.
private struct MissionLiveVehicleHealthCard: View {
    let slotTitle: String
    /// Same text as roster slot subtitle (`roleType` · position hint, or "—").
    let rosterSubtitle: String
    let vehicleID: String?
    let simulationImageBasenames: [String]?
    let hub: FleetHubVehicleTelemetry?

    private let cardFill = Color(red: 0.10, green: 0.10, blue: 0.11)
    private let cardStroke = Color.white.opacity(0.06)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    vehicleTypeThumbnail
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(slotTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(rosterSubtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.gray)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if let vehicleID {
                    Text(displayVehicleID(vehicleID))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.gray.opacity(0.75))
                        .lineLimit(1)
                        .help("Bridge vehicle key: \(vehicleID)")
                }

                if let hub {
                    Divider().opacity(0.22)
                    batteryAndGpsRows(hub)
                    healthChipsRow(hub)
                    if hub.healthAllOk == true {
                        Text("All OK")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(GuardianSemanticColors.successForeground)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(GuardianSemanticColors.successBackground)
                            .clipShape(Capsule())
                    }
                } else {
                    Text("No telemetry")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray.opacity(0.8))
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .padding(.trailing, 26)

            Color.clear
                .frame(width: 28, height: 28)
                .padding(.top, 6)
                .padding(.trailing, 6)
                .accessibilityLabel("Vehicle actions, coming soon")
        }
        .frame(width: 216, height: 140)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardStroke, lineWidth: 1)
        )
    }

    private var vehicleTypeThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.12, blue: 0.14),
                            Color(red: 0.05, green: 0.07, blue: 0.09),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let names = simulationImageBasenames, !names.isEmpty {
                SimulationDeviceThumbnail(imageBasenames: names)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(3)
            } else {
                Image(systemName: "fanblades")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan.opacity(0.9), .teal.opacity(0.65)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func batteryAndGpsRows(_ hub: FleetHubVehicleTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "battery.100")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(batteryIconTint(percent: hub.batteryRemainingPercent))
                if let p = hub.batteryRemainingPercent {
                    Text("\(Int(round(p)))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    Text("—")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.gray)
                }
                if let v = hub.batteryVoltageV {
                    Text(String(format: "%.1f V", v))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.gray)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.gray)
                if let n = hub.gpsNumSatellites {
                    Text("\(n)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    Text("—")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.gray)
                }
                if let fix = hub.gpsFixType, !fix.isEmpty {
                    Text(shortGpsFix(fix))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.gray)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Red below 10%, yellow from 10% up to (but not including) 80%, green at 80% and above. Unknown / out-of-range → neutral gray.
    private func normalizedBatteryPercent(_ raw: Double?) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        if raw < 0 || raw > 100 { return nil }
        return raw
    }

    private func batteryIconTint(percent: Double?) -> Color {
        guard let p = normalizedBatteryPercent(percent) else {
            return Color.gray.opacity(0.55)
        }
        if p < 10 {
            return Color.red.opacity(0.92)
        }
        if p < 80 {
            return Color.yellow.opacity(0.95)
        }
        return GuardianSemanticColors.successForeground
    }

    private func healthChipsRow(_ hub: FleetHubVehicleTelemetry) -> some View {
        HStack(spacing: 4) {
            healthChip("G", hub.healthGyrometerCalibrationOk, help: "Gyro calibration")
            healthChip("A", hub.healthAccelerometerCalibrationOk, help: "Accelerometer calibration")
            healthChip("M", hub.healthMagnetometerCalibrationOk, help: "Magnetometer calibration")
            healthChip("L", hub.healthLocalPositionOk, help: "Local position")
            healthChip("W", hub.healthGlobalPositionOk, help: "Global position")
            healthChip("H", hub.healthHomePositionOk, help: "Home position")
            healthChip("R", hub.healthArmable, help: "Armable")
        }
        .padding(.top, 2)
    }

    private func healthChip(_ label: String, _ ok: Bool?, help: String) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(healthChipForeground(ok))
            .frame(width: 18, height: 18)
            .background(healthChipBackground(ok))
            .clipShape(Circle())
            .help(help)
    }

    private func healthChipForeground(_ ok: Bool?) -> Color {
        guard let ok else { return .white.opacity(0.38) }
        return ok ? GuardianSemanticColors.successForeground : Color.red.opacity(0.9)
    }

    private func healthChipBackground(_ ok: Bool?) -> Color {
        guard let ok else { return Color.white.opacity(0.08) }
        return ok ? GuardianSemanticColors.successBackground : Color.red.opacity(0.18)
    }

    private func shortGpsFix(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = t.uppercased()
        if u.contains("NO_FIX") || u.contains("NO GPS") { return "—" }
        if u.contains("FIX_3D") || u.contains("3D_FIX") { return "3D" }
        if u.contains("FIX_2D") || u.contains("2D_FIX") { return "2D" }
        if u.contains("RTK") { return "RTK" }
        if t.count > 8 {
            return String(t.suffix(6))
        }
        return t
    }

    private func displayVehicleID(_ raw: String) -> String {
        if raw.hasPrefix("sysid:") {
            return String(raw.dropFirst("sysid:".count))
        }
        return raw
    }
}

private struct AddMissionRunSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var missionStore: MissionStore
    let onCreateRun: (Mission) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Mission")
                .font(.title3.bold())
            if missionStore.missions.isEmpty {
                Text("No mission templates available.")
                    .foregroundStyle(.gray)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(missionStore.missions) { mission in
                            Button {
                                onCreateRun(mission)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mission.name)
                                            .foregroundStyle(.white)
                                        Text(mission.description.isEmpty ? "No description" : mission.description)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.gray)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(red: 0.12, green: 0.12, blue: 0.13))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(width: 520, height: 420)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
    }
}
