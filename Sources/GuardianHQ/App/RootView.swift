import SwiftUI

struct RootView: View {
    @Binding var selection: AppSection
    @ObservedObject var fleetLinkService: FleetLinkService
    @ObservedObject var sitlService: SitlService
    @ObservedObject var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var appDrawer: AppDrawer
    @EnvironmentObject private var operatorPromptCenter: OperatorPromptCenter
    @EnvironmentObject private var operatorPromptReviewFocus: OperatorPromptReviewFocusController
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
            }
        }
        .preference(
            key: GuardianToastShellAnchorPreferenceKey.self,
            value: GuardianToastShellAnchor(topBarHeight: 52, topBarTrailingInset: GuardianSpacing.md)
        )
        .preference(
            key: GuardianOperatorPromptPersistentAnchorPreferenceKey.self,
            value: GuardianOperatorPromptPersistentAnchor(
                leadingContentInset: sidebarWidth + GuardianSpacing.md,
                topContentInset: 52 + GuardianSpacing.sm
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundBase)
        .onAppear {
            OperatorPromptCenter.shared.prepareOperatorPromptRoutingSession()
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
            FleetRecipeRunner.shared.liveMissionGate = { vehicleID in
                missionControlStore.isVehicleStreamUsedInLiveMission(
                    vehicleID: vehicleID,
                    fleetLink: fleetLinkService,
                    sitl: sitlService
                )
            }
        }
        .onChange(of: fleetLinkService.isSimulateEnabled) { sim in
            if !sim { sitlService.stopAll() }
        }
        .onChange(of: generalSettingsStore.logRetentionProfile) { profile in
            fleetLinkService.applyLogRetentionProfile(profile)
        }
        .onChange(of: generalSettingsStore.mainSidebarLaunchMode) { mode in
            withAnimation(GuardianMotion.drawerSlide) {
                isSidebarCollapsed = (mode == .collapsed)
            }
        }
        .onChange(of: selection) { _ in
            appDrawer.dismiss()
        }
        .onChange(of: operatorPromptReviewFocus.pendingPrimarySection) { newSection in
            guard let newSection else { return }
            if selection != newSection {
                selection = newSection
            }
            operatorPromptReviewFocus.consumePendingPrimarySection()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            HStack(alignment: .center, spacing: 0) {
                if isSidebarCollapsed {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(GuardianMotion.drawerSlide) {
                                isSidebarCollapsed = false
                            }
                        } label: {
                            GuardianSidebarLogoView(maxHeight: 28)
                                .frame(width: 44, height: 28)
                        }
                        .buttonStyle(GuardianPointerPlainButtonStyle())
                        .contentShape(Rectangle())
                        .help("Expand sidebar")
                        .accessibilityLabel("Guardian")
                        .accessibilityHint("Expands the sidebar")
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        withAnimation(GuardianMotion.drawerSlide) {
                            isSidebarCollapsed = true
                        }
                    } label: {
                        GuardianSidebarLogoView(maxHeight: 32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(GuardianPointerPlainButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Collapse sidebar")
                    .accessibilityLabel("Guardian")
                    .accessibilityHint("Collapses the sidebar")
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, GuardianSpacing.sm)
            .padding(.top, GuardianSpacing.md)
            .padding(.bottom, GuardianSpacing.xs)

            ScrollView {
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    ForEach(AppSection.primarySidebarRail, id: \.self) { section in
                        sidebarSectionRow(section: section)
                    }
                    ForEach(pluginRegistry.sidebarItems(for: .primary)) { item in
                        sidebarPluginRow(item: item)
                    }
                }
                .padding(.horizontal, GuardianSpacing.denseGutter)
                .padding(.bottom, GuardianSpacing.xsTight)
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                ForEach(pluginRegistry.sidebarItems(for: .secondary)) { item in
                    sidebarPluginRow(item: item)
                }
                ForEach(AppSection.secondarySidebarSections, id: \.self) { section in
                    sidebarSectionRow(section: section)
                }

                VStack(alignment: isSidebarCollapsed ? .center : .leading, spacing: GuardianSpacing.xxs) {
                    Text(isSidebarCollapsed ? AppMetadata.releaseVersion : appVersionLabel)
                        .font(GuardianTypography.font(.appVersionCaption))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .leading)
                .padding(.top, GuardianSpacing.xxs)
            }
            .padding(.horizontal, GuardianSpacing.denseGutter)
            .padding(.bottom, GuardianSpacing.cardBodyInset)
        }
    }

    private func sidebarSectionRow(section: AppSection) -> some View {
        Button {
            selection = section
        } label: {
            Group {
                if isSidebarCollapsed {
                    Image(systemName: section.systemImage)
                        .font(GuardianTypography.font(.appSidebarIconCollapsed))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    HStack {
                        Image(systemName: section.systemImage)
                            .font(GuardianTypography.font(.appSidebarIconExpanded))
                            .frame(width: 18, height: 18)
                        Text(section.rawValue)
                            .font(GuardianTypography.font(.appSidebarRowTitle(isSelected: section == selection)))
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, isSidebarCollapsed ? GuardianSpacing.xs : GuardianSpacing.cardBodyInset)
            .padding(.vertical, GuardianSpacing.denseGutter)
            .frame(maxWidth: .infinity)
            .background(section == selection ? theme.backgroundActive : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
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
                        .font(GuardianTypography.font(.appSidebarIconCollapsed))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    HStack {
                        Image(systemName: item.systemImage)
                            .font(GuardianTypography.font(.appSidebarIconExpanded))
                            .frame(width: 18, height: 18)
                        Text(item.title)
                            .font(GuardianTypography.font(.appSidebarRowTitle(isSelected: sidebarPluginRowIsSelected(item))))
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, isSidebarCollapsed ? GuardianSpacing.xs : GuardianSpacing.cardBodyInset)
            .padding(.vertical, GuardianSpacing.denseGutter)
            .frame(maxWidth: .infinity)
            .background(sidebarPluginRowIsSelected(item) ? theme.backgroundActive : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
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

    private var operatorPromptInboxTopBarButton: some View {
        let count = operatorPromptCenter.inboxPrompts.count
        return Button {
            presentOperatorPromptInbox()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "tray.full")
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(GuardianTypography.relativeFixed(size: 9, weight: .heavy, relativeTo: .caption2))
                        .foregroundStyle(.white)
                        .padding(.horizontal, count > 9 ? 4 : 5)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(GuardianSemanticColors.dangerForeground))
                        .offset(x: 8, y: -6)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
        .guardianPointerOnHover()
        .help(count == 0 ? "Decisions" : "Decisions — \(count) pending")
        .accessibilityLabel("Decisions")
        .accessibilityHint(count == 0 ? "Opens Decisions. Nothing is waiting for an answer." : "Opens Decisions. \(count) waiting for an answer.")
    }

    private func presentOperatorPromptInbox() {
        appDrawer.present(title: "Decisions", preferredWidth: 420) {
            OperatorPromptInboxDrawerView()
        }
    }

    private var topBar: some View {
        HStack(spacing: GuardianSpacing.md) {
            Text(selection.rawValue)
                .font(GuardianTypography.font(.appWindowToolbarTitle))
                .foregroundStyle(theme.textPrimary)
                .padding(.leading, GuardianSpacing.md)
            Spacer()

            operatorPromptInboxTopBarButton

            HStack(spacing: GuardianSpacing.xs) {
                Text("Simulate")
                    .font(GuardianTypography.font(.inlineNoticeTitle))
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

            HStack(spacing: GuardianSpacing.xs) {
                Text("Debug")
                    .font(GuardianTypography.font(.inlineNoticeTitle))
                    .foregroundStyle(theme.textSecondary)
                Toggle(
                    "",
                    isOn: Binding(
                        get: { fleetLinkService.isDebugEnabled },
                        set: { fleetLinkService.setDebugEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help("Show debug overlays and diagnostics")
            }

            Button {
                toggleAppearanceMode()
            } label: {
                Image(systemName: appearanceIconName)
                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GuardianPointerPlainButtonStyle())
            .help(appearanceButtonHelp)
            .padding(.trailing, GuardianSpacing.md)
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

