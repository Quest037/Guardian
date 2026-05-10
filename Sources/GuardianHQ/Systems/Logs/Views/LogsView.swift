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

    private var filtersCardConfiguration: GuardianCardConfiguration {
        GuardianCardConfiguration(
            border: .subtle,
            cornerRadius: GuardianCardLayout.cornerRadius,
            bodyPadding: GuardianCardLayout.defaultBodyPadding
        )
    }

    private var logsCardConfiguration: GuardianCardConfiguration {
        GuardianCardConfiguration(
            border: .subtle,
            cornerRadius: GuardianCardLayout.cornerRadius,
            bodyPadding: GuardianCardLayout.defaultBodyPadding
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            GuardianCard(
                configuration: filtersCardConfiguration,
                header: {
                    Text("Filters")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                },
                body: {
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
                        .padding(.trailing, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            )
            .frame(width: 260)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            GuardianCard(
                configuration: logsCardConfiguration,
                header: {
                    HStack(spacing: 10) {
                        Text("Logs")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        GuardianPrimaryProminentButton(title: "Copy Logs") {
                            copyFilteredLogsToPasteboard()
                        }
                        GuardianThemedButton(
                            title: "Clear",
                            accent: .danger,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            action: {
                                fleetLink.clearLog()
                                selectedVehicleIDs.removeAll()
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                },
                body: {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if filteredLogs.isEmpty {
                                Text("No log lines yet.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(Array(filteredLogs.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(theme.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
