import SwiftUI

/// Fleet vehicles — MAVLink / MAVSDK configuration is under Settings.
struct DevicesView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var generalSettings: GeneralSettingsStore
    @EnvironmentObject private var toastCenter: ToastCenter

    @State private var isAddSimSidebarPresented = false
    @State private var sidebarSpawnPlatform: SimulationPlatform = .ardupilot

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
                        simulationImageBasenames: nil,
                        isSimulation: false,
                        liveTelemetry: snapshot,
                        sitlAlive: nil,
                        sitlExitCode: nil,
                        onStopSim: nil,
                        onDismissSim: nil
                    )
                case .sim(let inst):
                    FleetVehicleGridCard(
                        title: inst.preset.displayName,
                        domain: inst.preset.vehicleDomain,
                        autopilotStack: FleetAutopilotStack(simulationPlatform: inst.platform),
                        simulationImageBasenames: inst.preset.simulationDeviceImageBasenames,
                        isSimulation: true,
                        liveTelemetry: nil,
                        sitlAlive: inst.isAlive,
                        sitlExitCode: inst.lastExitCode,
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

#Preview("Offline") {
    DevicesView(fleetLink: FleetLinkService(), sitl: SitlService(), generalSettings: GeneralSettingsStore())
        .environmentObject(ToastCenter())
        .frame(width: 720, height: 480)
}
