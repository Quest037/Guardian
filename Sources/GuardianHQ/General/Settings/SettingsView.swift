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

    private var settingsGroupCardConfiguration: GuardianCardConfiguration {
        GuardianCardConfiguration(
            border: .subtle,
            cornerRadius: GuardianCardLayout.cornerRadius,
            bodyPadding: GuardianCardLayout.defaultBodyPadding
        )
    }

    @ViewBuilder
    private func settingsGroupCardTitle(_ title: String) -> some View {
        Text(title)
            .font(GuardianTypography.font(.sectionHeadingSemibold))
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

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
            .padding(.horizontal, GuardianSpacing.sm)
            .padding(.vertical, GuardianSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundRaised)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.borderSubtle)
                    .frame(height: 1)
            }

            Group {
                switch selectedPane {
                case .general:
                    generalPane
                case .missions:
                    missionsPane
                case .sims:
                    simsPane
                case .liveDrive:
                    liveDrivePane
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
            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                GuardianCard(
                    configuration: settingsGroupCardConfiguration,
                    header: { settingsGroupCardTitle("Operator") },
                    body: {
                        settingsRow(
                            title: "Callsign",
                            description: "Your operator name or call sign. Used where the app identifies the local operator (e.g. Mission Control and logs)."
                        ) {
                            TextField("Callsign", text: $generalSettings.callsign)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(minWidth: 280, alignment: .trailing)
                        }
                    }
                )

                GuardianCard(
                    configuration: settingsGroupCardConfiguration,
                    header: { settingsGroupCardTitle("Appearance") },
                    body: {
                        settingsRow(
                            title: "Theme",
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
                    }
                )

                GuardianCard(
                    configuration: settingsGroupCardConfiguration,
                    header: { settingsGroupCardTitle("Navigation") },
                    body: {
                        VStack(alignment: .leading, spacing: 0) {
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
                        }
                    }
                )

                GuardianCard(
                    configuration: settingsGroupCardConfiguration,
                    header: { settingsGroupCardTitle("Logs") },
                    body: {
                        settingsRow(
                            title: "Log retention",
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
                )
            }
            .padding(GuardianSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var missionsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                GuardianCard(
                    configuration: settingsGroupCardConfiguration,
                    header: { settingsGroupCardTitle("Mission Control") },
                    body: {
                        settingsRow(
                            title: "Postpone step cap",
                            description:
                                "Maximum duration for one Alter step (Sooner / Later) while a run is active: scheduled mission start, per-task MAVLink start deferrals (including between-cycle restarts). Larger changes require multiple steps."
                        ) {
                            VStack(alignment: .trailing, spacing: GuardianSpacing.xs) {
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
                                .font(GuardianTypography.font(.inlineNoticeTitle))
                                .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                )

                GuardianCard(
                    configuration: settingsGroupCardConfiguration,
                    header: { settingsGroupCardTitle("Mission Run") },
                    body: {
                        VStack(alignment: .leading, spacing: 0) {
                            settingsRow(
                                title: "Isolate map to selected task",
                                description:
                                    "Hide all non-task mission data from the map when a task is selected."
                            ) {
                                Toggle(
                                    "",
                                    isOn: $generalSettings.missionControlLiveMapHideOtherTasksOnTaskSelect
                                )
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .frame(minWidth: 44, alignment: .trailing)
                            }
                            rowDivider
                            settingsRow(
                                title: "SIM battery drain",
                                description:
                                    "Simulate battery drain on SIMs during a mission run."
                            ) {
                                Picker("SIM battery drain", selection: $generalSettings.missionRunSimBatteryDrainRate) {
                                    ForEach(SimBatteryDrainRate.missionRunPickerCases, id: \.self) { rate in
                                        Text(rate.displayName).tag(rate)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(minWidth: 160, alignment: .trailing)
                                .accessibilityLabel("SIM battery drain while run executes")
                            }
                            rowDivider
                            settingsRow(
                                title: "Reset SIMs when run completes",
                                description:
                                    "Reset all SIM vehicles to their default start pose when a run completes."
                            ) {
                                Toggle(
                                    "",
                                    isOn: $generalSettings.missionRunResetSitlToStartPoseOnSuccessfulComplete
                                )
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .frame(minWidth: 44, alignment: .trailing)
                            }
                        }
                    }
                )
            }
            .padding(GuardianSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var simsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                GuardianCard(
                    configuration: settingsGroupCardConfiguration,
                    header: { settingsGroupCardTitle("Simulation platform") },
                    body: {
                        settingsRow(
                            title: "Default stack",
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
                    }
                )

                GuardianCard(
                    configuration: settingsGroupCardConfiguration,
                    header: { settingsGroupCardTitle("Default spawn") },
                    body: {
                        VStack(alignment: .leading, spacing: 0) {
                            settingsRow(
                                title: "Spawn location",
                                description: "Used for newly spawned SITL vehicles."
                            ) {
                                HStack(alignment: .top, spacing: GuardianSpacing.denseGutter) {
                                    VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                                        Text("Latitude")
                                            .font(GuardianTypography.font(.formFieldLabel))
                                            .foregroundStyle(theme.textSecondary)
                                        TextField(
                                            "Latitude",
                                            value: $generalSettings.simSpawnDefaults.latitudeDeg,
                                            format: .number.precision(.fractionLength(6))
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                        .frame(width: 130)
                                    }
                                    VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                                        Text("Longitude")
                                            .font(GuardianTypography.font(.formFieldLabel))
                                            .foregroundStyle(theme.textSecondary)
                                        TextField(
                                            "Longitude",
                                            value: $generalSettings.simSpawnDefaults.longitudeDeg,
                                            format: .number.precision(.fractionLength(6))
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                        .frame(width: 130)
                                    }
                                    VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                                        Text("Altitude")
                                            .font(GuardianTypography.font(.formFieldLabel))
                                            .foregroundStyle(theme.textSecondary)
                                        TextField("Altitude", value: .constant(0), format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .controlSize(.small)
                                            .frame(width: 72)
                                            .disabled(true)
                                    }
                                    VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                                        Text("\u{00a0}")
                                            .font(GuardianTypography.font(.formFieldLabel))
                                            .foregroundStyle(.clear)
                                        GuardianThemedButton(
                                            title: "Map",
                                            accent: .primary,
                                            surface: .solid,
                                            size: .small,
                                            shape: .cornered,
                                            action: {
                                                draftSimLatitudeDeg = generalSettings.simSpawnDefaults.latitudeDeg
                                                draftSimLongitudeDeg = generalSettings.simSpawnDefaults.longitudeDeg
                                                simSpawnMapModel.mapStyle = generalSettings.defaultMapTileStyle
                                                simSpawnMapModel.recenter()
                                                isLocationPickerPresented = true
                                            }
                                        )
                                    }
                                }
                                .frame(minWidth: 320, alignment: .trailing)
                            }
                            rowDivider
                            settingsRow(
                                title: "Heading",
                                description: "Initial heading in degrees (0–360)."
                            ) {
                                TextField(
                                    "Heading",
                                    value: $generalSettings.simSpawnDefaults.headingDeg,
                                    format: .number.precision(.fractionLength(1))
                                )
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(width: 96)
                            }
                            rowDivider
                            settingsRow(
                                title: "Battery percentage",
                                description:
                                    "Initial battery seed shown before the first telemetry sample arrives. Voltage and current seed the same telemetry window."
                            ) {
                                HStack(alignment: .top, spacing: GuardianSpacing.denseGutter) {
                                    VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                                        Text("Percent")
                                            .font(GuardianTypography.font(.formFieldLabel))
                                            .foregroundStyle(theme.textSecondary)
                                        TextField(
                                            "Percent",
                                            value: $generalSettings.simSpawnDefaults.batteryPercent,
                                            format: .number.precision(.fractionLength(0))
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                        .frame(width: 82)
                                    }
                                    VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                                        Text("Voltage (V)")
                                            .font(GuardianTypography.font(.formFieldLabel))
                                            .foregroundStyle(theme.textSecondary)
                                        TextField(
                                            "Voltage",
                                            value: $generalSettings.simSpawnDefaults.batteryVoltageV,
                                            format: .number.precision(.fractionLength(2))
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                        .frame(width: 96)
                                    }
                                    VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                                        Text("Current (A)")
                                            .font(GuardianTypography.font(.formFieldLabel))
                                            .foregroundStyle(theme.textSecondary)
                                        TextField(
                                            "Current",
                                            value: $generalSettings.simSpawnDefaults.batteryCurrentA,
                                            format: .number.precision(.fractionLength(2))
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                        .frame(width: 96)
                                    }
                                }
                            }
                        }
                    }
                )
            }
            .padding(GuardianSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var liveDrivePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                GuardianCard(
                    configuration: settingsGroupCardConfiguration,
                    header: { settingsGroupCardTitle("SIMs") },
                    body: {
                        settingsRow(
                            title: "SIM battery drain",
                            description: "Simulate battery drain on SIMs during Live Drive freestyle sessions."
                        ) {
                            Picker("SIM battery drain", selection: $generalSettings.liveDriveSimBatteryDrainRate) {
                                ForEach(SimBatteryDrainRate.missionRunPickerCases, id: \.self) { rate in
                                    Text(rate.displayName).tag(rate)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(minWidth: 160, alignment: .trailing)
                            .accessibilityLabel("SIM battery drain during Live Drive freestyle")
                        }
                    }
                )
            }
            .padding(GuardianSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(theme.borderSubtle)
            .frame(height: 1)
            .padding(.vertical, GuardianSpacing.sm)
    }

    private var controlsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                GuardianCard(
                    configuration: settingsGroupCardConfiguration,
                    header: {
                        HStack(spacing: GuardianSpacing.denseGutter) {
                            Text("Live Drive keyboard")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                                .foregroundStyle(theme.textPrimary)
                            Spacer(minLength: GuardianSpacing.xs)
                            GuardianThemedButton(
                                title: "Reset defaults",
                                accent: .neutral,
                                surface: .outline,
                                size: .small,
                                shape: .cornered,
                                action: { manualControlSettings.resetDefaults() }
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    },
                    body: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Bindings use a single key or a named key (Space, Return, Delete, …).")
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, GuardianSpacing.sm)

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
                                    .controlSize(.small)
                                    .frame(width: 96, alignment: .trailing)
                                }
                                if action != ManualControlAction.allCases.last {
                                    rowDivider
                                }
                            }
                        }
                    }
                )

                GuardianCard(
                    configuration: settingsGroupCardConfiguration,
                    header: { settingsGroupCardTitle("Keyboard bump distance") },
                    body: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Per vehicle class: step size for keyboard nudges in Live Drive.")
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, GuardianSpacing.denseGutter)

                            ForEach([UniversalVehicleClass.uav, .ugv, .usv, .uuv], id: \.rawValue) { vehicleClass in
                                let profile = manualControlSettings.stepProfile(for: vehicleClass)
                                VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                                    Text(vehicleClass.displayName)
                                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                                        .foregroundStyle(theme.textPrimary)
                                    HStack(spacing: GuardianSpacing.denseGutter) {
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
                                .padding(.vertical, GuardianSpacing.xsTight)
                                if vehicleClass != .uuv {
                                    rowDivider
                                }
                            }
                        }
                    }
                )
            }
            .padding(GuardianSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsRow<Trailing: View>(
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: GuardianSpacing.lg) {
            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                Text(title)
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(theme.textPrimary)
                Text(description)
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func controlNumberField(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
            Text(title)
                .font(GuardianTypography.font(.formFieldLabel))
                .foregroundStyle(theme.textSecondary)
            TextField("", value: value, format: .number.precision(.fractionLength(3)))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 118)
        }
    }

    private var simLocationPickerSheet: some View {
        Modal(
            title: "Pick SIM Spawn Location",
            headerActions: {
                HStack(spacing: GuardianSpacing.xs) {
                    GuardianThemedButton(
                        title: "Cancel",
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        action: { isLocationPickerPresented = false }
                    )
                    GuardianPrimaryProminentButton(title: "Save") {
                        generalSettings.simSpawnDefaults.latitudeDeg = draftSimLatitudeDeg
                        generalSettings.simSpawnDefaults.longitudeDeg = draftSimLongitudeDeg
                        isLocationPickerPresented = false
                    }
                }
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                    Text(
                        String(
                            format: "Selected lat/lng: %.6f, %.6f",
                            draftSimLatitudeDeg,
                            draftSimLongitudeDeg
                        )
                    )
                    .font(GuardianTypography.relativeFixed(size: 12, weight: .regular, design: .monospaced, relativeTo: .caption))
                    .foregroundStyle(theme.textPrimary)

                    GuardianMapView(
                        model: simSpawnMapModel,
                        onMapClick: { lat, lon in
                            draftSimLatitudeDeg = lat
                            draftSimLongitudeDeg = lon
                        },
                        onVehicleMarkerMoved: { _, lat, lon in
                            draftSimLatitudeDeg = lat
                            draftSimLongitudeDeg = lon
                        },
                        onVehicleTap: { ev in
                            draftSimLatitudeDeg = ev.lat
                            draftSimLongitudeDeg = ev.lon
                        },
                        onVehicleDoubleTap: { ev in
                            draftSimLatitudeDeg = ev.lat
                            draftSimLongitudeDeg = ev.lon
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
