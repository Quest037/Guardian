import SwiftUI

/// Fleet vehicles — MAVLink / MAVSDK configuration is under Settings.
struct DevicesView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var generalSettings: GeneralSettingsStore
    @ObservedObject var missionControlStore: MissionControlStore
    @EnvironmentObject private var toastCenter: ToastCenter

    @State private var isAddSimSidebarPresented = false
    @State private var sidebarSpawnPlatform: SimulationPlatform = .ardupilot
    @State private var infoSheetVehicleTitle: String?
    @State private var infoSheetVehicleID: String?
    @State private var infoSheetSitlSessionUUID: String?
    @State private var pendingSimStop: PendingSimStop?
    @State private var testArmSheetContext: VehicleTestArmSheetContext?

    private let bgMain = Color(red: 0.07, green: 0.07, blue: 0.08)

    var body: some View {
        devicesContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgMain)
        .confirmationDialog(
            "Stop simulator?",
            isPresented: Binding(
                get: { pendingSimStop != nil },
                set: { if !$0 { pendingSimStop = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Stop", role: .destructive) {
                if let id = pendingSimStop?.id {
                    sitl.stop(id: id)
                }
                pendingSimStop = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSimStop = nil
            }
        } message: {
            if let label = pendingSimStop?.vehicleLabel {
                Text("Stop “\(label)”? This shuts down the simulator and ends telemetry for that vehicle.")
            }
        }
        .onChange(of: sitl.lastError) { newValue in
            if let newValue {
                toastCenter.show(newValue, style: .error, duration: 4.5)
            }
        }
        .sheet(isPresented: infoSheetIsPresented) {
            VehicleTelemetryInfoSheet(
                title: infoSheetVehicleTitle ?? "Vehicle telemetry",
                vehicleID: infoSheetVehicleID,
                sitlSessionUUID: infoSheetSitlSessionUUID,
                model: infoSheetVehicleID.flatMap(fleetLink.vehicleModel(forVehicleID:)),
                hub: infoSheetVehicleID.flatMap(fleetLink.hubTelemetry(forVehicleID:)) ?? fleetLink.hubTelemetry
            )
        }
        .sheet(item: $testArmSheetContext) { ctx in
            VehicleTestArmSheet(
                vehicleTitle: ctx.title,
                vehicleID: ctx.vehicleID,
                fleetLink: fleetLink,
                sitl: sitl,
                controlStore: missionControlStore
            )
        }
    }

    private struct VehicleTestArmSheetContext: Identifiable {
        var id: String { vehicleID }
        let vehicleID: String
        let title: String
    }

    private func fleetVehicleLiveMissionLockReason(vehicleID: String) -> String? {
        missionControlStore.isVehicleStreamUsedInLiveMission(vehicleID: vehicleID, fleetLink: fleetLink, sitl: sitl)
            ? "Vehicle is assigned to a live Mission Control run."
            : nil
    }

    /// Disables Vehicles **Test arm** using the same lifecycle gate as Mission Control arm preflight (`.live` = green on fleet card).
    private func fleetVehicleTestArmDisabledReason(vehicleID: String) -> String? {
        if let lock = fleetVehicleLiveMissionLockReason(vehicleID: vehicleID) { return lock }
        guard let model = fleetLink.vehicleModel(forVehicleID: vehicleID) else {
            return MissionControlStore.armProbeNoVehicleDetail
        }
        guard model.collections.lifecycleStatus.stage == .live else {
            return MissionControlStore.armProbeNotConnectedDetail
        }
        return nil
    }

    private var infoSheetIsPresented: Binding<Bool> {
        Binding(
            get: { infoSheetVehicleTitle != nil },
            set: { showing in
                if !showing {
                    infoSheetVehicleTitle = nil
                    infoSheetVehicleID = nil
                    infoSheetSitlSessionUUID = nil
                }
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
                sitl.spawn(
                    preset: preset,
                    platform: sidebarSpawnPlatform,
                    defaults: generalSettings.simSpawnDefaults
                )
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
                case .live(let vehicleID, let model):
                    let snapshot = model.collections.telemetrySnapshot
                    let testArmBlock = fleetVehicleTestArmDisabledReason(vehicleID: vehicleID)
                    FleetVehicleGridCard(
                        autopilotStack: snapshot?.autopilotStack ?? .unknown,
                        simulationImageBasenames: nil,
                        isSimulation: false,
                        vehicleModel: model,
                        sitlAlive: nil,
                        sitlExitCode: nil,
                        onInfo: {
                            infoSheetVehicleTitle = "Live vehicle telemetry"
                            infoSheetVehicleID = vehicleID
                            infoSheetSitlSessionUUID = nil
                        },
                        onTestArm: {
                            testArmSheetContext = VehicleTestArmSheetContext(
                                vehicleID: vehicleID,
                                title: "Live vehicle"
                            )
                        },
                        testArmDisabledReason: testArmBlock,
                        onStopSim: nil,
                        stopSimDisabledReason: nil,
                        onDismissSim: nil
                    )
                case .sim(let inst):
                    let systemID = inst.stackInstanceIndex + 1
                    let resolvedVehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
                    let model = fleetLink.vehicleModel(forVehicleID: resolvedVehicleID)
                    let status = statusForSim(
                        resolvedVehicleID: resolvedVehicleID,
                        systemID: systemID,
                        instance: inst,
                        model: model
                    )
                    let testArmBlock = fleetVehicleTestArmDisabledReason(vehicleID: resolvedVehicleID)
                    FleetVehicleGridCard(
                        autopilotStack: FleetAutopilotStack(simulationPlatform: inst.platform),
                        simulationImageBasenames: inst.preset.simulationDeviceImageBasenames,
                        isSimulation: true,
                        vehicleModel: {
                            if var existing = model {
                                existing.collections.lifecycleStatus = status
                                return existing
                            }
                            return FleetVehicleModel(
                                vehicleID: resolvedVehicleID,
                                systemID: systemID,
                                initialStatus: status
                            )
                        }(),
                        sitlAlive: inst.isAlive,
                        sitlExitCode: inst.lastExitCode,
                        onInfo: {
                            infoSheetVehicleTitle = "\(inst.preset.displayName) telemetry"
                            infoSheetVehicleID = resolvedVehicleID
                            infoSheetSitlSessionUUID = inst.id.uuidString
                        },
                        onTestArm: {
                            testArmSheetContext = VehicleTestArmSheetContext(
                                vehicleID: resolvedVehicleID,
                                title: "\(inst.preset.displayName) (sim)"
                            )
                        },
                        testArmDisabledReason: testArmBlock,
                        onStopSim: {
                            pendingSimStop = PendingSimStop(id: inst.id, vehicleLabel: inst.preset.displayName)
                        },
                        stopSimDisabledReason: fleetVehicleLiveMissionLockReason(vehicleID: resolvedVehicleID),
                        onDismissSim: { sitl.dismiss(id: inst.id) }
                    )
                }
            }
        }
    }

    private struct PendingSimStop {
        let id: UUID
        let vehicleLabel: String
    }

    private enum FleetGridEntry {
        case live(vehicleID: String, model: FleetVehicleModel)
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
        let simVehicleIDs = Set(
            sitl.instances.map { "sysid:\($0.stackInstanceIndex + 1)" }
        )
        let liveHardwareVehicleIDs = fleetLink.vehicleModelsByVehicleID.keys
            .filter { !simVehicleIDs.contains($0) }
            .sorted()
        if let firstHardwareVehicleID = liveHardwareVehicleIDs.first,
           let model = fleetLink.vehicleModel(forVehicleID: firstHardwareVehicleID),
           model.collections.telemetrySnapshot != nil {
            rows.append(.live(vehicleID: firstHardwareVehicleID, model: model))
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
        return .orange
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
        return "Connecting telemetry"
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
        return "Vehicle sessions are starting."
    }

    private func statusForSim(
        resolvedVehicleID: String,
        systemID: Int,
        instance: SitlRunningInstance,
        model: FleetVehicleModel?
    ) -> VehicleLifecycleStatus {
        if let code = instance.lastExitCode, !instance.isAlive {
            return VehicleLifecycleStatus(
                stage: .failed,
                sentenceOverride: "The simulator exited with code \(code), so telemetry is unavailable until this vehicle is restarted."
            )
        }
        if let explicit = model?.collections.lifecycleStatus ?? fleetLink.vehicleStatus(forVehicleID: resolvedVehicleID) {
            return explicit
        }
        if model?.data.telemetry != nil {
            return VehicleLifecycleStatus(stage: .live)
        }
        if instance.isAlive {
            return VehicleLifecycleStatus(stage: .connecting)
        }
        return VehicleLifecycleStatus(stage: .stopped)
    }

}

#Preview("Offline") {
    DevicesView(
        fleetLink: FleetLinkService(),
        sitl: SitlService(),
        generalSettings: GeneralSettingsStore(),
        missionControlStore: MissionControlStore()
    )
    .environmentObject(ToastCenter())
    .frame(width: 720, height: 480)
}
