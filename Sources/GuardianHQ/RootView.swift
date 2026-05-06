import SwiftUI
import AppKit

struct RootView: View {
    @Binding var selection: AppSection
    @StateObject private var missionStore = MissionStore()
    @StateObject private var missionControlStore = MissionControlStore()
    @StateObject private var fleetLinkService = FleetLinkService()
    @StateObject private var generalSettingsStore = GeneralSettingsStore()
    @StateObject private var sitlService = SitlService()
    @State private var settingsPane: SettingsPane = .general
    @State private var isSidebarCollapsed = false

    private let bgMain = Color(red: 0.07, green: 0.07, blue: 0.08)
    private let bgRail = Color(red: 0.12, green: 0.12, blue: 0.13)
    private let bgTop = Color(red: 0.14, green: 0.14, blue: 0.15)
    private let bgActive = Color(red: 0.20, green: 0.20, blue: 0.21)

    private var sidebarWidth: CGFloat {
        isSidebarCollapsed ? 72 : 260
    }

    private var appVersionLabel: String {
        "v\(AppMetadata.releaseVersion)"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
                .background(bgRail)

            VStack(spacing: 0) {
                topBar
                    .frame(height: 52)
                    .background(bgTop)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(bgMain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgMain)
        .onAppear {
            sitlService.attachFleetLink(fleetLinkService)
            fleetLinkService.applyLogRetentionProfile(generalSettingsStore.logRetentionProfile)
        }
        .onChange(of: fleetLinkService.isSimulateEnabled) { sim in
            if !sim { sitlService.stopAll() }
        }
        .onChange(of: generalSettingsStore.logRetentionProfile) { profile in
            fleetLinkService.applyLogRetentionProfile(profile)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .tint(.gray.opacity(0.35))

                if !isSidebarCollapsed {
                    Text("Guardian")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Group {
                        if isSidebarCollapsed {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            HStack {
                                Image(systemName: section.systemImage)
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 18, height: 18)
                            Text(section.rawValue)
                                .font(.system(size: 14, weight: section == selection ? .semibold : .regular))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, isSidebarCollapsed ? 8 : 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(section == selection ? bgActive : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .help(section.rawValue)
            }

            Spacer()

            VStack(alignment: isSidebarCollapsed ? .center : .leading, spacing: 4) {
                Text(isSidebarCollapsed ? AppMetadata.releaseVersion : appVersionLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Text(selection.rawValue)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.leading, 16)
            Spacer()

            HStack(spacing: 8) {
                Text("Simulate")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.gray)
                Toggle(
                    "",
                    isOn: Binding(
                        get: { fleetLinkService.isSimulateEnabled },
                        set: { fleetLinkService.setSimulateEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help("Simulate")
            }

            Text("Dark Mode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.gray)
                .padding(.trailing, 16)
        }
    }

    private var content: some View {
        Group {
            switch selection {
            case .dashboard:
                DashboardView(
                    missionStore: missionStore,
                    missionControlStore: missionControlStore,
                    fleetLink: fleetLinkService,
                    sitl: sitlService
                )
            case .missions:
                MissionsView(store: missionStore, generalSettings: generalSettingsStore)
            case .missionControl:
                MissionControlView(
                    missionStore: missionStore,
                    controlStore: missionControlStore,
                    fleetLink: fleetLinkService,
                    sitl: sitlService,
                    generalSettings: generalSettingsStore
                )
            case .devices:
                DevicesView(
                    fleetLink: fleetLinkService,
                    sitl: sitlService,
                    generalSettings: generalSettingsStore
                )
            case .settings:
                SettingsView(
                    selectedPane: $settingsPane,
                    generalSettings: generalSettingsStore
                )
            case .logs:
                LogsView(fleetLink: fleetLinkService)
            }
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var missionControlStore: MissionControlStore
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService

    private var activeMissionRuns: Int {
        missionControlStore.runs.filter { $0.status == .running }.count
    }

    private var simInstanceRowCount: Int {
        sitl.instances.count
    }

    /// Same cardinality as `fleetGridEntries` on Devices (live MAVLink row when connected, plus every SITL row).
    private var vehiclesTotalCount: Int {
        let liveVehicleCount = fleetLink.telemetryByVehicleID.count
        return liveVehicleCount + simInstanceRowCount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    dashboardStatCard(
                        title: "Missions",
                        value: "\(missionStore.missions.count)",
                    )
                    dashboardStatCard(
                        title: "Live Missions",
                        value: "\(activeMissionRuns)",
                    )
                }
                HStack(spacing: 16) {
                    dashboardStatCard(
                        title: "Vehicles",
                        value: "\(vehiclesTotalCount)",
                    )
                    dashboardStatCard(
                        title: "Vehicles (sims)",
                        value: "\(simInstanceRowCount)",
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dashboardStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct LogsView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @State private var selectedVehicleIDs: Set<String> = []
    @State private var vehiclesAccordionExpanded = true
    @State private var levelsAccordionExpanded = false
    @State private var sessionsAccordionExpanded = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filters")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        DisclosureGroup(
                            isExpanded: $vehiclesAccordionExpanded,
                            content: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(fleetLink.vehicleLogIDs(), id: \.self) { vehicleID in
                                        Toggle(
                                            vehicleID.replacingOccurrences(of: "sysid:", with: "System "),
                                            isOn: Binding(
                                                get: { selectedVehicleIDs.contains(vehicleID) },
                                                set: { enabled in
                                                    if enabled {
                                                        selectedVehicleIDs.insert(vehicleID)
                                                    } else {
                                                        selectedVehicleIDs.remove(vehicleID)
                                                    }
                                                }
                                            )
                                        )
                                        .toggleStyle(.checkbox)
                                        .foregroundStyle(.gray)
                                    }
                                }
                                .padding(.top, 6)
                            },
                            label: {
                                Text("Vehicles")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        )

                        DisclosureGroup(
                            isExpanded: $levelsAccordionExpanded,
                            content: {
                                Text("Coming soon")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.gray)
                                    .padding(.top, 6)
                            },
                            label: {
                                Text("Levels")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        )

                        DisclosureGroup(
                            isExpanded: $sessionsAccordionExpanded,
                            content: {
                                Text("Coming soon")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.gray)
                                    .padding(.top, 6)
                            },
                            label: {
                                Text("Sessions")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        )
                        .padding(.bottom, 2)
                    }
                    .padding(.trailing, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(14)
            .frame(width: 260)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Logs")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Copy Logs") {
                        copyFilteredLogsToPasteboard()
                    }
                    .buttonStyle(.bordered)
                    Button("Clear") {
                        fleetLink.clearLog()
                        selectedVehicleIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(filteredLogs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(24)
    }

    private var filteredLogs: [String] {
        fleetLink.combinedLogs(filteredVehicleIDs: selectedVehicleIDs)
    }

    private func copyFilteredLogsToPasteboard() {
        let joined = filteredLogs.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(joined, forType: .string)
    }
}
