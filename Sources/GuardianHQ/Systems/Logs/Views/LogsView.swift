import SwiftUI
import AppKit

struct LogsView: View {
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
