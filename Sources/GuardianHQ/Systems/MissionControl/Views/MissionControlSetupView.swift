// MissionControlSetupView.swift — MC-S: setup roster chrome, staging helpers, and ``MissionControlSetupView`` shell.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Roster slot card: role + vehicle from fleet picker (Vehicles tab inventory).
struct MissionControlRosterSlotCard: View {
    let title: String
    let subtitle: String
    /// Class for bundled ``SimulationDevices`` art: roster slot expectation when empty; linked fleet ``FleetVehicleModel`` type when assigned (unless sim-specific basenames apply).
    let vehicleClassForBundledDeviceArt: FleetVehicleType
    /// Slot has a fleet or legacy device binding (chrome, buttons).
    let isAttached: Bool
    /// Extra line under titles (live mode summary, etc.); omits generic sim preset names like “Multirotor”.
    let assignedVehicleDetail: String?
    /// MAVLink bridge battery summary when a fleet vehicle is assigned (`nil` if unassigned).
    let rosterBatterySummary: FleetVehicleOperationalModel.BatterySummary?
    /// `nil` when unassigned or legacy free-text only; `false` = live MAVLink, `true` = built-in sim.
    let assignedFleetIsSimulation: Bool?
    /// ArduPilot / PX4 badge when a fleet vehicle is bound (matches Vehicles grid).
    let autopilotStack: FleetAutopilotStack?
    let simulationImageBasenames: [String]?
    /// Shown under the type glyph when a vehicle is assigned (two-word lifecycle line).
    let lifecycleStatus: VehicleLifecycleStatus?
    /// ``FleetVehicleModel/displayShortID`` when linked (e.g. `UAV-C:1`); `nil` if unresolved.
    let fleetDisplayShortID: String?
    let isSelectedForSetupMap: Bool
    let onSelectForSetupMap: () -> Void
    let onChooseVehicle: () -> Void
    let onRemoveVehicle: () -> Void
    /// Opens the shared ``VehicleCalibrationModal`` (Vehicle Inspector) for the bound fleet vehicle (mirrors Vehicles grid).
    let onCalibration: (() -> Void)?
    /// When simulate is on and this is set, empty cards show a **Sim** control next to **Choose** (same picker as Vehicles → Add Sim).
    let simulateSystemOn: Bool
    let onPickAndAssignSim: (() -> Void)?
    /// Bulk SIM spawn: dim card and show spinner on the slot currently being spawned for.
    let showsWorkingOverlay: Bool
    /// Opens Mission Control slot settings (policies, etc.) in a trailing sidebar.
    var onOpenSettings: (() -> Void)? = nil
    /// MC-R / MCS **running** roster: show merged slot-state chip when non-nil severity (``MissionRunAssignmentSlotState/missionControlRosterBadgeSeverity`` in ``MissionControlModels``).
    var missionControlShowsSlotStateBadge: Bool = false
    /// Merged slot display state (``MissionRunAssignmentSlotLaneMerge/preferredDisplayState``); ignored when ``missionControlShowsSlotStateBadge`` is false.
    var missionControlMergedSlotDisplayState: MissionRunAssignmentSlotState = .idle

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var rosterSlotCardConfiguration: GuardianCardConfiguration {
        GuardianCardConfiguration(
            border: rosterSlotUsesStrokeOverlay ? .none : .subtle,
            cornerRadius: GuardianCardLayout.cornerRadius,
            bodyPadding: MissionRunPrepLayout.rosterSlotPadding
        )
    }

    private var rosterSlotUsesStrokeOverlay: Bool {
        isSelectedForSetupMap || isAttached
    }

    var body: some View {
        GuardianCard(
            configuration: rosterSlotCardConfiguration,
            body: {
                Group {
                    if isAttached {
                        attachedRosterCardBody
                    } else {
                        emptyRosterCardBody
                    }
                }
                .frame(minHeight: MissionRunPrepLayout.rosterSlotMinHeight, alignment: .topLeading)
            }
        )
        .overlay {
            if isSelectedForSetupMap {
                RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                    .strokeBorder(GuardianSemanticColors.infoForeground.opacity(0.55), lineWidth: 2)
                    .allowsHitTesting(false)
            } else if isAttached {
                RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                    .strokeBorder(GuardianSemanticColors.successForeground.opacity(0.65), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if showsWorkingOverlay {
                ZStack {
                    RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                }
                .allowsHitTesting(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous))
        .onTapGesture {
            onSelectForSetupMap()
        }
    }

    private var emptyRosterCardBody: some View {
        HStack(alignment: .center, spacing: MissionRunPrepLayout.rosterSlotIconRowSpacing) {
            iconTile
                .frame(width: MissionRunPrepLayout.rosterSlotIconSize, height: MissionRunPrepLayout.rosterSlotIconSize)

            VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterTitleStackSpacing) {
                Text(title)
                    .font(GuardianTypography.font(.inlineNoticeTitle))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
                if missionControlShowsSlotStateBadge {
                    Text("No vehicle on this row — use Choose or Sim to bind this slot for mission policy while the run is live.")
                        .font(GuardianTypography.font(.denseCaption10Regular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Empty roster slot: bind a fleet vehicle or simulator for mission policy during this live run.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: GuardianSpacing.xs) {
                Button(action: onChooseVehicle) {
                    Text("Choose")
                }
                .font(GuardianTypography.font(.formFieldLabel))
                .buttonStyle(.bordered).guardianPointerOnHover()
                .tint(.blue)
                .controlSize(.small)

                if simulateSystemOn, let onPickAndAssignSim {
                    Button(action: onPickAndAssignSim) {
                        Text("Sim")
                    }
                    .font(GuardianTypography.font(.formFieldLabel))
                    .buttonStyle(.bordered).guardianPointerOnHover()
                    .tint(.blue)
                    .controlSize(.small)
                    .help("Pick a simulator and assign it to this roster slot (same as Vehicles → Add Sim).")
                }

                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .font(GuardianTypography.font(.inlineNoticeTitle))
                    }
                    .buttonStyle(.bordered).guardianPointerOnHover()
                    .controlSize(.small)
                    .help("Slot settings")
                }
            }
        }
    }

    private var attachedRosterCardBody: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterSlotStackSpacing) {
            HStack(alignment: .center, spacing: MissionRunPrepLayout.rosterSlotIconRowSpacing) {
                iconTile
                    .frame(width: MissionRunPrepLayout.rosterSlotIconSize, height: MissionRunPrepLayout.rosterSlotIconSize)

                VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterTitleStackSpacing) {
                    Text(title)
                        .font(GuardianTypography.font(.inlineNoticeTitle))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(GuardianTypography.font(.denseCaption10Regular))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                    if missionControlShowsSlotStateBadge,
                       let sev = missionControlMergedSlotDisplayState.missionControlRosterBadgeSeverity {
                        MissionControlRosterSlotAttentionCapsule(
                            severity: sev,
                            title: missionControlMergedSlotDisplayState.displayTitle,
                            help: missionControlMergedSlotDisplayState.rosterSlotChipHelp,
                            compactMetrics: false
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let stack = autopilotStack {
                    HStack(spacing: GuardianSpacing.xsTight) {
                        FleetAutopilotStackBadge(stack: stack)
                        if let isSim = assignedFleetIsSimulation {
                            FleetLiveSimBadge(isSimulation: isSim)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                    Text(fleetDisplayShortID ?? "—")
                        .font(GuardianTypography.font(.telemetryMono10Semibold))
                        .foregroundStyle(theme.textPrimary.opacity(0.9))
                        .lineLimit(1)
                        .layoutPriority(1)
                        .help(
                            fleetDisplayShortID.map { "Fleet vehicle: \($0)" }
                                ?? "Fleet vehicle identifier not resolved yet"
                        )

                    if let lifecycleStatus {
                        Text(lifecycleStatus.compactTwoWordStatus)
                            .font(GuardianTypography.font(.denseCaption10Semibold))
                            .foregroundStyle(lifecycleStatus.color.uiColor.opacity(0.95))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("—")
                            .font(GuardianTypography.font(.denseCaption10Semibold))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: GuardianSpacing.xs)

                    rosterSetupBatteryCompact
                }

                if let detail = assignedVehicleDetail, !detail.isEmpty {
                    Text(detail)
                        .font(GuardianTypography.font(.denseCaption10Regular))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                Button(action: onChooseVehicle) {
                    Image(systemName: "pencil")
                        .font(GuardianTypography.font(.inlineNoticeTitle))
                }
                .buttonStyle(.bordered).guardianPointerOnHover()
                .controlSize(.small)
                .help("Change vehicle assignment")

                if let onCalibration {
                    Button(action: onCalibration) {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(GuardianTypography.font(.inlineNoticeTitle))
                    }
                    .buttonStyle(.bordered).guardianPointerOnHover()
                    .controlSize(.small)
                    .help("Open Vehicle Inspector (calibration, preflight, telemetry)")
                }

                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .font(GuardianTypography.font(.inlineNoticeTitle))
                    }
                    .buttonStyle(.bordered).guardianPointerOnHover()
                    .controlSize(.small)
                    .help("Slot settings")
                }

                Spacer(minLength: 0)

                Button(action: onRemoveVehicle) {
                    Image(systemName: "trash")
                        .font(GuardianTypography.font(.inlineNoticeTitle))
                }
                .buttonStyle(.bordered).guardianPointerOnHover()
                .tint(.red)
                .controlSize(.small)
                .help("Remove vehicle from this slot")
            }
        }
    }

    private var rosterSetupBatteryCompact: some View {
        HStack(alignment: .center, spacing: GuardianSpacing.xxs) {
            Image(systemName: rosterBatterySymbol)
                .font(GuardianTypography.font(.windowHeading16Semibold))
                .foregroundStyle(rosterBatteryIconTint)
            Text(rosterBatteryPercentText)
                .font(GuardianTypography.font(.telemetryMono12Semibold))
                .foregroundStyle(theme.textPrimary.opacity(0.94))
                .lineLimit(1)
        }
        .help(rosterBatteryHoverText)
    }

    private var rosterBatteryPercentText: String {
        rosterBatterySummary?.compactPercentLabel ?? "—"
    }

    private var rosterBatterySymbol: String {
        rosterBatterySummary?.compactTelemetryBatterySymbolName ?? "battery.100"
    }

    private var rosterBatteryIconTint: Color {
        rosterBatterySummary?.trafficBand.trafficLightIconTint ?? FleetVehicleBatteryTrafficBand.unknown.trafficLightIconTint
    }

    private var rosterBatteryHoverText: String {
        rosterBatterySummary.map(\.compactHoverHelpSummary) ?? "Battery —"
    }

    private var slotLeadingThumbnailBasenames: [String] {
        if let names = simulationImageBasenames, !names.isEmpty { return names }
        return vehicleClassForBundledDeviceArt.defaultSimulationDeviceImageBasenames
    }

    private var slotLeadingGlyph: some View {
        SimulationDeviceThumbnail(imageBasenames: slotLeadingThumbnailBasenames)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(GuardianSpacing.titleStackTight)
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.12, blue: 0.14),
                            Color(red: 0.05, green: 0.07, blue: 0.09),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            slotLeadingGlyph
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

enum LiveConsoleMediaTab: Hashable {
    case camera
    case map
}

enum MissionRunSetupTab: String, CaseIterable, Identifiable, Hashable {
    case timing
    case rosters
    case rules
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timing: return "Timing"
        case .rosters: return "Tasks"
        case .rules: return "Rules"
        case .settings: return "Settings"
        }
    }
}

/// Segmented control inside MC-S **Tasks** (setup) tab: roster accordions vs template map points.
enum MissionControlSetupRostersSidebarTab: String, CaseIterable, Identifiable {
    case tasks
    case points
    case fences
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .points: "Points"
        case .fences: "Fences"
        }
    }
}

/// Inputs that affect roster staging map mission-point chrome (toolbar arm, hit testing, geometry placement flag).
///
/// **Geofence selection / template topology / “show fences”** intentionally **omit** here so add/delete/edit fence
/// and fence list selection do not cancel the staging map ``.task(id:)`` (which would refit bounds and reset the map).
/// Those drive ``setupStagingMapMarkerCoordinateDigest`` → ``pushSetupStagingMapMarkersOnly()`` instead.
struct MissionControlSetupRosterStagingMissionPointChrome: Equatable {
    let listTab: MissionControlSetupRostersSidebarTab
    let selectedPointID: UUID?
}

/// Stable inputs for ``MissionRunDetailView`` staging map `.task(id:)` — **excludes** live lat/lon so fleet
/// telemetry / ``FleetLinkService/applySimState`` cannot invalidate the task every frame (which breaks Leaflet drag
/// and triggers “onChange … multiple times per frame”). Coordinate-only updates use ``setupStagingMapMarkerCoordinateDigest``.
///
/// **Geofence template topology, run augmentation topology, fence selection, fences visibility, and geofence coordinates**
/// are excluded so MCS fence edits use marker-only pushes (preserve map zoom/pan). See ``setupStagingMapMarkerCoordinateDigest``.
struct SetupStagingMapStructureIdentity: Equatable {
    let missionID: UUID?
    let homeCoord: RouteCoordinate?
    let allTasksCoords: [[RouteCoordinate]]
    let taskPathIDs: [UUID]
    /// Mission map points: ids, kind, closed, and map selection — not coordinates.
    let missionPointTopologySignature: String
    /// Roster ↔ fleet token rows (``setupMapBoundsSignature``).
    let assignmentFleetBindingSignature: String
    let rosterStagingMissionPointChrome: MissionControlSetupRosterStagingMissionPointChrome
    /// Exclusive map chrome: which task polyline (if any) is the active map selection on MCS staging.
    let selectedTaskPathID: UUID?
    /// Which roster assignment is selected for staging-map vehicle chrome (draggable SIM, ring, tooltip).
    let selectedStagingRosterAssignmentID: UUID?
    /// MCS reserve-pool bulk home placement arm; participates in staging map ``.task(id:)`` so Leaflet refreshes when arming/disarming.
    let mcsReservePoolHomePlacementTaskID: UUID?
    /// Selected floating-reserve pool berth on the MCS staging map (``taskID`` + ``slotID`` signature for ``MissionControlReservePoolMapMarkerID``).
    let stagingReservePoolBerthSelectionSignature: String
}

/// MCS staging SITL drag: optimistic map pose until hub telemetry **stably** matches or ``MissionControlSetupSimDragOverlayPolicy/pendingSyncTimeoutSeconds`` elapses.
struct MissionRunStagingSimDragOverlay: Equatable {
    var coordinate: RouteCoordinate
    var startedAt: Date
    /// First instant (this process) hub lat/lon fell inside epsilon of ``coordinate`` without a divergent sample in between.
    var hubAgreesSince: Date?
}

/// MC Setup roster: confirm before bulk-spawn SIMs (one task or entire mission).
enum MissionRunBulkSpawnSimsConfirmKind: Equatable {
    case singleTask(UUID)
    case allMissionSlots
}

/// While a bulk spawn is running, all spawn controls stay disabled and one slot shows the spinner.
enum MissionRunBulkSimSpawnBusyKind: Equatable {
    case singleTask(UUID)
    case allMissionSlots
}
