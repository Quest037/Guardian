import SwiftUI
import AppKit

struct RootView: View {
    @Binding var selection: AppSection
    @ObservedObject var fleetLinkService: FleetLinkService
    @ObservedObject var sitlService: SitlService
    @ObservedObject var generalSettingsStore: GeneralSettingsStore
    @StateObject private var missionStore = MissionStore()
    @StateObject private var missionControlStore = MissionControlStore()
    @StateObject private var liveDriveStore = LiveDriveStore()
    @StateObject private var manualControlSettings = ManualControlSettingsStore()
    @State private var settingsPane: SettingsPane = .general
    @State private var isSidebarCollapsed = false
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

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
                .background(theme.backgroundRaised)

            VStack(spacing: 0) {
                topBar
                    .frame(height: 52)
                    .background(theme.backgroundElevated)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(theme.backgroundBase)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundBase)
        .onAppear {
            PaladinEngine.shared.missionControlDomainBridge().connect(to: missionControlStore)
            fleetLinkService.applyLogRetentionProfile(generalSettingsStore.logRetentionProfile)
            fleetLinkService.onAutopilotMissionCycleFinished = { vehicleID in
                Task { @MainActor in
                    missionControlStore.ingestAutopilotMissionCycleFinished(
                        vehicleID: vehicleID,
                        fleetLink: fleetLinkService,
                        sitl: sitlService,
                        missionsProvider: { missionStore.missions }
                    )
                }
            }
            fleetLinkService.onMirrorFleetLineToPaladin = { vehicleID, line in
                Task { @MainActor in
                    missionControlStore.ingestFleetMirrorLine(
                        vehicleID: vehicleID,
                        line: line,
                        fleetLink: fleetLinkService,
                        sitl: sitlService
                    )
                }
            }
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
                        .foregroundStyle(theme.textPrimary)
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
                    .background(section == selection ? theme.backgroundActive : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .help(section.rawValue)
            }

            Spacer()

            VStack(alignment: isSidebarCollapsed ? .center : .leading, spacing: 4) {
                Text(isSidebarCollapsed ? AppMetadata.releaseVersion : appVersionLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
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
                .foregroundStyle(theme.textPrimary)
                .padding(.leading, 16)
            Spacer()

            HStack(spacing: 8) {
                Text("Simulate")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
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

            Button {
                toggleAppearanceMode()
            } label: {
                Image(systemName: appearanceIconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(appearanceButtonHelp)
            .padding(.trailing, 16)
        }
    }

    private var appearanceIconName: String {
        colorScheme == .dark ? "moon.fill" : "sun.max.fill"
    }

    private var appearanceButtonHelp: String {
        "Toggle appearance (current: \(generalSettingsStore.appearanceMode.displayName))"
    }

    private func toggleAppearanceMode() {
        switch generalSettingsStore.appearanceMode {
        case .light:
            generalSettingsStore.appearanceMode = .dark
        case .dark:
            generalSettingsStore.appearanceMode = .light
        case .system:
            generalSettingsStore.appearanceMode = (colorScheme == .dark) ? .light : .dark
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
                VehiclesView(
                    fleetLink: fleetLinkService,
                    sitl: sitlService,
                    generalSettings: generalSettingsStore,
                    missionControlStore: missionControlStore,
                    liveDriveStore: liveDriveStore
                )
            case .liveDrive:
                LiveDriveView(
                    store: liveDriveStore,
                    fleetLink: fleetLinkService,
                    sitl: sitlService,
                    missionControlStore: missionControlStore,
                    manualControlSettings: manualControlSettings,
                    generalSettings: generalSettingsStore
                )
            case .settings:
                SettingsView(
                    selectedPane: $settingsPane,
                    generalSettings: generalSettingsStore,
                    manualControlSettings: manualControlSettings
                )
            case .logs:
                LogsView(fleetLink: fleetLinkService)
            }
        }
    }
}

