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
            fleetLinkService.applyLogRetentionProfile(generalSettingsStore.logRetentionProfile)
            fleetLinkService.onAutopilotMissionCycleFinished = { vehicleID in
                Task { @MainActor in
                    missionControlStore.handleAutopilotMissionCycleFinished(
                        vehicleID: vehicleID,
                        fleetLink: fleetLinkService,
                        sitl: sitlService,
                        missionsProvider: { missionStore.missions }
                    )
                }
            }
            fleetLinkService.onMirrorFleetLineToPaladin = { vehicleID, line in
                Task { @MainActor in
                    missionControlStore.ingestFleetMirrorLineForPaladin(
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
                DevicesView(
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

private struct DashboardView: View {
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var missionControlStore: MissionControlStore
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var activeMissionRuns: Int {
        missionControlStore.runs.filter { $0.status == .running }.count
    }

    private var pausedMissionRuns: Int {
        missionControlStore.runs.filter { $0.status == .paused }.count
    }

    private var completedMissionRuns: Int {
        missionControlStore.runs.filter { $0.status == .completed }.count
    }

    private var simInstanceRowCount: Int {
        sitl.instances.count
    }

    private var simVehicleIDs: Set<String> {
        Set(sitl.instances.map { "sysid:\($0.stackInstanceIndex + 1)" })
    }

    /// Same cardinality as `fleetGridEntries` on Devices (live MAVLink row when connected, plus every SITL row).
    private var vehiclesTotalCount: Int {
        allVehicleIDs.count
    }

    private var allVehicleIDs: [String] {
        Array(Set(fleetLink.vehicleModelsByVehicleID.keys).union(simVehicleIDs)).sorted()
    }

    private var liveVehicleCount: Int {
        allVehicleIDs.filter { !simVehicleIDs.contains($0) }.count
    }

    private var readinessRows: [DashboardVehicleReadinessRow] {
        allVehicleIDs.map { vehicleID in
            let status = fleetLink.vehicleStatus(forVehicleID: vehicleID)
            let telemetry = fleetLink.hubTelemetry(forVehicleID: vehicleID)
            let operational = fleetLink.vehicleOperationalModel(forVehicleID: vehicleID)
            let batteryPercent = operational.battery.percent0to100
            let telemetryAgeS = operational.telemetryAgeS
            let isTelemetryStale = (telemetryAgeS ?? .infinity) > 4

            let gpsRaw = (telemetry?.gpsFixType ?? "").uppercased()
            let gpsReady = gpsRaw.contains("3D") || gpsRaw.contains("RTK")
            let armable = telemetry?.healthArmable == true
            let lifecycleLive = status?.stage == .live
            let batteryReady = (batteryPercent ?? 100) >= 30

            let readinessIssues = [
                !lifecycleLive ? "Link not live" : nil,
                armable ? nil : "Not armable",
                gpsReady ? nil : "GPS weak",
                batteryReady ? nil : "Low battery",
                isTelemetryStale ? "Telemetry stale" : nil,
            ].compactMap { $0 }
            let ready = readinessIssues.isEmpty
            return DashboardVehicleReadinessRow(
                vehicleID: vehicleID,
                shortID: fleetLink.displayShortID(forVehicleID: vehicleID),
                isSimulation: simVehicleIDs.contains(vehicleID),
                batteryPercent: batteryPercent,
                issueSummary: readinessIssues.joined(separator: ", "),
                isReady: ready
            )
        }
    }

    private var readyVehicleCount: Int {
        readinessRows.count(where: { $0.isReady })
    }

    private var notReadyVehicleCount: Int {
        readinessRows.count - readyVehicleCount
    }

    private var readinessBreakdown: [DashboardBreakdownRow] {
        [
            DashboardBreakdownRow(label: "Link not live", count: readinessRows.count(where: { $0.issueSummary.contains("Link not live") })),
            DashboardBreakdownRow(label: "Not armable", count: readinessRows.count(where: { $0.issueSummary.contains("Not armable") })),
            DashboardBreakdownRow(label: "GPS weak", count: readinessRows.count(where: { $0.issueSummary.contains("GPS weak") })),
            DashboardBreakdownRow(label: "Low battery", count: readinessRows.count(where: { $0.issueSummary.contains("Low battery") })),
            DashboardBreakdownRow(label: "Telemetry stale", count: readinessRows.count(where: { $0.issueSummary.contains("Telemetry stale") })),
        ].filter { $0.count > 0 }
    }

    private var missionHealthLabel: String {
        if activeMissionRuns > 0 && !alertRows.isEmpty { return "Degraded" }
        if activeMissionRuns > 0 { return "Healthy" }
        if pausedMissionRuns > 0 { return "Paused" }
        return "Idle"
    }

    private var missionHealthColor: Color {
        switch missionHealthLabel {
        case "Healthy": return .green
        case "Degraded": return .orange
        case "Paused": return .yellow
        default: return .gray
        }
    }

    private var alertRows: [DashboardAlertRow] {
        let lines = fleetLink.combinedLogs(filteredVehicleIDs: [])
        return lines.reversed().compactMap { line in
            let lower = line.lowercased()
            let severity: DashboardAlertSeverity
            if lower.contains("failed") || lower.contains("fatal") || lower.contains("terminate") {
                severity = .critical
            } else if lower.contains("error") || lower.contains("denied") || lower.contains("timeout") || lower.contains("rejected") {
                severity = .high
            } else if lower.contains("warning") || lower.contains("reconnect") || lower.contains("stale") || lower.contains("awaiting") {
                severity = .medium
            } else {
                return nil
            }
            return DashboardAlertRow(severity: severity, text: line)
        }
        .prefix(8)
        .map { $0 }
    }

    private var criticalBatteryRows: [DashboardVehicleReadinessRow] {
        readinessRows
            .filter { ($0.batteryPercent ?? 100) < 35 }
            .sorted { ($0.batteryPercent ?? 100) < ($1.batteryPercent ?? 100) }
    }

    private var utilizationRows: [DashboardBreakdownRow] {
        let ready = readyVehicleCount
        let atRisk = readinessRows.count(where: { !$0.isReady && ($0.batteryPercent ?? 100) >= 30 })
        let lowBattery = readinessRows.count(where: { ($0.batteryPercent ?? 100) < 30 })
        let unknown = max(0, vehiclesTotalCount - ready - atRisk - lowBattery)
        return [
            DashboardBreakdownRow(label: "Ready", count: ready),
            DashboardBreakdownRow(label: "At risk", count: atRisk),
            DashboardBreakdownRow(label: "Low battery", count: lowBattery),
            DashboardBreakdownRow(label: "Unknown", count: unknown),
        ]
    }

    private var maxUtilizationCount: Int {
        max(utilizationRows.map(\.count).max() ?? 1, 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    dashboardStatCard(title: "Missions", value: "\(missionStore.missions.count)")
                    dashboardStatCard(title: "Live Missions", value: "\(activeMissionRuns)")
                    dashboardStatCard(title: "Paused", value: "\(pausedMissionRuns)")
                    dashboardStatCard(title: "Completed", value: "\(completedMissionRuns)")
                }

                HStack(alignment: .top, spacing: 16) {
                    dashboardMissionHealthCard
                    dashboardFleetReadinessCard
                }

                HStack(alignment: .top, spacing: 16) {
                    dashboardUtilizationCard
                    dashboardBatteryRiskCard
                }

                dashboardAlertsCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dashboardMissionHealthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mission Health")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(missionHealthLabel)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(missionHealthColor)
                Text("Runs: \(activeMissionRuns) active")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            if pausedMissionRuns > 0 {
                Text("Paused runs need operator confirmation.")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow.opacity(0.9))
            } else if activeMissionRuns == 0 {
                Text("No live mission runs right now.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            } else {
                Text("Missions are currently advancing.")
                    .font(.system(size: 12))
                    .foregroundStyle(.green.opacity(0.85))
            }
        }
        .dashboardPanelStyle(minHeight: 148, background: theme.backgroundRaised)
    }

    private var dashboardFleetReadinessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fleet Readiness")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 14) {
                readinessCounter(title: "Ready", value: readyVehicleCount, color: .green)
                readinessCounter(title: "Unready", value: notReadyVehicleCount, color: .orange)
                readinessCounter(title: "Total", value: vehiclesTotalCount, color: theme.textPrimary.opacity(0.9))
                readinessCounter(title: "SIM", value: simInstanceRowCount, color: .blue.opacity(0.9))
                readinessCounter(title: "Live", value: liveVehicleCount, color: theme.textPrimary.opacity(0.9))
            }
            if readinessBreakdown.isEmpty {
                Text("No active readiness blockers.")
                    .font(.system(size: 12))
                    .foregroundStyle(.green.opacity(0.85))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(readinessBreakdown) { row in
                        Text("• \(row.label): \(row.count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
        .dashboardPanelStyle(minHeight: 148, background: theme.backgroundRaised)
    }

    private var dashboardUtilizationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fleet Utilization")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(utilizationRows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(row.label)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textSecondary)
                            Spacer(minLength: 0)
                            Text("\(row.count)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.textPrimary)
                        }
                        GeometryReader { geo in
                            let ratio = CGFloat(row.count) / CGFloat(maxUtilizationCount)
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(theme.borderSubtle)
                                Capsule()
                                    .fill(utilizationColor(for: row.label))
                                    .frame(width: max(4, geo.size.width * ratio))
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
        .dashboardPanelStyle(minHeight: 180, background: theme.backgroundRaised)
    }

    private var dashboardBatteryRiskCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Battery Risk Watchlist")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            if criticalBatteryRows.isEmpty {
                Text("No vehicles below 35% battery.")
                    .font(.system(size: 12))
                    .foregroundStyle(.green.opacity(0.85))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(criticalBatteryRows.prefix(6)), id: \.vehicleID) { row in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(row.isSimulation ? Color.blue.opacity(0.85) : Color.white.opacity(0.75))
                                .frame(width: 7, height: 7)
                            Text(row.shortID)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.textPrimary)
                            Spacer(minLength: 0)
                            Text(batteryText(for: row.batteryPercent))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.orange.opacity(0.95))
                        }
                    }
                }
            }
        }
        .dashboardPanelStyle(minHeight: 180, background: theme.backgroundRaised)
    }

    private var dashboardAlertsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Active Alerts")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
                Text("Recent \(alertRows.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
            }
            if alertRows.isEmpty {
                Text("No high-signal alerts detected in current logs.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(alertRows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(row.severity.color)
                                .frame(width: 7, height: 7)
                                .padding(.top, 4)
                            Text(row.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .dashboardPanelStyle(minHeight: 220, background: theme.backgroundRaised)
    }

    private func dashboardStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func readinessCounter(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(theme.textSecondary)
            Text("\(value)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func batteryText(for value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(round(value)))%"
    }

    private func utilizationColor(for label: String) -> Color {
        switch label {
        case "Ready":
            return .green.opacity(0.9)
        case "At risk":
            return .yellow.opacity(0.9)
        case "Low battery":
            return .orange.opacity(0.95)
        default:
            return .gray.opacity(0.85)
        }
    }
}

private struct DashboardVehicleReadinessRow {
    let vehicleID: String
    let shortID: String
    let isSimulation: Bool
    let batteryPercent: Double?
    let issueSummary: String
    let isReady: Bool
}

private struct DashboardBreakdownRow: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
}

private struct DashboardAlertRow {
    let severity: DashboardAlertSeverity
    let text: String
}

private enum DashboardAlertSeverity {
    case medium
    case high
    case critical

    var color: Color {
        switch self {
        case .medium: return .yellow.opacity(0.9)
        case .high: return .orange.opacity(0.95)
        case .critical: return .red.opacity(0.95)
        }
    }
}

private extension View {
    func dashboardPanelStyle(minHeight: CGFloat, background: Color) -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private extension Array {
    func count(where predicate: (Element) -> Bool) -> Int {
        filter(predicate).count
    }
}

private struct LogsView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @State private var selectedVehicleIDs: Set<String> = []
    @State private var vehiclesAccordionExpanded = true
    @State private var levelsAccordionExpanded = false
    @State private var sessionsAccordionExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filters")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        DisclosureGroup(
                            isExpanded: $vehiclesAccordionExpanded,
                            content: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(fleetLink.vehicleLogIDs(), id: \.self) { vehicleID in
                                        Toggle(
                                            fleetLink.displayShortID(forVehicleID: vehicleID),
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
                                        .foregroundStyle(theme.textSecondary)
                                    }
                                }
                                .padding(.top, 6)
                            },
                            label: {
                                Text("Vehicles")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                            }
                        )

                        DisclosureGroup(
                            isExpanded: $levelsAccordionExpanded,
                            content: {
                                Text("Coming soon")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textSecondary)
                                    .padding(.top, 6)
                            },
                            label: {
                                Text("Levels")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                            }
                        )

                        DisclosureGroup(
                            isExpanded: $sessionsAccordionExpanded,
                            content: {
                                Text("Coming soon")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textSecondary)
                                    .padding(.top, 6)
                            },
                            label: {
                                Text("Sessions")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
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
            .background(theme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Logs")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
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
                                .foregroundStyle(theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.backgroundRaised)
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
