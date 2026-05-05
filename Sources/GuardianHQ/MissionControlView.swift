import SwiftUI

struct MissionControlView: View {
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var controlStore: MissionControlStore

    @State private var selectedRunID: UUID?
    @State private var showingAddRunSheet = false

    var body: some View {
        Group {
            if let run = selectedRun {
                MissionRunDetailView(
                    run: run,
                    missionStore: missionStore,
                    onBack: { selectedRunID = nil },
                    onUpdate: { controlStore.updateRun($0) },
                    onStart: { controlStore.startRun(id: $0.id) }
                )
            } else {
                missionRunGrid
            }
        }
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
                VStack(spacing: 8) {
                    Spacer()
                    Text("No mission running")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Add a run from a mission template to begin.")
                        .foregroundStyle(.gray)
                    Spacer()
                }
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

private struct MissionRunCard: View {
    let run: MissionRun

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(run.missionName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(run.status.rawValue.capitalized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.gray)
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

/// Roster slot card for Mission Control setup: drone placeholder, name/role, simulated attach field, add (no-op), unlink.
private struct MissionControlRosterSlotCard: View {
    let title: String
    let subtitle: String
    @Binding var attachedDevice: String

    private var isAttached: Bool {
        !attachedDevice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
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
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            TextField("Attached device (simulated)", text: $attachedDevice)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            HStack(spacing: 10) {
                Button {
                    // Reserved for future “pick device” flow.
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
                .labelStyle(.titleAndIcon)

                Spacer()

                if isAttached {
                    Button {
                        attachedDevice = ""
                    } label: {
                        Label("Unlink", systemImage: "link.badge.minus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.10, green: 0.10, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isAttached ? Color.green.opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: isAttached ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: isAttached ? 6 : 2, y: isAttached ? 2 : 1)
    }
}

private struct MissionRunDetailView: View {
    @State var run: MissionRun
    @ObservedObject var missionStore: MissionStore
    let onBack: () -> Void
    let onUpdate: (MissionRun) -> Void
    let onStart: (MissionRun) -> Void

    private var resolvedMission: Mission? {
        missionStore.missions.first { $0.id == run.missionId }
    }

    private var allRosterFilled: Bool {
        run.assignments.allSatisfy { !$0.attachedDevice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var canStart: Bool {
        guard allRosterFilled else { return false }
        if run.scheduleMode == .loop {
            return run.loopIntervalMinutes > 0
        }
        return true
    }

    var body: some View {
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
                    Button("Start Run") {
                        run.status = .running
                        onStart(run)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!canStart)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))

            if run.status == .setup {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        scheduleSetupCard
                        rosterSetupCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        runningCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        .onDisappear {
            onUpdate(run)
        }
    }

    private var scheduleSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var rosterSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Roster")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text("Each path has its own slots. Attach hardware (simulated below) before starting.")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
                .fixedSize(horizontal: false, vertical: true)

            if run.assignments.isEmpty {
                Text("No roster slots on this mission template.")
                    .foregroundStyle(.gray)
            } else if let mission = resolvedMission {
                ForEach(mission.routeMacro.paths) { path in
                    pathRosterRow(path: path, mission: mission)
                }
                legacyUnassignedRosterSection(mission: mission)
            } else {
                Text("Mission template not found — roster slots are frozen from when the run was created.")
                    .foregroundStyle(.gray)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                    ForEach(run.assignments.indices, id: \.self) { idx in
                        MissionControlRosterSlotCard(
                            title: run.assignments[idx].slotName,
                            subtitle: "—",
                            attachedDevice: bindingForAssignment(at: idx)
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var legacyUnassignedIndices: [Int] {
        run.assignments.indices.filter { run.assignments[$0].pathId == nil }
    }

    @ViewBuilder
    private func legacyUnassignedRosterSection(mission: Mission) -> some View {
        let indices = legacyUnassignedIndices
        if !indices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mission roster")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text("Slots not tied to a specific path.")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                    ForEach(indices, id: \.self) { idx in
                        let a = run.assignments[idx]
                        let device = mission.rosterDevices.first { $0.id == a.rosterDeviceId }
                        MissionControlRosterSlotCard(
                            title: a.slotName,
                            subtitle: rosterRoleSubtitle(device),
                            attachedDevice: bindingForAssignment(at: idx)
                        )
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func pathRosterRow(path: RoutePath, mission: Mission) -> some View {
        let indices = run.assignments.indices.filter { run.assignments[$0].pathId == path.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(path.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(path.waypoints.count) waypoints")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
            }
            if indices.isEmpty {
                Text("No roster slots linked to this path. Link devices to the path in Missions → Roster.")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                    ForEach(indices, id: \.self) { idx in
                        let a = run.assignments[idx]
                        let device = mission.rosterDevices.first { $0.id == a.rosterDeviceId }
                        MissionControlRosterSlotCard(
                            title: a.slotName,
                            subtitle: rosterRoleSubtitle(device),
                            attachedDevice: bindingForAssignment(at: idx)
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func rosterRoleSubtitle(_ device: RosterDevice?) -> String {
        guard let device else { return "—" }
        let hint = device.positionHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if hint.isEmpty { return device.roleType }
        return "\(device.roleType) · \(hint)"
    }

    private func bindingForAssignment(at index: Int) -> Binding<String> {
        Binding(
            get: { run.assignments[index].attachedDevice },
            set: { run.assignments[index].attachedDevice = $0 }
        )
    }

    private var runningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Running")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text("Camera outputs")
                .foregroundStyle(.gray)

            if let mission = resolvedMission {
                ForEach(mission.routeMacro.paths) { path in
                    let pathAssignments = run.assignments.filter { $0.pathId == path.id }
                    if !pathAssignments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(path.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(pathAssignments.count) feed\(pathAssignments.count == 1 ? "" : "s")")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.gray)
                            }
                            runningFeedGrid(assignments: pathAssignments)
                        }
                        .padding(.bottom, 4)
                    }
                }
                let loose = run.assignments.filter { $0.pathId == nil }
                if !loose.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Other slots")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        runningFeedGrid(assignments: loose)
                    }
                }
            } else {
                runningFeedGrid(assignments: run.assignments)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func runningFeedGrid(assignments: [MissionRunAssignment]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
            ForEach(assignments, id: \.id) { assignment in
                VStack(alignment: .leading, spacing: 6) {
                    Text(assignment.slotName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(assignment.attachedDevice.isEmpty ? "Unassigned" : assignment.attachedDevice)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.35))
                        .frame(height: 120)
                        .overlay(
                            Text("Feed placeholder")
                                .font(.system(size: 11))
                                .foregroundStyle(.gray)
                        )
                }
                .padding(10)
                .background(Color(red: 0.10, green: 0.10, blue: 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
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
