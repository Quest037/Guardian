import SwiftUI

struct SettingsView: View {
    @Binding var selectedPane: SettingsPane
    @ObservedObject var generalSettings: GeneralSettingsStore

    private let bgBar = Color(red: 0.12, green: 0.12, blue: 0.13)
    private let bgMain = Color(red: 0.07, green: 0.07, blue: 0.08)
    @State private var isLocationPickerPresented = false
    @State private var draftSimLatitudeDeg = 0.0
    @State private var draftSimLongitudeDeg = 0.0
    @State private var locationPickerRecenterNonce = 0

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
            .background(bgBar)

            Group {
                switch selectedPane {
                case .general:
                    generalPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(bgMain)
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
                    .foregroundStyle(.white)
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
                    title: "Default SIM spawn location",
                    description: "Used for newly spawned SITL vehicles. Altitude is fixed at 0m so defaults remain safe across UAV/USV/UUV presets."
                ) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Latitude")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.gray)
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
                                .foregroundStyle(.gray)
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
                                .foregroundStyle(.gray)
                            TextField(
                                "Altitude",
                                value: .constant(0),
                                format: .number
                            )
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
                                locationPickerRecenterNonce &+= 1
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
        .background(bgMain)
    }

    private var rowDivider: some View {
        Divider()
            .opacity(0.22)
            .padding(.vertical, 14)
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
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var simLocationPickerSheet: some View {
        GuardianModalTemplate(
            title: "Pick SIM Spawn Location",
            headerActions: {
                HStack(spacing: 8) {
                    Button("Recenter") {
                        locationPickerRecenterNonce &+= 1
                    }
                    .buttonStyle(.bordered)

                    Button("Cancel") {
                        isLocationPickerPresented = false
                    }
                    .buttonStyle(.bordered)

                    Button("Use Location") {
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

                    OSMMapView(
                        home: RouteHome(
                            coord: RouteCoordinate(
                                lat: draftSimLatitudeDeg,
                                lon: draftSimLongitudeDeg
                            ),
                            altitude: RouteAltitude(value: 0, unit: .m, reference: .agl),
                            heading: 0,
                            radiusMeters: 3,
                            dockAllowed: true,
                            fallbackOnly: false
                        ),
                        allPathsCoords: [],
                        selectedPathWaypoints: [],
                        selectedWaypointIndex: nil,
                        vehicleMarkers: [
                            MapVehicleMarker(
                                id: "sim-spawn-default",
                                lat: draftSimLatitudeDeg,
                                lon: draftSimLongitudeDeg,
                                label: "SIM Default",
                                colorHex: "#3b82f6",
                                selected: true,
                                draggable: true
                            )
                        ],
                        mapStyle: generalSettings.defaultMapTileStyle,
                        recenterNonce: locationPickerRecenterNonce,
                        headingPreview: nil,
                        cameraPreview: nil,
                        preserveView: true,
                        isEditingPath: false
                    ) { lat, lon in
                        draftSimLatitudeDeg = lat
                        draftSimLongitudeDeg = lon
                    } onVehicleMarkerMoved: { _, lat, lon in
                        draftSimLatitudeDeg = lat
                        draftSimLongitudeDeg = lon
                    } onWaypointClick: { _ in
                    } onWaypointMoved: { _, _, _ in
                    } onWaypointDelete: { _ in
                    } onPathInsert: { _, _, _ in
                    }
                    .frame(minHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        )
        .frame(minWidth: 860, minHeight: 560)
    }
}
