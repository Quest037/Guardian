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
        HStack(alignment: .top, spacing: GuardianSpacing.md) {
            GuardianCard(
                configuration: filtersCardConfiguration,
                header: {
                    Text("Filters")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                },
                body: {
                    ScrollView {
                        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                            DisclosureGroup(
                                isExpanded: $vehiclesAccordionExpanded,
                                content: {
                                    VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
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
                                    .padding(.top, GuardianSpacing.xsTight)
                                },
                                label: {
                                    Text("Vehicles")
                                        .font(GuardianTypography.font(.inlineNoticeTitle))
                                        .foregroundStyle(theme.textPrimary)
                                }
                            )

                            DisclosureGroup(
                                isExpanded: $levelsAccordionExpanded,
                                content: {
                                    Text("No options in this group.")
                                        .font(GuardianTypography.font(.denseFootnoteRegular))
                                        .foregroundStyle(theme.textSecondary)
                                        .padding(.top, GuardianSpacing.xsTight)
                                },
                                label: {
                                    Text("Levels")
                                        .font(GuardianTypography.font(.inlineNoticeTitle))
                                        .foregroundStyle(theme.textPrimary)
                                }
                            )

                            DisclosureGroup(
                                isExpanded: $sessionsAccordionExpanded,
                                content: {
                                    Text("No options in this group.")
                                        .font(GuardianTypography.font(.denseFootnoteRegular))
                                        .foregroundStyle(theme.textSecondary)
                                        .padding(.top, GuardianSpacing.xsTight)
                                },
                                label: {
                                    Text("Sessions")
                                        .font(GuardianTypography.font(.inlineNoticeTitle))
                                        .foregroundStyle(theme.textPrimary)
                                }
                            )
                            .padding(.bottom, GuardianSpacing.micro)
                        }
                        .padding(.trailing, GuardianSpacing.xxs)
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
                    HStack(spacing: GuardianSpacing.denseGutter) {
                        Text("Logs")
                            .font(GuardianTypography.font(.sectionHeadingSemibold))
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
                        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                            if filteredLogs.isEmpty {
                                Text("No log lines yet.")
                                    .font(GuardianTypography.font(.denseCaption12Regular))
                                    .foregroundStyle(theme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, GuardianSpacing.xxs)
                            } else {
                                ForEach(Array(filteredLogs.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(GuardianTypography.font(.telemetryMono11Regular))
                                        .foregroundStyle(theme.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(GuardianSpacing.xl)
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
