// MissionControlSetupView.swift — MC-S: setup-phase run experience (`MissionRunDetailView`), prep layout, roster chrome.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Spacing and widths for mission setup / roster prep.
///
/// Values alias ``GuardianSpacing`` / ``GuardianCardLayout`` so MC-S tracks the global grid; tune **here** when
/// adding sim battery, pre-place coordinates, staging waypoints, or other per-slot controls.
enum MissionRunPrepLayout {
    static let setupScrollPaddingH: CGFloat = GuardianSpacing.denseGutter
    static let setupScrollPaddingV: CGFloat = GuardianSpacing.denseGutter
    static let setupBlockSpacing: CGFloat = GuardianSpacing.denseGutter
    static let taskCardPadding: CGFloat = GuardianSpacing.missionTaskCardOuterInset
    static let taskCardInnerSpacing: CGFloat = GuardianSpacing.sectionStack
    static let tasksOuterSpacing: CGFloat = GuardianSpacing.missionTaskCardOuterInset
    /// Former default ~200pt; +50% for wider prep columns.
    static let rosterGridMinWidth: CGFloat = GuardianSpacing.missionRosterGridMinWidth
    static let rosterGridSpacing: CGFloat = GuardianSpacing.missionRosterGridGap
    static let scheduleCardPadding: CGFloat = GuardianSpacing.missionScheduleCardInset
    static let scheduleCardSpacing: CGFloat = GuardianSpacing.missionScheduleBlockGap
    static let rosterSlotPadding: CGFloat = GuardianSpacing.denseGutter
    static let rosterSlotStackSpacing: CGFloat = GuardianSpacing.denseGutter
    static let rosterSlotIconSize: CGFloat = 44
    static let rosterSlotIconRowSpacing: CGFloat = GuardianSpacing.cardBodyInset
    static let rosterTitleStackSpacing: CGFloat = GuardianSpacing.titleStackTight
    /// Wingman / reserve visual indent under a primary (matches Missions roster nesting).
    static let rosterSlotWingmanIndent: CGFloat = GuardianSpacing.cardBodyInset
    /// Slot cards use ``GuardianCard``; same radius as ``GuardianCardLayout/cornerRadius`` (theme catalog / docs).
    static let rosterSlotCornerRadius: CGFloat = GuardianCardLayout.cornerRadius
    static let rosterSlotMinHeight: CGFloat = 100
    /// Below this width, Setup **Tasks** tab stacks map above the accordion.
    static let rostersMapAccordionStackBreakpoint: CGFloat = GuardianSpacing.missionRosterMapAccordionBreakpoint
}

/// Matches the golden-angle route line hue in ``OSMMapView`` so route lines and progress bars align visually.
enum MissionTaskMapColor {
    static func hueDegrees(forTaskIndex index: Int) -> Double {
        (Double(index) * 137.508).truncatingRemainder(dividingBy: 360)
    }

    static func swiftUIColor(forTaskIndex index: Int) -> Color {
        Color(hue: hueDegrees(forTaskIndex: index) / 360, saturation: 0.88, brightness: 0.62)
    }
}


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
        guard let p = rosterBatterySummary?.percent0to100 else { return "—" }
        return "\(Int(round(p)))%"
    }

    private var rosterBatterySymbol: String {
        if rosterBatterySummary?.isCharging == true {
            return "battery.100.bolt"
        }
        return "battery.100"
    }

    private var rosterBatteryIconTint: Color {
        guard let p = rosterBatterySummary?.percent0to100 else {
            return Color.gray.opacity(0.55)
        }
        if p < 10 {
            return Color.red.opacity(0.92)
        }
        if p < 80 {
            return Color.yellow.opacity(0.95)
        }
        return GuardianSemanticColors.successForeground
    }

    private var rosterBatteryHoverText: String {
        let pct = rosterBatteryPercentText
        let v = rosterBatterySummary?.voltageV.map { String(format: "%.1f V", $0) } ?? "—"
        let a = rosterBatterySummary?.currentA.map { String(format: "%.1f A", $0) } ?? "—"
        return "Battery \(pct), \(v), \(a)"
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timing: return "Timing"
        case .rosters: return "Tasks"
        case .rules: return "Rules"
        }
    }
}

/// Segmented control inside MC-S **Tasks** (setup) tab: roster accordions vs template map points.
enum MissionControlSetupRostersSidebarTab: String, CaseIterable, Identifiable {
    case tasks
    case points
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .points: "Points"
        }
    }
}

/// Inputs that affect roster staging map mission-point chrome (toolbar arm, hit testing, geometry placement flag).
struct MissionControlSetupRosterStagingMissionPointChrome: Equatable {
    let listTab: MissionControlSetupRostersSidebarTab
    let selectedPointID: UUID?
}

/// Stable inputs for ``MissionRunDetailView`` staging map `.task(id:)` — **excludes** live lat/lon so fleet
/// telemetry / ``FleetLinkService/applySimState`` cannot invalidate the task every frame (which breaks Leaflet drag
/// and triggers “onChange … multiple times per frame”). Coordinate-only updates use ``setupStagingMapMarkerCoordinateDigest``.
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
}

private struct MissionControlSetupRosterMissionPointDeleteCandidate: Identifiable, Equatable {
    let id: UUID
}

/// MC Setup roster: confirm before bulk-spawn SIMs (one task or entire mission).
enum MissionRunBulkSpawnSimsConfirmKind: Equatable {
    case singleTask(UUID)
    case allMissionSlots
}

/// While a bulk spawn is running, all wands stay disabled and one slot shows the spinner.
enum MissionRunBulkSimSpawnBusyKind: Equatable {
    case singleTask(UUID)
    case allMissionSlots
}

/// Presented as one in-window overlay from ``MissionRunDetailView`` (replaces stacked `confirmationDialog` modifiers).
private enum MissionRunPresentedConfirm: Identifiable, Equatable {
    case deleteRun
    case skipScheduledMissionStart
    case skipTaskStartDeferral
    /// Spawn scope is part of the item so the window-level confirm host always rebuilds with the correct copy (no orphaned `@State`).
    case bulkSpawnSims(MissionRunBulkSpawnSimsConfirmKind)

    var id: String {
        switch self {
        case .deleteRun: "deleteRun"
        case .skipScheduledMissionStart: "skipScheduledMissionStart"
        case .skipTaskStartDeferral: "skipTaskStartDeferral"
        case .bulkSpawnSims(let scope):
            switch scope {
            case .allMissionSlots: "bulkSpawnSims.allMissionSlots"
            case .singleTask(let taskID): "bulkSpawnSims.task.\(taskID.uuidString)"
            }
        }
    }
}

struct MissionRunDetailView: View {
    @ObservedObject var run: MissionRunEnvironment
    @ObservedObject var missionStore: MissionStore
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    @ObservedObject var controlStore: MissionControlStore
    @ObservedObject var generalSettings: GeneralSettingsStore
    @EnvironmentObject private var appDrawer: AppDrawer
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var bottomPromptCenter = GuardianBottomPromptCenter()

    /// Internal so MC-C extensions in other files can share the same palette as setup/live chrome.
    var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }
    let onBack: () -> Void
    let onUpdate: (MissionRunEnvironment) -> Void
    let onStart: (MissionRunEnvironment) -> Void
    let onDelete: (UUID) -> Void

    @State private var setupSelectedAssignmentId: UUID?
    /// MCS staging SITL: operator-dragged lat/lon applied **synchronously** to the map payload so Leaflet is not
    /// overwritten by stale hub telemetry until ``FleetLinkService/applySimState`` finishes (same frame as drag moves).
    @State private var setupStagingSimDragCoordByAssignmentID: [UUID: RouteCoordinate] = [:]
    /// Shared model for both the Setup staging map and the Live overview map —
    /// owns the tile style, recenter nonce, and the per-tab content that gets
    /// pushed in via `.task(id:)`.
    @StateObject private var mapModel: GuardianMapModel
    /// MC-R: focused task triage — filters the live mission log and roster to this task; shows triage sheet on Tasks card.
    @State private var focusedLiveTaskID: UUID? = nil
    /// MC-R: focused roster slot triage — slides a vehicle detail sheet up over the Tasks card.
    /// Mutually exclusive with ``focusedLiveTaskID`` so only one overlay is mounted at a time.
    @State private var focusedLiveAssignmentID: UUID? = nil
    /// MC-R §4.2: runtime map-points sheet over the Tasks card (slide-up; stacks above task triage and vehicle overlays).
    @State private var liveRuntimeMissionPointsOverlayPresented = false
    @State private var liveRuntimeMissionPointDrawerEditingID: UUID?
    @State private var liveRuntimeMissionMapViewportCenter: RouteCoordinate?
    /// MC-R live overview map: selected runtime map point (list + map pin); enables drag reposition on the pin.
    @State private var liveRuntimeOverviewSelectedMissionPointID: UUID?
    /// Bumps after adding a map point so the overlay list scrolls that row into view.
    @State private var liveRuntimeMapPointsListScrollEpoch: UInt = 0
    @State private var liveRuntimeMapPointsListScrollTargetRow: UUID?
    /// MC-R: when true, log card body shrinks to one line so the live map column gains height.
    @State private var liveLogPanelCollapsed = false
    /// User dismissed the recovery status anchored prompt for this visit (does not change MRE).
    @State private var dismissedRecoveryStatusPrompt = false
    /// User dismissed the abort-session status anchored prompt for this visit (does not change MRE).
    @State private var dismissedAbortStatusPrompt = false
    @State private var liveConsoleMediaTab: LiveConsoleMediaTab = .map
    @ObservedObject private var logTemplateRegistry: MissionRunLogTemplateRegistry
    @State private var startPreflightPresented = false
    @State private var rosterCalibrationVehicleID: String?
    @State private var rosterCalibrationFallbackModel: FleetVehicleModel?
    /// Deferred one-off schedule: value + unit for **Go** on the running countdown banner (same control model as MCS Timing Tasks).
    @State private var scheduledStartPostponeValue: Double = 5
    @State private var scheduledStartPostponeUnit: DelayUnit = .mins
    @State private var confirmSkipScheduledMissionMessage = ""
    /// Per-task deferral Alter controls: value + unit (same model as scheduled start banner; covers initial and between-cycle MAVLink start waits).
    @State private var taskStartDeferralPostponeValue: Double = 5
    @State private var taskStartDeferralPostponeUnit: DelayUnit = .mins
    @State private var confirmSkipTaskStartDeferralTaskID: UUID?
    @State private var confirmSkipTaskStartDeferralMessage = ""
    @State private var setupMainTab: MissionRunSetupTab = .timing
    @State private var rosterSetupExpandedTaskIDs: Set<UUID> = []
    @State private var rosterSetupLegacyMissionRosterExpanded: Bool = true
    /// Single sheet for run-level confirms (replaces stacked `confirmationDialog` modifiers).
    @State private var presentedRunConfirm: MissionRunPresentedConfirm?
    @State private var rosterBulkSimSpawnBusy: MissionRunBulkSimSpawnBusyKind?
    @State private var rosterBulkSimSpawnWorkingAssignmentId: UUID?
    /// Stack segment for **Sim** on empty roster cards (`SimulationVehiclePickerSidebar`, same as Vehicles → Add Sim).
    @State private var rosterSimSidebarSpawnPlatform: SimulationPlatform = .ardupilot
    @State private var rostersSidebarListTab: MissionControlSetupRostersSidebarTab = .tasks
    @State private var setupRostersSelectedMissionPointID: UUID?
    @State private var setupRostersMapViewportCenter: RouteCoordinate?
    @State private var setupRostersMissionPointDrawerEditingID: UUID?
    @State private var setupRostersMissionPointDeleteCandidate: MissionControlSetupRosterMissionPointDeleteCandidate?
    @State private var setupRostersMapPointsListScrollEpoch: UInt = 0
    @State private var setupRostersMapPointsListScrollTargetRow: UUID?
    /// MCS staging map: at most one of point / vehicle / task path may be “map selected” at a time (see ``applyExclusiveMCSStagingMapSelectionForTaskPath`` / vehicle / point handlers).
    @State private var setupStagingMapSelectedTaskPathID: UUID?

    /// Shared live progress / deferral values for task list rows and the in-card triage sheet.
    private struct MissionLiveTaskProgressDerived {
        let hub: FleetHubVehicleTelemetry?
        let taskActiveInCycle: Bool
        let tint: Color
        let inTaskStartDeferral: Bool
        let taskStartDef: MissionTaskStartDeferral?
        let barFraction: Double
        let barTint: Color
    }

    /// Which per-path fleet wind-down controls are enabled in MC-R triage (mutually exclusive graceful intents, whole-run graceful, deferrals, protocol phase).
    private struct MissionLiveTaskWindDownAvailability: Equatable {
        let abortNow: Bool
        let abortGraceful: Bool
        let completeNow: Bool
        let completeGraceful: Bool
        let revokeTaskGraceful: Bool
    }

    init(
        run: MissionRunEnvironment,
        missionStore: MissionStore,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        controlStore: MissionControlStore,
        generalSettings: GeneralSettingsStore,
        defaultLiveMapStyle: MapTileStyle,
        onBack: @escaping () -> Void,
        onUpdate: @escaping (MissionRunEnvironment) -> Void,
        onStart: @escaping (MissionRunEnvironment) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        _run = ObservedObject(wrappedValue: run)
        self.missionStore = missionStore
        self.fleetLink = fleetLink
        self.sitl = sitl
        self.controlStore = controlStore
        self.generalSettings = generalSettings
        self.onBack = onBack
        self.onUpdate = onUpdate
        self.onStart = onStart
        self.onDelete = onDelete
        _setupSelectedAssignmentId = State(initialValue: nil)
        _mapModel = StateObject(
            wrappedValue: GuardianMapModel(
                mapStyle: defaultLiveMapStyle,
                preserveView: true
            )
        )
        _logTemplateRegistry = ObservedObject(wrappedValue: MissionRunLogTemplateRegistry.shared)
    }

    private var rosterPickerSpring: Animation {
        .spring(response: 0.36, dampingFraction: 0.88)
    }

    /// Applies operator alter-step cap; toasts when the requested change exceeds the cap (Settings › Missions).
    private func clampedOperatorAlterStepSeconds(rawSeconds: Int, capSeconds: Int) -> Int {
        let add = MissionDelayPolicy.clampPostponeStepSeconds(rawSeconds, capSeconds: capSeconds)
        if rawSeconds > capSeconds {
            toastCenter.show(
                "Each Alter step is limited to \(MissionDelayPolicy.humanReadableDuration(seconds: TimeInterval(capSeconds))) (Settings › Missions).",
                style: .info
            )
        }
        return add
    }

    /// Clears ``rosterBulkSimSpawnWorkingAssignmentId`` after the roster card has had a chance to re-render as attached (avoids spinner vanishing before the SIM chrome appears).
    @MainActor
    private func clearRosterBulkSimSpawnWorkingAfterLayoutCatchup() async {
        await Task.yield()
        await Task.yield()
        rosterBulkSimSpawnWorkingAssignmentId = nil
    }

    /// Present the MC-R cog → mission policies + Rules-of-Engagement sidebar editor.
    private func presentRunControlsSidebar() {
        let anim = rosterPickerSpring
        appDrawer.present(
            title: "Run controls",
            preferredWidth: 420,
            scrimTapDismisses: true,
            animation: anim
        ) {
            ScrollView {
                MissionRunControlsSidebarView(
                    run: run,
                    missionStore: missionStore,
                    generalSettings: generalSettings,
                    onChange: {
                        syncRunFromStore()
                        onUpdate(run)
                    }
                )
            }
        }
    }

    private func presentMissionRosterVehiclePicker(assignmentId: UUID) {
        let anim = rosterPickerSpring
        appDrawer.present(
            title: nil,
            preferredWidth: 420,
            scrimTapDismisses: true,
            animation: anim
        ) {
            MissionRosterVehiclePickerSidebar(
                vehicles: buildMissionPickableVehicles(fleetLink: fleetLink, sitl: sitl),
                rowIsEnabled: { rosterPickDisabledReason($0, assignmentId: assignmentId) == nil },
                rowDisabledReason: { rosterPickDisabledReason($0, assignmentId: assignmentId) },
                onSelect: { v in
                    applyFleetVehicle(v, assignmentId: assignmentId)
                    appDrawer.dismiss(animation: anim)
                },
                onClose: {
                    appDrawer.dismiss(animation: anim)
                }
            )
        }
    }

    /// Vehicles → **Add Sim**–style picker; spawns SITL then binds the new instance to this roster slot.
    private func presentRosterSimPickerForAssignment(assignmentId: UUID) {
        rosterSimSidebarSpawnPlatform = generalSettings.defaultSimulationPlatform
        let anim = rosterPickerSpring
        appDrawer.present(
            title: nil,
            preferredWidth: 352,
            scrimTapDismisses: true,
            animation: anim
        ) {
            SimulationVehiclePickerSidebar(
                platform: $rosterSimSidebarSpawnPlatform,
                onSelect: { preset in
                    rosterBulkSimSpawnWorkingAssignmentId = assignmentId
                    let beforeIDs = Set(sitl.instances.map(\.id))
                    sitl.spawn(
                        preset: preset,
                        platform: rosterSimSidebarSpawnPlatform,
                        defaults: generalSettings.simSpawnDefaults
                    )
                    guard let inst = sitl.instances.first(where: { !beforeIDs.contains($0.id) }) else {
                        rosterBulkSimSpawnWorkingAssignmentId = nil
                        appDrawer.dismiss(animation: anim)
                        return
                    }
                    let systemID = inst.stackInstanceIndex + 1
                    let vehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
                    let resolvedShortID = fleetLink.vehicleModel(forVehicleID: vehicleID)?.displayShortID
                        ?? "\(inst.preset.fleetVehicleType.classCode):\(systemID)"
                    let lifecycle = fleetLink.vehicleStatus(forVehicleID: vehicleID)
                        ?? (inst.isAlive ? VehicleLifecycleStatus(stage: .awaitingTelemetry) : VehicleLifecycleStatus(stage: .stopped))
                    let pickable = MissionPickableFleetVehicle(
                        token: .sitl(inst.id),
                        title: inst.preset.displayName,
                        detailLine: inst.platform.displayName,
                        vehicleIDText: "\(systemID)",
                        vehicleShortID: resolvedShortID,
                        lifecycleStatus: lifecycle,
                        autopilotStack: FleetAutopilotStack(simulationPlatform: inst.platform),
                        domain: inst.preset.vehicleDomain,
                        simulationImageBasenames: inst.preset.simulationDeviceImageBasenames,
                        isSimulation: true
                    )
                    if rosterPickDisabledReason(pickable, assignmentId: assignmentId) == nil {
                        applyFleetVehicle(pickable, assignmentId: assignmentId)
                        onUpdate(run)
                        appDrawer.dismiss(animation: anim)
                        Task { await clearRosterBulkSimSpawnWorkingAfterLayoutCatchup() }
                    } else {
                        rosterBulkSimSpawnWorkingAssignmentId = nil
                        appDrawer.dismiss(animation: anim)
                    }
                },
                onClose: {
                    appDrawer.dismiss(animation: anim)
                }
            )
        }
    }

    private func presentTaskSettingsSidebar(task: MissionTask) {
        let anim = rosterPickerSpring
        appDrawer.present(
            title: nil,
            preferredWidth: 400,
            scrimTapDismisses: true,
            animation: anim
        ) {
            AppDrawerChrome(title: "Task settings", onClose: { appDrawer.dismiss(animation: anim) }) {
                MissionRunTaskPolicyOverridesSidebarView(
                    run: run,
                    missionStore: missionStore,
                    generalSettings: generalSettings,
                    taskId: task.id,
                    taskName: task.name,
                    onChange: {
                        syncRunFromStore()
                        onUpdate(run)
                    }
                )
            }
        }
    }

    private func presentAssignmentSettingsSidebar(assignmentIndex: Int) {
        presentAssignmentSettingsSidebar(assignmentID: run.assignments[assignmentIndex].id)
    }

    /// Id-based variant used by the MC-R vehicle overlay (and any other site that holds a stable id
    /// rather than a positional index, which can shift if the roster is mutated under us).
    private func presentAssignmentSettingsSidebar(assignmentID: UUID) {
        guard let assignment = run.assignments.first(where: { $0.id == assignmentID }) else { return }
        let anim = rosterPickerSpring
        let slotTitle = assignment.slotName
        appDrawer.present(
            title: nil,
            preferredWidth: 400,
            scrimTapDismisses: true,
            animation: anim
        ) {
            AppDrawerChrome(title: "Slot settings", onClose: { appDrawer.dismiss(animation: anim) }) {
                MissionRunAssignmentPolicyOverridesSidebarView(
                    run: run,
                    generalSettings: generalSettings,
                    assignmentId: assignmentID,
                    slotTitle: slotTitle,
                    onChange: {
                        syncRunFromStore()
                        onUpdate(run)
                    }
                )
            }
        }
    }

    /// Empty roster slots across every task plus legacy mission roster rows.
    private func emptyRosterSlotCountAcrossMission(mission: Mission) -> Int {
        var n = 0
        for task in mission.routeMacro.tasks {
            let indices = run.assignments.indices.filter {
                missionRunAssignmentBelongsToTask(run.assignments[$0], task: task, mission: mission)
            }
            n += indices.filter { !run.assignments[$0].hasFleetOrLegacyAssignment }.count
        }
        n += legacyUnassignedIndices.filter { !run.assignments[$0].hasFleetOrLegacyAssignment }.count
        return n
    }

    /// Spawns and assigns one built-in SITL per empty slot along ``rows`` (caller owns busy / confirm UI).
    private func bulkSpawnAndAssignAlongOrderedRows(
        _ rows: [(assignmentIndex: Int, indent: Int)],
        mission: Mission
    ) async -> Bool {
        var assignedAny = false
        for row in rows {
            let idx = row.assignmentIndex
            guard run.assignments.indices.contains(idx) else { continue }
            guard !run.assignments[idx].hasFleetOrLegacyAssignment else { continue }
            let assignment = run.assignments[idx]
            rosterBulkSimSpawnWorkingAssignmentId = assignment.id
            await Task.yield()
            let rosterClass = mission.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId })?.vehicleClass ?? .unknown
            let preset = rosterClass.builtInSimulationVehiclePreset
            let platform = generalSettings.defaultSimulationPlatform
            let defaults = generalSettings.simSpawnDefaults
            let beforeIDs = Set(sitl.instances.map(\.id))
            sitl.spawn(preset: preset, platform: platform, defaults: defaults)
            await Task.yield()
            guard let inst = sitl.instances.first(where: { !beforeIDs.contains($0.id) }) else {
                rosterBulkSimSpawnWorkingAssignmentId = nil
                continue
            }
            let systemID = inst.stackInstanceIndex + 1
            let vehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
            let resolvedShortID = fleetLink.vehicleModel(forVehicleID: vehicleID)?.displayShortID
                ?? "\(inst.preset.fleetVehicleType.classCode):\(systemID)"
            let lifecycle = fleetLink.vehicleStatus(forVehicleID: vehicleID)
                ?? (inst.isAlive ? VehicleLifecycleStatus(stage: .awaitingTelemetry) : VehicleLifecycleStatus(stage: .stopped))
            let pickable = MissionPickableFleetVehicle(
                token: .sitl(inst.id),
                title: inst.preset.displayName,
                detailLine: inst.platform.displayName,
                vehicleIDText: "\(systemID)",
                vehicleShortID: resolvedShortID,
                lifecycleStatus: lifecycle,
                autopilotStack: FleetAutopilotStack(simulationPlatform: inst.platform),
                domain: inst.preset.vehicleDomain,
                simulationImageBasenames: inst.preset.simulationDeviceImageBasenames,
                isSimulation: true
            )
            guard rosterPickDisabledReason(pickable, assignmentId: assignment.id) == nil else {
                rosterBulkSimSpawnWorkingAssignmentId = nil
                continue
            }
            applyFleetVehicle(pickable, assignmentId: assignment.id)
            assignedAny = true
            await clearRosterBulkSimSpawnWorkingAfterLayoutCatchup()
        }
        return assignedAny
    }

    /// One built-in SITL per empty roster slot for this task (after confirm): preset from ``RosterDevice/vehicleClass``, stack + spawn from ``GeneralSettingsStore``.
    private func performBulkSpawnSitlForEmptyRosterSlots(task: MissionTask, mission: Mission) async {
        guard fleetLink.isSimulateEnabled else { return }
        rosterBulkSimSpawnBusy = .singleTask(task.id)
        defer {
            rosterBulkSimSpawnBusy = nil
            rosterBulkSimSpawnWorkingAssignmentId = nil
        }
        let rows = missionRunTaskRosterOrderedSlots(task: task, mission: mission)
        let assignedAny = await bulkSpawnAndAssignAlongOrderedRows(rows, mission: mission)
        if assignedAny {
            onUpdate(run)
        }
    }

    /// One built-in SITL per empty roster slot for **every** task and the legacy mission roster (after confirm).
    private func performBulkSpawnSitlForAllMissionSlots(mission: Mission) async {
        guard fleetLink.isSimulateEnabled else { return }
        rosterBulkSimSpawnBusy = .allMissionSlots
        defer {
            rosterBulkSimSpawnBusy = nil
            rosterBulkSimSpawnWorkingAssignmentId = nil
        }
        var assignedAny = false
        for task in mission.routeMacro.tasks {
            let rows = missionRunTaskRosterOrderedSlots(task: task, mission: mission)
            if await bulkSpawnAndAssignAlongOrderedRows(rows, mission: mission) {
                assignedAny = true
            }
        }
        let legacyRows = missionRunLegacyRosterOrderedSlots(mission: mission)
        if await bulkSpawnAndAssignAlongOrderedRows(legacyRows, mission: mission) {
            assignedAny = true
        }
        if assignedAny {
            onUpdate(run)
        }
    }

    private func syncRunFromStore() {
        guard let r = controlStore.runs.first(where: { $0.id == run.id }) else { return }
        r.refreshDerivedTaskStates()
    }

    private func bulkSpawnSimsConfirmMessagePlain(for scope: MissionRunBulkSpawnSimsConfirmKind) -> String {
        switch scope {
        case .singleTask(let taskID):
            if let mission = resolvedMission,
               let t = mission.routeMacro.tasks.first(where: { $0.id == taskID }) {
                return "Spawn one built-in simulator for each empty roster slot in “\(t.name)”? Each uses that slot’s vehicle class and your default simulation stack and spawn location from Settings."
            }
            return "Spawn one built-in simulator for each empty roster slot? Each uses that slot’s vehicle class and your default simulation stack and spawn location from Settings."
        case .allMissionSlots:
            return "Spawn a suitable sim for every empty roster slot? Each empty slot uses that slot’s vehicle class and your default simulation stack and spawn location from Settings."
        }
    }

    @ViewBuilder
    private func missionRunPresentedConfirmOverlayContent(_ kind: MissionRunPresentedConfirm) -> some View {
        Group {
            switch kind {
                case .deleteRun:
                    GuardianConfirmDanger(
                        title: "Delete “\(run.missionName)”?",
                        message: "This removes the run from Mission Control. The mission template is not deleted.",
                        cancelTitle: "Cancel",
                        confirmTitle: "Delete run",
                        onCancel: { presentedRunConfirm = nil },
                        onConfirm: {
                            let id = run.id
                            presentedRunConfirm = nil
                            onDelete(id)
                            onBack()
                        }
                    )
                case .skipScheduledMissionStart:
                    GuardianConfirm(
                        title: "Start mission now?",
                        message: confirmSkipScheduledMissionMessage,
                        cancelTitle: "Cancel",
                        confirmTitle: "Start now",
                        onCancel: { presentedRunConfirm = nil },
                        onConfirm: {
                            run.systems.scheduling.beginDeferredOneOffImmediately()
                            onStart(run)
                            syncRunFromStore()
                            onUpdate(run)
                            presentedRunConfirm = nil
                        }
                    )
                case .skipTaskStartDeferral:
                    GuardianConfirm(
                        title: "Start this task now?",
                        message: confirmSkipTaskStartDeferralMessage,
                        cancelTitle: "Cancel",
                        confirmTitle: "Start now",
                        onCancel: {
                            confirmSkipTaskStartDeferralTaskID = nil
                            presentedRunConfirm = nil
                        },
                        onConfirm: {
                            if let taskID = confirmSkipTaskStartDeferralTaskID {
                                run.systems.scheduling.skipMissionTaskStartDeferral(taskID: taskID)
                            }
                            confirmSkipTaskStartDeferralTaskID = nil
                            syncRunFromStore()
                            onUpdate(run)
                            presentedRunConfirm = nil
                        }
                    )
                case .bulkSpawnSims(let spawnScope):
                    GuardianConfirm(
                        title: "Spawn simulators?",
                        message: bulkSpawnSimsConfirmMessagePlain(for: spawnScope),
                        systemImage: "wand.and.stars",
                        cancelTitle: "Cancel",
                        confirmTitle: "Spawn",
                        onCancel: {
                            presentedRunConfirm = nil
                        },
                        onConfirm: {
                            presentedRunConfirm = nil
                            guard let mission = resolvedMission else { return }
                            switch spawnScope {
                            case .singleTask(let taskID):
                                guard let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }) else { return }
                                Task { @MainActor in
                                    await performBulkSpawnSitlForEmptyRosterSlots(task: task, mission: mission)
                                }
                            case .allMissionSlots:
                                Task { @MainActor in
                                    await performBulkSpawnSitlForAllMissionSlots(mission: mission)
                                }
                            }
                        }
                    )
                }
        }
    }

    /// Vertical rule between adjacent controls. `Divider()` in an `HStack` stretches to the full row height; a fixed `Rectangle` does not.
    private func compactVerticalControlSeparator() -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 16)
    }

    private func missionLiveTaskStateForeground(_ state: MissionTaskState) -> Color {
        switch state {
        case .compiling, .ready: return theme.textSecondary
        case .staging: return Color.cyan.opacity(0.95)
        case .executing: return Color.green.opacity(0.92)
        case .between: return Color.orange.opacity(0.9)
        case .recovery: return Color.orange.opacity(0.95)
        case .aborting: return Color.red.opacity(0.88)
        case .aborted: return Color.red.opacity(0.92)
        case .completed: return Color.blue.opacity(0.9)
        }
    }

    private func missionLiveTaskStateBadge(_ state: MissionTaskState) -> some View {
        Text(state.displayTitle.uppercased())
            .font(GuardianTypography.font(.mapWaypointMicroHeavy))
            .tracking(0.4)
            .padding(.horizontal, GuardianSpacing.xsTight)
            .padding(.vertical, GuardianSpacing.titleStackTight)
            .foregroundStyle(missionLiveTaskStateForeground(state))
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        Capsule()
                            .strokeBorder(missionLiveTaskStateForeground(state).opacity(0.35), lineWidth: 1)
                    )
            )
    }

    private func missionLiveTaskStateBanner(_ state: MissionTaskState) -> some View {
        HStack(spacing: GuardianSpacing.xs) {
            Circle()
                .fill(missionLiveTaskStateForeground(state))
                .frame(width: 7, height: 7)
            Text(state.displayTitle)
                .font(GuardianTypography.font(.inlineNoticeTitle))
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .padding(.vertical, GuardianSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(missionLiveTaskStateForeground(state).opacity(0.32), lineWidth: 1)
                )
        )
    }

    private func missionLiveTaskEndProtocolAcknowledgementVisible(for task: RoutePath) -> Bool {
        switch run.taskStateByTaskID[task.id] ?? .ready {
        case .recovery, .aborting: return true
        default: return false
        }
    }

    @ViewBuilder
    private func missionLiveTaskEndProtocolAcknowledgementBlock(task: RoutePath, compact: Bool) -> some View {
        switch run.taskStateByTaskID[task.id] ?? .ready {
        case .recovery:
            VStack(alignment: .leading, spacing: compact ? GuardianSpacing.xxs : GuardianSpacing.xsTight) {
                Text("When this task’s roster has finished recovery, confirm here.")
                    .font(GuardianTypography.denseAcknowledgementCaption(compact: compact))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                GuardianThemedButton(
                    title: "Recovery complete",
                    accent: .primary,
                    surface: .solid,
                    size: compact ? .small : .medium,
                    shape: .cornered,
                    action: {
                        run.acknowledgeTaskMissionEndRecovery(taskID: task.id)
                        onUpdate(run)
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, compact ? GuardianSpacing.micro : 0)
        case .aborting:
            VStack(alignment: .leading, spacing: compact ? GuardianSpacing.xxs : GuardianSpacing.xsTight) {
                Text("When this task’s roster has finished the abort protocol, confirm here.")
                    .font(GuardianTypography.denseAcknowledgementCaption(compact: compact))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                GuardianThemedButton(
                    title: "Abort protocol complete",
                    accent: .primary,
                    surface: .solid,
                    size: compact ? .small : .medium,
                    shape: .cornered,
                    action: {
                        run.acknowledgeTaskMissionEndAbort(taskID: task.id)
                        onUpdate(run)
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, compact ? GuardianSpacing.micro : 0)
        default:
            EmptyView()
        }
    }

    /// Matches ``AppDrawerChrome`` close control (hierarchical `xmark.circle.fill`).
    private func missionLiveSidebarStyleCloseButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(GuardianTypography.font(.heroGlyph18Medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.textSecondary)
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
        .keyboardShortcut(.cancelAction)
        .help("Close")
    }

    /// MC-R overlay header: plain hierarchical glyph (same weight as the close control), no bordered chip.
    private func missionLiveOverlayHeaderGlyphButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(GuardianTypography.font(.heroGlyph18Medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.textSecondary)
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
        .help(help)
    }

    /// Matches ``missionLiveSidebarStyleCloseButton`` weight; opens a settings sidebar (abort / complete policy overrides).
    /// `helpText` defaults to the task-overlay phrasing for the most common caller; vehicle-overlay callers
    /// override with slot-specific copy so the tooltip matches the sheet that opens.
    private func missionLiveSidebarStyleCogButton(
        helpText: String = "Task settings (abort & complete policy)",
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(GuardianTypography.font(.windowHeading16Medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.textSecondary)
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
        .help(helpText)
    }

    /// Vehicle overlay action that opens the shared Vehicle Inspector for the roster assignment.
    /// Uses telemetry/radio semantics because the inspector now includes calibration, preflight, and
    /// raw telemetry in one modal.
    private func missionLiveSidebarStyleVehicleInspectorButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(GuardianTypography.font(.windowHeading16Medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.textSecondary)
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
        .help("Open Vehicle Inspector")
    }

    private func missionLiveTaskProgressDerived(
        task: RoutePath,
        taskIndex: Int,
        mission: Mission,
        now: Date
    ) -> MissionLiveTaskProgressDerived {
        let hub = liveHubForTask(task: task, mission: mission)
        let taskActiveInCycle = run.activeCycleTaskIDs.contains(task.id)
        let tint = MissionTaskMapColor.swiftUIColor(forTaskIndex: taskIndex)
        let taskStartDef = run.taskStartDeferralByTaskID[task.id]
        let inTaskStartDeferral = task.enabled
            && run.status == .running
            && (taskStartDef.map { now < $0.startAt } ?? false)

        let missionFraction = missionLiveTaskFraction(task: task, taskActiveInCycle: taskActiveInCycle, hub: hub)
        let barFraction: Double
        let barTint: Color
        if inTaskStartDeferral, let def = taskStartDef {
            let remaining = def.startAt.timeIntervalSince(now)
            let elapsed = def.totalDelay - max(0, remaining)
            barFraction = def.totalDelay > 0 ? min(1, max(0, elapsed / def.totalDelay)) : 1
            barTint = Color.cyan.opacity(0.78)
        } else {
            barFraction = missionFraction
            barTint = task.enabled ? tint : Color.gray.opacity(0.35)
        }

        return MissionLiveTaskProgressDerived(
            hub: hub,
            taskActiveInCycle: taskActiveInCycle,
            tint: tint,
            inTaskStartDeferral: inTaskStartDeferral,
            taskStartDef: taskStartDef,
            barFraction: barFraction,
            barTint: barTint
        )
    }

    @ViewBuilder
    private func missionLiveTaskProgressCounterGroup(
        task: RoutePath,
        derived: MissionLiveTaskProgressDerived,
        now: Date,
        hero: Bool
    ) -> some View {
        let deferralFont = hero ? GuardianTypography.font(.telemetryMono13Regular) : GuardianTypography.font(.telemetryMono10Regular)
        let counterFont = hero
            ? GuardianTypography.relativeFixed(size: 15, weight: .regular, design: .monospaced, relativeTo: .headline)
            : GuardianTypography.font(.telemetryMono10Regular)
        let labelFont = hero ? GuardianTypography.font(.denseSubsection13Regular) : GuardianTypography.font(.denseCaption10Regular)
        let dashOpacity = hero ? 0.55 : 0.45

        if derived.inTaskStartDeferral, let taskStartDef = derived.taskStartDef {
            Text(formattedTaskStartDeferralStatus(
                remaining: max(0, taskStartDef.startAt.timeIntervalSince(now)),
                totalDelay: taskStartDef.totalDelay
            ))
            .font(deferralFont)
            .foregroundStyle(Color.cyan.opacity(0.9))
            .lineLimit(hero ? 3 : 2)
            .multilineTextAlignment(hero ? .center : .trailing)
        } else if derived.taskActiveInCycle, let hub = derived.hub, let tot = hub.missionProgressTotal, tot > 0,
                  let cur = hub.missionProgressCurrent
        {
            Text("\(cur)/\(tot)")
                .font(counterFont)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(hero ? .center : .trailing)
        } else if !task.enabled {
            Text("Off")
                .font(labelFont)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(hero ? .center : .trailing)
        } else {
            Text("—")
                .font(counterFont)
                .foregroundStyle(theme.textSecondary.opacity(dashOpacity))
                .multilineTextAlignment(hero ? .center : .trailing)
        }
    }

    @ViewBuilder
    private func missionLiveTaskProgressDeferralControls(
        task: RoutePath,
        taskStartDefForControls: MissionTaskStartDeferral,
        now: Date,
        hero: Bool
    ) -> some View {
        let controlSize: ControlSize = hero ? .regular : .small
        HStack(alignment: .center, spacing: hero ? GuardianSpacing.denseGutter : GuardianSpacing.xs) {
            Spacer(minLength: 0)
            MissionDelayPostponeValueUnitRow(
                postponeLabelColor: theme.textPrimary,
                value: $taskStartDeferralPostponeValue,
                unit: $taskStartDeferralPostponeUnit,
                minimumTotalSeconds: 1,
                maximumTotalSeconds: TimeInterval(generalSettings.missionControlPostponeStepCapSeconds),
                numericFieldWidth: hero ? 96 : 88,
                unitPickerWidth: hero ? 72 : 68,
                controlSize: controlSize
            )
            Button("Sooner") {
                let raw = Int(
                    MissionDelayPolicy.totalSeconds(
                        value: taskStartDeferralPostponeValue,
                        unit: taskStartDeferralPostponeUnit
                    ).rounded()
                )
                let step = clampedOperatorAlterStepSeconds(
                    rawSeconds: raw,
                    capSeconds: generalSettings.missionControlPostponeStepCapSeconds
                )
                run.systems.scheduling.adjustMissionTaskStartDeferralBySeconds(
                    taskID: task.id,
                    deltaSeconds: -step,
                    referenceNow: now
                )
                syncRunFromStore()
                onUpdate(run)
            }
            .buttonStyle(.borderedProminent).guardianPointerOnHover()
            .tint(.blue)
            .controlSize(controlSize)
            Button("Later") {
                let raw = Int(
                    MissionDelayPolicy.totalSeconds(
                        value: taskStartDeferralPostponeValue,
                        unit: taskStartDeferralPostponeUnit
                    ).rounded()
                )
                let step = clampedOperatorAlterStepSeconds(
                    rawSeconds: raw,
                    capSeconds: generalSettings.missionControlPostponeStepCapSeconds
                )
                run.systems.scheduling.adjustMissionTaskStartDeferralBySeconds(
                    taskID: task.id,
                    deltaSeconds: step,
                    referenceNow: now
                )
                syncRunFromStore()
                onUpdate(run)
            }
            .buttonStyle(.borderedProminent).guardianPointerOnHover()
            .tint(.blue)
            .controlSize(controlSize)
            compactVerticalControlSeparator()
                .padding(.horizontal, hero ? GuardianSpacing.xs : GuardianSpacing.xsTight)
            Button("Start") {
                let rough = humanizedRoughTimeUntilScheduledStart(
                    executeAt: taskStartDefForControls.startAt,
                    from: now
                )
                confirmSkipTaskStartDeferralTaskID = task.id
                confirmSkipTaskStartDeferralMessage =
                    "This task’s MAVLink mission is scheduled to start in \(rough). Start it immediately?"
                presentedRunConfirm = .skipTaskStartDeferral
            }
            .buttonStyle(.borderedProminent).guardianPointerOnHover()
            .tint(.blue)
            .controlSize(controlSize)
            if hero {
                Spacer(minLength: 0)
            }
        }
        .fixedSize(horizontal: !hero, vertical: true)
        .frame(maxWidth: .infinity, alignment: hero ? .center : .trailing)
    }

    /// Operator **Trigger** only when the task is not already in an active MAVLink cycle (see ``MissionTaskState/executing``).
    private func showMissionTaskTrigger(for task: RoutePath) -> Bool {
        guard run.status == .running, task.enabled, task.regularity == .operatorTriggered else { return false }
        return run.taskStateByTaskID[task.id] != .executing
    }

    private func missionLiveTaskProgressTriggerControl(task: RoutePath, hero: Bool) -> some View {
        let controlSize: ControlSize = hero ? .regular : .small
        return Button("Trigger") {
            if run.startMissionTask(taskID: task.id) {
                toastCenter.show("Task cycle starting: \(task.name)", style: .info)
            } else {
                toastCenter.show(
                    "Could not start that task — check each slot has a primary vehicle with token, task has waypoints, and the mission log for planner errors.",
                    style: .error
                )
            }
            syncRunFromStore()
            onUpdate(run)
        }
        .buttonStyle(.borderedProminent).guardianPointerOnHover()
        .tint(.blue)
        .controlSize(controlSize)
    }

    private func missionLiveTaskWindDownSectionVisible(task: RoutePath, now: Date) -> Bool {
        guard task.enabled else { return false }
        guard !run.assignmentsBoundToMissionTask(taskID: task.id).isEmpty else { return false }
        guard run.status == .running || run.status == .paused else { return false }
        let a = missionLiveTaskWindDownAvailability(task: task, now: now)
        return a.revokeTaskGraceful || a.abortNow || a.abortGraceful || a.completeNow || a.completeGraceful
    }

    private func missionLiveTaskWindDownAvailability(task: RoutePath, now: Date) -> MissionLiveTaskWindDownAvailability {
        let pending = run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id]
        let revokeTaskGraceful = pending != nil

        let hasSlots = !run.assignmentsBoundToMissionTask(taskID: task.id).isEmpty
        let runActive = run.status == .running || run.status == .paused
        let inExecutingPhase = run.sessionPhase == .executing
        let state = run.taskStateByTaskID[task.id] ?? .ready
        let wholeRunGraceful = run.gracefulStopKind != .none
        let abortIssued = run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id)
        let completeIssued = run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id)
        let taskStartDef = run.taskStartDeferralByTaskID[task.id]
        let inStartDeferral = task.enabled && run.status == .running && (taskStartDef.map { now < $0.startAt } ?? false)

        let baseAPI = task.enabled
            && hasSlots
            && runActive
            && inExecutingPhase
            && !wholeRunGraceful

        let protocolBlocksNewWindDown: Bool = {
            switch state {
            case .recovery, .aborting, .completed, .aborted:
                return true
            default:
                return false
            }
        }()

        let blockedByIssued = abortIssued || completeIssued

        var abortNow = baseAPI && !protocolBlocksNewWindDown && !blockedByIssued
        var abortGraceful = baseAPI && !protocolBlocksNewWindDown && !blockedByIssued && !inStartDeferral
        var completeNow = baseAPI && !protocolBlocksNewWindDown && !blockedByIssued
        var completeGraceful = baseAPI && !protocolBlocksNewWindDown && !blockedByIssued && !inStartDeferral

        switch pending {
        case .some(.abortAfterCycle):
            completeNow = false
            completeGraceful = false
            abortGraceful = false
        case .some(.completeAfterCycle):
            abortNow = false
            abortGraceful = false
            completeGraceful = false
        case .none:
            break
        }

        return MissionLiveTaskWindDownAvailability(
            abortNow: abortNow,
            abortGraceful: abortGraceful,
            completeNow: completeNow,
            completeGraceful: completeGraceful,
            revokeTaskGraceful: revokeTaskGraceful
        )
    }

    @ViewBuilder
    private func missionLiveTaskWindDownActionsSection(task: RoutePath, now: Date) -> some View {
        let a = missionLiveTaskWindDownAvailability(task: task, now: now)
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            Text("Path wind-down")
                .font(GuardianTypography.font(.denseCaption10Semibold))
                .foregroundStyle(theme.textSecondary)
            Text("Abort and complete are opposite intents — only one graceful end-of-cycle schedule at a time for this path.")
                .font(GuardianTypography.font(.denseCaption10Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: GuardianSpacing.xs) {
                Button("Abort now") {
                    applyTaskAbortNow(task: task)
                }
                .buttonStyle(.borderedProminent).guardianPointerOnHover()
                .tint(.red)
                .controlSize(.small)
                .disabled(!a.abortNow)
                .help(
                    a.abortNow
                        ? "Issue abort-policy fleet commands for this path’s slots immediately."
                        : "Unavailable while another intent blocks it, this path is in recovery/abort protocol, a whole-run end-of-cycle stop is active, or the run is not executing."
                )
                Button("Abort after cycle") {
                    applyTaskAbortGraceful(task: task)
                }
                .buttonStyle(.borderedProminent).guardianPointerOnHover()
                .tint(.red)
                .controlSize(.small)
                .disabled(!a.abortGraceful)
                .help(
                    a.abortGraceful
                        ? "Schedule abort-policy commands at the next shared autopilot mission cycle end for this path only."
                        : "Unavailable if complete-after-cycle is already scheduled, during MAVLink start deferral, or while a whole-run graceful stop is active."
                )
            }
            HStack(spacing: GuardianSpacing.xs) {
                Button("Complete now") {
                    applyTaskCompleteNow(task: task)
                }
                .buttonStyle(.borderedProminent).guardianPointerOnHover()
                .tint(.blue)
                .controlSize(.small)
                .disabled(!a.completeNow)
                .help(
                    a.completeNow
                        ? "Issue complete-policy recovery wind-down for this path’s slots immediately."
                        : "Unavailable while another intent blocks it, this path is in recovery/abort protocol, a whole-run end-of-cycle stop is active, or the run is not executing."
                )
                Button("Complete after cycle") {
                    applyTaskCompleteGraceful(task: task)
                }
                .buttonStyle(.borderedProminent).guardianPointerOnHover()
                .tint(.blue)
                .controlSize(.small)
                .disabled(!a.completeGraceful)
                .help(
                    a.completeGraceful
                        ? "Schedule recovery wind-down at the next shared autopilot mission cycle end for this path only."
                        : "Unavailable if abort-after-cycle is already scheduled, during MAVLink start deferral, or while a whole-run graceful stop is active."
                )
            }
            if a.revokeTaskGraceful {
                Button("Revoke scheduled path wind-down") {
                    applyTaskRevokeGracefulWindDown(task: task)
                }
                .buttonStyle(.borderedProminent).guardianPointerOnHover()
                .tint(.red)
                .controlSize(.small)
                .help("Cancel the scheduled end-of-cycle wind-down for this path only (does not change a whole-run graceful stop).")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, GuardianSpacing.xs)
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func applyTaskAbortNow(task: RoutePath) {
        run.attachServices(fleetLink: fleetLink, sitl: sitl)
        if run.abortMissionTask(.task(task.id)) {
            toastCenter.show("Abort issued for path \"\(task.name)\".", style: .info)
        } else {
            toastCenter.show("Could not abort this path — check the mission log and that the run is executing.", style: .error)
        }
        syncRunFromStore()
        onUpdate(run)
    }

    private func applyTaskAbortGraceful(task: RoutePath) {
        if run.abortMissionTaskGraceful(.task(task.id)) {
            toastCenter.show("Abort after cycle scheduled for path \"\(task.name)\".", style: .info)
        } else {
            toastCenter.show("Could not schedule path abort after cycle — a whole-run stop may be active or there are no bound slots.", style: .error)
        }
        syncRunFromStore()
        onUpdate(run)
    }

    private func applyTaskCompleteNow(task: RoutePath) {
        run.attachServices(fleetLink: fleetLink, sitl: sitl)
        if run.completeMissionTask(.task(task.id)) {
            toastCenter.show("Complete wind-down issued for path \"\(task.name)\".", style: .info)
        } else {
            toastCenter.show("Could not complete this path — check policies, the mission log, and that the run is executing.", style: .error)
        }
        syncRunFromStore()
        onUpdate(run)
    }

    private func applyTaskCompleteGraceful(task: RoutePath) {
        if run.completeMissionTaskGraceful(.task(task.id)) {
            toastCenter.show("Complete after cycle scheduled for path \"\(task.name)\".", style: .info)
        } else {
            toastCenter.show("Could not schedule path complete after cycle — a whole-run stop may be active or there are no bound slots.", style: .error)
        }
        syncRunFromStore()
        onUpdate(run)
    }

    private func applyTaskRevokeGracefulWindDown(task: RoutePath) {
        run.revokeMissionTaskGracefulWindDown(forTaskID: task.id)
        toastCenter.show("Revoked scheduled wind-down for path \"\(task.name)\".", style: .info)
        syncRunFromStore()
        onUpdate(run)
    }

    private func missionLiveTaskTriageProgressHero(task: RoutePath, taskIndex: Int, mission: Mission, now: Date) -> some View {
        let d = missionLiveTaskProgressDerived(task: task, taskIndex: taskIndex, mission: mission, now: now)
        return VStack(spacing: GuardianSpacing.sectionStack) {
            missionLiveTaskProgressCounterGroup(task: task, derived: d, now: now, hero: true)
                .frame(maxWidth: .infinity, alignment: .center)
            missionLiveAnimatedProgressBar(
                fraction: d.barFraction,
                tint: d.barTint,
                height: 11
            )
            .frame(maxWidth: .infinity)

            if d.inTaskStartDeferral, let taskStartDefForControls = d.taskStartDef {
                missionLiveTaskProgressDeferralControls(
                    task: task,
                    taskStartDefForControls: taskStartDefForControls,
                    now: now,
                    hero: true
                )
                .padding(.top, GuardianSpacing.xxs)
            } else if showMissionTaskTrigger(for: task) {
                HStack {
                    Spacer(minLength: 0)
                    missionLiveTaskProgressTriggerControl(task: task, hero: true)
                    Spacer(minLength: 0)
                }
                .padding(.top, GuardianSpacing.xxs)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func refreshVehicleVoiceNarrativeFromTelemetry() {
        syncRunFromStore()
        guard run.status == .running || run.status == .paused else { return }
        let mission = missionStore.missions.first { $0.id == run.missionId }
        run.systems.logging.ingestVehicleTelemetryNarrative(
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    private func applyAbortImmediate() {
        run.attachServices(fleetLink: fleetLink, sitl: sitl)
        run.systems.scheduling.abortNow()
        onUpdate(run)
        syncRunFromStore()
    }

    private func applyAbortAfterCycle() {
        run.systems.scheduling.abortAfterCycle()
        onUpdate(run)
        syncRunFromStore()
    }

    private func applyCompleteImmediate() {
        run.attachServices(fleetLink: fleetLink, sitl: sitl)
        run.systems.scheduling.completeNow()
        onUpdate(run)
        syncRunFromStore()
    }

    private func applyCompleteAfterCycle() {
        run.systems.scheduling.completeAfterCycle()
        onUpdate(run)
        syncRunFromStore()
    }

    private func applyRevokeGracefulStopIntent() {
        run.systems.scheduling.revokeGracefulAfterCycleStop()
        onUpdate(run)
        syncRunFromStore()
    }

    private func applyResetToSetup() {
        controlStore.resetRunToSetup(id: run.id)
        syncRunFromStore()
    }

    private func isSimulationVehicleID(_ vehicleID: String) -> Bool {
        sitl.instances.contains { inst in
            let sid = inst.stackInstanceIndex + 1
            let resolved = fleetLink.vehicleID(forSystemID: sid) ?? "sysid:\(sid)"
            return resolved == vehicleID
        }
    }

    private var assignedSimulationVehicleIDs: [String] {
        Array(
            Set(
                run.assignments.compactMap { assignment in
                    guard let vid = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
                          isSimulationVehicleID(vid)
                    else { return nil }
                    return vid
                }
            )
        )
    }

    /// Mission Control Running owns SIM battery drain policy for this run:
    /// running => drain on, otherwise off.
    private func syncSimBatteryDrainForRunStatus() {
        let enableDrain = (run.status == .running)
        for vehicleID in assignedSimulationVehicleIDs {
            fleetLink.setSimBatteryDrainEnabled(
                vehicleID: vehicleID,
                enabled: enableDrain,
                rate: generalSettings.defaultSimBatteryDrainRate,
                source: "missionControl.runStatus.\(run.status.rawValue)",
                onResult: nil
            )
        }
    }

    private var resolvedMission: Mission? {
        missionStore.missions.first { $0.id == run.missionId }
    }

    /// Fleet stream id for the assignment bound to this task (legacy single-task runs may use a nil `taskId` slot).
    private func resolvedLiveVehicleID(forTask task: RoutePath, mission: Mission) -> String? {
        let assignment =
            run.assignments.first(where: { $0.taskId == task.id })
            ?? {
                let enabled = mission.routeMacro.tasks.filter(\.enabled)
                if enabled.count == 1, enabled.first?.id == task.id {
                    return run.assignments.first(where: { $0.taskId == nil }) ?? run.assignments.first
                }
                return nil
            }()
        guard let assignment else { return nil }
        return resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl)
    }

    private func liveHubForTask(task: RoutePath, mission: Mission) -> FleetHubVehicleTelemetry? {
        guard let id = resolvedLiveVehicleID(forTask: task, mission: mission) else { return nil }
        return fleetLink.hubTelemetry(forVehicleID: id)
    }

    /// Latest MAVLink mission progress tick across all enabled task vehicles (keeps multi-task progress UI fresh).
    private var liveMissionProgressPulseDate: Date? {
        guard let mission = resolvedMission else { return nil }
        var latest: Date?
        for task in mission.routeMacro.tasks where task.enabled {
            guard let d = liveHubForTask(task: task, mission: mission)?.lastUpdate else { continue }
            latest = latest.map { max($0, d) } ?? d
        }
        return latest
    }

    /// Live log lines for MC-R: all events when no task focus; when focused, task-tagged lines **plus** vehicle
    /// narrative for roster slots tied to that task (same rules as ``filteredLiveRosterAssignments``), so
    /// telemetry lines are not dropped when role-track context omitted `taskID` on the event.
    private var liveLogEventsFiltered: [MissionRunEvent] {
        let events = run.events
        guard let focus = focusedLiveTaskID else { return events }
        guard let mission = resolvedMission else {
            return events.filter { $0.taskID == focus }
        }
        let focusedSlots = Set(
            run.assignments
                .filter { assignmentMatchesLiveFocus($0, mission: mission) }
                .map(\.slotName)
        )
        return events.filter { event in
            if event.taskID == focus { return true }
            if event.taskID == nil, case .vehicleSlot(let slot) = event.speaker {
                return focusedSlots.contains(slot)
            }
            return false
        }
    }

    /// Last event id in the live log strip (suffix window) — drives auto-scroll to the latest line.
    private var liveLogVisibleTailAnchorID: UUID? {
        liveLogEventsFiltered.suffix(80).last?.id
    }

    private var bulkSpawnSimsConfirmIsActive: Bool {
        if case .bulkSpawnSims = presentedRunConfirm { return true }
        return false
    }

    private func assignmentMatchesLiveFocus(_ assignment: MissionRunAssignment, mission: Mission) -> Bool {
        guard let focus = focusedLiveTaskID else { return true }
        if assignment.taskId == focus { return true }
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        if enabled.count == 1, enabled.first?.id == focus {
            return assignment.taskId == nil || assignment.taskId == focus
        }
        return false
    }

    /// Roster slots shown in MC-R when a task is focused (matches Paladin / store single-task fallback).
    private var filteredLiveRosterAssignments: [MissionRunAssignment] {
        guard let mission = resolvedMission else { return Array(run.assignments) }
        return run.assignments.filter { assignmentMatchesLiveFocus($0, mission: mission) }
    }

    private func syncRecoveryPromptIfNeeded() {
        guard run.status == .recovery, !dismissedRecoveryStatusPrompt else { return }
        guard bottomPromptCenter.activePrompt == nil else { return }
        bottomPromptCenter.present(
            "Recovery in progress. When fleet recovery actions are finished, mark this run completed.",
            style: .info,
            onDismiss: { dismissedRecoveryStatusPrompt = true }
        )
    }

    private func syncAbortSessionPromptIfNeeded() {
        guard run.status == .running || run.status == .paused else { return }
        guard run.sessionPhase == .aborting || run.sessionPhase == .aborted else { return }
        guard !dismissedAbortStatusPrompt else { return }
        guard bottomPromptCenter.activePrompt == nil else { return }
        bottomPromptCenter.present(
            "Abort protocol in progress. When fleet actions for your abort policy are finished and task confirmations are done, mark this run completed.",
            style: .info,
            onDismiss: { dismissedAbortStatusPrompt = true }
        )
    }

    private func syncGracefulStopPromptIfNeeded() {
        guard run.gracefulStopKind != .none, run.status == .running || run.status == .paused else { return }
        guard run.status != .recovery else { return }
        guard run.sessionPhase != .aborting, run.sessionPhase != .aborted else { return }
        guard bottomPromptCenter.activePrompt == nil else { return }
        let message: String = {
            switch run.gracefulStopKind {
            case .abortAfterCycle:
                return "This run will stop after the current autopilot mission cycle using your abort policy (hold, land, return to launch, or none). No further mission cycles will be scheduled."
            case .completeAfterCycle:
                return "This run will stop after the current autopilot mission cycle for recovery using your complete policy (hold, land, return to launch, or none) on bound slots. When recovery is done, mark the run completed from the recovery screen."
            case .none:
                return ""
            }
        }()
        guard !message.isEmpty else { return }
        bottomPromptCenter.presentChoice(
            message,
            style: .warning,
            confirmTitle: "Keep running",
            dismissTitle: "Dismiss",
            onConfirm: {
                applyRevokeGracefulStopIntent()
            },
            onDismiss: nil
        )
    }

    /// Camera vs map for MC-R live console (icons only — segmented control lives in the title bar).
    private var missionLiveMediaModeSubBarToggle: some View {
        let activeFill = theme.backgroundElevated.opacity(0.55)
        return HStack(spacing: GuardianSpacing.micro) {
            Button {
                liveConsoleMediaTab = .map
            } label: {
                Image(systemName: "map.fill")
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(liveConsoleMediaTab == .map ? theme.textPrimary : theme.textTertiary)
                    .frame(width: 30, height: 26)
                    .background(liveConsoleMediaTab == .map ? activeFill : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(GuardianPointerPlainButtonStyle())
            .accessibilityLabel("Map")

            Button {
                liveConsoleMediaTab = .camera
            } label: {
                Image(systemName: "video.fill")
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(liveConsoleMediaTab == .camera ? theme.textPrimary : theme.textTertiary)
                    .frame(width: 30, height: 26)
                    .background(liveConsoleMediaTab == .camera ? activeFill : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(GuardianPointerPlainButtonStyle())
            .accessibilityLabel("Camera")
        }
        .padding(GuardianSpacing.titleStackTight)
        .background(theme.borderSubtle.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var allRosterFilled: Bool {
        run.assignments.allSatisfy(\.hasFleetOrLegacyAssignment)
    }

    private func canStart(referenceNow: Date) -> Bool {
        guard allRosterFilled else { return false }
        if run.oneOffStartAt != nil, run.oneOffScheduledTimeTooFarInPast(referenceNow: referenceNow) {
            return false
        }
        return true
    }

    @ViewBuilder
    private func runSetupActionButtons(referenceNow: Date) -> some View {
        HStack(spacing: GuardianSpacing.denseGutter) {
            GuardianThemedButton(
                title: "Start Run",
                accent: .primary,
                surface: .solid,
                size: .small,
                shape: .cornered,
                isEnabled: canStart(referenceNow: referenceNow),
                action: { startPreflightPresented = true }
            )

            GuardianDestructiveProminentButton(title: "Delete Run") {
                presentedRunConfirm = .deleteRun
            }
        }
    }

    /// ``Menu`` label chip aligned with ``GuardianThemedButton`` outline geometry.
    private func runDetailToolbarMenuChip(_ title: String) -> some View {
        Text(title)
            .font(GuardianTypography.font(.inlineNoticeTitle))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, GuardianSpacing.denseGutter)
            .frame(height: 28)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.borderSubtle, lineWidth: 1.5)
            )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: GuardianSpacing.md) {
                        HStack(spacing: GuardianSpacing.sm) {
                            GuardianThemedButton(
                                accent: .neutral,
                                surface: .outline,
                                size: .small,
                                shape: .cornered,
                                contentSizing: .squareToolbarCell,
                                action: onBack,
                                label: {
                                    Image(systemName: "arrow.left")
                                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                                }
                            )
                            .help("Back to runs")

                            Text(run.missionName)
                                .font(GuardianTypography.font(.panelEmphasisTitleBold))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)

                            if run.status == .running || run.status == .paused || run.status == .recovery {
                                missionLiveMediaModeSubBarToggle
                            }

                            if run.status == .setup {
                                Picker("Mission setup", selection: $setupMainTab) {
                                    ForEach(MissionRunSetupTab.allCases) { tab in
                                        Text(tab.title).tag(tab)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(maxWidth: 380)
                                .accessibilityLabel("Mission setup section")
                            }
                        }

                        Spacer(minLength: GuardianSpacing.xs)

                        HStack(spacing: GuardianSpacing.denseGutter) {
                            if run.status == .setup {
                                if run.oneOffStartAt != nil {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        runSetupActionButtons(referenceNow: context.date)
                                    }
                                } else {
                                    runSetupActionButtons(referenceNow: Date())
                                }
                            } else if run.status == .recovery
                                || ((run.status == .running || run.status == .paused)
                                    && (run.sessionPhase == .aborting || run.sessionPhase == .aborted))
                            {
                                GuardianPrimaryProminentButton(title: "Mark Completed") {
                                    run.systems.lifecycle.markCompleted(kind: run.completionKind)
                                    syncRunFromStore()
                                    onUpdate(run)
                                }
                            } else if run.status == .running || run.status == .paused {
                                Menu {
                                    Button("Abort", role: .destructive) {
                                        applyAbortImmediate()
                                    }
                                    Button("Graceful abort", role: .destructive) {
                                        applyAbortAfterCycle()
                                    }
                                    Button("Complete") {
                                        applyCompleteImmediate()
                                    }
                                    Button("Graceful complete") {
                                        applyCompleteAfterCycle()
                                    }
                                } label: {
                                    runDetailToolbarMenuChip("Stop run")
                                }
                                .menuStyle(.borderlessButton)
                                .guardianPointerOnHover()

                                GuardianNeutralBorderedButton(
                                    systemImage: liveRuntimeMissionPointsOverlayPresented
                                        ? "mappin.circle.fill"
                                        : "mappin.and.ellipse",
                                    help: liveRuntimeMissionPointsOverlayPresented
                                        ? "Hide map points panel on the Tasks card"
                                        : "Runtime map points — shows the Tasks card panel to list or manage points for this run only (not saved to the mission file on disk)",
                                    action: {
                                        withAnimation(triageSheetSpring) {
                                            liveRuntimeMissionPointsOverlayPresented.toggle()
                                        }
                                    }
                                )

                                GuardianNeutralBorderedButton(
                                    systemImage: "gearshape",
                                    help: "Run policies & rules of engagement",
                                    action: { presentRunControlsSidebar() }
                                )
                            } else if run.status == .completed {
                                GuardianPrimaryProminentButton(title: "Back to setup") {
                                    applyResetToSetup()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, GuardianSpacing.sm)
                    .padding(.vertical, GuardianSpacing.xs)
                    .frame(maxWidth: .infinity)
                    .background(theme.backgroundRaised)

                    if run.status == .running, run.oneOffDeferredExecution != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if let deferred = run.oneOffDeferredExecution {
                                oneOffDeferredExecutionBanner(
                                    deferred: deferred,
                                    now: context.date,
                                    postponeValue: $scheduledStartPostponeValue,
                                    postponeUnit: $scheduledStartPostponeUnit,
                                    onAlterLater: {
                                        let raw = Int(
                                            MissionDelayPolicy.totalSeconds(
                                                value: scheduledStartPostponeValue,
                                                unit: scheduledStartPostponeUnit
                                            ).rounded()
                                        )
                                        let step = clampedOperatorAlterStepSeconds(
                                            rawSeconds: raw,
                                            capSeconds: generalSettings.missionControlPostponeStepCapSeconds
                                        )
                                        run.systems.scheduling.adjustDeferredOneOffExecutionBySeconds(
                                            step,
                                            referenceNow: context.date
                                        ) {
                                            onStart(run)
                                        }
                                        syncRunFromStore()
                                        onUpdate(run)
                                    },
                                    onAlterSooner: {
                                        let raw = Int(
                                            MissionDelayPolicy.totalSeconds(
                                                value: scheduledStartPostponeValue,
                                                unit: scheduledStartPostponeUnit
                                            ).rounded()
                                        )
                                        let step = clampedOperatorAlterStepSeconds(
                                            rawSeconds: raw,
                                            capSeconds: generalSettings.missionControlPostponeStepCapSeconds
                                        )
                                        run.systems.scheduling.adjustDeferredOneOffExecutionBySeconds(
                                            -step,
                                            referenceNow: context.date
                                        ) {
                                            onStart(run)
                                        }
                                        syncRunFromStore()
                                        onUpdate(run)
                                    },
                                    onRequestStartNow: {
                                        if let def = run.oneOffDeferredExecution {
                                            let rough = humanizedRoughTimeUntilScheduledStart(
                                                executeAt: def.executeAt,
                                                from: Date()
                                            )
                                            confirmSkipScheduledMissionMessage =
                                                "This mission is scheduled to start in \(rough). Are you sure you want to start it now?"
                                            presentedRunConfirm = .skipScheduledMissionStart
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                if run.status == .setup {
                    Group {
                        if setupMainTab == .rosters {
                            setupRostersTabContent
                                .padding(.horizontal, MissionRunPrepLayout.setupScrollPaddingH)
                                .padding(.vertical, MissionRunPrepLayout.setupScrollPaddingV)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: MissionRunPrepLayout.setupBlockSpacing) {
                                    switch setupMainTab {
                                    case .timing:
                                        setupTimingTabContent
                                    case .rules:
                                        setupRulesTabContent
                                    case .rosters:
                                        EmptyView()
                                    }
                                }
                                .padding(.horizontal, MissionRunPrepLayout.setupScrollPaddingH)
                                .padding(.vertical, MissionRunPrepLayout.setupScrollPaddingV)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if run.status == .completed {
                    ScrollView {
                        VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                            missionCompletedReportCards
                            completedMissionLogExportSection
                        }
                        .padding(.horizontal, GuardianSpacing.xl)
                        .padding(.vertical, GuardianSpacing.sectionStack)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                        missionLiveConsole
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, GuardianSpacing.denseGutter)
                    .padding(.vertical, GuardianSpacing.denseGutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: fleetLink.hubTelemetry?.lastUpdate) { _ in
                        refreshVehicleVoiceNarrativeFromTelemetry()
                    }
                    .onChange(of: liveMissionProgressPulseDate) { _ in
                        refreshVehicleVoiceNarrativeFromTelemetry()
                    }
                    .onAppear {
                        refreshVehicleVoiceNarrativeFromTelemetry()
                    }
                    .onChange(of: focusedLiveTaskID) { _ in
                        pruneLiveRuntimeMapPointSelectionIfOutOfFilter()
                    }
                }
            }
        .background(theme.backgroundBase)
        .guardianConfirmOverlay(item: $presentedRunConfirm, onDismiss: {
            confirmSkipTaskStartDeferralTaskID = nil
        }, dialog: missionRunPresentedConfirmOverlayContent)
        .guardianConfirmOverlay(item: $setupRostersMissionPointDeleteCandidate, dialog: { candidate in
            GuardianConfirmDanger(
                title: "Delete map point?",
                message: "This removes the point from the mission template.",
                cancelTitle: "Cancel",
                confirmTitle: "Delete",
                onCancel: { setupRostersMissionPointDeleteCandidate = nil },
                onConfirm: {
                    persistMissionMutation { mission in
                        mission.missionPoints.removeAll { $0.id == candidate.id }
                        mission.renumberMissionPointSlugsByListOrder()
                    }
                    if setupRostersSelectedMissionPointID == candidate.id {
                        setupRostersSelectedMissionPointID = nil
                    }
                    if setupRostersMissionPointDrawerEditingID == candidate.id {
                        setupRostersMissionPointDrawerEditingID = nil
                        appDrawer.dismiss()
                    }
                    setupRostersMissionPointDeleteCandidate = nil
                    toastCenter.show("Map point removed", style: .success)
                }
            )
        })
        .sheet(isPresented: $startPreflightPresented) {
            MissionRunStartPreflightSheet(
                run: run,
                fleetLink: fleetLink,
                sitl: sitl,
                controlStore: controlStore,
                onSuccess: {
                    if let mission = resolvedMission {
                        let fleet = buildMissionPickableVehicles(fleetLink: fleetLink, sitl: sitl)
                        controlStore.compileMissionControlPlan(
                            run: run,
                            mission: mission,
                            fleetVehicles: fleet
                        )
                    }
                    run.status = .running
                    let deferOneOff: Bool = {
                        guard let t = run.oneOffStartAt else { return false }
                        return t.timeIntervalSince(Date()) > MissionRunEnvironment.oneOffScheduleTimeTolerance
                    }()
                    if deferOneOff, let executeAt = run.oneOffStartAt {
                        controlStore.updateRun(run)
                        run.systems.scheduling.scheduleDeferredOneOffExecution(executeAt: executeAt) {
                            onStart(run)
                        }
                    } else {
                        onStart(run)
                    }
                    syncRunFromStore()
                },
                onAbandonWithoutStart: {}
            )
        }
        .onAppear {
            run.attachServices(fleetLink: fleetLink, sitl: sitl)
            installMissionTemplatePersister()
            syncRunFromStore()
            mapModel.recenter()
            syncSimBatteryDrainForRunStatus()
            if run.status == .setup {
                pruneStaleRosterFleetAssignmentsIfNeeded()
            }
            syncRecoveryPromptIfNeeded()
            syncAbortSessionPromptIfNeeded()
            syncGracefulStopPromptIfNeeded()
        }
        .onChange(of: setupMapBoundsSignature) { _ in
            mapModel.recenter()
        }
        .onChange(of: sitlRosterPruneSignature) { _ in
            if run.status == .setup {
                pruneStaleRosterFleetAssignmentsIfNeeded()
            }
        }
        .onChange(of: fleetRosterPruneSignature) { _ in
            if run.status == .setup {
                pruneStaleRosterFleetAssignmentsIfNeeded()
            }
        }
        .onChange(of: run.status) { newStatus in
            syncSimBatteryDrainForRunStatus()
            if newStatus == .setup || newStatus == .completed {
                focusLiveTask(nil)
                focusLiveAssignment(nil)
                clearLiveRuntimeMissionPointsOverlayChrome()
                dismissedRecoveryStatusPrompt = false
                dismissedAbortStatusPrompt = false
                bottomPromptCenter.dismiss()
                if newStatus == .setup {
                    pruneStaleRosterFleetAssignmentsIfNeeded()
                }
                appDrawer.dismiss()
            } else if newStatus == .recovery {
                dismissedRecoveryStatusPrompt = false
                bottomPromptCenter.dismiss()
                syncRecoveryPromptIfNeeded()
                appDrawer.dismiss()
            } else {
                bottomPromptCenter.dismiss()
                appDrawer.dismiss()
            }
        }
        .onChange(of: run.sessionPhase) { newPhase in
            guard run.status == .running || run.status == .paused else { return }
            if newPhase == .aborting {
                dismissedAbortStatusPrompt = false
                bottomPromptCenter.dismiss()
                syncAbortSessionPromptIfNeeded()
                clearLiveRuntimeMissionPointsOverlayChrome()
                appDrawer.dismiss()
            } else if newPhase == .aborted {
                syncAbortSessionPromptIfNeeded()
            }
        }
        .onChange(of: setupMainTab) { newTab in
            appDrawer.dismiss()
            if newTab != .rosters {
                rostersSidebarListTab = .tasks
                clearSetupRostersMissionPointChrome()
            }
            if newTab == .rosters, rosterSetupExpandedTaskIDs.isEmpty, let mission = resolvedMission {
                rosterSetupExpandedTaskIDs = Set(mission.routeMacro.tasks.map(\.id))
            }
        }
        .onChange(of: rostersSidebarListTab) { newTab in
            if newTab == .tasks {
                appDrawer.dismiss()
                setupRostersMissionPointDrawerEditingID = nil
            }
        }
        .onChange(of: appDrawer.presented?.id) { newDrawerID in
            if newDrawerID == nil {
                setupRostersMissionPointDrawerEditingID = nil
                liveRuntimeMissionPointDrawerEditingID = nil
            }
        }
        .onChange(of: run.assignments) { _ in
            syncSimBatteryDrainForRunStatus()
        }
        .onChange(of: run.gracefulStopKind) { kind in
            if kind != .none {
                syncGracefulStopPromptIfNeeded()
            } else {
                bottomPromptCenter.dismiss()
            }
        }
        .onDisappear {
            appDrawer.dismiss()
            bottomPromptCenter.dismiss()
            for vehicleID in assignedSimulationVehicleIDs {
                fleetLink.setSimBatteryDrainEnabled(
                    vehicleID: vehicleID,
                    enabled: false,
                    rate: generalSettings.defaultSimBatteryDrainRate,
                    source: "missionControl.viewDisappear",
                    onResult: nil
                )
            }
            onUpdate(run)
        }

            if let vid = rosterCalibrationVehicleID {
                VehicleInspectorHostOverlay(onDismiss: {
                    rosterCalibrationVehicleID = nil
                    rosterCalibrationFallbackModel = nil
                }) {
                    VehicleCalibrationModal(
                        fleetLink: fleetLink,
                        controlStore: controlStore,
                        sitl: sitl,
                        vehicleID: vid,
                        fallback: rosterCalibrationFallbackModel,
                        onClose: {
                            rosterCalibrationVehicleID = nil
                            rosterCalibrationFallbackModel = nil
                        }
                    )
                    .environmentObject(toastCenter)
                }
                .transition(.opacity)
                // In-window modal above main run chrome, below bottom prompt (see shell z-order: content → modal → prompt).
                .zIndex(1)
            }

            GuardianBottomPromptBanner(center: bottomPromptCenter)
                .zIndex(2)
        }
    }

    /// SITL instances + aliveness — roster slots drop removed sims.
    private var sitlRosterPruneSignature: String {
        sitl.instances
            .map { "\($0.id.uuidString)|\($0.isAlive)" }
            .sorted()
            .joined(separator: ";")
    }

    /// Fleet vehicle keys + lifecycle stages — roster drops stopped / failed sessions.
    private var fleetRosterPruneSignature: String {
        let keys = fleetLink.vehicleModelsByVehicleID.keys.sorted().joined(separator: ",")
        let stages = fleetLink.vehicleStatusByVehicleID
            .map { "\($0.key):\($0.value.stage.rawValue)" }
            .sorted()
            .joined(separator: ";")
        return "\(keys)|\(stages)"
    }

    private func presentRosterCalibrationSheet(for assignment: MissionRunAssignment) {
        guard let vehicleID = telemetryVehicleID(for: assignment) else { return }
        rosterCalibrationVehicleID = vehicleID
        rosterCalibrationFallbackModel = fleetLink.vehicleModel(forVehicleID: vehicleID)
    }

    /// Clears fleet binding when the vehicle no longer exists in Vehicles or is stopped/failed.
    private func pruneStaleRosterFleetAssignmentsIfNeeded() {
        guard run.status == .setup else { return }
        var changed = false
        for assignment in run.assignments {
            guard assignment.attachedFleetVehicleToken != nil else { continue }
            guard let token = FleetMissionVehicleToken(storageKey: assignment.attachedFleetVehicleToken!) else { continue }

            if case .sitl(let uuid) = token {
                guard sitl.instances.contains(where: { $0.id == uuid }) else {
                    clearFleetVehicle(assignmentId: assignment.id)
                    changed = true
                    continue
                }
            }

            guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl) else {
                clearFleetVehicle(assignmentId: assignment.id)
                changed = true
                continue
            }

            if let stage = fleetLink.vehicleStatus(forVehicleID: vehicleID)?.stage,
               stage == .stopped || stage == .failed
            {
                clearFleetVehicle(assignmentId: assignment.id)
                changed = true
            }
        }
        if changed {
            onUpdate(run)
        }
    }

    private func rosterAutopilotStack(for assignment: MissionRunAssignment) -> FleetAutopilotStack? {
        guard assignment.attachedFleetVehicleToken != nil else { return nil }
        if let vid = telemetryVehicleID(for: assignment),
           let snap = fleetLink.vehicleModel(forVehicleID: vid)?.collections.telemetrySnapshot
        {
            return snap.autopilotStack
        }
        if let key = assignment.attachedFleetVehicleToken,
           let token = FleetMissionVehicleToken(storageKey: key),
           case .sitl(let uuid) = token,
           let inst = sitl.instances.first(where: { $0.id == uuid })
        {
            return FleetAutopilotStack(simulationPlatform: inst.platform)
        }
        return .unknown
    }

    private func rosterLifecycleStatus(for assignment: MissionRunAssignment) -> VehicleLifecycleStatus? {
        guard assignment.attachedFleetVehicleToken != nil else { return nil }
        guard let vid = telemetryVehicleID(for: assignment) else { return nil }
        return fleetLink.vehicleModel(forVehicleID: vid)?.collections.lifecycleStatus
            ?? fleetLink.vehicleStatus(forVehicleID: vid)
    }

    private func humanizedRoughTimeUntilScheduledStart(executeAt: Date, from now: Date) -> String {
        let secs = max(1, Int(ceil(executeAt.timeIntervalSince(now))))
        if secs < 90 {
            return secs == 1 ? "about 1 second" : "about \(secs) seconds"
        }
        let minutes = (secs + 59) / 60
        if minutes < 120 {
            return minutes == 1 ? "about 1 minute" : "about \(minutes) minutes"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        if remMin == 0 {
            return hours == 1 ? "about 1 hour" : "about \(hours) hours"
        }
        return "about \(hours) h \(remMin) min"
    }

    private func oneOffDeferredExecutionBanner(
        deferred: MissionOneOffDeferredExecution,
        now: Date,
        postponeValue: Binding<Double>,
        postponeUnit: Binding<DelayUnit>,
        onAlterLater: @escaping () -> Void,
        onAlterSooner: @escaping () -> Void,
        onRequestStartNow: @escaping () -> Void
    ) -> some View {
        let remaining = max(0, deferred.executeAt.timeIntervalSince(now))
        let total = max(deferred.executeAt.timeIntervalSince(deferred.countdownStartedAt), 0.001)
        let progress = 1 - min(1, max(0, remaining / total))
        return GuardianInlineNotice(
            kind: .informational,
            title: "Scheduled mission start",
            detail:
                "Execution begins \(deferred.executeAt.guardianScheduleOnAtPhrase) — in \(formattedOneOffCountdown(seconds: remaining)).",
            trailing: {
                HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                    MissionDelayPostponeValueUnitRow(
                        postponeLabel: "Alter",
                        postponeLabelColor: theme.textPrimary,
                        value: postponeValue,
                        unit: postponeUnit,
                        minimumTotalSeconds: 1,
                        maximumTotalSeconds: TimeInterval(generalSettings.missionControlPostponeStepCapSeconds),
                        numericFieldWidth: 88,
                        unitPickerWidth: 68,
                        controlSize: .small
                    )
                    Button("Sooner") {
                        onAlterSooner()
                    }
                    .buttonStyle(.borderedProminent).guardianPointerOnHover()
                    .tint(.blue)
                    .controlSize(.small)
                    Button("Later") {
                        onAlterLater()
                    }
                    .buttonStyle(.borderedProminent).guardianPointerOnHover()
                    .tint(.blue)
                    .controlSize(.small)
                    compactVerticalControlSeparator()
                        .padding(.horizontal, GuardianSpacing.xsTight)
                    Button("Start") {
                        onRequestStartNow()
                    }
                    .buttonStyle(.borderedProminent).guardianPointerOnHover()
                    .tint(.blue)
                    .controlSize(.small)
                }
                .fixedSize(horizontal: true, vertical: true)
                .padding(.top, GuardianSpacing.hairlineStack)
            },
            bottom: {
                ProgressView(value: progress)
                    .tint(GuardianSemanticColors.infoForeground.opacity(0.88))
            }
        )
    }

    private func formattedOneOffCountdown(seconds: TimeInterval) -> String {
        let s = max(0, Int(ceil(seconds)))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }

    private var liveConsoleCardFill: Color { theme.backgroundElevated }
    private var liveConsoleCardStroke: Color { theme.borderSubtle }

    /// MC-R overlay sheets (task triage, vehicle detail): same header strip + hairline rhythm as ``GuardianCard`` header slot.
    @ViewBuilder
    private func missionLiveOverlayHeader<Trailing: View>(
        title: String,
        subtitle: String?,
        titleMuted: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                    Text(title)
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(titleMuted ? theme.textSecondary : theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
            }
            .frame(minHeight: GuardianCardLayout.headerContentMinHeight, alignment: .center)
            .padding(.horizontal, GuardianCardLayout.headerHorizontalPadding)
            .padding(.vertical, GuardianCardLayout.headerVerticalPadding)
            .background(theme.backgroundElevated)
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
    }

    private func clearLiveRuntimeMissionPointsOverlayChrome() {
        liveRuntimeMissionPointsOverlayPresented = false
        liveRuntimeMissionPointDrawerEditingID = nil
        liveRuntimeMissionMapViewportCenter = nil
        liveRuntimeOverviewSelectedMissionPointID = nil
    }

    private func pruneLiveRuntimeMapPointSelectionIfOutOfFilter() {
        guard let sid = liveRuntimeOverviewSelectedMissionPointID else { return }
        let visible = MissionPoint.filteredForMissionControlLiveMap(run.runtimeMissionPoints, focusedTaskID: focusedLiveTaskID)
        if !visible.contains(where: { $0.id == sid }) {
            liveRuntimeOverviewSelectedMissionPointID = nil
        }
    }

    private var missionLiveFilteredRuntimeMissionPoints: [MissionPoint] {
        MissionPoint.filteredForMissionControlLiveMap(run.runtimeMissionPoints, focusedTaskID: focusedLiveTaskID)
    }

    @ViewBuilder
    private var missionLiveRuntimeMissionPointsOverlay: some View {
        if liveRuntimeMissionPointsOverlayPresented {
            VStack(alignment: .leading, spacing: 0) {
                missionLiveOverlayHeader(
                    title: "Map points",
                    subtitle: nil,
                    titleMuted: false
                ) {
                    HStack(spacing: GuardianSpacing.xs) {
                        missionLiveOverlayHeaderGlyphButton(
                            systemImage: "plus.circle",
                            help: "Add map point at the live map centre (rally, default catchment) and select it for drag on the map"
                        ) {
                            addLiveRuntimeMissionPointAtMapCentreAndRevealInList()
                        }
                        missionLiveSidebarStyleCloseButton {
                            withAnimation(triageSheetSpring) {
                                liveRuntimeMissionPointsOverlayPresented = false
                            }
                        }
                    }
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                            if missionLiveFilteredRuntimeMissionPoints.isEmpty {
                                Text("No map points match the current filter.")
                                    .font(GuardianTypography.font(.denseCaption12Regular))
                                    .foregroundStyle(theme.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(missionLiveFilteredRuntimeMissionPoints, id: \.id) { mp in
                                    missionLiveRuntimeMissionPointRow(mp: mp)
                                        .id(mp.id)
                                }
                            }
                        }
                        .padding(.horizontal, GuardianCardLayout.defaultBodyPadding)
                        .padding(.vertical, GuardianSpacing.denseGutter)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .onChange(of: liveRuntimeMapPointsListScrollEpoch) { _ in
                        guard let id = liveRuntimeMapPointsListScrollTargetRow else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.22)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.backgroundRaised)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(3)
        }
    }

    @ViewBuilder
    private func missionLiveRuntimeMissionPointRow(mp: MissionPoint) -> some View {
        let cur = run.runtimeMissionPoints.first(where: { $0.id == mp.id }) ?? mp
        let rowSelected = liveRuntimeOverviewSelectedMissionPointID == mp.id
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: rowSelected ? .primary : .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianSpacing.cardBodyInset
            ),
            body: {
                VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                    HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                        VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                            Text(cur.mapChipLabel)
                                .font(GuardianTypography.font(.subsectionTitleSemibold))
                                .foregroundStyle(cur.isClosed ? theme.textTertiary : theme.textPrimary)
                                .strikethrough(cur.isClosed)
                            Text(cur.kind.rawValue.capitalized)
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if liveRuntimeOverviewSelectedMissionPointID == mp.id {
                                liveRuntimeOverviewSelectedMissionPointID = nil
                            } else {
                                liveRuntimeOverviewSelectedMissionPointID = mp.id
                            }
                        }

                        GuardianThemedButton(
                            accent: .primary,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            contentSizing: .squareToolbarCell,
                            action: { openLiveRuntimeMissionPointEditDrawer(missionPointID: mp.id) },
                            label: {
                                Image(systemName: "pencil")
                                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                            }
                        )
                        .help("Edit map point")
                    }

                    Toggle(isOn: Binding(
                        get: {
                            run.runtimeMissionPoints.first(where: { $0.id == mp.id })?.isClosed ?? false
                        },
                        set: { closed in
                            _ = run.applyRuntimeMissionPointSetClosed(id: mp.id, isClosed: closed, source: "operator")
                            onUpdate(run)
                        }
                    )) {
                        Text("Closed")
                            .font(GuardianTypography.font(.formFieldLabel))
                    }
                    .tint(GuardianSemanticColors.infoForeground)
                }
            }
        )
    }

    private func openLiveRuntimeMissionPointEditDrawer(missionPointID: UUID) {
        guard let mission = resolvedMission else { return }
        guard run.runtimeMissionPoints.contains(where: { $0.id == missionPointID }) else { return }
        liveRuntimeMissionPointDrawerEditingID = missionPointID
        appDrawer.present(title: "Edit map point", preferredWidth: 400, scrimTapDismisses: true) {
            MissionControlRuntimeMissionPointEditDrawer(
                missionPointID: missionPointID,
                run: run,
                mission: mission,
                onPersist: {
                    onUpdate(run)
                }
            )
        }
    }

    /// Adds a rally point at the live map centre (or mission home / origin), selects it for map drag, and scrolls the list row into view.
    private func addLiveRuntimeMissionPointAtMapCentreAndRevealInList() {
        guard let mission = resolvedMission else {
            toastCenter.show("No mission template for this run", style: .warning)
            return
        }
        let coord =
            liveRuntimeMissionMapViewportCenter
            ?? mission.routeMacro.home?.coord
            ?? RouteCoordinate()
        let rowID = UUID()
        let tempPointId = "mre.create.\(rowID.uuidString.lowercased())"
        let point = MissionPoint(
            id: rowID,
            pointId: tempPointId,
            label: "",
            kind: .rally,
            coordinate: coord,
            taskID: focusedLiveTaskID,
            catchmentRadiusM: MissionPoint.defaultCatchmentRadiusM
        )
        guard run.applyRuntimeMissionPointCreate(point, source: "operator") else {
            toastCenter.show("Could not add map point", style: .warning)
            return
        }
        onUpdate(run)
        liveRuntimeOverviewSelectedMissionPointID = rowID
        liveRuntimeMapPointsListScrollTargetRow = rowID
        liveRuntimeMapPointsListScrollEpoch &+= 1
        toastCenter.show("Map point added — drag the pin on the map to move it", style: .success)
    }

    /// MC-R left column: map **260** (grows when log is collapsed) → **10** → roster **210** → **10** → Logs (**flex** or one-line collapsed).
    private let liveConsoleMapHeight: CGFloat = 260
    private let liveConsoleRosterHeight: CGFloat = 210
    /// Vertical gap between map↔roster and roster↔log (same value both places).
    private let liveConsoleStackSpacing: CGFloat = GuardianSpacing.denseGutter
    private let liveConsoleStackGutter: CGFloat = GuardianSpacing.denseGutter
    /// Total ``GuardianCard`` height (header + one log line body) when the log is collapsed.
    private let liveLogCollapsedCardHeight: CGFloat = 100

    /// Running / paused: **70%** map + roster + live mission log; **30%** Tasks card (overview or task triage sheet).
    private var missionLiveConsole: some View {
        let gutter = liveConsoleStackGutter
        let baseMapH = liveConsoleMapHeight
        let rosterH = liveConsoleRosterHeight
        let vGap = liveConsoleStackSpacing
        return GeometryReader { geo in
            let innerW = max(0, geo.size.width)
            let innerH = max(0, geo.size.height)
            let leftW = (innerW - gutter) * 0.7
            let rightW = (innerW - gutter) * 0.3
            let defaultLogH = max(0, innerH - baseMapH - vGap - rosterH - vGap)
            let collapsedLogH = min(liveLogCollapsedCardHeight, defaultLogH)
            let logH = liveLogPanelCollapsed ? collapsedLogH : defaultLogH
            let mapH = liveLogPanelCollapsed ? baseMapH + max(0, defaultLogH - collapsedLogH) : baseMapH
            HStack(alignment: .top, spacing: gutter) {
                VStack(alignment: .leading, spacing: vGap) {
                    missionLiveMapOnlyColumn(width: leftW, height: mapH)
                    missionLiveVehicleStatusRow
                        .frame(maxWidth: .infinity)
                        .frame(height: rosterH, alignment: .topLeading)
                        .clipped()
                    missionLiveLogPlaceholder(maxTotalHeight: logH, logCollapsed: $liveLogPanelCollapsed)
                        .frame(maxWidth: .infinity)
                        .frame(height: logH, alignment: .topLeading)
                }
                .frame(width: leftW, height: innerH, alignment: .topLeading)
                .clipped()
                .animation(GuardianMotion.drawerSlide, value: liveLogPanelCollapsed)

                missionLiveTasksSideCard
                    .frame(width: rightW)
                    .frame(height: innerH, alignment: .topLeading)
            }
            .frame(width: innerW)
            .frame(height: innerH, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Map or camera only (mode toggle is in the header bar).
    private func missionLiveMapOnlyColumn(width: CGFloat, height: CGFloat) -> some View {
        Group {
            switch liveConsoleMediaTab {
            case .camera:
                missionLiveCameraPlaceholder
            case .map:
                missionLiveOverviewMap
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    /// Spring used by the task triage sheet's slide-up / slide-down transition.
    /// Defined as a per-call `Animation` (rather than a static let) because SwiftUI's
    /// `.spring(response:dampingFraction:)` is not `Sendable` and a static would
    /// require `@MainActor` isolation that fights the surrounding `View` body builder.
    private var triageSheetSpring: Animation {
        .spring(response: 0.42, dampingFraction: 0.86)
    }

    /// Right column: ``GuardianCard`` with **Tasks** header; ``fullCardOverlay`` stacks **Task triage → Assignment (vehicle) → Map points** (bottom → top). ``zIndex`` must stay ordered so map points stay above in-flight triage/vehicle sheets.
    private var missionLiveTasksSideCard: some View {
        GuardianCard(
            configuration: mcSetupGroupCardConfiguration,
            header: { mcSetupGroupCardTitle("Tasks") },
            body: {
                missionLiveTasksBaseLayer
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            },
            fullCardOverlay: {
                ZStack(alignment: .top) {
                    missionLiveTaskTriageOverlay
                    missionLiveVehicleOverlay
                    missionLiveRuntimeMissionPointsOverlay
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Tasks card overlay focus helpers

    /// Focus a task triage. Vehicle and task overlays stack independently
    /// (Tasks → Task triage → Vehicle detail) — no exclusivity enforced here.
    /// All callers funnel through this helper to share the same spring.
    private func focusLiveTask(_ id: UUID?) {
        withAnimation(triageSheetSpring) {
            focusedLiveTaskID = id
        }
    }

    /// Focus a roster slot vehicle overlay. Toggles when the same id is re-tapped (open ↔ close)
    /// so a second click on the live roster health card dismisses the sheet.
    private func focusLiveAssignment(_ id: UUID?) {
        withAnimation(triageSheetSpring) {
            if let id, focusedLiveAssignmentID == id {
                focusedLiveAssignmentID = nil
            } else {
                focusedLiveAssignmentID = id
            }
        }
    }

    @ViewBuilder
    private var missionLiveTasksBaseLayer: some View {
        if let mission = resolvedMission {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                    if run.status == .running,
                       !run.taskStartDeferralByTaskID.isEmpty
                    {
                        TimelineView(.periodic(from: .now, by: 0.25)) { context in
                            missionLiveTaskProgressList(mission: mission, now: context.date)
                        }
                    } else {
                        missionLiveTaskProgressList(mission: mission, now: Date())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("No mission template")
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textSecondary)
                .padding(.top, GuardianSpacing.xxs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var missionLiveTaskTriageOverlay: some View {
        if let mission = resolvedMission, focusedLiveTaskID != nil {
            Group {
                if let focusID = focusedLiveTaskID,
                   let task = mission.routeMacro.tasks.first(where: { $0.id == focusID }) {
                    missionLiveTaskTriageInnerSheet(task: task, mission: mission)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        missionLiveOverlayHeader(
                            title: "Task",
                            subtitle: nil,
                            titleMuted: false
                        ) {
                            missionLiveSidebarStyleCloseButton {
                                focusLiveTask(nil)
                            }
                        }
                        Text("This task is not in the current mission template.")
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(GuardianCardLayout.defaultBodyPadding)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(theme.backgroundRaised)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(1)
        }
    }

    /// Vehicle (roster slot) detail sheet that slides up over the Tasks list when a slot health
    /// card is tapped. Header mirrors the task triage overlay (title + inspector + cog + close) so
    /// MC-R stays visually uniform; cog opens the existing assignment policy overrides sidebar.
    @ViewBuilder
    private var missionLiveVehicleOverlay: some View {
        if let assignmentID = focusedLiveAssignmentID,
           let assignment = run.assignments.first(where: { $0.id == assignmentID })
        {
            missionLiveVehicleDetailSheet(assignment: assignment)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
        }
    }

    /// In-card vehicle detail body: header (slot callsign + cog + close) and a placeholder content area
    /// reserved for richer per-vehicle telemetry. Kept intentionally lean so we can layer in details
    /// (battery / GPS / link / mission progress) iteratively without churning the overlay shell.
    private func missionLiveVehicleDetailSheet(assignment: MissionRunAssignment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            missionLiveOverlayHeader(
                title: assignment.slotName,
                subtitle: nil,
                titleMuted: false
            ) {
                HStack(spacing: GuardianSpacing.xs) {
                    if telemetryVehicleID(for: assignment) != nil {
                        missionLiveSidebarStyleVehicleInspectorButton {
                            presentRosterCalibrationSheet(for: assignment)
                        }
                    }
                    missionLiveSidebarStyleCogButton(
                        helpText: "Vehicle settings (abort & complete policy)"
                    ) {
                        presentAssignmentSettingsSidebar(assignmentID: assignment.id)
                    }
                    missionLiveSidebarStyleCloseButton {
                        focusLiveAssignment(nil)
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                    if let device = resolvedMission?.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId }) {
                        Text(rosterRoleSubtitle(device))
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textSecondary)
                    }
                    if let vid = telemetryVehicleID(for: assignment) {
                        Text(vid)
                            .font(GuardianTypography.font(.telemetryMono10Regular))
                            .foregroundStyle(theme.textTertiary)
                            .help("Bridge vehicle key: \(vid)")
                    } else {
                        Text("No bridge link")
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, GuardianSpacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, GuardianCardLayout.defaultBodyPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.backgroundRaised)
    }

    /// In-card triage sheet for the selected task: hero progress, deferral / trigger controls, sidebar-style close.
    private func missionLiveTaskTriageInnerSheet(task: RoutePath, mission: Mission) -> some View {
        let taskIndex = mission.routeMacro.tasks.firstIndex(where: { $0.id == task.id }) ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            missionLiveOverlayHeader(
                title: task.name,
                subtitle: nil,
                titleMuted: !task.enabled
            ) {
                HStack(spacing: GuardianSpacing.xs) {
                    missionLiveSidebarStyleCogButton {
                        presentTaskSettingsSidebar(task: task)
                    }
                    missionLiveSidebarStyleCloseButton {
                        focusLiveTask(nil)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                missionLiveTaskStateBanner(run.taskStateByTaskID[task.id] ?? .ready)
                    .padding(.top, GuardianSpacing.denseGutter)

                missionLiveTaskEndProtocolAcknowledgementBlock(task: task, compact: false)
                    .padding(.bottom, GuardianSpacing.denseGutter)

                if run.status == .running || run.status == .paused {
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        if missionLiveTaskWindDownSectionVisible(task: task, now: context.date) {
                            missionLiveTaskWindDownActionsSection(task: task, now: context.date)
                                .padding(.bottom, GuardianSpacing.denseGutter)
                        }
                    }
                }

                if task.enabled, task.regularity == .continuous || task.regularity == .continuousWithDelay {
                    Text(
                        task.cycles > 0
                            ? "Cycles: \(run.taskCyclesCompletedByTaskID[task.id] ?? 0)/\(task.cycles)"
                            : "Cycles: \(run.taskCyclesCompletedByTaskID[task.id] ?? 0)/∞"
                    )
                    .font(GuardianTypography.font(.inlineNoticeDetail))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.bottom, GuardianSpacing.xs)
                }

                Group {
                    if run.status == .running {
                        TimelineView(.periodic(from: .now, by: 0.25)) { context in
                            missionLiveTaskTriageProgressHero(
                                task: task,
                                taskIndex: taskIndex,
                                mission: mission,
                                now: context.date
                            )
                        }
                    } else {
                        missionLiveTaskTriageProgressHero(
                            task: task,
                            taskIndex: taskIndex,
                            mission: mission,
                            now: Date()
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, GuardianCardLayout.defaultBodyPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.backgroundRaised)
    }

    @ViewBuilder
    private func missionLiveTaskProgressList(mission: Mission, now: Date) -> some View {
        ForEach(mission.routeMacro.tasks.indices, id: \.self) { index in
            let task = mission.routeMacro.tasks[index]
            missionLiveTaskProgressRow(task: task, taskIndex: index, mission: mission, now: now)
        }
    }

    private func missionLiveTaskProgressRow(task: RoutePath, taskIndex: Int, mission: Mission, now: Date) -> some View {
        let d = missionLiveTaskProgressDerived(task: task, taskIndex: taskIndex, mission: mission, now: now)
        return VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            Button {
                focusLiveTask(task.id)
            } label: {
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xsTight) {
                        missionLiveTaskStateBadge(run.taskStateByTaskID[task.id] ?? .ready)
                        missionLiveTaskTitleRow(task: task)
                        Spacer(minLength: GuardianSpacing.xsTight)
                        missionLiveTaskProgressCounterGroup(task: task, derived: d, now: now, hero: false)
                    }
                    missionLiveAnimatedProgressBar(
                        fraction: d.barFraction,
                        tint: d.barTint
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(GuardianPointerPlainButtonStyle())
            .help("Open task triage")

            if d.inTaskStartDeferral, let taskStartDefForControls = d.taskStartDef {
                missionLiveTaskProgressDeferralControls(
                    task: task,
                    taskStartDefForControls: taskStartDefForControls,
                    now: now,
                    hero: false
                )
            } else if showMissionTaskTrigger(for: task) {
                HStack {
                    Spacer(minLength: 0)
                    missionLiveTaskProgressTriggerControl(task: task, hero: false)
                }
            } else if missionLiveTaskEndProtocolAcknowledgementVisible(for: task) {
                missionLiveTaskEndProtocolAcknowledgementBlock(task: task, compact: true)
            }
        }
        .padding(.vertical, GuardianSpacing.xxs)
    }

    /// Live progress caption while a task awaits its initial MAVLink mission start (see ``MissionTaskStartDeferral``).
    private func formattedTaskStartDeferralStatus(remaining: TimeInterval, totalDelay: TimeInterval) -> String {
        if totalDelay < 1 {
            return remaining > 0.08 ? "Starting mission…" : "Starting mission…"
        }
        if remaining <= 0 {
            return "Starting mission…"
        }
        let secs = max(1, Int(ceil(remaining)))
        let m = secs / 60
        let s = secs % 60
        let clock = String(format: "%d:%02d", m, s)
        return "\(clock) until mission start"
    }

    @ViewBuilder
    private func missionLiveTaskTitleRow(task: RoutePath) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xxs) {
            Text(task.name)
                .font(GuardianTypography.font(.formFieldLabel))
                .foregroundStyle(task.enabled ? theme.textPrimary : theme.textSecondary)
            if task.enabled, task.regularity == .continuous || task.regularity == .continuousWithDelay {
                let done = run.taskCyclesCompletedByTaskID[task.id] ?? 0
                Text(task.cycles > 0 ? "(\(done)/\(task.cycles))" : "(\(done)/∞)")
                    .font(GuardianTypography.font(.denseCaption10Medium))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func missionLiveTaskFraction(task: RoutePath, taskActiveInCycle: Bool, hub: FleetHubVehicleTelemetry?) -> Double {
        guard task.enabled, taskActiveInCycle, let hub, let tot = hub.missionProgressTotal, tot > 0,
              let cur = hub.missionProgressCurrent
        else { return 0 }
        let t = Double(tot)
        let c = Double(cur)
        if c >= t { return 1 }
        return min(1, max(0, c / t))
    }

    private func missionLiveAnimatedProgressBar(fraction: Double, tint: Color, height: CGFloat = 7) -> some View {
        GeometryReader { geo in
            let w = max(0, min(1, fraction)) * geo.size.width
            ZStack(alignment: .leading) {
                // Recessed track: visible at 0% so the bar reads even when idle.
                Capsule()
                    .fill(Color.primary.opacity(0.11))
                Capsule()
                    .fill(tint)
                    .frame(width: w)
                    .animation(.easeInOut(duration: 0.35), value: fraction)
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
            )
        }
        .frame(height: height)
    }

    private var missionLiveCameraPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(liveConsoleCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(liveConsoleCardStroke, lineWidth: 1)
            )
    }

    /// Same Leaflet/OSM stack and bbox logic as Missions route tab: home marker and route polylines from the mission template.
    private var missionLiveOverviewMap: some View {
        Group {
            if resolvedMission != nil {
                GuardianMapView(
                    model: mapModel,
                    contextMenuPolicy: GuardianMapContextMenuPolicy(
                        vehicleActions: [.followVehicle, .stopFollowingVehicle, .centerMarker],
                        waypointActions: [],
                        homeActions: []
                    ),
                    onContextAction: { event in
                        guard event.markerType == .vehicle else { return }
                        switch event.action {
                        case .followVehicle:
                            if let markerID = event.markerID, !markerID.isEmpty {
                                mapModel.followedVehicleMarkerID = markerID
                            }
                        case .stopFollowingVehicle:
                            mapModel.followedVehicleMarkerID = nil
                        case .centerMarker, .deleteWaypoint, .deleteMissionPoint:
                            break
                        }
                    },
                    onMissionPointClick: { id in
                        if liveRuntimeOverviewSelectedMissionPointID == id {
                            liveRuntimeOverviewSelectedMissionPointID = nil
                        } else {
                            liveRuntimeOverviewSelectedMissionPointID = id
                        }
                    },
                    onMissionPointMoved: { id, lat, lon in
                        _ = run.applyRuntimeMissionPointUpdate(id: id, source: "operator") {
                            $0.coordinate.lat = lat
                            $0.coordinate.lon = lon
                        }
                        onUpdate(run)
                    },
                    onVehicleTap: { ev in
                        guard let raw = ev.markerID, let aid = UUID(uuidString: raw) else { return }
                        focusLiveAssignment(aid)
                    },
                    onTaskPathTap: { ev in
                        focusLiveTask(ev.taskPathID)
                    },
                    onViewportCenterChanged: { lat, lon in
                        liveRuntimeMissionMapViewportCenter = RouteCoordinate(lat: lat, lon: lon)
                    }
                )
                .task(id: liveOverviewMapSignature) {
                    if let mission = resolvedMission {
                        mapModel.routeGeometry = GuardianRouteMapGeometry(
                            home: mission.routeMacro.home,
                            allTasksCoords: mission.routeMacro.tasks.map { $0.waypoints.map(\.coord) },
                            taskPathIDs: mission.routeMacro.tasks.map(\.id),
                            selectedTaskWaypoints: [],
                            selectedWaypointIndex: nil,
                            headingPreview: nil,
                            cameraPreview: nil,
                            preserveView: true,
                            isEditingTask: false,
                            missionPointMarkers: missionLiveMissionPointMapMarkers,
                            missionPointPlacementArmed: false
                        )
                    } else {
                        mapModel.routeGeometry = .empty
                    }
                    mapModel.vehicleMarkers = missionLiveVehicleMarkers
                    if let followID = mapModel.followedVehicleMarkerID,
                       !missionLiveVehicleMarkers.contains(where: { $0.id == followID }) {
                        mapModel.followedVehicleMarkerID = nil
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(liveConsoleCardFill)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(liveConsoleCardStroke, lineWidth: 1)
        )
    }

    /// Equatable signature of every input that feeds the live overview map's
    /// shared model state. Captures the actual home, route, and marker data so the
    /// `.task` re-runs whenever any vehicle drifts, the mission is edited,
    /// etc. — not just when counts change.
    private var liveOverviewMapSignature: LiveOverviewMapSignature {
        LiveOverviewMapSignature(
            missionID: resolvedMission?.id,
            homeCoord: resolvedMission?.routeMacro.home?.coord,
            allTasksCoords: resolvedMission?.routeMacro.tasks.map { $0.waypoints.map(\.coord) } ?? [],
            markers: missionLiveVehicleMarkers,
            focusedTaskID: focusedLiveTaskID,
            missionPointMarkers: missionLiveMissionPointMapMarkers
        )
    }

    private var missionLiveMissionPointMapMarkers: [GuardianMissionPointMapMarker] {
        missionControlGuardianMissionPointMarkers(
            from: MissionPoint.filteredForMissionControlLiveMap(run.runtimeMissionPoints, focusedTaskID: focusedLiveTaskID),
            selectedMissionPointID: liveRuntimeOverviewSelectedMissionPointID
        )
    }

    /// Points drawn on the MCS roster staging map. While the run is still in **setup**, prefer the **mission
    /// template** list so markers appear even if ``runtimeMissionPoints`` has not been re-seeded yet; otherwise
    /// use the run envelope.
    private var setupStagingMissionPointRowsForMap: [MissionPoint] {
        if run.status == .setup, let m = resolvedMission {
            return m.missionPoints
        }
        return run.runtimeMissionPoints
    }

    /// Setup roster staging map: selected pin is **draggable** in Leaflet whenever a point is selected on the **Rosters** tab (sidebar Tasks vs Points does not strip selection from the map payload).
    private var setupStagingMissionPointMapMarkers: [GuardianMissionPointMapMarker] {
        let selected: UUID? = setupMainTab == .rosters ? setupRostersSelectedMissionPointID : nil
        return missionControlGuardianMissionPointMarkers(
            from: setupStagingMissionPointRowsForMap,
            selectedMissionPointID: selected
        )
    }

    private func missionControlGuardianMissionPointMarkers(
        from points: [MissionPoint],
        selectedMissionPointID: UUID? = nil
    ) -> [GuardianMissionPointMapMarker] {
        points.map { mp in
            GuardianMissionPointMapMarker(
                id: mp.id,
                lat: mp.coordinate.lat,
                lon: mp.coordinate.lon,
                mapLabelCompact: mp.mapGlyphDigit,
                mapLabelFull: mp.mapChipLabel,
                kindRaw: mp.kind.rawValue,
                isClosed: mp.isClosed,
                isSelected: selectedMissionPointID == mp.id
            )
        }
    }

    private var missionLiveVehicleMarkers: [MapVehicleMarker] {
        filteredLiveRosterAssignments.compactMap { assignment in
            guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
                  let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                  let lat = hub.latitudeDeg,
                  let lon = hub.longitudeDeg,
                  assignment.attachedFleetVehicleToken != nil
            else { return nil }
            let colorHex = fleetLink.mapColorHex(forVehicleID: vehicleID)
            let heading = hub.headingDeg ?? hub.yawDeg
            return MapVehicleMarker(
                id: assignment.id.uuidString,
                lat: lat,
                lon: lon,
                label: assignment.slotName,
                colorHex: colorHex,
                imageDataURL: missionControlRosterMapMarkerImageDataURL(for: assignment),
                selected: false,
                draggable: false,
                headingDeg: heading
            )
        }
    }

    private var missionLiveVehicleStatusRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GuardianSpacing.denseGutter) {
                if filteredLiveRosterAssignments.isEmpty {
                    MissionLiveVehicleHealthCard(
                        slotTitle: "—",
                        rosterSubtitle: "—",
                        vehicleID: nil,
                        simulationImageBasenames: nil,
                        vehicleClassForBundledDeviceArt: .unknown,
                        vehicleModel: fleetLink.primaryVehicleOperationalModel(),
                        slotHeight: liveConsoleRosterHeight
                    )
                } else {
                    ForEach(filteredLiveRosterAssignments) { assignment in
                        let device = resolvedMission.flatMap { m in
                            m.rosterDevices.first { $0.id == assignment.rosterDeviceId }
                        }
                        let vehicleID = telemetryVehicleID(for: assignment)
                        let rosterDeviceClass = device?.vehicleClass ?? .unknown
                        let deviceArtVehicleClass: FleetVehicleType = {
                            if let vid = vehicleID, let model = fleetLink.vehicleModel(forVehicleID: vid) {
                                return model.data.vehicleType
                            }
                            return rosterDeviceClass
                        }()
                        MissionLiveVehicleHealthCard(
                            slotTitle: assignment.slotName,
                            rosterSubtitle: rosterRoleSubtitle(device),
                            vehicleID: vehicleID,
                            simulationImageBasenames: simulationImageBasenamesForAssignment(assignment, sitl: sitl),
                            vehicleClassForBundledDeviceArt: deviceArtVehicleClass,
                            vehicleModel: vehicleID.map { fleetLink.vehicleOperationalModel(forVehicleID: $0) }
                                ?? FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil),
                            slotHeight: liveConsoleRosterHeight,
                            onTap: {
                                focusLiveAssignment(assignment.id)
                            }
                        )
                    }
                }
            }
            // Do not add vertical padding here: row height is exactly `liveConsoleRosterHeight` and `.clipped()`;
            // extra height would clip the bottom of cards (including `strokeBorder`).
        }
    }

    /// Live mission log: ``GuardianCard`` header (elevated strip) + body with ``ScrollView`` so header/body match Settings chrome.
    private func missionLiveLogPlaceholder(maxTotalHeight: CGFloat, logCollapsed: Binding<Bool>) -> some View {
        GuardianCard(
            configuration: mcSetupGroupCardConfiguration,
            header: {
                HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                    Text("Logs")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textPrimary)

                    if focusedLiveTaskID != nil {
                        Text("· task filter")
                            .font(GuardianTypography.font(.denseCaption10Medium))
                            .foregroundStyle(theme.textTertiary)
                    }

                    if let compiledPlan = run.compiledPlan {
                        let phaseStyle = GuardianSemanticColors.paladinPhaseBadgeStyle(for: run.sessionPhase)
                        HStack(spacing: GuardianSpacing.xsTight) {
                            Text(run.sessionPhase.rawValue.capitalized)
                                .font(GuardianTypography.font(.telemetryNano9Semibold))
                                .foregroundStyle(phaseStyle.foreground)
                                .padding(.horizontal, GuardianSpacing.chromeTightInset)
                                .padding(.vertical, GuardianSpacing.micro)
                                .background(phaseStyle.background)
                                .clipShape(Capsule())
                            Text(condensedHeaderMetadata(plan: compiledPlan))
                                .font(GuardianTypography.font(.telemetryMono10Regular))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: GuardianSpacing.xs)

                    GuardianThemedButton(
                        title: "Copy log",
                        accent: .primary,
                        surface: .solid,
                        size: .small,
                        shape: .cornered,
                        isEnabled: !liveLogEventsFiltered.isEmpty,
                        action: { copyLiveLogToPasteboard() }
                    )

                    GuardianNeutralBorderedButton(
                        systemImage: logCollapsed.wrappedValue ? "chevron.up" : "chevron.down",
                        help: logCollapsed.wrappedValue ? "Expand log panel" : "Collapse log to one line",
                        action: {
                            withAnimation(GuardianMotion.drawerSlide) {
                                logCollapsed.wrappedValue.toggle()
                            }
                        }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            body: {
                Group {
                    if !liveLogEventsFiltered.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                                    ForEach(liveLogEventsFiltered.suffix(80)) { event in
                                        logEventRow(event: event)
                                            .id(event.id)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .environment(\.openURL, OpenURLAction { url in
                                handleMcrLogURL(url)
                            })
                            .onAppear {
                                if let id = liveLogVisibleTailAnchorID {
                                    DispatchQueue.main.async {
                                        proxy.scrollTo(id, anchor: .bottom)
                                    }
                                }
                            }
                            .onChange(of: liveLogVisibleTailAnchorID) { newID in
                                guard let id = newID else { return }
                                DispatchQueue.main.async {
                                    withAnimation(GuardianMotion.feedbackCrossfade) {
                                        proxy.scrollTo(id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(
                                focusedLiveTaskID == nil
                                    ? "No mission log entries for this run yet."
                                    : "No log entries for this task or its roster vehicles yet."
                            )
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: maxTotalHeight, alignment: .topLeading)
        .clipped()
    }

    private func condensedHeaderMetadata(plan: MissionControlPlan) -> String {
        "\(plan.taskTopology.rawValue) · \(plan.teamTopology.rawValue) · \(plan.roleTracks.count) trk"
    }

    private func condensedHeaderLine(phase: MissionRunSessionPhase, plan: MissionControlPlan) -> String {
        "\(phase.rawValue) · \(condensedHeaderMetadata(plan: plan))"
    }

    func liveLogPlainText(
        events: [MissionRunEvent],
        phase: MissionRunSessionPhase,
        plan: MissionControlPlan?
    ) -> String {
        let header = plan.map { "Logs - \(condensedHeaderLine(phase: phase, plan: $0))" } ?? "Mission log"
        let body = events.map {
            $0.plainTextLine(mission: resolvedMission, assignments: run.assignments)
        }
        return ([header] + body).joined(separator: "\n")
    }

    private func colorFromMapHex(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let n = UInt32(s, radix: 16) else {
            return Color(red: 0.55, green: 0.55, blue: 0.58)
        }
        let r = Double((n >> 16) & 0xFF) / 255
        let g = Double((n >> 8) & 0xFF) / 255
        let b = Double(n & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    private func logSeverityBorderColor(_ level: MissionRunEventLevel) -> Color {
        switch level {
        case .info: return Color.white.opacity(0.22)
        case .warning: return Color.orange.opacity(0.9)
        case .error: return Color.red.opacity(0.9)
        }
    }

    private func logEventRow(event: MissionRunEvent) -> some View {
        let mission = resolvedMission
        let routeTint: Color? = {
            guard let pid = event.taskID, let mission else { return nil }
            if let idx = mission.routeMacro.tasks.firstIndex(where: { $0.id == pid }) {
                return MissionTaskMapColor.swiftUIColor(forTaskIndex: idx)
            }
            return nil
        }()
        let routeTextColor = routeTint ?? Color.gray.opacity(0.85)
        let speakerColor: Color = {
            switch event.speaker {
            case .missionControl:
                return theme.textPrimary
            case .assistant:
                return theme.textPrimary
            case .operator:
                return theme.textPrimary
            case .vehicleSlot(let slot):
                return slotSpeakerColor(slotName: slot)
            }
        }()
        let bodyColor: Color = {
            switch event.level {
            case .info: return Color.gray.opacity(0.92)
            case .warning: return Color.orange.opacity(0.88)
            case .error: return Color.red.opacity(0.9)
            }
        }()

        // Build the line as a single Text concat: [Wrapper] + [Speaker] + AttributedString(@target body)
        // — wrapper/speaker are static metadata (no link); target + body @handles are linkable.
        var line = Text(verbatim: "")
        if let pl = event.resolvedTaskLogPrefix(mission: resolvedMission, assignments: run.assignments) {
            line = line + Text(verbatim: "[\(pl)]").foregroundColor(routeTextColor)
        }
        line = line + speakerLogText(event.speaker, color: speakerColor)
        line = line + Text(attributedTargetAndBody(event: event, defaultColor: bodyColor))

        return HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(logSeverityBorderColor(event.level))
                .frame(width: 3)
            line
                .font(GuardianTypography.font(.telemetryMono11Regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, GuardianSpacing.xsTight)
                .padding(.vertical, GuardianSpacing.micro)
        }
        .textSelection(.enabled)
    }

    /// `[Speaker]` segment as a `Text` so it can be concatenated with the wrapper + attributed body.
    /// Assistant display names are resolved through ``MissionRunAssistantRegistry`` so adding a new
    /// assistant only requires a one-time profile registration — no renderer changes here.
    private func speakerLogText(_ speaker: MissionRunEventSpeaker, color: Color) -> Text {
        switch speaker {
        case .missionControl:
            return Text(verbatim: "[MissionControl]").foregroundColor(color)
        case .assistant(let key):
            let name = MissionRunAssistantRegistry.shared.displayName(forKey: key)
            return Text(verbatim: "[\(name)]").foregroundColor(color)
        case .vehicleSlot(let s):
            return Text(verbatim: "[\(s)]").foregroundColor(color)
        case .operator(let displayName):
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Text(verbatim: trimmed.isEmpty ? "[Operator]" : "[Operator][\(trimmed)]")
                .foregroundColor(color)
        }
    }

    /// Combined `@target body` AttributedString — structural addressee mention plus any free-form
    /// `@handle` mentions inside the body. Each mention carries `.foregroundColor` (canonical task /
    /// slot / role color) and a `.link` URL like `guardian://mcr/task/<uuid>` /
    /// `guardian://mcr/slot/<uuid>` so clicks open the matching MCR overlay
    /// (intercepted by ``handleMcrLogURL(_:)`` via `OpenURLAction`).
    private func attributedTargetAndBody(event: MissionRunEvent, defaultColor: Color) -> AttributedString {
        var result = AttributedString("")
        var leadingSpace = AttributedString(" ")
        leadingSpace.foregroundColor = defaultColor
        result.append(leadingSpace)

        let target = event.effectiveTarget
        var mention = AttributedString("@\(mcrTargetDisplayName(target))")
        mention.foregroundColor = mcrTargetColor(target)
        if let url = mcrTargetLinkURL(target) {
            mention.link = url
        }
        result.append(mention)

        let body = " " + logTemplateRegistry.resolveDisplayBody(for: event)
        result.append(buildAttributedBody(body, defaultColor: defaultColor))
        return result
    }

    /// Universal `@handle` body renderer. Walks the body and turns any `@<uuid>` (preferred,
    /// id-keyed) **or** `@<Name>` (back-compat, longest-prefix name match) substring matching a
    /// known task or slot into a colored, clickable AttributedString span.
    ///
    /// Id-based path is unambiguous (no name collisions, survives renames, surfaces deletions as
    /// `@<deleted>`) and is the canonical authoring form — catalog templates emit `@{{taskID}}` /
    /// `@{{slotID}}` (assignment id) and the catalog `{{...}}` interpolation hands a literal UUID
    /// string to this renderer. The name path stays as a fallback for handwritten / legacy
    /// templates so nothing breaks during migration.
    ///
    /// Future MCR sites can just emit `@<id>` in their template body and this renderer will tint +
    /// link it automatically — no changes needed at the call site or in the catalog.
    private func buildAttributedBody(_ body: String, defaultColor: Color) -> AttributedString {
        struct NameCandidate {
            let name: String
            let color: Color
            let url: URL?
        }
        var nameCandidates: [NameCandidate] = []
        if let mission = resolvedMission {
            for (idx, task) in mission.routeMacro.tasks.enumerated() where !task.name.isEmpty {
                nameCandidates.append(
                    NameCandidate(
                        name: task.name,
                        color: MissionTaskMapColor.swiftUIColor(forTaskIndex: idx),
                        url: URL(string: "guardian://mcr/task/\(task.id.uuidString)")
                    )
                )
            }
        }
        for assignment in run.assignments where !assignment.slotName.isEmpty {
            nameCandidates.append(
                NameCandidate(
                    name: assignment.slotName,
                    color: slotSpeakerColor(slotName: assignment.slotName),
                    url: URL(string: "guardian://mcr/slot/\(assignment.id.uuidString)")
                )
            )
        }
        nameCandidates.sort { $0.name.count > $1.name.count }

        let mutedColor = Color.gray.opacity(0.6)
        let deletedDisplay = "deleted"

        var result = AttributedString("")
        var i = body.startIndex
        var pending = ""

        func flushPending() {
            if !pending.isEmpty {
                var p = AttributedString(pending)
                p.foregroundColor = defaultColor
                result.append(p)
                pending = ""
            }
        }

        func appendMention(display: String, color: Color, url: URL?) {
            flushPending()
            var mention = AttributedString("@\(display)")
            mention.foregroundColor = color
            if let url { mention.link = url }
            result.append(mention)
        }

        while i < body.endIndex {
            if body[i] == "@" {
                let after = body.index(after: i)

                if let uuidEnd = body.index(after, offsetBy: 36, limitedBy: body.endIndex) {
                    let candidate = String(body[after..<uuidEnd])
                    if let uuid = UUID(uuidString: candidate) {
                        if let assignment = run.assignments.first(where: { $0.id == uuid }) {
                            appendMention(
                                display: assignment.slotName.isEmpty
                                    ? "slot:\(uuid.uuidString.prefix(8))"
                                    : assignment.slotName,
                                color: slotSpeakerColor(slotName: assignment.slotName),
                                url: URL(string: "guardian://mcr/slot/\(uuid.uuidString)")
                            )
                            i = uuidEnd
                            continue
                        }
                        if let mission = resolvedMission,
                           let idx = mission.routeMacro.tasks.firstIndex(where: { $0.id == uuid }) {
                            let task = mission.routeMacro.tasks[idx]
                            appendMention(
                                display: task.name.isEmpty ? "task:\(uuid.uuidString.prefix(8))" : task.name,
                                color: MissionTaskMapColor.swiftUIColor(forTaskIndex: idx),
                                url: URL(string: "guardian://mcr/task/\(uuid.uuidString)")
                            )
                            i = uuidEnd
                            continue
                        }
                        appendMention(display: deletedDisplay, color: mutedColor, url: nil)
                        i = uuidEnd
                        continue
                    }
                }

                let suffix = body[after...]
                if let match = nameCandidates.first(where: { suffix.hasPrefix($0.name) }) {
                    appendMention(display: match.name, color: match.color, url: match.url)
                    i = body.index(i, offsetBy: match.name.count + 1)
                    continue
                }
            }
            pending.append(body[i])
            i = body.index(after: i)
        }
        flushPending()
        return result
    }

    /// Display token for an `@target` mention. Lower-case for role kinds (`missionControl`,
    /// `operator`) so they read like handles; task / slot resolve to their current human name from
    /// the live mission / assignment set (id-keyed for slots so renames stay live and deleted slots
    /// surface as `slot:<short uuid>`); assistants use their registered display name from
    /// ``MissionRunAssistantRegistry`` (lower-cased to read like a handle, e.g. `@paladin`).
    private func mcrTargetDisplayName(_ target: MissionRunEventTarget) -> String {
        switch target {
        case .missionControl: return "missionControl"
        case .assistant(let key):
            let name = MissionRunAssistantRegistry.shared.displayName(forKey: key)
            return name.isEmpty ? key : name.lowercased()
        case .task(_, let name): return name
        case .slot(let id):
            if let name = run.assignments.first(where: { $0.id == id })?.slotName, !name.isEmpty {
                return name
            }
            return "slot:\(id.uuidString.prefix(8))"
        case .operator(let displayName):
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "operator" : trimmed
        }
    }

    private func mcrTargetColor(_ target: MissionRunEventTarget) -> Color {
        switch target {
        case .missionControl: return theme.textPrimary
        case .assistant: return theme.textPrimary
        case .task(let id, _):
            if let idx = resolvedMission?.routeMacro.tasks.firstIndex(where: { $0.id == id }) {
                return MissionTaskMapColor.swiftUIColor(forTaskIndex: idx)
            }
            return Color.gray.opacity(0.85)
        case .slot(let id):
            if let name = run.assignments.first(where: { $0.id == id })?.slotName, !name.isEmpty {
                return slotSpeakerColor(slotName: name)
            }
            return Color.gray.opacity(0.6)
        case .operator: return theme.textPrimary
        }
    }

    private func mcrTargetLinkURL(_ target: MissionRunEventTarget) -> URL? {
        switch target {
        case .missionControl, .assistant, .operator:
            return nil
        case .task(let id, _):
            return URL(string: "guardian://mcr/task/\(id.uuidString)")
        case .slot(let id):
            return URL(string: "guardian://mcr/slot/\(id.uuidString)")
        }
    }

    /// `OpenURLAction` handler installed on the MCR log scroll: routes `guardian://mcr/...` clicks
    /// to the matching `focusLive*` helper so `@Alpha` opens the vehicle overlay and `@Continuous`
    /// opens the task triage. Returns `.discarded` for unrecognized hosts so they don't leak out
    /// to the system handler.
    private func handleMcrLogURL(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "guardian", url.host == "mcr" else { return .discarded }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return .discarded }
        switch parts[0] {
        case "task":
            focusLiveTask(id)
            return .handled
        case "slot":
            focusLiveAssignment(id)
            return .handled
        default:
            return .discarded
        }
    }

    /// Canonical color for a roster slot's speaker / mention attribution: bound vehicle map
    /// color when telemetry resolves, otherwise a neutral gray (matches the prior fallback).
    private func slotSpeakerColor(slotName: String) -> Color {
        guard let a = run.assignments.first(where: { $0.slotName == slotName }),
              let vid = resolvedFleetStreamVehicleID(assignment: a, fleetLink: fleetLink, sitl: sitl)
        else { return Color.gray.opacity(0.9) }
        return colorFromMapHex(fleetLink.mapColorHex(forVehicleID: vid))
    }

    private func copyLiveLogToPasteboard() {
        guard !liveLogEventsFiltered.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(
            liveLogPlainText(events: liveLogEventsFiltered, phase: run.sessionPhase, plan: run.compiledPlan),
            forType: .string
        )
    }

    /// Same chrome rhythm as ``SettingsView/settingsGroupCardConfiguration`` (header strip + body).
    private var mcSetupGroupCardConfiguration: GuardianCardConfiguration {
        GuardianCardConfiguration(
            border: .subtle,
            cornerRadius: GuardianCardLayout.cornerRadius,
            bodyPadding: GuardianCardLayout.defaultBodyPadding
        )
    }

    @ViewBuilder
    private func mcSetupGroupCardTitle(_ title: String) -> some View {
        Text(title)
            .font(GuardianTypography.font(.sectionHeadingSemibold))
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Label + optional description + trailing control — mirrors ``SettingsView/settingsRow``.
    private func mcSetupSettingsRow<Trailing: View>(
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: GuardianSpacing.lg) {
            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                Text(title)
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(theme.textPrimary)
                if !description.isEmpty {
                    Text(description)
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mcSetupRowDivider: some View {
        Rectangle()
            .fill(theme.borderSubtle)
            .frame(height: 1)
            .padding(.vertical, GuardianSpacing.sm)
    }

    private var setupScheduleCard: some View {
        GuardianCard(
            configuration: mcSetupGroupCardConfiguration,
            header: { mcSetupGroupCardTitle("Schedule") },
            body: {
                scheduleSetupScheduleTabContent
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setupTasksDelaysCard: some View {
        GuardianCard(
            configuration: mcSetupGroupCardConfiguration,
            header: { mcSetupGroupCardTitle("Tasks") },
            body: {
                scheduleSetupTasksTabContent
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Two headered cards side-by-side when space allows; stacked in narrow widths. No ``GeometryReader`` inside ``ScrollView``.
    private var setupTimingTabContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: GuardianSpacing.md) {
                setupScheduleCard
                setupTasksDelaysCard
            }
            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                setupScheduleCard
                setupTasksDelaysCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var setupRostersTabContent: some View {
        GeometryReader { geo in
            let stackVertically = geo.size.width < MissionRunPrepLayout.rostersMapAccordionStackBreakpoint
            let totalH = geo.size.height
            let totalW = geo.size.width
            let rowGap: CGFloat = GuardianSpacing.cardBodyInset
            let mapW = stackVertically ? totalW : max(0, (totalW - rowGap) * 0.7)
            let accW = stackVertically ? totalW : max(0, (totalW - rowGap) * 0.3)
            Group {
                if stackVertically {
                    VStack(alignment: .leading, spacing: rowGap) {
                        rostersStagingMapBare
                            .frame(width: mapW, height: max(200, (totalH - rowGap) * 0.52), alignment: .topLeading)
                        rostersAccordionColumn
                            .frame(width: accW, height: max(160, (totalH - rowGap) * 0.48 - rowGap), alignment: .topLeading)
                    }
                } else {
                    HStack(alignment: .top, spacing: rowGap) {
                        rostersStagingMapBare
                            .frame(width: mapW, height: totalH, alignment: .topLeading)
                        rostersAccordionColumn
                            .frame(width: accW, height: totalH, alignment: .topLeading)
                    }
                }
            }
            .frame(width: totalW, height: totalH, alignment: .topLeading)
        }
    }

    private var rostersAccordionColumn: some View {
        GuardianCard(
            configuration: mcSetupGroupCardConfiguration,
            body: {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                            if let mission = resolvedMission {
                                rostersSidebarTabChromeRow(mission: mission)
                                switch rostersSidebarListTab {
                                case .tasks:
                                    if run.assignments.isEmpty {
                                        Text("No roster slots on this mission template.")
                                            .foregroundStyle(theme.textSecondary)
                                    } else {
                                        ForEach(mission.routeMacro.tasks) { task in
                                            taskRosterAccordionSection(task: task, mission: mission)
                                        }
                                        legacyRostersAccordionSection(mission: mission)
                                    }
                                case .points:
                                    mcsRosterMissionPointsListScroll(mission: mission)
                                }
                            } else {
                                missionMissingTemplateRosterFallback
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .onChange(of: setupRostersMapPointsListScrollEpoch) { _ in
                        guard let id = setupRostersMapPointsListScrollTargetRow else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.22)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rostersSidebarTabChromeRow(mission: Mission) -> some View {
        let emptyAll = emptyRosterSlotCountAcrossMission(mission: mission)
        let busy = rosterBulkSimSpawnBusy != nil
        return HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            HStack(spacing: GuardianSpacing.denseGutter) {
                Picker("", selection: $rostersSidebarListTab) {
                    ForEach(MissionControlSetupRostersSidebarTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: GuardianSpacing.sm)

            if rostersSidebarListTab == .tasks, !run.assignments.isEmpty, fleetLink.isSimulateEnabled {
                Button {
                    presentedRunConfirm = .bulkSpawnSims(.allMissionSlots)
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                }
                .buttonStyle(.bordered).guardianPointerOnHover()
                .controlSize(.small)
                .disabled(emptyAll == 0 || bulkSpawnSimsConfirmIsActive || busy)
                .help(
                    "Spawn a sim for every empty roster slot in this mission (all tasks and the mission roster, if any). Uses each slot’s class and your default stack and spawn location from Settings."
                )
            }

            if rostersSidebarListTab == .points {
                GuardianPrimaryProminentButton(title: "Add point") {
                    appendSetupRosterMissionPointAtViewportCenter()
                }
                .guardianPointerOnHover()
            }
        }
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .padding(.vertical, GuardianSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func mcsRosterMissionPointsListScroll(mission: Mission) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            if mission.missionPoints.isEmpty {
                Text("No map points yet.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textTertiary)
            } else {
                ForEach(mission.missionPoints, id: \.id) { mp in
                    mcsRosterMissionPointListRow(mp: mp)
                        .id(mp.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func mcsRosterMissionPointListRow(mp: MissionPoint) -> some View {
        let sel = mp.id == setupRostersSelectedMissionPointID
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianSpacing.cardBodyInset
            ),
            body: {
                HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                    VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                        Text(mp.mapChipLabel)
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(mp.isClosed ? theme.textTertiary : theme.textPrimary)
                            .strikethrough(mp.isClosed)
                        Text(mp.kind.rawValue.capitalized)
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GuardianThemedButton(
                        accent: .primary,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: { toggleSetupRostersMissionPointEditDrawer(missionPointID: mp.id) },
                        label: {
                            Image(systemName: "pencil")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Open or close edit drawer")

                    GuardianThemedButton(
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        contentSizing: .squareToolbarCell,
                        action: { setupRostersMissionPointDeleteCandidate = MissionControlSetupRosterMissionPointDeleteCandidate(id: mp.id) },
                        label: {
                            Image(systemName: "trash")
                                .font(GuardianTypography.font(.sectionHeadingSemibold))
                        }
                    )
                    .help("Delete map point")
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSetupRostersMissionPointMapSelection(missionPointID: mp.id)
        }
        .overlay {
            if sel {
                RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                    .strokeBorder(GuardianSemanticColors.infoForeground.opacity(0.45), lineWidth: 2)
            }
        }
    }

    private func missionRunAssignmentBelongsToTask(
        _ assignment: MissionRunAssignment,
        task: MissionTask,
        mission: Mission
    ) -> Bool {
        if assignment.taskId == task.id { return true }
        if assignment.taskId == nil {
            let enabled = mission.routeMacro.tasks.filter(\.enabled)
            if enabled.count == 1, enabled.first?.id == task.id { return true }
        }
        return false
    }

    /// Same ordering as ``MissionsView/taskRosterDisplayRows``: primaries in roster order, then each primary’s wingmen and reserves.
    private func missionRunTaskRosterOrderedSlots(task: MissionTask, mission: Mission) -> [(assignmentIndex: Int, indent: Int)] {
        let ids = task.rosterDeviceIds
        func device(for rosterId: UUID) -> RosterDevice? {
            mission.rosterDevices.first { $0.id == rosterId }
        }
        func slot(for rosterId: UUID, indent: Int) -> (assignmentIndex: Int, indent: Int)? {
            guard let idx = run.assignments.firstIndex(where: {
                $0.rosterDeviceId == rosterId && missionRunAssignmentBelongsToTask($0, task: task, mission: mission)
            }) else { return nil }
            return (idx, indent)
        }
        var emitted = Set<UUID>()
        var rows: [(assignmentIndex: Int, indent: Int)] = []
        let primaryIds = ids.filter { device(for: $0)?.slot == .primary }
        for pid in primaryIds {
            guard device(for: pid)?.slot == .primary else { continue }
            if let r = slot(for: pid, indent: 0) {
                rows.append(r)
                emitted.insert(pid)
            }
            let wingmanIds = ids.filter {
                guard let d = device(for: $0), d.slot == .wingman, d.leaderRosterDeviceId == pid else { return false }
                return true
            }
            let reserveIds = ids.filter {
                guard let d = device(for: $0), d.slot == .reserve, d.leaderRosterDeviceId == pid else { return false }
                return true
            }
            for wid in wingmanIds {
                if let r = slot(for: wid, indent: 1) {
                    rows.append(r)
                    emitted.insert(wid)
                }
            }
            for rid in reserveIds {
                if let r = slot(for: rid, indent: 1) {
                    rows.append(r)
                    emitted.insert(rid)
                }
            }
        }
        for id in ids where !emitted.contains(id) {
            let d = device(for: id)
            let indent = (d?.slot == .wingman || d?.slot == .reserve) ? 1 : 0
            if let r = slot(for: id, indent: indent) {
                rows.append(r)
                emitted.insert(id)
            }
        }
        return rows
    }

    private func missionRunLegacyRosterOrderedSlots(mission: Mission) -> [(assignmentIndex: Int, indent: Int)] {
        let indices = legacyUnassignedIndices
        let devicesById = Dictionary(uniqueKeysWithValues: mission.rosterDevices.map { ($0.id, $0) })
        let order = mission.rosterDevices.map(\.id)
        let sorted = indices.sorted {
            let da = run.assignments[$0].rosterDeviceId
            let db = run.assignments[$1].rosterDeviceId
            let ia = order.firstIndex(of: da) ?? Int.max
            let ib = order.firstIndex(of: db) ?? Int.max
            return ia < ib
        }
        return sorted.map { idx in
            let rid = run.assignments[idx].rosterDeviceId
            let d = devicesById[rid]
            let indent = (d?.slot == .wingman || d?.slot == .reserve) ? 1 : 0
            return (idx, indent)
        }
    }

    /// Inset accordion title row (elevated strip + hairline) — not a nested ``GuardianCard``; sits inside the roster column card.
    private func mcRosterAccordionHeaderChrome(
        title: String,
        filled: Int,
        total: Int,
        isExpanded: Bool,
        enabled: Bool
    ) -> some View {
        HStack(spacing: GuardianSpacing.xs) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(GuardianTypography.font(.formFieldLabel))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 14, alignment: .center)
            Text(title)
                .font(GuardianTypography.font(.subsectionTitleSemibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: GuardianSpacing.xsTight)
            Text("\(filled)/\(total)")
                .font(GuardianTypography.font(.inlineNoticeDetail))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .padding(.vertical, GuardianSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        )
        .opacity(enabled ? 1 : 0.55)
    }

    @ViewBuilder
    private func taskRosterAccordionSection(task: MissionTask, mission: Mission) -> some View {
        let expanded = rosterSetupExpandedTaskIDs.contains(task.id)
        let indices = run.assignments.indices.filter { missionRunAssignmentBelongsToTask(run.assignments[$0], task: task, mission: mission) }
        let filled = indices.filter { run.assignments[$0].hasFleetOrLegacyAssignment }.count
        let emptyRosterSlotCount = indices.count - filled
        let rows = missionRunTaskRosterOrderedSlots(task: task, mission: mission)
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                Button {
                    if expanded {
                        rosterSetupExpandedTaskIDs.remove(task.id)
                    } else {
                        rosterSetupExpandedTaskIDs.insert(task.id)
                    }
                } label: {
                    mcRosterAccordionHeaderChrome(
                        title: task.name,
                        filled: filled,
                        total: indices.count,
                        isExpanded: expanded,
                        enabled: task.enabled
                    )
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    presentTaskSettingsSidebar(task: task)
                } label: {
                    Image(systemName: "gearshape")
                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                }
                .buttonStyle(.bordered).guardianPointerOnHover()
                .controlSize(.small)
                .help("Task settings")

                if fleetLink.isSimulateEnabled {
                    Button {
                        presentedRunConfirm = .bulkSpawnSims(.singleTask(task.id))
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                    }
                    .buttonStyle(.bordered).guardianPointerOnHover()
                    .controlSize(.small)
                    .disabled(
                        emptyRosterSlotCount == 0
                            || bulkSpawnSimsConfirmIsActive
                            || rosterBulkSimSpawnBusy != nil
                    )
                    .help("Spawn a sim for each empty roster slot (class + default stack in Settings).")
                }
            }

            if expanded {
                rostersOrderedSlotsList(rows: rows, mission: mission)
            }
        }
    }

    @ViewBuilder
    private func rostersOrderedSlotsList(rows: [(assignmentIndex: Int, indent: Int)], mission: Mission?) -> some View {
        if rows.isEmpty {
            Text("No roster slots linked to this task. Link devices to the task in Missions → Roster.")
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: MissionRunPrepLayout.rosterGridSpacing) {
                ForEach(rows, id: \.assignmentIndex) { row in
                    rosterSlotCard(assignmentIndex: row.assignmentIndex, mission: mission)
                        .padding(.leading, CGFloat(row.indent) * MissionRunPrepLayout.rosterSlotWingmanIndent)
                }
            }
        }
    }

    @ViewBuilder
    private func legacyRostersAccordionSection(mission: Mission) -> some View {
        let indices = legacyUnassignedIndices
        if !indices.isEmpty {
            let expanded = rosterSetupLegacyMissionRosterExpanded
            let filled = indices.filter { run.assignments[$0].hasFleetOrLegacyAssignment }.count
            let rows = missionRunLegacyRosterOrderedSlots(mission: mission)
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                Button {
                    rosterSetupLegacyMissionRosterExpanded.toggle()
                } label: {
                    mcRosterAccordionHeaderChrome(
                        title: "Mission roster",
                        filled: filled,
                        total: indices.count,
                        isExpanded: expanded,
                        enabled: true
                    )
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())

                if rosterSetupLegacyMissionRosterExpanded {
                    rostersOrderedSlotsList(rows: rows, mission: mission)
                }
            }
        }
    }

    private var setupRulesPoliciesCard: some View {
        GuardianCard(
            configuration: mcSetupGroupCardConfiguration,
            header: { mcSetupGroupCardTitle("Policies") },
            body: {
                if resolvedMission != nil {
                    VStack(spacing: 0) {
                        mcSetupSettingsRow(
                            title: "Abort Policy",
                            description:
                                "Mission-wide default when a task (or roster slot) does not set its own abort policy."
                        ) {
                            Picker("", selection: missionAbortPolicyBinding) {
                                ForEach(MissionRunAbortPolicy.setupPickerCases, id: \.self) { policy in
                                    Text(policy.setupMenuLabel).tag(policy)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(minWidth: 160, alignment: .trailing)
                        }
                        mcSetupRowDivider
                        mcSetupSettingsRow(
                            title: "Complete Policy",
                            description:
                                "Mission-wide default for recovery wind-down when a task or roster slot does not override it."
                        ) {
                            Picker("", selection: missionCompletePolicyBinding) {
                                ForEach(MissionRunCompletePolicy.setupPickerCases, id: \.self) { policy in
                                    Text(policy.setupMenuLabel).tag(policy)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(minWidth: 160, alignment: .trailing)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                        Text("Mission defaults unavailable")
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(
                            "This run’s mission is not in the library (or failed to load). Add or restore the mission to edit abort/complete defaults."
                        )
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setupRulesEngagementCard: some View {
        GuardianCard(
            configuration: mcSetupGroupCardConfiguration,
            header: { mcSetupGroupCardTitle("Rules of engagement") },
            body: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(
                        "Paladin and Mission Control resolve these dispositions when an action is requested during a run. Unlisted actions default to autonomous."
                    )
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, GuardianSpacing.xs)

                    ForEach(MissionRunEngagementAction.allCases.indices, id: \.self) { idx in
                        let action = MissionRunEngagementAction.allCases[idx]
                        if idx > 0 {
                            mcSetupRowDivider
                        }
                        mcSetupSettingsRow(title: action.setupLabel, description: "") {
                            Picker("", selection: engagementDispositionBinding(for: action)) {
                                ForEach(MissionRunEngagementDisposition.allCases, id: \.self) { disposition in
                                    Text(disposition.setupMenuLabel).tag(disposition)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(minWidth: 160, alignment: .trailing)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setupRulesTabContent: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.md) {
            setupRulesPoliciesCard
            setupRulesEngagementCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func persistMissionMutation(_ mutate: (inout Mission) -> Void) {
        guard var mission = missionStore.missions.first(where: { $0.id == run.missionId }) else { return }
        mutate(&mission)
        missionStore.updateMission(mission)
        if let fresh = missionStore.missions.first(where: { $0.id == mission.id }) {
            run.updateTemplate(fresh)
        } else {
            run.updateTemplate(mission)
        }
        onUpdate(run)
    }

    /// Wires the MRE template persister so mission / task policy edits routed through
    /// ``MissionRunEnvironment`` policy APIs (cog sidebar, future assistants) survive a refresh
    /// by writing through to the ``MissionStore``.
    private func installMissionTemplatePersister() {
        run.missionTemplatePersister = { [weak missionStore, weak run] mission in
            guard let missionStore else { return }
            missionStore.updateMission(mission)
            if let fresh = missionStore.missions.first(where: { $0.id == mission.id }) {
                run?.updateTemplate(fresh)
            } else {
                run?.updateTemplate(mission)
            }
        }
    }

    /// Local operator credential for MRE policy / Rules-of-Engagement edits made from this screen.
    /// `displayName` is the live callsign so log lines render as `[Operator][<callsign>]`.
    private var localOperatorCredential: MissionRunPolicyEditCredential {
        .localOperator(callsign: generalSettings.callsign)
    }

    private var missionAbortPolicyBinding: Binding<MissionRunAbortPolicy> {
        Binding(
            get: {
                missionStore.missions.first(where: { $0.id == run.missionId })?.routeMacro.rules.missionAbortPolicy
                    ?? .returnToLaunch
            },
            set: { newValue in
                _ = run.updateMissionAbortPolicy(newValue, credential: localOperatorCredential)
                syncRunFromStore()
                onUpdate(run)
            }
        )
    }

    private var missionCompletePolicyBinding: Binding<MissionRunCompletePolicy> {
        Binding(
            get: {
                missionStore.missions.first(where: { $0.id == run.missionId })?.routeMacro.rules.missionCompletePolicy
                    ?? .returnToLaunch
            },
            set: { newValue in
                _ = run.updateMissionCompletePolicy(newValue, credential: localOperatorCredential)
                syncRunFromStore()
                onUpdate(run)
            }
        )
    }

    private func engagementDispositionBinding(for action: MissionRunEngagementAction) -> Binding<MissionRunEngagementDisposition> {
        Binding(
            get: {
                run.resolvedEngagementDisposition(for: action)
            },
            set: { newDisposition in
                _ = run.updateMissionEngagementDisposition(
                    action: action,
                    disposition: newDisposition,
                    credential: localOperatorCredential
                )
                onUpdate(run)
            }
        )
    }

    private func templateMissionTask(forTaskId taskId: UUID) -> MissionTask? {
        resolvedMission?.routeMacro.tasks.first(where: { $0.id == taskId })
    }

    private func commitTaskStartDelayOverride(taskId: UUID, value: Double, unit: DelayUnit, template: MissionTask) {
        let newRow = TaskStartDelay(taskId: taskId, startDelayValue: value, startDelayUnit: unit)
        var list = run.taskStartDelays
        list.removeAll { $0.taskId == taskId }
        let tSecs = Int(template.startDelayTotalSeconds.rounded())
        let nSecs = Int(newRow.totalSeconds.rounded())
        if tSecs != nSecs {
            list.append(newRow)
        }
        run.taskStartDelays = list
        onUpdate(run)
    }

    /// Run override if present, otherwise the mission template task’s start delay (same value+unit model as Missions authoring).
    private func taskStartDelayValueBinding(for task: MissionTask) -> Binding<Double> {
        Binding(
            get: {
                if let o = run.taskStartDelays.first(where: { $0.taskId == task.id }) {
                    return o.startDelayValue
                }
                return templateMissionTask(forTaskId: task.id)?.startDelayValue ?? task.startDelayValue
            },
            set: { newVal in
                let tmpl = templateMissionTask(forTaskId: task.id) ?? task
                let unit = run.taskStartDelays.first(where: { $0.taskId == task.id })?.startDelayUnit ?? tmpl.startDelayUnit
                commitTaskStartDelayOverride(taskId: task.id, value: newVal, unit: unit, template: tmpl)
            }
        )
    }

    private func taskStartDelayUnitBinding(for task: MissionTask) -> Binding<DelayUnit> {
        Binding(
            get: {
                run.taskStartDelays.first(where: { $0.taskId == task.id })?.startDelayUnit
                    ?? templateMissionTask(forTaskId: task.id)?.startDelayUnit
                    ?? task.startDelayUnit
            },
            set: { newUnit in
                let tmpl = templateMissionTask(forTaskId: task.id) ?? task
                let val = run.taskStartDelays.first(where: { $0.taskId == task.id })?.startDelayValue ?? tmpl.startDelayValue
                commitTaskStartDelayOverride(taskId: task.id, value: val, unit: newUnit, template: tmpl)
            }
        )
    }

    private func missionControlTaskStartDelayFieldRow(task: MissionTask) -> some View {
        HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
            Text(task.name)
                .font(GuardianTypography.font(.inlineNoticeTitle))
                .foregroundStyle(task.enabled ? theme.textPrimary : theme.textSecondary.opacity(0.72))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: GuardianSpacing.xs)
            MissionDelayValueUnitEditor(
                label: "",
                value: taskStartDelayValueBinding(for: task),
                unit: taskStartDelayUnitBinding(for: task),
                minimumTotalSeconds: 0,
                numericFieldWidth: 88,
                unitPickerWidth: 68,
                labelColumnWidth: 0,
                secondaryLabelColor: theme.textSecondary,
                controlSize: .regular
            )
        }
        .opacity(task.enabled ? 1 : 0.55)
    }

    private var scheduleSetupTasksTabContent: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.scheduleCardSpacing) {
            Text("Manage task start delays")
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let mission = resolvedMission {
                ForEach(mission.routeMacro.tasks) { task in
                    missionControlTaskStartDelayFieldRow(task: task)
                }
            } else {
                Text("Mission template unavailable for this run.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var scheduleSetupScheduleTabContent: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.scheduleCardSpacing) {
            Toggle(
                "Start immediately",
                isOn: Binding(
                    get: { run.oneOffStartAt == nil },
                    set: { immediate in
                        if immediate {
                            run.oneOffStartAt = nil
                        } else if run.oneOffStartAt == nil {
                            run.oneOffStartAt = scheduleDefaultDeferredStartDate()
                        }
                        onUpdate(run)
                    }
                )
            )
            .tint(.blue)

            if run.oneOffStartAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                        DatePicker(
                            "Start date & time",
                            selection: Binding(
                                get: { run.oneOffStartAt ?? Date() },
                                set: { run.oneOffStartAt = $0; onUpdate(run) }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        if run.oneOffScheduledTimeTooFarInPast(referenceNow: context.date) {
                            Text("That time is in the past. Move it forward or enable “Start immediately”.")
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(Color.orange.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func scheduleDefaultDeferredStartDate() -> Date {
        Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
    }

    /// Setup **Tasks** tab: staging map in a media-only ``GuardianCard`` (matches accordion column chrome).
    private var rostersStagingMapBare: some View {
        GuardianCard(
            configuration: mcSetupGroupCardConfiguration,
            media: {
                GuardianMapView(
                    model: mapModel,
                    contextMenuPolicy: GuardianMapContextMenuPolicy(
                        vehicleActions: [],
                        waypointActions: [],
                        homeActions: [],
                        missionPointActions: rostersSidebarListTab == .points ? [.deleteMissionPoint] : []
                    ),
                    onMapClick: { _, _ in
                        clearStagingSetupMapSelectionFromBackgroundTap()
                    },
                    onVehicleMarkerMoved: { markerID, lat, lon in
                        applySetupMarkerDrag(markerID: markerID, lat: lat, lon: lon)
                    },
                    onContextAction: { event in
                        guard rostersSidebarListTab == .points,
                              event.markerType == .missionPoint,
                              event.action == .deleteMissionPoint,
                              let raw = event.markerID,
                              let uuid = UUID(uuidString: raw)
                        else { return }
                        setupRostersMissionPointDeleteCandidate = MissionControlSetupRosterMissionPointDeleteCandidate(id: uuid)
                    },
                    onMissionPointClick: { id in
                        toggleSetupRostersMissionPointMapSelection(missionPointID: id)
                    },
                    onMissionPointMoved: { id, lat, lon in
                        persistMissionMutation { mission in
                            guard let idx = mission.missionPoints.firstIndex(where: { $0.id == id }) else { return }
                            mission.missionPoints[idx].coordinate.lat = lat
                            mission.missionPoints[idx].coordinate.lon = lon
                        }
                    },
                    onVehicleTap: { ev in
                        guard let raw = ev.markerID, let aid = UUID(uuidString: raw) else { return }
                        toggleStagingVehicleMapSelection(assignmentId: aid)
                    },
                    onTaskPathTap: { ev in
                        setupStagingMapSelectedTaskPathID = ev.taskPathID
                        setupRostersSelectedMissionPointID = nil
                        setupSelectedAssignmentId = nil
                        setupStagingSimDragCoordByAssignmentID.removeAll()
                        dismissSetupRostersMissionPointDrawerIfNeeded()
                    },
                    onViewportCenterChanged: { lat, lon in
                        setupRostersMapViewportCenter = RouteCoordinate(lat: lat, lon: lon)
                    }
                )
                .task(id: setupStagingMapStructureIdentity) {
                    pushSetupStagingMapModelFromMissionTemplate()
                }
                .onChange(of: setupStagingMapMarkerCoordinateDigest) { _ in
                    pushSetupStagingMapMarkersOnly()
                    reconcileSetupStagingSimDragOverlayWithHubTelemetry()
                }
                .onChange(of: fleetLink.hubTelemetry?.lastUpdate) { _ in
                    reconcileSetupStagingSimDragOverlayWithHubTelemetry()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
    }

    /// Topology + bindings for staging map geometry (no live coordinates — see ``setupStagingMapMarkerCoordinateDigest``).
    private var setupStagingMapStructureIdentity: SetupStagingMapStructureIdentity {
        let mission = resolvedMission
        let rows = setupStagingMissionPointRowsForMap
        let topo = rows
            .map { mp in
                let sel = setupRostersSelectedMissionPointID == mp.id ? "1" : "0"
                return "\(mp.id.uuidString)|\(mp.kind.rawValue)|\(mp.isClosed)|\(sel)"
            }
            .joined(separator: ";")
        return SetupStagingMapStructureIdentity(
            missionID: mission?.id,
            homeCoord: mission?.routeMacro.home?.coord,
            allTasksCoords: mission?.routeMacro.tasks.map { $0.waypoints.map(\.coord) } ?? [],
            taskPathIDs: mission?.routeMacro.tasks.map(\.id) ?? [],
            missionPointTopologySignature: topo,
            assignmentFleetBindingSignature: setupMapBoundsSignature,
            rosterStagingMissionPointChrome: MissionControlSetupRosterStagingMissionPointChrome(
                listTab: rostersSidebarListTab,
                selectedPointID: setupRostersSelectedMissionPointID
            ),
            selectedTaskPathID: setupStagingMapSelectedTaskPathID,
            selectedStagingRosterAssignmentID: setupSelectedAssignmentId
        )
    }

    /// Quantized lat/lon for mission map points + roster vehicle markers; drives marker-only pushes without churning `.task(id:)`.
    private var setupStagingMapMarkerCoordinateDigest: String {
        let pts = setupStagingMissionPointRowsForMap
            .map { mp in
                String(format: "%@:%.5f:%.5f", mp.id.uuidString, mp.coordinate.lat, mp.coordinate.lon)
            }
            .joined(separator: "|")
        let veh = setupVehicleMarkers
            .map { m in
                String(format: "%@:%.5f:%.5f", m.id, m.lat, m.lon)
            }
            .joined(separator: "|")
        return pts + "§" + veh
    }

    /// Clears mission-point / task-path / roster-vehicle map selection after a map background tap (same policy as mutual exclusivity elsewhere).
    private func clearStagingSetupMapSelectionFromBackgroundTap() {
        setupRostersSelectedMissionPointID = nil
        setupStagingMapSelectedTaskPathID = nil
        setupSelectedAssignmentId = nil
        setupStagingSimDragCoordByAssignmentID.removeAll()
        dismissSetupRostersMissionPointDrawerIfNeeded()
    }

    /// Roster staging map: toggle which assignment is selected for vehicle ring + SIM drag (clears point / task-path map selection).
    private func toggleStagingVehicleMapSelection(assignmentId: UUID) {
        if setupSelectedAssignmentId == assignmentId {
            setupSelectedAssignmentId = nil
            setupStagingSimDragCoordByAssignmentID.removeValue(forKey: assignmentId)
        } else {
            setupRostersSelectedMissionPointID = nil
            setupStagingMapSelectedTaskPathID = nil
            dismissSetupRostersMissionPointDrawerIfNeeded()
            setupStagingSimDragCoordByAssignmentID.removeAll()
            setupSelectedAssignmentId = assignmentId
        }
    }

    /// Hub lat/lon for a roster assignment when it is bound to SITL and telemetry exists (for drag-overlay reconcile).
    private func stagingSimHubCoordinate(forAssignmentId assignmentId: UUID) -> RouteCoordinate? {
        guard let assignment = run.assignments.first(where: { $0.id == assignmentId }),
              let tokenKey = assignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: tokenKey),
              case .sitl(let sitlInstanceID) = token,
              let inst = sitl.instances.first(where: { $0.id == sitlInstanceID })
        else { return nil }
        let systemID = inst.stackInstanceIndex + 1
        let vehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
        guard let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else { return nil }
        return RouteCoordinate(lat: lat, lon: lon)
    }

    /// Drops SIM drag optimistic coords once hub reflects the same pose (avoids a visible jump back to stale telemetry).
    private func reconcileSetupStagingSimDragOverlayWithHubTelemetry() {
        guard !setupStagingSimDragCoordByAssignmentID.isEmpty else { return }
        let eps = 2.5e-5
        var toRemove: [UUID] = []
        for (aid, pending) in setupStagingSimDragCoordByAssignmentID {
            guard let hub = stagingSimHubCoordinate(forAssignmentId: aid) else { continue }
            if abs(hub.lat - pending.lat) < eps, abs(hub.lon - pending.lon) < eps {
                toRemove.append(aid)
            }
        }
        for aid in toRemove {
            setupStagingSimDragCoordByAssignmentID.removeValue(forKey: aid)
        }
    }

    private func pushSetupStagingMapModelFromMissionTemplate() {
        if let mission = resolvedMission {
            mapModel.routeGeometry = GuardianRouteMapGeometry(
                home: mission.routeMacro.home,
                allTasksCoords: mission.routeMacro.tasks.map { $0.waypoints.map(\.coord) },
                taskPathIDs: mission.routeMacro.tasks.map(\.id),
                selectedTaskWaypoints: [],
                selectedWaypointIndex: nil,
                headingPreview: nil,
                cameraPreview: nil,
                preserveView: true,
                isEditingTask: false,
                missionPointMarkers: setupStagingMissionPointMapMarkers,
                missionPointPlacementArmed: false
            )
        } else {
            mapModel.routeGeometry = .empty
        }
        mapModel.vehicleMarkers = setupVehicleMarkers
    }

    private func pushSetupStagingMapMarkersOnly() {
        guard let mission = resolvedMission else {
            pushSetupStagingMapModelFromMissionTemplate()
            return
        }
        let expectedIDs = mission.routeMacro.tasks.map(\.id)
        if mapModel.routeGeometry.taskPathIDs != expectedIDs {
            pushSetupStagingMapModelFromMissionTemplate()
            return
        }
        var geo = mapModel.routeGeometry
        geo.missionPointMarkers = setupStagingMissionPointMapMarkers
        mapModel.routeGeometry = geo
        mapModel.vehicleMarkers = setupVehicleMarkers
    }

    private var rosterMissionTemplateBinding: Binding<Mission> {
        Binding(
            get: {
                missionStore.missions.first(where: { $0.id == run.missionId })
                    ?? Mission(id: run.missionId, name: "", description: "", type: .mobile)
            },
            set: { newMission in
                missionStore.updateMission(newMission)
                if let fresh = missionStore.missions.first(where: { $0.id == newMission.id }) {
                    run.updateTemplate(fresh)
                } else {
                    run.updateTemplate(newMission)
                }
                onUpdate(run)
            }
        )
    }

    private func persistRosterMissionTemplateFromPointsEditor() {
        guard let m = missionStore.missions.first(where: { $0.id == run.missionId }) else { return }
        missionStore.updateMission(m)
        if let fresh = missionStore.missions.first(where: { $0.id == m.id }) {
            run.updateTemplate(fresh)
        } else {
            run.updateTemplate(m)
        }
        onUpdate(run)
    }

    private func clearSetupRostersMissionPointChrome() {
        setupRostersSelectedMissionPointID = nil
        setupRostersMissionPointDrawerEditingID = nil
        setupRostersMissionPointDeleteCandidate = nil
        setupStagingMapSelectedTaskPathID = nil
    }

    private func dismissSetupRostersMissionPointDrawerIfNeeded() {
        guard setupRostersMissionPointDrawerEditingID != nil else { return }
        setupRostersMissionPointDrawerEditingID = nil
        appDrawer.dismiss()
    }

    private func appendSetupRosterMissionPointAtViewportCenter() {
        let coord = setupRostersMapViewportCenter ?? RouteCoordinate()
        let newID = UUID()
        persistMissionMutation { mission in
            mission.missionPoints.append(
                MissionPoint(
                    id: newID,
                    pointId: "rally.0",
                    label: "",
                    kind: .rally,
                    coordinate: coord,
                    taskID: nil
                )
            )
            mission.renumberMissionPointSlugsByListOrder()
        }
        setupRostersSelectedMissionPointID = newID
        setupSelectedAssignmentId = nil
        setupStagingSimDragCoordByAssignmentID.removeAll()
        setupStagingMapSelectedTaskPathID = nil
        setupRostersMapPointsListScrollTargetRow = newID
        setupRostersMapPointsListScrollEpoch &+= 1
        toastCenter.show("Map point added — drag the pin on the map to move it", style: .success)
    }

    private func openSetupRostersMissionPointEditDrawer(missionPointID: UUID) {
        guard resolvedMission?.missionPoints.contains(where: { $0.id == missionPointID }) == true else { return }
        setupSelectedAssignmentId = nil
        setupStagingSimDragCoordByAssignmentID.removeAll()
        setupStagingMapSelectedTaskPathID = nil
        setupRostersSelectedMissionPointID = missionPointID
        setupRostersMissionPointDrawerEditingID = missionPointID
        appDrawer.present(title: "Edit map point", preferredWidth: 400, scrimTapDismisses: true) {
            MissionWorkspaceMissionPointEditDrawer(
                missionPointID: missionPointID,
                mission: rosterMissionTemplateBinding,
                onStructuralChange: {
                    persistMissionMutation { $0.renumberMissionPointSlugsByListOrder() }
                },
                persist: {
                    persistRosterMissionTemplateFromPointsEditor()
                }
            )
        }
    }

    private func toggleSetupRostersMissionPointEditDrawer(missionPointID: UUID) {
        guard resolvedMission?.missionPoints.contains(where: { $0.id == missionPointID }) == true else { return }
        if setupRostersMissionPointDrawerEditingID == missionPointID {
            setupRostersMissionPointDrawerEditingID = nil
            appDrawer.dismiss()
            return
        }
        openSetupRostersMissionPointEditDrawer(missionPointID: missionPointID)
    }

    private func toggleSetupRostersMissionPointMapSelection(missionPointID: UUID) {
        guard resolvedMission?.missionPoints.contains(where: { $0.id == missionPointID }) == true else { return }
        if setupRostersSelectedMissionPointID == missionPointID {
            setupRostersSelectedMissionPointID = nil
            if setupRostersMissionPointDrawerEditingID == missionPointID {
                setupRostersMissionPointDrawerEditingID = nil
                appDrawer.dismiss()
            }
        } else {
            setupSelectedAssignmentId = nil
            setupStagingSimDragCoordByAssignmentID.removeAll()
            setupStagingMapSelectedTaskPathID = nil
            if setupRostersMissionPointDrawerEditingID != nil {
                appDrawer.dismiss()
                setupRostersMissionPointDrawerEditingID = nil
            }
            setupRostersSelectedMissionPointID = missionPointID
        }
    }

    /// Bundled vehicle-class / SIM preset art — same basename resolution as ``MissionControlRosterSlotCard`` — for MCS staging and MCR live overview map thumbnails.
    private func missionControlRosterMapMarkerImageDataURL(for assignment: MissionRunAssignment) -> String? {
        let basenames: [String] = {
            if let sim = simulationImageBasenamesForAssignment(assignment, sitl: sitl), !sim.isEmpty {
                return sim
            }
            let device = resolvedMission.flatMap { m in
                m.rosterDevices.first { $0.id == assignment.rosterDeviceId }
            }
            let rosterDeviceClass = device?.vehicleClass ?? .unknown
            if let vid = telemetryVehicleID(for: assignment),
               let model = fleetLink.vehicleModel(forVehicleID: vid)
            {
                return model.data.vehicleType.defaultSimulationDeviceImageBasenames
            }
            return rosterDeviceClass.defaultSimulationDeviceImageBasenames
        }()
        guard let image = SimulationDeviceBundleImage.nsImage(firstMatching: basenames),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }

    private var setupVehicleMarkers: [MapVehicleMarker] {
        run.assignments.compactMap { assignment in
            guard let tokenKey = assignment.attachedFleetVehicleToken,
                  let token = FleetMissionVehicleToken(storageKey: tokenKey)
            else { return nil }
            let selected = assignment.id == setupSelectedAssignmentId
            let label = "\(assignment.slotName)"
            let imageDataURL = missionControlRosterMapMarkerImageDataURL(for: assignment)
            switch token {
            case .sitl(let uuid):
                guard let inst = sitl.instances.first(where: { $0.id == uuid }) else { return nil }
                let systemID = inst.stackInstanceIndex + 1
                let vehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
                let colorHex = fleetLink.mapColorHex(forVehicleID: vehicleID)
                if let optimistic = setupStagingSimDragCoordByAssignmentID[assignment.id] {
                    let heading: Double? = {
                        guard let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID) else { return nil }
                        return hub.headingDeg ?? hub.yawDeg
                    }()
                    return MapVehicleMarker(
                        id: assignment.id.uuidString,
                        lat: optimistic.lat,
                        lon: optimistic.lon,
                        label: "\(label) (SIM)",
                        colorHex: colorHex,
                        imageDataURL: imageDataURL,
                        selected: selected,
                        draggable: selected,
                        headingDeg: heading
                    )
                }
                guard let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                      let lat = hub.latitudeDeg,
                      let lon = hub.longitudeDeg else { return nil }
                let heading = hub.headingDeg ?? hub.yawDeg
                return MapVehicleMarker(
                    id: assignment.id.uuidString,
                    lat: lat,
                    lon: lon,
                    label: "\(label) (SIM)",
                    colorHex: colorHex,
                    imageDataURL: imageDataURL,
                    selected: selected,
                    draggable: selected,
                    headingDeg: heading
                )
            case .live:
                guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
                      let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                      let lat = hub.latitudeDeg,
                      let lon = hub.longitudeDeg
                else { return nil }
                let heading = hub.headingDeg ?? hub.yawDeg
                return MapVehicleMarker(
                    id: assignment.id.uuidString,
                    lat: lat,
                    lon: lon,
                    label: "\(label) (Live)",
                    colorHex: fleetLink.mapColorHex(forVehicleID: vehicleID),
                    imageDataURL: imageDataURL,
                    selected: selected,
                    draggable: false,
                    headingDeg: heading
                )
            }
        }
    }

    /// **SITL-only:** applies dragged lat/lon to the bound sim via ``FleetLinkService/applySimState`` (SIM_OPOS_* / SIH_LOC_*).
    private func applySetupMarkerDrag(markerID: String, lat: Double, lon: Double) {
        guard let aid = UUID(uuidString: markerID),
              let idx = run.assignments.firstIndex(where: { $0.id == aid }),
              let tokenKey = run.assignments[idx].attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: tokenKey)
        else { return }
        guard case .sitl(let sitlInstanceID) = token else { return }
        guard let inst = sitl.instances.first(where: { $0.id == sitlInstanceID }) else { return }
        let systemID = inst.stackInstanceIndex + 1
        let vehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
        let stack = fleetLink.hubTelemetry(forVehicleID: vehicleID)?.autopilotStack
            ?? fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.telemetry?.autopilotStack
            ?? .unknown
        guard stack != .unknown else { return }

        let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
        let alt = hub?.absoluteAltM ?? hub?.altitudeAmslM
        let yaw = Float(hub?.headingDeg ?? hub?.yawDeg ?? 0)

        setupRostersSelectedMissionPointID = nil
        setupStagingMapSelectedTaskPathID = nil
        dismissSetupRostersMissionPointDrawerIfNeeded()
        setupSelectedAssignmentId = aid

        let sent = RouteCoordinate(lat: lat, lon: lon)
        setupStagingSimDragCoordByAssignmentID[aid] = sent

        let state = FleetSimState(
            latitudeDeg: lat,
            longitudeDeg: lon,
            absoluteAltitudeM: alt,
            yawDeg: yaw,
            batteryVoltageV: nil,
            ardupilotSimBattCapAh: nil,
            px4SimBatDrain: nil
        )
        Task { @MainActor in
            await fleetLink.applySimState(
                vehicleID: vehicleID,
                state: state,
                autopilotStack: stack,
                source: "mcs.setup_map_drag"
            )
            reconcileSetupStagingSimDragOverlayWithHubTelemetry()
        }
    }

    private var setupMapBoundsSignature: String {
        run.assignments
            .compactMap { assignment -> String? in
                guard let token = assignment.attachedFleetVehicleToken else { return nil }
                return "\(assignment.id.uuidString)|\(token)"
            }
            .sorted()
            .joined(separator: ";")
    }

    private var legacyUnassignedIndices: [Int] {
        run.assignments.indices.filter { run.assignments[$0].taskId == nil }
    }

    private var missionMissingTemplateRosterFallback: some View {
        VStack(alignment: .leading, spacing: MissionRunPrepLayout.taskCardInnerSpacing) {
            Text("Roster")
                .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                .foregroundStyle(theme.textPrimary)
            Text("Mission template not found — roster slots are frozen from when the run was created.")
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: MissionRunPrepLayout.rosterGridMinWidth),
                        spacing: MissionRunPrepLayout.rosterGridSpacing,
                        alignment: .top
                    ),
                ],
                spacing: MissionRunPrepLayout.rosterGridSpacing
            ) {
                ForEach(run.assignments.indices, id: \.self) { idx in
                    rosterSlotCard(assignmentIndex: idx, mission: nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rosterSlotCard(assignmentIndex: Int, mission: Mission?) -> some View {
        let a = run.assignments[assignmentIndex]
        let device = mission.flatMap { m in m.rosterDevices.first { $0.id == a.rosterDeviceId } }
        let detailLine = resolvedRosterVehicleSecondaryLine(assignment: a, fleetLink: fleetLink, sitl: sitl)
        let basenames = simulationImageBasenamesForAssignment(a, sitl: sitl)
        let assignmentId = a.id
        let slotFilled = a.hasFleetOrLegacyAssignment
        let batterySummary: FleetVehicleOperationalModel.BatterySummary? = {
            guard let vid = telemetryVehicleID(for: a) else { return nil }
            return fleetLink.vehicleOperationalModel(forVehicleID: vid).battery
        }()
        let infoVehicleID = telemetryVehicleID(for: a)
        let rosterDeviceClass = device?.vehicleClass ?? .unknown
        let fleetDisplayShortID: String? = {
            guard slotFilled, let vid = telemetryVehicleID(for: a) else { return nil }
            if let model = fleetLink.vehicleModel(forVehicleID: vid) {
                return model.displayShortID
            }
            if let key = a.attachedFleetVehicleToken,
               let token = FleetMissionVehicleToken(storageKey: key),
               case .sitl(let uuid) = token,
               let inst = sitl.instances.first(where: { $0.id == uuid })
            {
                let systemID = inst.stackInstanceIndex + 1
                return "\(inst.preset.fleetVehicleType.classCode):\(systemID)"
            }
            let prefix = "sysid:"
            if vid.hasPrefix(prefix), let n = Int(vid.dropFirst(prefix.count)) {
                return "\(rosterDeviceClass.classCode):\(n)"
            }
            return nil
        }()
        let deviceArtVehicleClass: FleetVehicleType = {
            guard slotFilled,
                  let vid = telemetryVehicleID(for: a),
                  let model = fleetLink.vehicleModel(forVehicleID: vid)
            else { return rosterDeviceClass }
            return model.data.vehicleType
        }()
        return MissionControlRosterSlotCard(
            title: a.slotName,
            subtitle: rosterRoleSubtitle(device),
            vehicleClassForBundledDeviceArt: deviceArtVehicleClass,
            isAttached: slotFilled,
            assignedVehicleDetail: detailLine,
            rosterBatterySummary: batterySummary,
            assignedFleetIsSimulation: rosterAssignmentFleetIsSimulation(a),
            autopilotStack: rosterAutopilotStack(for: a),
            simulationImageBasenames: basenames,
            lifecycleStatus: rosterLifecycleStatus(for: a),
            fleetDisplayShortID: fleetDisplayShortID,
            isSelectedForSetupMap: setupSelectedAssignmentId == assignmentId,
            onSelectForSetupMap: {
                toggleStagingVehicleMapSelection(assignmentId: assignmentId)
            },
            onChooseVehicle: {
                setupRostersSelectedMissionPointID = nil
                setupStagingMapSelectedTaskPathID = nil
                dismissSetupRostersMissionPointDrawerIfNeeded()
                setupStagingSimDragCoordByAssignmentID.removeAll()
                setupSelectedAssignmentId = assignmentId
                presentMissionRosterVehiclePicker(assignmentId: assignmentId)
            },
            onRemoveVehicle: {
                clearFleetVehicle(assignmentId: assignmentId)
            },
            onCalibration: infoVehicleID == nil
                ? nil
                : {
                    presentRosterCalibrationSheet(for: a)
                },
            simulateSystemOn: fleetLink.isSimulateEnabled,
            onPickAndAssignSim: fleetLink.isSimulateEnabled && !slotFilled
                ? { presentRosterSimPickerForAssignment(assignmentId: assignmentId) }
                : nil,
            showsWorkingOverlay: rosterBulkSimSpawnWorkingAssignmentId == assignmentId,
            onOpenSettings: {
                presentAssignmentSettingsSidebar(assignmentIndex: assignmentIndex)
            }
        )
    }

    private func rosterRoleSubtitle(_ device: RosterDevice?) -> String {
        guard let device else { return "—" }
        return "\(device.slot.rawValue) · \(device.behaviorRoleID)"
    }

    /// `nil` when there is no fleet token (unassigned or legacy typed label only).
    private func rosterAssignmentFleetIsSimulation(_ assignment: MissionRunAssignment) -> Bool? {
        guard let key = assignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: key)
        else { return nil }
        switch token {
        case .live: return false
        case .sitl: return true
        }
    }

    private func applyFleetVehicle(_ vehicle: MissionPickableFleetVehicle, assignmentId: UUID) {
        guard let idx = run.assignments.firstIndex(where: { $0.id == assignmentId }) else { return }
        run.assignments[idx].attachedFleetVehicleToken = vehicle.token.storageKey
        run.assignments[idx].attachedDevice = vehicle.title
        setupStagingSimDragCoordByAssignmentID.removeValue(forKey: assignmentId)
    }

    private func clearFleetVehicle(assignmentId: UUID) {
        guard let idx = run.assignments.firstIndex(where: { $0.id == assignmentId }) else { return }
        run.assignments[idx].attachedFleetVehicleToken = nil
        run.assignments[idx].attachedDevice = ""
        setupStagingSimDragCoordByAssignmentID.removeValue(forKey: assignmentId)
    }

    private func rosterPickDisabledReason(_ vehicle: MissionPickableFleetVehicle, assignmentId: UUID) -> String? {
        let key = vehicle.token.storageKey
        if run.assignments.first(where: { $0.id == assignmentId })?.attachedFleetVehicleToken == key {
            return nil
        }
        if controlStore.isFleetVehicleLockedByOtherLiveMission(tokenKey: key, excludingRunId: run.id) {
            return "In use by another live mission"
        }
        if controlStore.isFleetVehicleUsedOnOtherSlotInRun(tokenKey: key, run: run, assignmentId: assignmentId) {
            return "Already assigned in this mission"
        }
        return nil
    }

    /// Bridge vehicle stream key for a roster assignment (`sysid:<id>` for SITL).
    private func telemetryVehicleID(for assignment: MissionRunAssignment) -> String? {
        resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl)
    }
}

/// One vehicle column in Mission Control: vehicle-type thumbnail + slot title / roster role subtitle, battery/GPS, MAVSDK health, and slot actions (including settings).

