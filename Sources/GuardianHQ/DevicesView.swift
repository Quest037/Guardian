import SwiftUI

/// Fleet vehicles — MAVLink / MAVSDK configuration is under Settings.
struct DevicesView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var generalSettings: GeneralSettingsStore
    @EnvironmentObject private var toastCenter: ToastCenter

    @State private var isAddSimSidebarPresented = false
    @State private var sidebarSpawnPlatform: SimulationPlatform = .ardupilot
    @State private var infoSheetVehicleTitle: String?
    @State private var infoSheetVehicleID: String?

    private let bgMain = Color(red: 0.07, green: 0.07, blue: 0.08)

    var body: some View {
        Group {
            if fleetLink.isRunning {
                devicesContent
            } else {
                serverOfflineMessage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgMain)
        .onChange(of: sitl.lastError) { newValue in
            if let newValue {
                toastCenter.show(newValue, style: .error, duration: 4.5)
            }
        }
        .sheet(isPresented: infoSheetIsPresented) {
            VehicleTelemetryInfoSheet(
                title: infoSheetVehicleTitle ?? "Vehicle telemetry",
                vehicleID: infoSheetVehicleID,
                hub: infoSheetVehicleID.flatMap(fleetLink.hubTelemetry(forVehicleID:)) ?? fleetLink.hubTelemetry
            )
        }
    }

    private var infoSheetIsPresented: Binding<Bool> {
        Binding(
            get: { infoSheetVehicleTitle != nil },
            set: { showing in
                if !showing {
                    infoSheetVehicleTitle = nil
                    infoSheetVehicleID = nil
                }
            }
        )
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

    /// Same layout as `serverOfflineMessage` (icon 44pt medium gray, title 20pt semibold white, subtitle 14pt gray, max 480pt, padding 32, centered in the pane).
    private var noVehiclesEmptyState: some View {
        centeredEmptyStateBlock(
            systemImage: "car.side",
            title: "No Vehicles",
            subtitle: {
                Text("No vehicles currently linked")
            }
        )
    }

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

    private var devicesHeaderRow: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Vehicles")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            if fleetLink.isSimulateEnabled {
                Button("Add Sim") {
                    sidebarSpawnPlatform = generalSettings.defaultSimulationPlatform
                    withAnimation(addSimSidebarSpring) {
                        isAddSimSidebarPresented = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.regular)
            }
            telemetryHeaderIndicator
        }
    }

    private var addSimSidebarSpring: Animation {
        .spring(response: 0.36, dampingFraction: 0.88)
    }

    private var devicesContent: some View {
        ZStack(alignment: .trailing) {
            Group {
                if fleetGridEntries.isEmpty {
                    VStack(spacing: 0) {
                        devicesHeaderRow
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                        noVehiclesEmptyState
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            devicesHeaderRow
                            vehicleFleetSection
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // Separate `if` branches so each view’s transition runs (one ZStack would animate as a single insert).
            if isAddSimSidebarPresented {
                Color.black.opacity(0.45)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(addSimSidebarSpring) {
                            isAddSimSidebarPresented = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
            if isAddSimSidebarPresented {
                addSimulationSidebarPanel
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }
        }
    }

    private var addSimulationSidebarPanel: some View {
        SimulationVehiclePickerSidebar(
            platform: $sidebarSpawnPlatform,
            onSelect: { preset in
                sitl.spawn(preset: preset, platform: sidebarSpawnPlatform)
                withAnimation(addSimSidebarSpring) {
                    isAddSimSidebarPresented = false
                }
            },
            onClose: {
                withAnimation(addSimSidebarSpring) {
                    isAddSimSidebarPresented = false
                }
            }
        )
        .frame(width: 352)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private var vehicleFleetSection: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 228, maximum: 360), spacing: 14, alignment: .top)],
            spacing: 14
        ) {
            ForEach(fleetGridEntries, id: \.id) { entry in
                switch entry {
                case .live(let snapshot):
                    FleetVehicleGridCard(
                        title: "Live vehicle",
                        domain: .aerial,
                        autopilotStack: snapshot.autopilotStack,
                        vehicleId: primaryLiveVehicleIDDisplayText,
                        systemId: nil,
                        sessionUUID: nil,
                        simulationImageBasenames: nil,
                        isSimulation: false,
                        liveTelemetry: snapshot,
                        sitlAlive: nil,
                        sitlExitCode: nil,
                        onInfo: {
                            infoSheetVehicleTitle = "Live vehicle telemetry"
                            infoSheetVehicleID = primaryLiveVehicleID
                        },
                        onStopSim: nil,
                        onDismissSim: nil
                    )
                case .sim(let inst):
                    let systemID = inst.stackInstanceIndex + 1
                    let resolvedVehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
                    FleetVehicleGridCard(
                        title: inst.preset.displayName,
                        domain: inst.preset.vehicleDomain,
                        autopilotStack: FleetAutopilotStack(simulationPlatform: inst.platform),
                        vehicleId: String(systemID),
                        systemId: systemID,
                        sessionUUID: inst.id.uuidString,
                        simulationImageBasenames: inst.preset.simulationDeviceImageBasenames,
                        isSimulation: true,
                        liveTelemetry: nil,
                        sitlAlive: inst.isAlive,
                        sitlExitCode: inst.lastExitCode,
                        onInfo: {
                            infoSheetVehicleTitle = "\(inst.preset.displayName) telemetry"
                            infoSheetVehicleID = resolvedVehicleID
                        },
                        onStopSim: { sitl.stop(id: inst.id) },
                        onDismissSim: { sitl.dismiss(id: inst.id) }
                    )
                }
            }
        }
    }

    private enum FleetGridEntry {
        case live(FleetTelemetrySnapshot)
        case sim(SitlRunningInstance)

        var id: String {
            switch self {
            case .live: return "fleet-live-primary"
            case .sim(let i): return i.id.uuidString
            }
        }
    }

    private var fleetGridEntries: [FleetGridEntry] {
        var rows: [FleetGridEntry] = []
        // First MAVLink system the bridge binds to (hardware or any SITL stack). Sim rows track local processes.
        if fleetLink.bridgePhase == .live {
            rows.append(.live(fleetLink.telemetry ?? .empty))
        }
        for inst in sitl.instances {
            rows.append(.sim(inst))
        }
        return rows
    }

    private var primaryLiveVehicleID: String? {
        fleetLink.hubTelemetryByVehicleID.keys.sorted().first
    }

    private var primaryLiveVehicleIDDisplayText: String? {
        guard let key = primaryLiveVehicleID else { return nil }
        if key.hasPrefix("sysid:") {
            return String(key.dropFirst("sysid:".count))
        }
        return key
    }

    /// Dot + two-word status on the same row as the "Vehicles" title (no subtitle).
    private var telemetryHeaderIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(bridgeStatusColor)
                .frame(width: 9, height: 9)
            Text(bridgeHeaderTitleTwoWords)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bridgeHeaderTitleTwoWords), \(bridgeStatusAccessibilityHint)")
    }

    private var bridgeStatusColor: Color {
        switch fleetLink.bridgePhase {
        case .live:
            return .green
        case .awaitingVehicle:
            return .yellow
        case .connecting, .inactive:
            break
        }
        if fleetLink.isRunning { return .orange }
        return .gray
    }

    private var bridgeHeaderTitleTwoWords: String {
        switch fleetLink.bridgePhase {
        case .live:
            return "Live telemetry"
        case .awaitingVehicle:
            return "Awaiting vehicles"
        case .connecting, .inactive:
            break
        }
        if fleetLink.isRunning { return "Connecting telemetry" }
        return "Link offline"
    }

    private var bridgeStatusAccessibilityHint: String {
        switch fleetLink.bridgePhase {
        case .live:
            return "Receiving updates from the first aircraft on this link."
        case .awaitingVehicle:
            return "MAVSDK is listening for a MAVLink system."
        case .connecting, .inactive:
            break
        }
        if fleetLink.isRunning {
            return "Bridge is starting."
        }
        return "Server off."
    }

}

private struct VehicleTelemetryInfoSheet: View {
    let title: String
    let vehicleID: String?
    let hub: FleetHubVehicleTelemetry?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            if let vehicleID {
                Text("Vehicle stream: \(vehicleID)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.gray)
            }
            Divider().opacity(0.2)
            ScrollView {
                if let hub {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(telemetryRows(from: hub), id: \.0) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(row.0)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.gray)
                                    .frame(width: 240, alignment: .leading)
                                Text(row.1)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.95))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                } else {
                    Text("No telemetry available for this vehicle stream.")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
    }

    private func telemetryRows(from hub: FleetHubVehicleTelemetry) -> [(String, String)] {
        Mirror(reflecting: hub).children.compactMap { child in
            guard let label = child.label else { return nil }
            let value = String(describing: child.value)
            if value == "nil" { return nil }
            return (label, value)
        }
        .sorted { $0.0 < $1.0 }
    }
}

#Preview("Offline") {
    DevicesView(fleetLink: FleetLinkService(), sitl: SitlService(), generalSettings: GeneralSettingsStore())
        .environmentObject(ToastCenter())
        .frame(width: 720, height: 480)
}
