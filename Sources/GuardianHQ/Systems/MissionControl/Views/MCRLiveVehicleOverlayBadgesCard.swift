// MCRLiveVehicleOverlayBadgesCard.swift — MC-R vehicle / reserve-berth overlay: triage badges via ``FleetVehicleLiveChannel`` (Phase 6).
import SwiftUI

private enum MCRLiveVehicleOverlayBadgesCardLayout {
    static let cardConfiguration = GuardianCardConfiguration(
        border: .subtle,
        cornerRadius: GuardianCardLayout.cornerRadius,
        bodyPadding: GuardianCardLayout.defaultBodyPadding
    )
}

/// Assignment triage badges: slot / role / vehicle id capsules, operator phase, live arm / motion / mode / battery / AGL.
struct MCRLiveVehicleOverlayBadgesCard: View {
    let assignment: MissionRunAssignment
    let rosterDevice: RosterDevice?
    let fleetLink: FleetLinkService
    let sitl: SitlService

    var body: some View {
        let streamID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl)
        if let vid = streamID, !vid.isEmpty {
            MCRLiveVehicleOverlayBadgesCardFleetHost(
                rosterDevice: rosterDevice,
                fleetLink: fleetLink,
                vehicleID: vid
            )
        } else {
            MCRLiveVehicleOverlayBadgesCardBody(
                rosterDevice: rosterDevice,
                overlayFleetSlice: nil
            )
        }
    }
}

// MARK: - Fleet channel

private struct MCRLiveVehicleOverlayBadgesCardFleetHost: View {
    let rosterDevice: RosterDevice?
    let fleetLink: FleetLinkService
    let vehicleID: String

    @ObservedObject private var vehicleLiveChannel: FleetVehicleLiveChannel

    init(
        rosterDevice: RosterDevice?,
        fleetLink: FleetLinkService,
        vehicleID: String
    ) {
        self.rosterDevice = rosterDevice
        self.fleetLink = fleetLink
        self.vehicleID = vehicleID
        _vehicleLiveChannel = ObservedObject(wrappedValue: fleetLink.mcrRosterLiveChannel(forVehicleID: vehicleID))
    }

    var body: some View {
        MCRLiveVehicleOverlayBadgesCardBody(
            rosterDevice: rosterDevice,
            overlayFleetSlice: vehicleLiveChannel.overlayFleetSlice
        )
        .onAppear {
            fleetLink.mcrRosterRetainLiveChannel(forVehicleID: vehicleID)
            vehicleLiveChannel.refresh(from: fleetLink)
        }
        .onDisappear {
            fleetLink.mcrRosterReleaseLiveChannel(forVehicleID: vehicleID)
        }
    }
}

// MARK: - Card body

private struct MCRLiveVehicleOverlayBadgesCardBody: View {
    let rosterDevice: RosterDevice?
    let overlayFleetSlice: MCRLiveVehicleOverlayFleetSlice?

    var body: some View {
        GuardianCard(configuration: MCRLiveVehicleOverlayBadgesCardLayout.cardConfiguration, body: {
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                    if let rosterDevice {
                        MCRLiveAssignmentTriageSlotCapsuleBadge(slot: rosterDevice.slot)
                        MCRLiveAssignmentTriageNeutralCapsuleBadge(
                            title: RosterRoleCatalog.displayName(forBehaviorRoleID: rosterDevice.behaviorRoleID)
                        )
                    }
                    if let slice = overlayFleetSlice {
                        MCRLiveAssignmentTriageVehicleIdCapsuleBadge(title: slice.displayShortID)
                            .help("Bridge vehicle key: \(slice.vehicleID)")
                    } else {
                        MCRLiveAssignmentTriageNeutralCapsuleBadge(title: "No bridge link")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let slice = overlayFleetSlice {
                    MCRLiveAssignmentTriageMcrOperatorPhaseFullWidthBadge(phase: slice.mcrOperatorPhase)
                        .help("Mission Control operator phase for this bridge vehicle.")
                    HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                        MCRLiveAssignmentTriageActiveStateCapsuleBadge(
                            title: slice.liveStatusBadgeRow.arm.title,
                            isActive: slice.liveStatusBadgeRow.arm.isActive
                        )
                        MCRLiveAssignmentTriageActiveStateCapsuleBadge(
                            title: slice.liveStatusBadgeRow.motion.title,
                            isActive: slice.liveStatusBadgeRow.motion.isActive
                        )
                        MCRLiveAssignmentTriageActiveStateCapsuleBadge(
                            title: slice.liveStatusBadgeRow.mode.title,
                            isActive: slice.liveStatusBadgeRow.mode.isActive
                        )
                        MCRLiveAssignmentTriageBatteryTrafficBadge(chip: slice.liveStatusBadgeRow.battery)
                        MCRLiveAssignmentTriageNeutralCapsuleBadge(title: slice.liveStatusBadgeRow.altitude.title)
                            .help(slice.liveStatusBadgeRow.altitude.helpSummary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        })
    }
}

// MARK: - Badge chrome

private struct MCRLiveAssignmentTriageSlotCapsuleBadge: View {
    let slot: MissionRosterSlotRole

    var body: some View {
        let pair = slotSemanticColors(slot)
        Text(slot.rawValue.capitalized)
            .font(GuardianTypography.font(.denseCaption10Semibold))
            .foregroundStyle(pair.foreground)
            .lineLimit(1)
            .padding(.horizontal, GuardianSpacing.chromeTightInset)
            .padding(.vertical, GuardianSpacing.titleStackTight)
            .background(pair.background)
            .clipShape(Capsule())
    }

    private func slotSemanticColors(_ slot: MissionRosterSlotRole) -> (background: Color, foreground: Color) {
        switch slot {
        case .primary:
            return (GuardianSemanticColors.infoBackground, GuardianSemanticColors.infoForeground)
        case .wingman:
            return (GuardianSemanticColors.successBackground, GuardianSemanticColors.successForeground)
        case .reserve:
            return (GuardianSemanticColors.warningBackground, GuardianSemanticColors.warningForeground)
        }
    }
}

private struct MCRLiveAssignmentTriageMcrOperatorPhaseFullWidthBadge: View {
    let phase: FleetMcrOperatorVehiclePhase

    var body: some View {
        let pair = phaseSemanticColors(phase)
        Text(phase.missionControlAssignmentTriageBadgeTitle)
            .font(GuardianTypography.font(.denseCaption10Semibold))
            .foregroundStyle(pair.foreground)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GuardianSpacing.sm)
            .padding(.vertical, GuardianSpacing.xs)
            .background(pair.background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func phaseSemanticColors(_ phase: FleetMcrOperatorVehiclePhase) -> (background: Color, foreground: Color) {
        switch phase {
        case .unknown:
            return (GuardianSemanticColors.neutralBadgeBackground, GuardianSemanticColors.neutralBadgeForeground)
        case .onMission:
            return (GuardianSemanticColors.infoBackground, GuardianSemanticColors.infoForeground)
        case .operatorParkAwaitingContinue:
            return (GuardianSemanticColors.warningBackground, GuardianSemanticColors.warningForeground)
        }
    }
}

private struct MCRLiveAssignmentTriageActiveStateCapsuleBadge: View {
    let title: String
    let isActive: Bool

    var body: some View {
        let background = isActive ? GuardianSemanticColors.successBackground : GuardianSemanticColors.neutralBadgeBackground
        let foreground = isActive ? GuardianSemanticColors.successForeground : GuardianSemanticColors.neutralBadgeForeground
        Text(title)
            .font(GuardianTypography.font(.denseCaption10Semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, GuardianSpacing.chromeTightInset)
            .padding(.vertical, GuardianSpacing.titleStackTight)
            .background(background)
            .clipShape(Capsule())
    }
}

private struct MCRLiveAssignmentTriageBatteryTrafficBadge: View {
    let chip: FleetVehicleLiveStatusBadgeRow.BatteryChip

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: GuardianSpacing.xxs) {
            Image(systemName: chip.systemImageName)
                .font(GuardianTypography.font(.denseCaption10Semibold))
                .foregroundStyle(chip.trafficBand.trafficLightIconTint)
            Text(chip.percentLabel)
                .font(GuardianTypography.font(.telemetryMono10Semibold))
                .foregroundStyle(theme.textPrimary.opacity(0.94))
                .lineLimit(1)
        }
        .padding(.horizontal, GuardianSpacing.chromeTightInset)
        .padding(.vertical, GuardianSpacing.titleStackTight)
        .background(GuardianSemanticColors.neutralBadgeBackground)
        .clipShape(Capsule())
        .help(chip.helpSummary)
    }
}

private struct MCRLiveAssignmentTriageNeutralCapsuleBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(GuardianTypography.font(.denseCaption10Semibold))
            .foregroundStyle(GuardianSemanticColors.neutralBadgeForeground)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, GuardianSpacing.chromeTightInset)
            .padding(.vertical, GuardianSpacing.titleStackTight)
            .background(GuardianSemanticColors.neutralBadgeBackground)
            .clipShape(Capsule())
    }
}

private struct MCRLiveAssignmentTriageVehicleIdCapsuleBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(GuardianTypography.font(.telemetryMono10Semibold))
            .foregroundStyle(GuardianSemanticColors.neutralBadgeForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, GuardianSpacing.chromeTightInset)
            .padding(.vertical, GuardianSpacing.titleStackTight)
            .background(GuardianSemanticColors.neutralBadgeBackground)
            .clipShape(Capsule())
    }
}
