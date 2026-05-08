import SwiftUI

struct DashboardView: View {
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
