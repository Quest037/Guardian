import SwiftUI

/// Fleet vehicles — MAVLink / MAVSDK configuration is under Settings.
struct VehiclesView: View {
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var generalSettings: GeneralSettingsStore
    @ObservedObject var missionControlStore: MissionControlStore
    @ObservedObject var liveDriveStore: LiveDriveStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @EnvironmentObject private var appDrawer: AppDrawer
    @Environment(\.colorScheme) private var colorScheme

    @State private var sidebarSpawnPlatform: SimulationPlatform = .ardupilot
    @State private var pendingSimStop: PendingSimStop?
    @State private var calibrationSheetContext: VehicleCalibrationSheetContext?
    /// Suppresses duplicate `sitl.lastError` surfaces so `ToastCenter` is not reset on every identical republish.
    @State private var lastSitlErrorSurfacedForToast: String?

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var pendingSimStopConfirmMessage: String {
        guard let pending = pendingSimStop else {
            return "This shuts down the simulator and ends telemetry for that vehicle."
        }
        return "Stop “\(pending.vehicleLabel)”? This shuts down the simulator and ends telemetry for that vehicle."
    }

    var body: some View {
        ZStack {
            devicesContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
                .guardianConfirmOverlay(
                    isPresented: Binding(
                        get: { pendingSimStop != nil },
                        set: { if !$0 { pendingSimStop = nil } }
                    )
                ) {
                    GuardianConfirmDanger(
                        title: "Stop simulator?",
                        message: pendingSimStopConfirmMessage,
                        cancelTitle: "Cancel",
                        confirmTitle: "Stop",
                        onCancel: { pendingSimStop = nil },
                        onConfirm: {
                            guard let pending = pendingSimStop else {
                                pendingSimStop = nil
                                return
                            }
                            if missionControlStore.isVehicleStreamUsedInLiveMission(
                                vehicleID: pending.vehicleID,
                                fleetLink: fleetLink,
                                sitl: sitl
                            ) {
                                toastCenter.show(
                                    "Cannot stop simulator while vehicle is assigned to a live Mission Control run.",
                                    style: .error,
                                    duration: 4
                                )
                                pendingSimStop = nil
                                return
                            }
                            teardownLiveDriveIfNeeded(vehicleID: pending.vehicleID)
                            sitl.stop(id: pending.id)
                            pendingSimStop = nil
                        }
                    )
                }
                .onChange(of: sitl.lastError) { newValue in
                    if let newValue {
                        guard newValue != lastSitlErrorSurfacedForToast else { return }
                        lastSitlErrorSurfacedForToast = newValue
                        toastCenter.show(newValue, style: .error, duration: 4.5)
                    } else {
                        lastSitlErrorSurfacedForToast = nil
                    }
                }

            if let ctx = calibrationSheetContext {
                VehicleInspectorHostOverlay(onDismiss: { calibrationSheetContext = nil }) {
                    VehicleCalibrationModal(
                        fleetLink: fleetLink,
                        controlStore: missionControlStore,
                        sitl: sitl,
                        vehicleID: ctx.vehicleID,
                        simSpawnDefaults: generalSettings.simSpawnDefaults,
                        fallback: ctx.fallback,
                        onClose: { calibrationSheetContext = nil }
                    )
                    .environmentObject(toastCenter)
                }
                .transition(.opacity)
                // In-window Vehicle Inspector above tab content (window shell adds drawer → confirm → toast above this).
                .zIndex(1)
            }
        }
        .animation(GuardianMotion.confirmPresent, value: calibrationSheetContext?.id)
    }

    private struct VehicleCalibrationSheetContext: Identifiable {
        var id: String { vehicleID }
        let vehicleID: String
        let fallback: FleetVehicleModel?
    }

    private func fleetVehicleLiveMissionLockReason(vehicleID: String) -> String? {
        missionControlStore.isVehicleStreamUsedInLiveMission(vehicleID: vehicleID, fleetLink: fleetLink, sitl: sitl)
            ? "Vehicle is assigned to a live Mission Control run."
            : nil
    }

    private func simReconnectLinkAction(vehicleID: String, lifecycleStage: VehicleLifecycleStage) -> (() -> Void)? {
        guard GuardianSitlFleetLinkReconnectPolicy.mayOfferReconnectLinkOnDevicesGrid(
            fleetLink: fleetLink,
            sitl: sitl,
            vehicleID: vehicleID,
            lifecycleStage: lifecycleStage
        ) else { return nil }
        return {
            Task { @MainActor in
                let ok = await sitl.reconnectFleetLink(
                    forGuardianVehicleID: vehicleID,
                    spawnDefaults: generalSettings.simSpawnDefaults
                )
                if ok {
                    toastCenter.show("Reconnecting telemetry link…", style: .info, duration: 2.5)
                } else {
                    let msg = sitl.lastError ?? fleetLink.lastError ?? "Reconnect failed."
                    toastCenter.show(msg, style: .error, duration: 4.5)
                }
            }
        }
    }

    private var noVehiclesEmptyState: some View {
        GuardianEmptyState(
            systemImage: AppSection.devices.systemImage,
            title: "No Vehicles",
            detail: "No vehicles currently linked.",
            primaryTitle: fleetLink.isSimulateEnabled ? "Add Sim" : nil,
            primaryAction: fleetLink.isSimulateEnabled
                ? {
                    sidebarSpawnPlatform = generalSettings.defaultSimulationPlatform
                    presentAddSimulationSidebar()
                }
                : nil
        )
    }

    /// Strip under the window title bar: live link status and Add Sim (trailing).
    private var vehiclesSubBar: some View {
        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            Spacer(minLength: 0)
            telemetryHeaderIndicator
            if fleetLink.isSimulateEnabled {
                GuardianPrimaryProminentButton(title: "Add Sim") {
                    sidebarSpawnPlatform = generalSettings.defaultSimulationPlatform
                    presentAddSimulationSidebar()
                }
            }
        }
    }

    private var addSimSidebarSpring: Animation {
        .spring(response: 0.36, dampingFraction: 0.88)
    }

    private var devicesContent: some View {
        VStack(spacing: 0) {
            vehiclesSubBar
                .padding(.horizontal, GuardianSpacing.sm)
                .padding(.vertical, GuardianSpacing.xs)
                .frame(maxWidth: .infinity)
                .background(theme.backgroundRaised)

            if fleetGridEntries.isEmpty {
                noVehiclesEmptyState
            } else {
                ScrollView {
                    vehicleFleetSection
                        .padding(GuardianSpacing.xl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func presentAddSimulationSidebar() {
        appDrawer.present(
            title: nil,
            preferredWidth: 352,
            scrimTapDismisses: true,
            animation: addSimSidebarSpring
        ) {
            SimulationVehiclePickerSidebar(
                platform: $sidebarSpawnPlatform,
                onSelect: { preset in
                    sitl.spawn(
                        preset: preset,
                        platform: sidebarSpawnPlatform,
                        defaults: generalSettings.simSpawnDefaults
                    )
                    appDrawer.dismiss(animation: addSimSidebarSpring)
                },
                onClose: {
                    appDrawer.dismiss(animation: addSimSidebarSpring)
                }
            )
        }
    }

    private var vehicleFleetSection: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 228, maximum: 360), spacing: GuardianSpacing.cardBodyInset, alignment: .top)],
            spacing: GuardianSpacing.cardBodyInset
        ) {
            ForEach(fleetGridEntries, id: \.id) { entry in
                switch entry {
                case .live(let vehicleID, let model):
                    let snapshot = model.collections.telemetrySnapshot
                    FleetVehicleGridCard(
                        autopilotStack: snapshot?.autopilotStack ?? .unknown,
                        simulationImageBasenames: nil,
                        isSimulation: false,
                        vehicleModel: model,
                        sitlAlive: nil,
                        sitlExitCode: nil,
                        onCalibration: {
                            calibrationSheetContext = VehicleCalibrationSheetContext(
                                vehicleID: vehicleID,
                                fallback: model
                            )
                        },
                        onStopSim: nil,
                        stopSimDisabledReason: nil,
                        onDismissSim: nil,
                        onCloneSim: nil,
                        onReconnectLink: nil
                    )
                case .sim(let inst):
                    let resolvedVehicleID = fleetLink.vehicleID(forSystemID: inst.mavlinkSystemID)
                        ?? inst.guardianVehicleStreamKey
                    let model = fleetLink.vehicleModel(forVehicleID: resolvedVehicleID)
                    let status = statusForSim(
                        resolvedVehicleID: resolvedVehicleID,
                        systemID: inst.mavlinkSystemID,
                        instance: inst,
                        model: model
                    )
                    let cardModel: FleetVehicleModel = {
                        if var existing = model {
                            existing.collections.lifecycleStatus = status
                            return existing
                        }
                        return FleetVehicleModel(
                            vehicleID: resolvedVehicleID,
                            systemID: inst.mavlinkSystemID,
                            vehicleType: inst.preset.fleetVehicleType,
                            initialStatus: status
                        )
                    }()
                    FleetVehicleGridCard(
                        autopilotStack: FleetAutopilotStack(simulationPlatform: inst.platform),
                        simulationImageBasenames: inst.preset.simulationDeviceImageBasenames,
                        isSimulation: true,
                        vehicleModel: cardModel,
                        sitlAlive: inst.isAlive,
                        sitlExitCode: inst.lastExitCode,
                        onCalibration: {
                            calibrationSheetContext = VehicleCalibrationSheetContext(
                                vehicleID: resolvedVehicleID,
                                fallback: cardModel
                            )
                        },
                        onStopSim: {
                            pendingSimStop = PendingSimStop(
                                id: inst.id,
                                vehicleLabel: inst.preset.displayName,
                                vehicleID: resolvedVehicleID
                            )
                        },
                        stopSimDisabledReason: fleetVehicleLiveMissionLockReason(vehicleID: resolvedVehicleID),
                        onDismissSim: { sitl.dismiss(id: inst.id) },
                        onCloneSim: {
                            sitl.spawn(
                                preset: inst.preset,
                                platform: inst.platform,
                                defaults: generalSettings.simSpawnDefaults
                            )
                            toastCenter.show("Cloning simulator…", style: .info, duration: 2)
                        },
                        onReconnectLink: simReconnectLinkAction(
                            vehicleID: resolvedVehicleID,
                            lifecycleStage: status.stage
                        )
                    )
                }
            }
        }
    }

    private struct PendingSimStop {
        let id: UUID
        let vehicleLabel: String
        let vehicleID: String
    }

    private func teardownLiveDriveIfNeeded(vehicleID: String) {
        let vehicleIsInLiveDrive = liveDriveStore.activeVehicleID == vehicleID
            || liveDriveStore.activeControlledVehicleID == vehicleID
        guard vehicleIsInLiveDrive else { return }

        Task { @MainActor in
            await fleetLink.stopManualControlStream(vehicleID: vehicleID)
            fleetLink.clearLiveDriveControlSessionVehicleIfMatches(vehicleID: vehicleID)
            missionControlStore.clearOperatorLiveDriveHandoffForClearedControlSessionVehicle(
                vehicleID: vehicleID,
                fleetLink: fleetLink,
                sitl: sitl
            )
            fleetLink.setCommandAuthorityGate(vehicleID: vehicleID, minimumCategory: .missionControl)
        }
        if liveDriveStore.activeControlledVehicleID == vehicleID {
            liveDriveStore.discardActiveSessionRecording()
        }
        if liveDriveStore.activeVehicleID == vehicleID {
            liveDriveStore.selectVehicle(nil)
        }
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
        let simVehicleIDs = Set(sitl.instances.map(\.guardianVehicleStreamKey))
        let liveHardwareSessionIDs = fleetLink.activeVehicleSessionIDs()
            .filter { !simVehicleIDs.contains($0) }
        if let firstHardwareVehicleID = liveHardwareSessionIDs.first,
           let model = fleetLink.vehicleModel(forVehicleID: firstHardwareVehicleID),
           model.collections.telemetrySnapshot != nil {
            rows.append(.live(vehicleID: firstHardwareVehicleID, model: model))
        }
        for inst in sitl.instances {
            rows.append(.sim(inst))
        }
        return rows
    }

    /// Dot + two-word MAVLink bridge status for the sub-bar.
    private var telemetryHeaderIndicator: some View {
        HStack(spacing: GuardianSpacing.xs) {
            Circle()
                .fill(bridgeStatusColor)
                .frame(width: 9, height: 9)
            Text(bridgeHeaderTitleTwoWords)
                .font(GuardianTypography.font(.sectionHeadingSemibold))
                .foregroundStyle(theme.textPrimary)
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
    VehiclesView(
        fleetLink: FleetLinkService(),
        sitl: SitlService(),
        generalSettings: GeneralSettingsStore(),
        missionControlStore: MissionControlStore(),
        liveDriveStore: LiveDriveStore()
    )
    .environmentObject(ToastCenter())
    .environmentObject(GuardianConfirmOverlayHost())
    .frame(width: 720, height: 480)
}
