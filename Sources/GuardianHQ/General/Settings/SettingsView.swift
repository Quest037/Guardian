import SwiftUI

struct SettingsView: View {
    @Binding var selectedPane: SettingsPane
    @ObservedObject var generalSettings: GeneralSettingsStore
    @ObservedObject var manualControlSettings: ManualControlSettingsStore
    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }
    @State private var isLocationPickerPresented = false
    @State private var draftSimLatitudeDeg = 0.0
    @State private var draftSimLongitudeDeg = 0.0
    @StateObject private var simSpawnMapModel = GuardianMapModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker("Section", selection: $selectedPane) {
                    ForEach(SettingsPane.allCases) { pane in
                        Text(pane.rawValue).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundRaised)

            Group {
                switch selectedPane {
                case .general:
                    generalPane
                case .missions:
                    missionsPane
                case .sims:
                    simsPane
                case .controls:
                    controlsPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.backgroundBase)
        }
        .sheet(isPresented: $isLocationPickerPresented) {
            simLocationPickerSheet
        }
    }

    private var generalPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("General")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.bottom, 16)

                settingsRow(
                    title: "Callsign",
                    description: "Your operator name or call sign. Used where the app identifies the local operator (e.g. Mission Control and logs)."
                ) {
                    TextField("Callsign", text: $generalSettings.callsign)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280, alignment: .trailing)
                }

                rowDivider

                settingsRow(
                    title: "Appearance",
                    description: "Default app theme. System follows your macOS appearance."
                ) {
                    Picker("Appearance", selection: $generalSettings.appearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(minWidth: 280, alignment: .trailing)
                }

                rowDivider

                settingsRow(
                    title: "Main sidebar",
                    description: "Navigation rail when you open the app: collapsed shows icons only; expanded shows section names. You can still toggle the rail with the control at the top of the sidebar."
                ) {
                    Picker("Main sidebar", selection: $generalSettings.mainSidebarLaunchMode) {
                        ForEach(MainSidebarLaunchMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(minWidth: 220, alignment: .trailing)
                }

                rowDivider

                settingsRow(
                    title: "Default map view",
                    description: "Starting basemap for Missions (route editor) and Mission Control live overview. You can still switch per map."
                ) {
                    Picker("Default map view", selection: $generalSettings.defaultMapTileStyle) {
                        Text("Standard").tag(MapTileStyle.standard)
                        Text("Satellite").tag(MapTileStyle.satellite)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(minWidth: 220, alignment: .trailing)
                }

                rowDivider

                settingsRow(
                    title: "Logs",
                    description: "How many log lines stay visible in Logs. Long keeps more history in memory."
                ) {
                    Picker("Log length", selection: $generalSettings.logRetentionProfile) {
                        ForEach(LogRetentionProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(minWidth: 280, alignment: .trailing)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundBase)
    }

    private var missionsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Missions")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.bottom, 16)

                settingsRow(
                    title: "Mission Control postpone cap",
                    description:
                        "Maximum duration for one Alter step (Sooner / Later) while a run is active: scheduled mission start, per-task MAVLink start deferrals (including between-cycle restarts). Larger changes require multiple steps."
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { Double(generalSettings.missionControlPostponeStepCapSeconds) },
                                set: { generalSettings.missionControlPostponeStepCapSeconds = Int($0.rounded()) }
                            ),
                            in: Double(GeneralSettingsStore.minMissionPostponeStepCapSeconds)
                                ... Double(GeneralSettingsStore.maxMissionPostponeStepCapSeconds),
                            step: 60
                        )
                        .frame(minWidth: 280)
                        Text(MissionDelayPolicy.humanReadableDuration(
                            seconds: TimeInterval(generalSettings.missionControlPostponeStepCapSeconds)
                        ))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundBase)
    }

    private var simsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("SIMs")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.bottom, 16)

                settingsRow(
                    title: "Default simulation platform",
                    description: "Default flight controller stack for simulated vehicles."
                ) {
                    Picker("Default simulation platform", selection: $generalSettings.defaultSimulationPlatform) {
                        ForEach(SimulationPlatform.allCases) { platform in
                            Text(platform.displayName).tag(platform)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(minWidth: 320, alignment: .trailing)
                }

                rowDivider

                settingsRow(
                    title: "Default SIM spawn location",
                    description: "Used for newly spawned SITL vehicles."
                ) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Latitude")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)
                            TextField(
                                "Latitude",
                                value: $generalSettings.simSpawnDefaults.latitudeDeg,
                                format: .number.precision(.fractionLength(6))
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Longitude")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)
                            TextField(
                                "Longitude",
                                value: $generalSettings.simSpawnDefaults.longitudeDeg,
                                format: .number.precision(.fractionLength(6))
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Altitude")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)
                            TextField("Altitude", value: .constant(0), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 72)
                                .disabled(true)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\u{00a0}")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.clear)
                            Button("Map") {
                                draftSimLatitudeDeg = generalSettings.simSpawnDefaults.latitudeDeg
                                draftSimLongitudeDeg = generalSettings.simSpawnDefaults.longitudeDeg
                                simSpawnMapModel.mapStyle = generalSettings.defaultMapTileStyle
                                simSpawnMapModel.recenter()
                                isLocationPickerPresented = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                    .frame(minWidth: 320, alignment: .trailing)
                }

                rowDivider

                settingsRow(
                    title: "Default SIM heading",
                    description: "Initial heading in degrees (0-360)."
                ) {
                    TextField(
                        "Heading",
                        value: $generalSettings.simSpawnDefaults.headingDeg,
                        format: .number.precision(.fractionLength(1))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                }

                rowDivider

                settingsRow(
                    title: "Default SIM battery",
                    description: "Seed values before first telemetry sample arrives."
                ) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Percent")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)
                            TextField(
                                "Percent",
                                value: $generalSettings.simSpawnDefaults.batteryPercent,
                                format: .number.precision(.fractionLength(0))
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 82)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Voltage (V)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)
                            TextField(
                                "Voltage",
                                value: $generalSettings.simSpawnDefaults.batteryVoltageV,
                                format: .number.precision(.fractionLength(2))
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 96)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current (A)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)
                            TextField(
                                "Current",
                                value: $generalSettings.simSpawnDefaults.batteryCurrentA,
                                format: .number.precision(.fractionLength(2))
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 96)
                        }
                    }
                }

                rowDivider

                settingsRow(
                    title: "Default SIM battery drain rate",
                    description: "Fallback when LiveDrive / Mission Control Running enable SIM drain."
                ) {
                    Picker("Default SIM battery drain rate", selection: $generalSettings.defaultSimBatteryDrainRate) {
                        ForEach(SimBatteryDrainRate.allCases) { rate in
                            Text(rate.displayName).tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(minWidth: 220, alignment: .trailing)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundBase)
    }

    private var rowDivider: some View {
        Divider()
            .opacity(0.22)
            .padding(.vertical, 14)
    }

    private var controlsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Controls")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 12)
                    Button("Reset Defaults") {
                        manualControlSettings.resetDefaults()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 16)

                Text("Live Drive keyboard command bindings (single key or named key: Space / Return / Delete).")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.bottom, 12)

                ForEach(ManualControlAction.allCases) { action in
                    settingsRow(
                        title: action.title,
                        description: action.behaviorHint.isEmpty ? " " : action.behaviorHint
                    ) {
                        TextField(
                            "Key",
                            text: Binding(
                                get: { manualControlSettings.key(for: action) },
                                set: { manualControlSettings.setKey($0, for: action) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96, alignment: .trailing)
                    }
                    if action != ManualControlAction.allCases.last {
                        rowDivider
                    }
                }

                rowDivider

                Text("Per-vehicle-class keyboard bump tuning")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.top, 2)
                    .padding(.bottom, 10)

                ForEach([UniversalVehicleClass.uav, .ugv, .usv, .uuv], id: \.rawValue) { vehicleClass in
                    let profile = manualControlSettings.stepProfile(for: vehicleClass)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(vehicleClass.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        HStack(spacing: 10) {
                            controlNumberField(
                                title: "Fwd/Back (m)",
                                value: Binding(
                                    get: { profile.moveForwardBackwardM },
                                    set: { manualControlSettings.setMoveForwardBackward($0, for: vehicleClass) }
                                )
                            )
                            controlNumberField(
                                title: "Left/Right (m)",
                                value: Binding(
                                    get: { profile.moveLeftRightM },
                                    set: { manualControlSettings.setMoveLeftRight($0, for: vehicleClass) }
                                )
                            )
                            controlNumberField(
                                title: "Yaw (deg)",
                                value: Binding(
                                    get: { profile.yawDeg },
                                    set: { manualControlSettings.setYaw($0, for: vehicleClass) }
                                )
                            )
                            controlNumberField(
                                title: "Vertical (m)",
                                value: Binding(
                                    get: { profile.verticalM },
                                    set: { manualControlSettings.setVertical($0, for: vehicleClass) }
                                )
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                    if vehicleClass != .uuv {
                        rowDivider
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundBase)
    }

    private func settingsRow<Trailing: View>(
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func controlNumberField(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            TextField("", value: value, format: .number.precision(.fractionLength(3)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 118)
        }
    }

    private var simLocationPickerSheet: some View {
        Modal(
            title: "Pick SIM Spawn Location",
            headerActions: {
                HStack(spacing: 8) {
                    Button("Cancel") {
                        isLocationPickerPresented = false
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        generalSettings.simSpawnDefaults.latitudeDeg = draftSimLatitudeDeg
                        generalSettings.simSpawnDefaults.longitudeDeg = draftSimLongitudeDeg
                        isLocationPickerPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        String(
                            format: "Selected lat/lng: %.6f, %.6f",
                            draftSimLatitudeDeg,
                            draftSimLongitudeDeg
                        )
                    )
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))

                    GuardianMapView(
                        model: simSpawnMapModel,
                        onMapClick: { lat, lon in
                            draftSimLatitudeDeg = lat
                            draftSimLongitudeDeg = lon
                        },
                        onVehicleMarkerMoved: { _, lat, lon in
                            draftSimLatitudeDeg = lat
                            draftSimLongitudeDeg = lon
                        }
                    )
                    .task(id: simSpawnDraftSignature) {
                        var geo = simSpawnMapModel.routeGeometry
                        geo.home = simSpawnDraftHome
                        simSpawnMapModel.routeGeometry = geo
                        simSpawnMapModel.vehicleMarkers = [simSpawnDraftMarker]
                    }
                    .frame(minHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        )
        .frame(minWidth: 860, minHeight: 560)
    }

    /// Equatable signature so `.task(id:)` only re-pushes home + marker into
    /// the shared map model when the draft coordinate actually changes.
    private var simSpawnDraftSignature: SimSpawnDraftSignature {
        SimSpawnDraftSignature(lat: draftSimLatitudeDeg, lon: draftSimLongitudeDeg)
    }

    private var simSpawnDraftHome: RouteHome {
        RouteHome(
            coord: RouteCoordinate(lat: draftSimLatitudeDeg, lon: draftSimLongitudeDeg),
            altitude: RouteAltitude(value: 0, unit: .m, reference: .agl),
            heading: 0,
            radiusMeters: 3,
            dockAllowed: true,
            fallbackOnly: false
        )
    }

    private var simSpawnDraftMarker: MapVehicleMarker {
        MapVehicleMarker(
            id: "sim-spawn-default",
            lat: draftSimLatitudeDeg,
            lon: draftSimLongitudeDeg,
            label: "SIM Default",
            colorHex: "#3b82f6",
            selected: true,
            draggable: true
        )
    }
}

private struct SimSpawnDraftSignature: Equatable {
    let lat: Double
    let lon: Double
}
