import SwiftUI

struct RootView: View {
    @Binding var selection: AppSection
    @ObservedObject var fleetLinkService: FleetLinkService
    @ObservedObject var sitlService: SitlService
    @ObservedObject var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var appDrawer: AppDrawer
    @EnvironmentObject private var pluginRegistry: GuardianPluginRegistry
    @StateObject private var missionStore = MissionStore()
    @StateObject private var missionControlStore = MissionControlStore()
    @StateObject private var liveDriveStore = LiveDriveStore()
    @StateObject private var manualControlSettings = ManualControlSettingsStore()
    @State private var settingsPane: SettingsPane = .general
    @State private var isSidebarCollapsed: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(
        selection: Binding<AppSection>,
        fleetLinkService: FleetLinkService,
        sitlService: SitlService,
        generalSettingsStore: GeneralSettingsStore
    ) {
        _selection = selection
        self.fleetLinkService = fleetLinkService
        self.sitlService = sitlService
        self.generalSettingsStore = generalSettingsStore
        _isSidebarCollapsed = State(
            initialValue: generalSettingsStore.mainSidebarLaunchMode == .collapsed
        )
    }

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
                    .background(theme.backgroundRaised)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(theme.backgroundBase)
                    .withToasts()
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
        .onChange(of: generalSettingsStore.mainSidebarLaunchMode) { mode in
            withAnimation(.easeInOut(duration: 0.2)) {
                isSidebarCollapsed = (mode == .collapsed)
            }
        }
        .onChange(of: selection) { _ in
            appDrawer.dismiss()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 0) {
                if isSidebarCollapsed {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSidebarCollapsed = false
                            }
                        } label: {
                            GuardianSidebarLogoView(maxHeight: 28)
                                .frame(width: 44, height: 28)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help("Expand sidebar")
                        .accessibilityLabel("Guardian")
                        .accessibilityHint("Expands the sidebar")
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSidebarCollapsed = true
                        }
                    } label: {
                        GuardianSidebarLogoView(maxHeight: 32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Collapse sidebar")
                    .accessibilityLabel("Guardian")
                    .accessibilityHint("Collapses the sidebar")
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(AppSection.primarySidebarRail, id: \.self) { section in
                        sidebarSectionRow(section: section)
                    }
                    ForEach(pluginRegistry.sidebarItems(for: .primary)) { item in
                        sidebarPluginRow(item: item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(pluginRegistry.sidebarItems(for: .secondary)) { item in
                    sidebarPluginRow(item: item)
                }
                ForEach(AppSection.secondarySidebarSections, id: \.self) { section in
                    sidebarSectionRow(section: section)
                }

                VStack(alignment: isSidebarCollapsed ? .center : .leading, spacing: 4) {
                    Text(isSidebarCollapsed ? AppMetadata.releaseVersion : appVersionLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .leading)
                .padding(.top, 4)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
    }

    private func sidebarSectionRow(section: AppSection) -> some View {
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
        .frame(maxWidth: .infinity)
        .help(section.rawValue)
    }

    private func sidebarPluginRow(item: GuardianPluginSidebarItem) -> some View {
        Button {
            switch item.tapAction {
            case .openAppSection(let section):
                selection = section
            }
        } label: {
            Group {
                if isSidebarCollapsed {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    HStack {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 18, height: 18)
                        Text(item.title)
                            .font(.system(size: 14, weight: sidebarPluginRowIsSelected(item) ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, isSidebarCollapsed ? 8 : 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(sidebarPluginRowIsSelected(item) ? theme.backgroundActive : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textPrimary)
        .frame(maxWidth: .infinity)
        .help(item.title)
    }

    private func sidebarPluginRowIsSelected(_ item: GuardianPluginSidebarItem) -> Bool {
        switch item.tapAction {
        case .openAppSection(let section):
            return selection == section
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
                MissionsView(
                    store: missionStore,
                    missionControlStore: missionControlStore,
                    generalSettings: generalSettingsStore
                )
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
            case .theme:
                ThemePanelView()
            case .settings:
                SettingsView(
                    selectedPane: $settingsPane,
                    generalSettings: generalSettingsStore,
                    manualControlSettings: manualControlSettings
                )
            case .plugins:
                PluginsView()
            case .logs:
                LogsView(fleetLink: fleetLinkService)
            }
        }
    }
}

