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
    /// Floating reserve pool slot cards in the roster accordion (horizontal strip); slightly narrower than full roster grid cells.
    static let reservePoolSlotCardWidth: CGFloat = 212

    /// MC-R live console roster strip: column-major ``Grid`` row count for ``itemCount`` cards with at most ``slotsPerColumn`` rows per column (matches ``missionLiveVehicleStatusRow`` / ``missionLiveVehicleStatusRowRosterGrid`` indexing).
    static func liveConsoleColumnMajorGridRowCount(itemCount: Int, slotsPerColumn: Int) -> Int {
        let n = max(0, itemCount)
        if n == 0 { return 1 }
        let cap = max(1, slotsPerColumn)
        let maxRowIndex = (0 ..< n).map { $0 % cap }.max() ?? 0
        return min(cap, maxRowIndex + 1)
    }
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

/// Timing for MCS **Set reserve pool home** staging map behaviour (`MCSReservePoolMapToDo.md`).
private enum MCSReservePoolHomeStagingMapTiming {
    /// Hub / digest often lag the first ``applySimState`` pass; a second fit widens bbox once markers move.
    static let postBatchFitDelaySeconds: Double = 0.35
}

// MARK: - MC-R reserve pool mutation gates

/// Pure predicates for **which** floating reserve pool berths must reject competing operator mutations
/// (reserve swap-in preflight→commit vs berth arm preflight vs vehicle binding edits).
enum MissionControlReservePoolMutationGate: Sendable {

    /// Held for the whole ``MissionRunDetailView/runMcrFloatingReservePoolSwapAfterReservePreflight`` pipeline
    /// (after eligibility checks, through hub probe, roster/pool commit, and plan recompile).
    struct SwapOperationLock: Equatable, Sendable {
        let vacancyAssignmentID: UUID
        let taskID: UUID
        /// Set for floating-pool swap-in; `nil` while a **fixed template reserve** roster swap pipeline runs (no berth is locked).
        let poolSlotID: UUID?
    }

    /// `true` when a reserve swap-in pipeline is active (second confirms / new swap picks / berth edits must wait).
    static func swapOperationInFlight(lock: SwapOperationLock?) -> Bool {
        lock != nil
    }

    /// `true` when this **task + pool berth** must not accept vehicle binding changes, berth removal, or overlapping probes.
    static func reservePoolSlotMutationLocked(
        swapLock: SwapOperationLock?,
        berthPreflightTaskID: UUID?,
        berthPreflightSlotID: UUID?,
        taskID: UUID,
        slotID: UUID
    ) -> Bool {
        if let swapLock, swapLock.taskID == taskID,
           let lockedPool = swapLock.poolSlotID, lockedPool == slotID { return true }
        if let t = berthPreflightTaskID, let s = berthPreflightSlotID, t == taskID, s == slotID { return true }
        return false
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
                        MissionControlRosterSlotAttentionCapsule(severity: sev, title: missionControlMergedSlotDisplayState.displayTitle)
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
    /// MC-R: confirm floating **pool** berth chosen in ``liveReserveSwapPick`` before ``MissionRunEnvironment/swapRosterAssignmentWithFloatingReservePoolSlot``.
    case reserveSwapPoolPick(vacancyAssignmentID: UUID, taskID: UUID, poolSlotID: UUID)

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
        case .reserveSwapPoolPick(let vacancy, let task, let slot):
            "reserveSwap.\(vacancy.uuidString).\(task.uuidString).\(slot.uuidString)"
        }
    }
}

private struct LiveReserveSwapPickContext: Equatable {
    let vacancyAssignmentID: UUID
    let taskID: UUID
}

/// MC-R: focused floating **reserve pool berth** (not a roster ``MissionRunAssignment`` row).
private struct LiveReservePoolBerthFocus: Equatable {
    let taskID: UUID
    let slotID: UUID
}

    /// MC-R Engage: non-blocking telemetry watch after operator **Park** / **Loiter** from the Stop Vehicle card (``MissionRunEngageStabilizeTelemetryClassifier``).
    private struct MissionLiveEngageStabilizeTelemetryWatch: Equatable {
    let assignmentID: UUID
    let kind: MissionRunEngageStabilizeDispatchKind
    let startedAt: Date
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
    @EnvironmentObject private var operatorPromptCenter: OperatorPromptCenter
    @EnvironmentObject private var operatorPromptReviewFocus: OperatorPromptReviewFocusController
    /// When set from ``MissionControlView`` (e.g. Live Drive **Return to Mission**), opens that task triage once the run is live.
    @Binding var pendingPostOpenLiveMissionTaskID: UUID?
    /// When set from Live Drive **Return to Mission**, focuses this roster assignment (vehicle overlay) once MC‑R is live.
    @Binding var pendingPostOpenLiveMissionAssignmentID: UUID?
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
    @State private var setupStagingSimDragCoordByAssignmentID: [UUID: MissionRunStagingSimDragOverlay] = [:]
    /// Fires ``reconcileSetupStagingSimDragOverlayWithHubTelemetry`` after the pending-sync timeout for each assignment that still has an overlay.
    @State private var setupStagingSimDragTimeoutReconcileTasks: [UUID: Task<Void, Never>] = [:]
    /// Shared model for both the Setup staging map and the Live overview map —
    /// owns the tile style, recenter nonce, and the per-tab content that gets
    /// pushed in via `.task(id:)`.
    @StateObject private var mapModel: GuardianMapModel
    /// MC-R: focused task triage — filters the live mission log and roster to this task; shows triage sheet on Tasks card.
    @State private var focusedLiveTaskID: UUID? = nil
    /// MC-R: focused roster slot triage — slides a vehicle detail sheet up over the Tasks card.
    /// Mutually exclusive with ``focusedLiveTaskID`` so only one overlay is mounted at a time.
    @State private var focusedLiveAssignmentID: UUID? = nil
    /// MC-R: while set, the **global** roster health-card strip lists floating **pool** candidates for reserve swap-in instead of squad roster rows.
    @State private var liveReserveSwapPick: LiveReserveSwapPickContext? = nil
    /// MC-R: while set (and swap pick is **not** active), the roster strip lists **all** pool berths for this task for browse / manage — taps open ``focusedLiveReservePoolBerth``, not swap confirm.
    @State private var liveReservePoolBrowseTaskID: UUID? = nil
    /// MC-R: reserve pool berth detail sheet (above roster vehicle overlay, below map points).
    @State private var focusedLiveReservePoolBerth: LiveReservePoolBerthFocus? = nil
    /// MC-R §4.2: runtime map-points sheet over the Tasks card (slide-up; stacks above task triage and vehicle overlays).
    @State private var liveRuntimeMissionPointsOverlayPresented = false
    @State private var liveRuntimeMissionPointDrawerEditingID: UUID?
    @State private var liveRuntimeMissionMapViewportCenter: RouteCoordinate?
    /// MC-R live overview map: selected runtime map point (list + map pin); enables drag reposition on the pin.
    @State private var liveRuntimeOverviewSelectedMissionPointID: UUID?
    /// Bumps after adding a map point so the overlay list scrolls that row into view.
    @State private var liveRuntimeMapPointsListScrollEpoch: UInt = 0
    @State private var liveRuntimeMapPointsListScrollTargetRow: UUID?
    /// MC-R: when true, log card body shrinks to one line so the live map column gains height. Defaults collapsed.
    @State private var liveLogPanelCollapsed = true
    /// User dismissed the recovery status anchored prompt for this visit (does not change MRE).
    @State private var dismissedRecoveryStatusPrompt = false
    /// User dismissed the abort-session status anchored prompt for this visit (does not change MRE).
    @State private var dismissedAbortStatusPrompt = false
    @State private var liveConsoleMediaTab: LiveConsoleMediaTab = .map
    @ObservedObject private var logTemplateRegistry: MissionRunLogTemplateRegistry
    @State private var startPreflightPresented = false
    @State private var missionPreflightPostPickProbeAssignmentId: UUID?
    @State private var rosterCalibrationVehicleID: String?
    @State private var rosterCalibrationFallbackModel: FleetVehicleModel?
    /// MC-R reserve pool berth sheet: one-shot arm probe running (outcome via toast), keyed so other berths stay editable.
    @State private var reservePoolBerthPreflightFocus: LiveReservePoolBerthFocus? = nil
    /// MC-R: held across reserve swap-in hub probe → roster/pool commit so the pool berth (and competing swap picks) cannot race.
    @State private var mcrFloatingReserveSwapLock: MissionControlReservePoolMutationGate.SwapOperationLock? = nil
    /// MC-R: last floating-reserve **auto-suggest** toast per fleet vehicle id (debounce; see ``MissionRunReserveAutoSuggestPolicy``).
    @State private var reserveAutoSuggestLastToastAtByVehicleID: [String: Date] = [:]
    /// MC-R: last **reserve auto-swap** executor attempt per roster vacancy id (debounce; ``MissionRunReserveAutoSwapExecutorPolicy``).
    @State private var reserveAutoSwapLastAttemptAtByVacancyID: [UUID: Date] = [:]
    /// MC-R Engage: live **stabilize telemetry** watch (Park / Loiter) for one assignment at a time.
    @State private var missionLiveEngageStabilizeTelemetryWatch: MissionLiveEngageStabilizeTelemetryWatch?
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
    /// MCS **Set reserve pool home** map mode: when non-`nil`, staging-map placement is armed for this task’s pool SIMs (``MCSReservePoolMapToDo.md``).
    @State private var mcsReservePoolHomePlacementTaskID: UUID?
    /// Cursor position for the pool-home preview ring (Phase C); cleared when pool-home mode disarms.
    @State private var mcsReservePoolHomePlacementCursorCoordinate: RouteCoordinate?
    /// MCS staging map: selected floating-reserve pool berth (SIM ring + drag); mutually exclusive with roster vehicle selection.
    @State private var setupSelectedReservePoolTaskID: UUID?
    @State private var setupSelectedReservePoolSlotID: UUID?
    /// Optimistic pool SIM poses after staging-map drags until hub telemetry sustains (parallel to roster ``setupStagingSimDragCoordByAssignmentID``).
    @State private var setupStagingReservePoolSimDragCoordByEncodedMarkerID: [String: MissionRunStagingSimDragOverlay] = [:]
    @State private var setupStagingReservePoolSimDragTimeoutReconcileTasks: [String: Task<Void, Never>] = [:]
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
        onDelete: @escaping (UUID) -> Void,
        pendingPostOpenLiveMissionTaskID: Binding<UUID?>,
        pendingPostOpenLiveMissionAssignmentID: Binding<UUID?>
    ) {
        _run = ObservedObject(wrappedValue: run)
        _missionStore = ObservedObject(wrappedValue: missionStore)
        _fleetLink = ObservedObject(wrappedValue: fleetLink)
        _sitl = ObservedObject(wrappedValue: sitl)
        _controlStore = ObservedObject(wrappedValue: controlStore)
        _generalSettings = ObservedObject(wrappedValue: generalSettings)
        _pendingPostOpenLiveMissionTaskID = pendingPostOpenLiveMissionTaskID
        _pendingPostOpenLiveMissionAssignmentID = pendingPostOpenLiveMissionAssignmentID
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

    /// Present MC-R **switch.2** → app-wide Mission Run toggles (same rows as Setup → **Settings** / App Settings → Missions → Mission Run; not wrapped in a card).
    private func presentMcrRunSettingsDrawer() {
        let anim = rosterPickerSpring
        appDrawer.present(
            title: "Settings",
            preferredWidth: 420,
            scrimTapDismisses: true,
            animation: anim
        ) {
            ScrollView {
                mcSetupMissionRunAppSettingsMirrorFormBody
                    .padding(GuardianSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    /// Present the MC-R cog → mission policy chains + rules of engagement (MCS **Rules** tab content).
    private func presentRunControlsSidebar() {
        let anim = rosterPickerSpring
        appDrawer.present(
            title: "Run Rules",
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

    private func presentMissionRosterVehiclePicker(assignmentId: UUID, onVehicleApplied: (() -> Void)? = nil) {
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
                    onVehicleApplied?()
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
                    missionStore: missionStore,
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
                run.missionControlAssignmentBelongsToTask(run.assignments[$0], task: task, mission: mission)
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
        let rows = run.missionControlTaskRosterOrderedSlotAssignmentIndices(task: task, mission: mission)
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
            let rows = run.missionControlTaskRosterOrderedSlotAssignmentIndices(task: task, mission: mission)
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
                case .reserveSwapPoolPick(let vacancyAID, let taskID, let poolSlotID):
                    GuardianConfirm(
                        title: "Swap in this reserve?",
                        message: MissionRunReserveSwapOperatorCopy.reserveSwapPoolPickConfirmMessage,
                        systemImage: "arrow.triangle.swap",
                        cancelTitle: "Cancel",
                        confirmTitle: "Swap",
                        onCancel: { presentedRunConfirm = nil },
                        onConfirm: {
                            presentedRunConfirm = nil
                            Task { @MainActor in
                                await runMcrFloatingReservePoolSwapAfterReservePreflight(
                                    vacancyAssignmentID: vacancyAID,
                                    taskID: taskID,
                                    poolSlotID: poolSlotID
                                )
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
    private func missionLiveOverlayHeaderGlyphButton(
        systemImage: String,
        help: String,
        foreground: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let fg = foreground ?? theme.textSecondary
        return Button(action: action) {
            Image(systemName: systemImage)
                .font(GuardianTypography.font(.heroGlyph18Medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(fg)
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

    /// Compact **Sooner** / **Later** alter-step controls (icon-only; tooltips + accessibility carry the text labels).
    @ViewBuilder
    private func missionDeferralAlterSoonerLaterIconButtons(
        controlSize: ControlSize,
        onSooner: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) -> some View {
        HStack(spacing: GuardianSpacing.xsTight) {
            Button(action: onSooner) {
                Image(systemName: "gobackward")
            }
            .buttonStyle(.borderedProminent)
            .guardianPointerOnHover()
            .tint(.blue)
            .controlSize(controlSize)
            .accessibilityLabel("Sooner")
            .help("Shift earlier by one alter step (Sooner).")

            Button(action: onLater) {
                Image(systemName: "goforward")
            }
            .buttonStyle(.borderedProminent)
            .guardianPointerOnHover()
            .tint(.blue)
            .controlSize(controlSize)
            .accessibilityLabel("Later")
            .help("Shift later by one alter step (Later).")
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
                numericFieldWidth: hero ? 96 : 22,
                unitPickerWidth: hero ? 72 : 56,
                controlSize: controlSize
            )
            missionDeferralAlterSoonerLaterIconButtons(controlSize: controlSize) {
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
            } onLater: {
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
            missionLiveTriageActionRowCard(bodyCaption: "Abort Task") {
                HStack(spacing: GuardianSpacing.xs) {
                    GuardianThemedButton(
                        title: "Now",
                        accent: .danger,
                        surface: .solid,
                        size: .small,
                        shape: .cornered,
                        action: { applyTaskAbortNow(task: task) }
                    )
                    .disabled(!a.abortNow)
                    .guardianPointerOnHover()
                    .help(
                        a.abortNow
                            ? "Issue abort-policy fleet commands for this path’s slots immediately."
                            : "Unavailable while another intent blocks it, this path is in recovery/abort protocol, a whole-run end-of-cycle stop is active, or the run is not executing."
                    )

                    GuardianThemedButton(
                        title: "After cycle",
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        action: { applyTaskAbortGraceful(task: task) }
                    )
                    .disabled(!a.abortGraceful)
                    .guardianPointerOnHover()
                    .help(
                        a.abortGraceful
                            ? "Schedule abort-policy commands at the next shared autopilot mission cycle end for this path only."
                            : "Unavailable if complete-after-cycle is already scheduled, during MAVLink start deferral, or while a whole-run graceful stop is active."
                    )
                }
            }

            missionLiveTriageActionRowCard(bodyCaption: "Complete Task") {
                HStack(spacing: GuardianSpacing.xs) {
                    GuardianThemedButton(
                        title: "Now",
                        accent: .primary,
                        surface: .solid,
                        size: .small,
                        shape: .cornered,
                        action: { applyTaskCompleteNow(task: task) }
                    )
                    .disabled(!a.completeNow)
                    .guardianPointerOnHover()
                    .help(
                        a.completeNow
                            ? "Issue complete-policy recovery wind-down for this path’s slots immediately."
                            : "Unavailable while another intent blocks it, this path is in recovery/abort protocol, a whole-run end-of-cycle stop is active, or the run is not executing."
                    )

                    GuardianThemedButton(
                        title: "After cycle",
                        accent: .primary,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        action: { applyTaskCompleteGraceful(task: task) }
                    )
                    .disabled(!a.completeGraceful)
                    .guardianPointerOnHover()
                    .help(
                        a.completeGraceful
                            ? "Schedule recovery wind-down at the next shared autopilot mission cycle end for this path only."
                            : "Unavailable if abort-after-cycle is already scheduled, during MAVLink start deferral, or while a whole-run graceful stop is active."
                    )
                }
            }

            if a.revokeTaskGraceful {
                GuardianThemedButton(
                    title: "Revoke scheduled path wind-down",
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: { applyTaskRevokeGracefulWindDown(task: task) }
                )
                .guardianPointerOnHover()
                .help("Cancel the scheduled end-of-cycle wind-down for this path only (does not change a whole-run graceful stop).")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyTaskAbortNow(task: RoutePath) {
        run.attachServices(fleetLink: fleetLink, sitl: sitl, generalSettings: generalSettings)
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
        run.attachServices(fleetLink: fleetLink, sitl: sitl, generalSettings: generalSettings)
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

    private func missionLiveTaskTriageCyclesLineText(task: RoutePath) -> String? {
        guard task.enabled,
              task.regularity == .continuous || task.regularity == .continuousWithDelay
        else { return nil }
        let done = run.taskCyclesCompletedByTaskID[task.id] ?? 0
        if task.cycles > 0 { return "Cycles: \(done)/\(task.cycles)" }
        return "Cycles: \(done)/∞"
    }

    private func missionLiveTaskTriageWaypointsLineText(task: RoutePath, derived: MissionLiveTaskProgressDerived) -> String {
        guard task.enabled else { return "Waypoints: —" }
        if derived.inTaskStartDeferral { return "Waypoints: —" }
        if derived.taskActiveInCycle, let hub = derived.hub,
           let tot = hub.missionProgressTotal, tot > 0, let cur = hub.missionProgressCurrent
        {
            return "Waypoints: \(cur)/\(tot)"
        }
        return "Waypoints: —"
    }

    /// Task triage progress card: **Cycles** + **Waypoints** share one font on a single baseline row, then the mission bar and deferral / trigger controls.
    @ViewBuilder
    private func missionLiveTaskTriageCycleWaypointCounterRow(
        task: RoutePath,
        derived: MissionLiveTaskProgressDerived
    ) -> some View {
        let font = GuardianTypography.font(.inlineNoticeDetail)
        let cycle = missionLiveTaskTriageCyclesLineText(task: task)
        let wpt = missionLiveTaskTriageWaypointsLineText(task: task, derived: derived)
        HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
            if let cycle {
                Text(cycle)
                    .font(font)
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: GuardianSpacing.xs)
            Text(wpt)
                .font(font)
                .foregroundStyle(theme.textSecondary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func missionLiveTaskTriageProgressCard(
        task: RoutePath,
        taskIndex: Int,
        mission: Mission,
        now: Date
    ) -> some View {
        let d = missionLiveTaskProgressDerived(task: task, taskIndex: taskIndex, mission: mission, now: now)
        GuardianCard(configuration: mcSetupGroupCardConfiguration, body: {
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                missionLiveTaskTriageCycleWaypointCounterRow(task: task, derived: d)
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
            }
        })
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

    /// MC-R: when telemetry / logs show distress on a **primary or wingman** roster aircraft and a class-matched
    /// floating reserve exists on the focused task, surface a debounced toast pointing operators at **Swap in reserve**.
    ///
    /// When ``MissionRunEngagementAction/swapInReserve`` is **autonomous** and exactly **one** reserve swap candidate
    /// exists (pool or fixed template reserve), may run **reserve auto-swap executor** (arm probe on the reserve, then roster commit) instead of toasting.
    private func evaluateReserveAutoSuggestFromLiveSignalsIfNeeded(now: Date = Date()) {
        syncRunFromStore()
        guard liveReserveSwapPick == nil else { return }
        guard !mcrReserveSwapOperationInFlight() else { return }
        guard run.status == .running || run.status == .paused else { return }
        guard run.sessionPhase == .executing else { return }
        guard let mission = resolvedMission, let tid = focusedLiveTaskID else { return }
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == tid }) else { return }
        guard task.enabled else { return }

        if let auto = MissionRunReserveAutoSwapLiveEvaluator.firstMatch(
            run: run,
            mission: mission,
            task: task,
            fleetLink: fleetLink,
            sitl: sitl,
            now: now
        ),
           MissionRunReserveAutoSwapExecutorPolicy.debounceAllowsAttempt(
            lastAttemptAt: reserveAutoSwapLastAttemptAtByVacancyID[auto.vacancyAssignment.id],
            now: now
           ) {
            reserveAutoSwapLastAttemptAtByVacancyID[auto.vacancyAssignment.id] = now
            Task { await performReserveAutoSwapIfNeeded(auto, taskID: tid) }
            return
        }

        guard let match = MissionRunReserveAutoSuggestLiveEvaluator.firstSuggestMatch(
            run: run,
            mission: mission,
            task: task,
            fleetLink: fleetLink,
            sitl: sitl,
            now: now
        ) else { return }

        guard MissionRunReserveAutoSuggestPolicy.debounceAllowsToast(
            lastToastAt: reserveAutoSuggestLastToastAtByVehicleID[match.vehicleID],
            debounce: MissionRunReserveAutoSuggestPolicy.defaultToastDebouncePerVehicleSeconds,
            now: now
        ) else { return }

        reserveAutoSuggestLastToastAtByVehicleID[match.vehicleID] = now
        toastCenter.show(match.reason.operatorToastBody, style: .warning)
    }

    @MainActor
    private func performReserveAutoSwapIfNeeded(_ match: MissionRunReserveAutoSwapLiveMatch, taskID: UUID) async {
        syncRunFromStore()
        guard liveReserveSwapPick == nil else { return }
        guard !mcrReserveSwapOperationInFlight() else { return }
        guard run.resolvedEngagementDisposition(for: .swapInReserve) == .autonomous else { return }
        guard MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: run.sessionPhase) else {
            return
        }
        guard let mission = resolvedMission else { return }
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }), task.enabled else { return }
        let refreshed = run.enumerateReserveSwapCandidates(vacancyAssignmentID: match.vacancyAssignment.id, taskID: taskID)
        guard refreshed.count == 1, refreshed[0] == match.loneCandidate else { return }

        switch match.loneCandidate {
        case .floatingPool(_, let slot):
            await runMcrFloatingReservePoolSwapAfterReservePreflight(
                vacancyAssignmentID: match.vacancyAssignment.id,
                taskID: taskID,
                poolSlotID: slot.id,
                triggerSource: "operator.missionControlRunning.reserveSwap.autoExecutor"
            )
        case .fixedRosterReserve(let reserve):
            await runMcrFixedTemplateReserveSwapAfterReservePreflight(
                vacancyAssignmentID: match.vacancyAssignment.id,
                reserveAssignment: reserve,
                taskID: taskID
            )
        }
    }

    private func applyAbortImmediate() {
        run.attachServices(fleetLink: fleetLink, sitl: sitl, generalSettings: generalSettings)
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
        run.attachServices(fleetLink: fleetLink, sitl: sitl, generalSettings: generalSettings)
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

    /// Mission Control Running applies SIM battery drain for roster SITL streams from **this run’s** ``MissionRunOperatorDisplaySettings/simBatteryDrainRateDuringRun`` while ``MissionRunStatus/running``; ``SimBatteryDrainRate/none`` keeps drain off. Not ``GeneralSettingsStore``.
    private func syncSimBatteryDrainForRunStatus() {
        let rate = run.operatorDisplaySettings.simBatteryDrainRateDuringRun
        let enableDrain = (run.status == .running) && (rate != .none)
        let rateForWire = enableDrain ? rate : .normal
        for vehicleID in assignedSimulationVehicleIDs {
            fleetLink.setSimBatteryDrainEnabled(
                vehicleID: vehicleID,
                enabled: enableDrain,
                rate: rateForWire,
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

    /// Task focus applied to the MC‑R **live overview map** only (paths, pins, vehicles, pool markers).
    /// When **Isolate map to selected task** is off for this run, the map stays full-mission even while triage keeps a task selected.
    private var liveOverviewMapFocusedTaskID: UUID? {
        guard run.operatorDisplaySettings.isolateLiveMapToSelectedTask else { return nil }
        return focusedLiveTaskID
    }

    /// Roster rows that supply **live map** vehicle markers (full roster when map isolation is off).
    private var missionLiveMapRosterAssignments: [MissionRunAssignment] {
        guard let mission = resolvedMission else { return Array(run.assignments) }
        guard liveOverviewMapFocusedTaskID != nil else { return Array(run.assignments) }
        return run.assignments.filter { assignmentMatchesLiveFocus($0, mission: mission) }
    }

    /// When ``liveReserveSwapPick`` is active, pool berths (ids) that may replace the vacancy — same slice and **pool-row order** as ``MissionRunEnvironment/enumerateReserveSwapCandidates`` with default ordering (floating pool rows only).
    private var mcrLiveReserveSwapEligiblePoolSlotsOrdered: [MissionRunReservePoolSlot] {
        guard let pick = liveReserveSwapPick else { return [] }
        return run.enumerateReserveSwapCandidates(vacancyAssignmentID: pick.vacancyAssignmentID, taskID: pick.taskID).compactMap { c in
            guard case .floatingPool(let tid, let slot) = c, tid == pick.taskID else { return nil }
            return slot
        }
    }

    /// Hub-linked pool markers to emphasize on the live map while picking a reserve swap-in berth.
    private var mcrLiveReserveSwapEligiblePoolSlotIDs: Set<UUID> {
        guard liveReserveSwapPick != nil else { return [] }
        return Set(mcrLiveReserveSwapEligiblePoolSlotsOrdered.map(\.id))
    }

    private func syncRecoveryPromptIfNeeded() {
        guard run.status == .recovery, !dismissedRecoveryStatusPrompt else { return }
        guard bottomPromptCenter.activePrompt == nil else { return }
        bottomPromptCenter.present(
            "Recovery in progress. When fleet recovery actions are finished, mark this run completed.",
            style: .success,
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
            style: .error,
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
        switch run.gracefulStopKind {
        case .abortAfterCycle:
            bottomPromptCenter.presentChoice(
                message,
                style: .error,
                confirmTitle: "Keep running",
                dismissTitle: "Dismiss",
                onConfirm: {
                    applyRevokeGracefulStopIntent()
                },
                onDismiss: nil
            )
        case .completeAfterCycle:
            bottomPromptCenter.presentChoice(
                message,
                style: .success,
                confirmTitle: "Keep running",
                dismissTitle: "Dismiss",
                onConfirm: {
                    applyRevokeGracefulStopIntent()
                },
                onDismiss: nil
            )
        case .none:
            break
        }
    }

    /// Camera vs map for MC-R live console (icons only — segmented control lives in the title bar).
    private var missionLiveMediaModeSubBarToggle: some View {
        GuardianToolbarDualIconModeToggle(
            selection: $liveConsoleMediaTab,
            leftMode: .map,
            leftSystemImage: "map.fill",
            leftAccessibilityLabel: "Map",
            rightMode: .camera,
            rightSystemImage: "video.fill",
            rightAccessibilityLabel: "Camera"
        )
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
                action: { withAnimation(triageSheetSpring) { startPreflightPresented = true } }
            )

            GuardianDestructiveProminentButton(title: "Delete Run") {
                presentedRunConfirm = .deleteRun
            }
        }
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
                                .frame(maxWidth: 520)
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
                                    GuardianNeutralOutlinedMenuTriggerLabel(title: "Stop Run")
                                }
                                .guardianStyledNeutralToolbarMenu()
                                .fixedSize(horizontal: true, vertical: false)
                                .guardianPointerOnHover()
                                .help("Abort, complete, or wind down this run")

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
                                    help: "Run rules — mission policy chains and rules of engagement",
                                    action: { presentRunControlsSidebar() }
                                )

                                GuardianNeutralBorderedButton(
                                    systemImage: "switch.2",
                                    help: "Mission Run settings — same toggles as Setup → Settings and App Settings → Missions → Mission Run",
                                    action: { presentMcrRunSettingsDrawer() }
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

                }
                ZStack(alignment: .topLeading) {
                    Group {
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
                                            case .settings:
                                                setupSettingsTabContent
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
                                evaluateReserveAutoSuggestFromLiveSignalsIfNeeded()
                            }
                            .onChange(of: liveMissionProgressPulseDate) { _ in
                                refreshVehicleVoiceNarrativeFromTelemetry()
                                evaluateReserveAutoSuggestFromLiveSignalsIfNeeded()
                            }
                            .onAppear {
                                refreshVehicleVoiceNarrativeFromTelemetry()
                                evaluateReserveAutoSuggestFromLiveSignalsIfNeeded()
                            }
                            .onChange(of: run.events.count) { _ in
                                evaluateReserveAutoSuggestFromLiveSignalsIfNeeded()
                            }
                            .onChange(of: run.sessionPhase) { _ in
                                evaluateReserveAutoSuggestFromLiveSignalsIfNeeded()
                            }
                            .onChange(of: run.taskStateByTaskID) { _ in
                                evaluateReserveAutoSuggestFromLiveSignalsIfNeeded()
                            }
                            .onChange(of: focusedLiveTaskID) { newID in
                                handleFocusedLiveTaskIDChanged(newID)
                            }
                        }
                    }
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    if startPreflightPresented && run.status == .setup {
                        MissionRunStartPreflightOverlay(
                            run: run,
                            mission: resolvedMission,
                            fleetLink: fleetLink,
                            sitl: sitl,
                            controlStore: controlStore,
                            contentSpring: triageSheetSpring,
                            resolveTelemetryVehicleID: { telemetryVehicleID(for: $0) },
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
                            onAbandonWithoutStart: {},
                            onDismiss: {
                                startPreflightPresented = false
                            },
                            onOpenVehicleInspector: { presentRosterCalibrationSheet(for: $0) },
                            onSwapVehicle: { assignmentId in
                                presentMissionRosterVehiclePicker(assignmentId: assignmentId) {
                                    missionPreflightPostPickProbeAssignmentId = assignmentId
                                }
                            },
                            postVehiclePickPreflightAssignmentId: $missionPreflightPostPickProbeAssignmentId
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(0.5)
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
        .onAppear {
            run.attachServices(fleetLink: fleetLink, sitl: sitl, generalSettings: generalSettings)
            installMissionTemplatePersister()
            syncRunFromStore()
            if run.status == .setup {
                fitSetupStagingMapToVisibleMissionContent()
            }
            syncSimBatteryDrainForRunStatus()
            if run.status == .setup {
                pruneStaleRosterFleetAssignmentsIfNeeded()
            }
            syncRecoveryPromptIfNeeded()
            syncAbortSessionPromptIfNeeded()
            syncGracefulStopPromptIfNeeded()
        }
        .onChange(of: setupMapBoundsSignature) { _ in
            guard run.status == .setup else { return }
            fitSetupStagingMapToVisibleMissionContent()
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
            disarmMCSReservePoolHomePlacement()
            syncSimBatteryDrainForRunStatus()
            if newStatus == .setup || newStatus == .completed {
                focusLiveTask(nil)
                focusLiveAssignment(nil)
                clearLiveRuntimeMissionPointsOverlayChrome()
                dismissedRecoveryStatusPrompt = false
                dismissedAbortStatusPrompt = false
                bottomPromptCenter.dismiss()
                missionLiveEngageStabilizeTelemetryWatch = nil
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
        .onChange(of: mcsReservePoolHomeArmLifecycleToken) { _ in
            syncMCSReservePoolHomePlacementWithMissionTemplateIfNeeded()
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
                disarmMCSReservePoolHomePlacement()
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
            } else {
                disarmMCSReservePoolHomePlacement()
            }
        }
        .onChange(of: appDrawer.presented?.id) { newDrawerID in
            if newDrawerID == nil {
                setupRostersMissionPointDrawerEditingID = nil
                liveRuntimeMissionPointDrawerEditingID = nil
            }
        }
        .onChange(of: run.operatorDisplaySettings) { _ in
            syncSimBatteryDrainForRunStatus()
        }
        .onChange(of: run.assignments) { _ in
            syncSimBatteryDrainForRunStatus()
        }
        .onChange(of: focusedLiveAssignmentID) { newID in
            guard let watch = missionLiveEngageStabilizeTelemetryWatch else { return }
            let rosterIDs = Set(run.assignments.map(\.id))
            guard rosterIDs.contains(watch.assignmentID) else { return }
            if newID != watch.assignmentID {
                missionLiveEngageStabilizeTelemetryWatch = nil
            }
        }
        .onChange(of: focusedLiveReservePoolBerth) { newBerth in
            guard let watch = missionLiveEngageStabilizeTelemetryWatch else { return }
            let rosterIDs = Set(run.assignments.map(\.id))
            if rosterIDs.contains(watch.assignmentID) { return }

            if newBerth == nil {
                missionLiveEngageStabilizeTelemetryWatch = nil
                return
            }
            guard let b = newBerth,
                  let slot = run.reservePool(forTaskID: b.taskID).entries.first(where: { $0.id == b.slotID })
            else {
                missionLiveEngageStabilizeTelemetryWatch = nil
                return
            }
            let syn = MissionRunAssignment.syntheticForReservePool(slot: slot)
            if syn.id != watch.assignmentID {
                missionLiveEngageStabilizeTelemetryWatch = nil
            }
        }
        .onChange(of: run.gracefulStopKind) { kind in
            if kind != .none {
                syncGracefulStopPromptIfNeeded()
            } else {
                bottomPromptCenter.dismiss()
            }
        }
        .onDisappear {
            disarmMCSReservePoolHomePlacement()
            appDrawer.dismiss()
            bottomPromptCenter.dismiss()
            for vehicleID in assignedSimulationVehicleIDs {
                fleetLink.setSimBatteryDrainEnabled(
                    vehicleID: vehicleID,
                    enabled: false,
                    rate: .normal,
                    source: "missionControl.viewDisappear",
                    onResult: nil
                )
            }
            onUpdate(run)
        }

            if run.status == .running, run.oneOffDeferredExecution != nil, bottomPromptCenter.activePrompt == nil {
                ZStack(alignment: .bottom) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let deferred = run.oneOffDeferredExecution {
                            scheduledMissionStartDockedBody(
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
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: missionControlDockedBottomPromptMinHeight,
                                alignment: .topLeading
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(2.2)
            }

            MissionRunOperatorRecipePromptBanner(missionRunID: run.id)
                .zIndex(2.5)

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

            GuardianBottomPromptBanner(
                center: bottomPromptCenter,
                layout: .missionControlDocked(minHeight: missionControlDockedBottomPromptMinHeight)
            )
                .zIndex(2)
        }
        .onAppear {
            operatorPromptCenter.noteMCRRunDetailViewPresented(missionRunID: run.id)
        }
        .onDisappear {
            operatorPromptCenter.noteMCRRunDetailViewDismissed(missionRunID: run.id)
        }
        .onAppear(perform: applyPendingPostOpenLiveMissionDrillInIfNeeded)
        .onChange(of: pendingPostOpenLiveMissionTaskID) { _ in
            applyPendingPostOpenLiveMissionDrillInIfNeeded()
        }
        .onChange(of: pendingPostOpenLiveMissionAssignmentID) { _ in
            applyPendingPostOpenLiveMissionDrillInIfNeeded()
        }
        .onChange(of: run.status) { _ in
            applyPendingPostOpenLiveMissionDrillInIfNeeded()
        }
    }

    /// Applies Live Drive / Decisions drill-in: assignment vehicle overlay first, else task triage (``MissionControlView``).
    private func applyPendingPostOpenLiveMissionDrillInIfNeeded() {
        guard run.status == .running || run.status == .paused || run.status == .recovery else { return }
        if let aid = pendingPostOpenLiveMissionAssignmentID {
            guard run.assignments.contains(where: { $0.id == aid }) else {
                pendingPostOpenLiveMissionAssignmentID = nil
                return
            }
            pendingPostOpenLiveMissionAssignmentID = nil
            pendingPostOpenLiveMissionTaskID = nil
            withAnimation(triageSheetSpring) {
                liveReserveSwapPick = nil
                liveReservePoolBrowseTaskID = nil
                focusedLiveReservePoolBerth = nil
                focusedLiveAssignmentID = aid
                focusedLiveTaskID = nil
            }
            return
        }
        guard let tid = pendingPostOpenLiveMissionTaskID else { return }
        withAnimation(triageSheetSpring) {
            focusedLiveTaskID = tid
            focusedLiveAssignmentID = nil
            liveReserveSwapPick = nil
            liveReservePoolBrowseTaskID = nil
            focusedLiveReservePoolBerth = nil
        }
        pendingPostOpenLiveMissionTaskID = nil
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

    private func scheduledMissionStartDockedBody(
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
        let style: GuardianBottomPromptStyle = .info
        return VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                Image(systemName: style.icon)
                    .font(GuardianTypography.font(.bottomPromptIcon))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                    Text("Scheduled mission start")
                        .font(GuardianTypography.font(.bottomPromptMessage))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(
                        "Execution begins \(deferred.executeAt.guardianScheduleOnAtPhrase) — in \(formattedOneOffCountdown(seconds: remaining))."
                    )
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(.white.opacity(0.95))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                    MissionDelayPostponeValueUnitRow(
                        postponeLabel: "Alter",
                        postponeLabelColor: .white,
                        value: postponeValue,
                        unit: postponeUnit,
                        minimumTotalSeconds: 1,
                        maximumTotalSeconds: TimeInterval(generalSettings.missionControlPostponeStepCapSeconds),
                        numericFieldWidth: 88,
                        unitPickerWidth: 68,
                        controlSize: .small
                    )
                    missionDeferralAlterSoonerLaterIconButtons(controlSize: .small) {
                        onAlterSooner()
                    } onLater: {
                        onAlterLater()
                    }
                    compactVerticalControlSeparator()
                        .padding(.horizontal, GuardianSpacing.xsTight)
                    Button("Start") {
                        onRequestStartNow()
                    }
                    .buttonStyle(.borderedProminent).guardianPointerOnHover()
                    .tint(.white)
                    .controlSize(.small)
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProgressView(value: progress)
                .tint(.white.opacity(0.88))
        }
        .padding(.horizontal, GuardianSpacing.cardBodyInset)
        .padding(.vertical, GuardianSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.bottomPromptBannerBackground)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.white.opacity(0.2)),
            alignment: .top
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

    /// Keeps floating-reserve browse / swap pick state aligned when task focus changes (extracted to ease Swift type-checking on the live map stack).
    private func handleFocusedLiveTaskIDChanged(_ newID: UUID?) {
        pruneLiveRuntimeMapPointSelectionIfOutOfFilter()
        if let pick = liveReserveSwapPick, newID == nil || newID != pick.taskID {
            liveReserveSwapPick = nil
        }
        if let browse = liveReservePoolBrowseTaskID, newID == nil || newID != browse {
            liveReservePoolBrowseTaskID = nil
            focusedLiveReservePoolBerth = nil
        }
        evaluateReserveAutoSuggestFromLiveSignalsIfNeeded()
    }

    /// Map pin tap: mirror list-row selection — show the Map points overlay and scroll the row into view.
    private func selectLiveRuntimeMissionPointFromMapPin(_ id: UUID) {
        withAnimation(triageSheetSpring) {
            liveRuntimeMissionPointsOverlayPresented = true
            liveRuntimeOverviewSelectedMissionPointID = id
        }
        liveRuntimeMapPointsListScrollTargetRow = id
        liveRuntimeMapPointsListScrollEpoch &+= 1
    }

    private func toggleLiveRuntimeMissionPointSelectionFromMapPin(_ id: UUID) {
        if liveRuntimeOverviewSelectedMissionPointID == id {
            withAnimation(triageSheetSpring) {
                liveRuntimeOverviewSelectedMissionPointID = nil
            }
            return
        }
        selectLiveRuntimeMissionPointFromMapPin(id)
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
                            action: { focusLiveMapOnRuntimeMissionPoint(mp: cur) },
                            label: {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(GuardianTypography.font(.sectionHeadingSemibold))
                            }
                        )
                        .help("Center the map on this map point (keep zoom)")

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

    /// MC-R left column: map **260** (grows when log is collapsed) → **10** → roster strip (height grows with roster count, capped at **3** card rows) → **10** → Logs (**flex** or one-line collapsed).
    private let liveConsoleMapHeight: CGFloat = 260
    /// Roster health card height (title + ID row, subtitle + battery row).
    private let liveConsoleRosterCardHeight: CGFloat = 56
    /// MC-R docked bottom prompts (recovery / abort / graceful / scheduled start): minimum panel height.
    private let missionControlDockedBottomPromptMinHeight: CGFloat = 55
    /// Maximum roster cards stacked **vertically** per column (column-major). Strip height uses **actual** row count up to this cap.
    private let liveConsoleRosterGridRows: Int = 3
    /// How many grid **rows** are populated for the current roster strip (1…``liveConsoleRosterGridRows``); empty roster uses **1** for the placeholder card.
    /// While **Swap in reserve** is picking a pool berth, or **browse reserves** is showing this task’s pool, counts **floating pool** rows instead of the normal roster so the strip height is not clipped (``missionLiveVehicleStatusRow`` + ``.clipped()``).
    private var liveConsoleRosterEffectiveRows: Int {
        MissionRunPrepLayout.liveConsoleColumnMajorGridRowCount(
            itemCount: liveConsoleRosterStripLayoutCardinality,
            slotsPerColumn: liveConsoleRosterGridRows
        )
    }

    /// Item count driving roster-strip **height** (normal roster assignments, or floating pool picks while ``liveReserveSwapPick`` is active).
    private var liveConsoleRosterStripLayoutCardinality: Int {
        if liveReserveSwapPick != nil,
           run.status == .running || run.status == .paused || run.status == .recovery {
            let pool = mcrLiveReserveSwapEligiblePoolSlotsOrdered
            return pool.isEmpty ? 1 : pool.count
        }
        if let browseTid = liveReservePoolBrowseTaskID,
           run.status == .running || run.status == .paused || run.status == .recovery {
            let n = run.reservePool(forTaskID: browseTid).entries.count
            return n == 0 ? 1 : n
        }
        let n = filteredLiveRosterAssignments.count
        return n == 0 ? 1 : n
    }
    /// Vertical space for the roster strip: card rows + gaps between them (remainder goes to the map + log flex).
    private var liveConsoleRosterStripHeight: CGFloat {
        let rows = CGFloat(liveConsoleRosterEffectiveRows)
        let gaps = CGFloat(max(0, liveConsoleRosterEffectiveRows - 1))
        return liveConsoleRosterCardHeight * rows + liveConsoleStackSpacing * gaps
    }
    /// Vertical gap between map↔roster and roster↔log (same value both places).
    private let liveConsoleStackSpacing: CGFloat = GuardianSpacing.denseGutter
    private let liveConsoleStackGutter: CGFloat = GuardianSpacing.denseGutter
    /// Total ``GuardianCard`` height (header + one log line body) when the log is collapsed.
    private let liveLogCollapsedCardHeight: CGFloat = 100

    /// Running / paused: **70%** map + roster + live mission log; **30%** Tasks card (overview or task triage sheet).
    private var missionLiveConsole: some View {
        let gutter = liveConsoleStackGutter
        let baseMapH = liveConsoleMapHeight
        let rosterH = liveConsoleRosterStripHeight
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// Right column: ``GuardianCard`` with **Tasks** header; ``fullCardOverlay`` stacks **Task triage → Assignment (vehicle) → Reserve berth → Map points** (bottom → top). ``zIndex`` must stay ordered so map points stay above in-flight sheets.
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
                    missionLiveReservePoolBerthOverlay
                    missionLiveRuntimeMissionPointsOverlay
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Tasks card overlay focus helpers

    /// Focus a task triage sheet on the Tasks card. Re-tapping the same task dismisses the sheet (same
    /// affordance as ``focusLiveAssignment``). Opening a task clears vehicle triage so one sheet is active.
    private func focusLiveTask(_ id: UUID?) {
        withAnimation(triageSheetSpring) {
            guard let id else {
                focusedLiveTaskID = nil
                liveReserveSwapPick = nil
                liveReservePoolBrowseTaskID = nil
                focusedLiveReservePoolBerth = nil
                return
            }
            if focusedLiveTaskID == id {
                focusedLiveTaskID = nil
                liveReserveSwapPick = nil
                liveReservePoolBrowseTaskID = nil
                focusedLiveReservePoolBerth = nil
            } else {
                focusedLiveTaskID = id
                focusedLiveAssignmentID = nil
                liveReserveSwapPick = nil
                liveReservePoolBrowseTaskID = nil
                focusedLiveReservePoolBerth = nil
            }
        }
    }

    /// Focus a roster slot vehicle overlay. Toggles when the same id is re-tapped (open ↔ close)
    /// so a second click on the live roster health card dismisses the sheet.
    private func focusLiveAssignment(_ id: UUID?) {
        withAnimation(triageSheetSpring) {
            if let id, focusedLiveAssignmentID == id {
                focusedLiveAssignmentID = nil
                liveReserveSwapPick = nil
            } else {
                if let pick = liveReserveSwapPick, pick.vacancyAssignmentID != id {
                    liveReserveSwapPick = nil
                }
                focusedLiveAssignmentID = id
                focusedLiveReservePoolBerth = nil
                if id != nil {
                    focusedLiveTaskID = nil
                }
            }
        }
    }

    private func focusLiveReservePoolBerth(_ focus: LiveReservePoolBerthFocus?) {
        withAnimation(triageSheetSpring) {
            focusedLiveReservePoolBerth = focus
            if focus != nil {
                focusedLiveAssignmentID = nil
                liveReserveSwapPick = nil
                focusedLiveTaskID = nil
            }
        }
    }

    private func setLiveReservePoolBrowseForTask(_ taskID: UUID?, enabled: Bool) {
        withAnimation(triageSheetSpring) {
            guard enabled else {
                liveReservePoolBrowseTaskID = nil
                focusedLiveReservePoolBerth = nil
                return
            }
            liveReserveSwapPick = nil
            focusedLiveReservePoolBerth = nil
            liveReservePoolBrowseTaskID = taskID
        }
    }

    // MARK: - MC-R live map focus from triage

    private func liveMapHubCoordinatesForAssignments(_ assignments: [MissionRunAssignment]) -> [(Double, Double)] {
        assignments.compactMap { a -> (Double, Double)? in
            guard let vid = resolvedFleetStreamVehicleID(assignment: a, fleetLink: fleetLink, sitl: sitl),
                  let hub = fleetLink.hubTelemetry(forVehicleID: vid),
                  let lat = hub.latitudeDeg,
                  let lon = hub.longitudeDeg
            else { return nil }
            return (lat, lon)
        }
    }

    /// Fit the live overview map to this task's route, roster vehicles bound to the task, and **task-owned**
    /// runtime map points (excludes mission-wide pins with `taskID == nil`).
    private func focusLiveMapOnTaskTriage(task: RoutePath) {
        let rosterCoords = liveMapHubCoordinatesForAssignments(run.assignmentsBoundToMissionTask(taskID: task.id))
        let poolSyn = run.reservePool(forTaskID: task.id).entries
            .filter(\.hasFleetOrLegacyBinding)
            .map { syntheticMissionRunAssignment(from: $0) }
        let poolCoords = liveMapHubCoordinatesForAssignments(poolSyn)
        let coords = MissionControlLiveMapFitCoordinates.taskTriageFitCoordinates(
            taskWaypoints: task.waypoints,
            taskID: task.id,
            runtimeMissionPoints: run.runtimeMissionPoints,
            rosterVehicleHubCoordinates: rosterCoords + poolCoords
        )
        guard !coords.isEmpty else {
            toastCenter.show("Nothing to show on the map for this task yet.", style: .info)
            return
        }
        liveConsoleMediaTab = .map
        mapModel.focusMapFitBounds(points: coords)
    }

    private func focusLiveMapOnAssignmentVehicle(assignment: MissionRunAssignment) {
        guard let vid = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
              let hub = fleetLink.hubTelemetry(forVehicleID: vid),
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else {
            toastCenter.show("No vehicle position on the map yet.", style: .warning)
            return
        }
        liveConsoleMediaTab = .map
        mapModel.focusMapPanRetainZoom(lat: lat, lon: lon)
    }

    private func focusLiveMapOnRuntimeMissionPoint(mp: MissionPoint) {
        let lat = mp.coordinate.lat
        let lon = mp.coordinate.lon
        guard lat.isFinite, lon.isFinite else {
            toastCenter.show("Map point has no valid coordinates.", style: .warning)
            return
        }
        liveConsoleMediaTab = .map
        mapModel.focusMapPanRetainZoom(lat: lat, lon: lon)
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

    /// MC-R: floating **reserve pool berth** detail (above roster vehicle overlay, below map points). Mutually exclusive with ``liveReserveSwapPick`` tap targets on the strip.
    @ViewBuilder
    private var missionLiveReservePoolBerthOverlay: some View {
        if let berth = focusedLiveReservePoolBerth,
           let slot = run.reservePool(forTaskID: berth.taskID).entries.first(where: { $0.id == berth.slotID }) {
            missionLiveReservePoolBerthDetailSheet(taskID: berth.taskID, slot: slot)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2.5)
        }
    }

    /// In-card vehicle detail body: header (slot callsign + cog + close) and a placeholder content area
    /// reserved for richer per-vehicle telemetry. Kept intentionally lean so we can layer in details
    /// (battery / GPS / link / mission progress) iteratively without churning the overlay shell.
    private func missionLiveVehicleDetailSheet(assignment: MissionRunAssignment) -> some View {
        let rosterDevice = resolvedMission?.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId })
        let tid = assignment.taskId ?? focusedLiveTaskID
        let aff = floatingReserveSwapAffordance(assignment: assignment, mission: resolvedMission, taskID: tid)
        let swapPickActive = liveReserveSwapPick?.vacancyAssignmentID == assignment.id
        let runAllowsReserveSwapChrome = run.status == .running || run.status == .paused || run.status == .recovery
        let showSwapInReserveHeaderGlyph = runAllowsReserveSwapChrome && aff.enabled && tid != nil

        return VStack(alignment: .leading, spacing: 0) {
            missionLiveOverlayHeader(
                title: assignment.slotName,
                subtitle: nil,
                titleMuted: false
            ) {
                HStack(spacing: GuardianSpacing.xs) {
                    missionLiveOverlayHeaderGlyphButton(
                        systemImage: "mappin.and.ellipse",
                        help: "Center the map on this vehicle (keep zoom)"
                    ) {
                        focusLiveMapOnAssignmentVehicle(assignment: assignment)
                    }
                    if showSwapInReserveHeaderGlyph {
                        missionLiveOverlayHeaderGlyphButton(
                            systemImage: "arrow.left.arrow.right",
                            help: swapPickActive
                                ? "Cancel reserve swap — return to normal roster strip."
                                : "Swap in reserve — show class-compatible floating reserves in the roster strip; tap one to confirm.",
                            foreground: swapPickActive ? GuardianSemanticColors.dangerForeground : nil
                        ) {
                            if swapPickActive {
                                cancelMcrReserveSwapPick()
                            } else {
                                beginMcrReserveSwapPick(for: assignment)
                            }
                        }
                        .disabled(!swapPickActive && mcrReserveSwapOperationInFlight())
                        .accessibilityLabel(swapPickActive ? "Cancel reserve swap" : "Swap in reserve")
                    }
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
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    if runAllowsReserveSwapChrome {
                        if let pick = liveReserveSwapPick, pick.vacancyAssignmentID == assignment.id {
                            GuardianInlineNotice(
                                kind: .informational,
                                title: "Pick a reserve",
                                detail: "Tap a pool vehicle in the roster strip below, then confirm."
                            )
                        } else if aff.showBlockedControl, !aff.blockedReason.isEmpty {
                            Text(aff.blockedReason)
                                .font(GuardianTypography.font(.denseCaption12Regular))
                                .foregroundStyle(theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    missionLiveAssignmentTriageBadgesCard(assignment: assignment, rosterDevice: rosterDevice)

                    if missionLiveEngageStabilizeChromeEnabled(assignment: assignment) {
                        let liveVid = telemetryVehicleID(for: assignment)
                        let phase = liveVid.map { fleetLink.mcrOperatorVehiclePhase(vehicleID: $0) } ?? .unknown
                        if phase == .operatorParkAwaitingContinue {
                            missionLiveTriageActionRowCard(bodyCaption: "Resume after park") {
                                GuardianPrimaryProminentButton(title: "Continue mission") {
                                    performOperatorContinueMissionAfterPark(assignment: assignment)
                                }
                                .guardianPointerOnHover()
                                .help("Set mission mode, arm if needed, and start mission execution on the autopilot.")
                            }
                            missionLiveTriageActionRowCard(bodyCaption: "Live Drive") {
                                GuardianPrimaryProminentButton(title: "Engage") {
                                    performOperatorEngageLiveDriveFromPark(assignment: assignment)
                                }
                                .guardianPointerOnHover()
                                .help("Open Live Drive for this vehicle to take manual control.")
                            }
                        } else {
                            missionLiveTriageActionRowCard(bodyCaption: "Stop Vehicle") {
                                HStack(spacing: GuardianSpacing.xs) {
                                    GuardianPrimaryProminentButton(title: "Park") {
                                        performOperatorEngageStabilize(assignment: assignment, kind: .park)
                                    }
                                    .guardianPointerOnHover()
                                    .help("Send a park catalogue command to this vehicle through the mission run log.")
                                    if missionLiveAssignmentTriageStabilizeOffersLoiter(
                                        assignment: assignment,
                                        rosterDevice: rosterDevice
                                    ) {
                                        GuardianThemedButton(
                                            title: "Loiter",
                                            accent: .primary,
                                            surface: .outline,
                                            size: .small,
                                            shape: .cornered,
                                            action: { performOperatorEngageStabilize(assignment: assignment, kind: .loiter) }
                                        )
                                        .guardianPointerOnHover()
                                        .help("Send a loiter / hold catalogue command to this vehicle through the mission run log.")
                                    }
                                }
                            }
                            missionLiveEngageStabilizeTelemetryNotice(assignment: assignment)
                        }
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

    /// MC-R: floating reserve **berth** sheet (pool row). Distinct from swap-in pick: strip taps here open this overlay; swap pick opens confirm.
    private func missionLiveReservePoolBerthDetailSheet(taskID: UUID, slot: MissionRunReservePoolSlot) -> some View {
        let syn = MissionRunAssignment.syntheticForReservePool(slot: slot)
        let taskName = resolvedMission?.routeMacro.tasks.first(where: { $0.id == taskID })?.name ?? "Task"
        let taskEnabled = reservePoolBerthTaskEditingEnabled(taskID: taskID)
        let poolMutationLocked = mcrReservePoolSlotMutationLocked(taskID: taskID, slotID: slot.id)
        return VStack(alignment: .leading, spacing: 0) {
            missionLiveOverlayHeader(
                title: slot.label,
                subtitle: "\(taskName) · Floating reserve",
                titleMuted: !taskEnabled
            ) {
                HStack(spacing: GuardianSpacing.xs) {
                    missionLiveOverlayHeaderGlyphButton(
                        systemImage: "mappin.and.ellipse",
                        help: "Center the map on this vehicle (keep zoom)"
                    ) {
                        focusLiveMapOnAssignmentVehicle(assignment: syn)
                    }
                    if telemetryVehicleID(for: syn) != nil {
                        missionLiveSidebarStyleVehicleInspectorButton {
                            presentRosterCalibrationSheet(for: syn)
                        }
                    }
                    missionLiveSidebarStyleCloseButton {
                        focusLiveReservePoolBerth(nil)
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    missionLiveAssignmentTriageBadgesCard(assignment: syn, rosterDevice: nil)

                    if missionLiveEngageStabilizeChromeEnabled(assignment: syn) {
                        let liveVid = telemetryVehicleID(for: syn)
                        let phase = liveVid.map { fleetLink.mcrOperatorVehiclePhase(vehicleID: $0) } ?? .unknown
                        if phase == .operatorParkAwaitingContinue {
                            missionLiveTriageActionRowCard(bodyCaption: "Resume after park") {
                                GuardianPrimaryProminentButton(title: "Continue mission") {
                                    performOperatorContinueMissionAfterPark(assignment: syn)
                                }
                                .guardianPointerOnHover()
                                .help("Set mission mode, arm if needed, and start mission execution on the autopilot.")
                            }
                            missionLiveTriageActionRowCard(bodyCaption: "Live Drive") {
                                GuardianPrimaryProminentButton(title: "Engage") {
                                    performOperatorEngageLiveDriveFromPark(assignment: syn)
                                }
                                .guardianPointerOnHover()
                                .help("Open Live Drive for this vehicle to take manual control.")
                            }
                        } else {
                            missionLiveTriageActionRowCard(bodyCaption: "Stop Vehicle") {
                                HStack(spacing: GuardianSpacing.xs) {
                                    GuardianPrimaryProminentButton(title: "Park") {
                                        performOperatorEngageStabilize(assignment: syn, kind: .park)
                                    }
                                    .guardianPointerOnHover()
                                    .help("Send a park catalogue command to this berth’s vehicle through the mission run log.")
                                    if missionLiveAssignmentTriageStabilizeOffersLoiter(assignment: syn, rosterDevice: nil) {
                                        GuardianThemedButton(
                                            title: "Loiter",
                                            accent: .primary,
                                            surface: .outline,
                                            size: .small,
                                            shape: .cornered,
                                            action: { performOperatorEngageStabilize(assignment: syn, kind: .loiter) }
                                        )
                                        .guardianPointerOnHover()
                                        .help("Send a loiter / hold catalogue command to this berth’s vehicle through the mission run log.")
                                    }
                                }
                            }
                            missionLiveEngageStabilizeTelemetryNotice(assignment: syn)
                        }
                    }

                    if poolMutationLocked {
                        Text("This berth is busy — reserve swap checks or arm preflight are still running. Wait for them to finish before changing the vehicle.")
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if taskEnabled {
                        missionLiveTriageActionRowCard(bodyCaption: "Replace vehicle") {
                            GuardianThemedButton(
                                title: reservePoolBerthPreflightBusy ? "Busy…" : "Choose",
                                accent: .primary,
                                surface: .outline,
                                size: .small,
                                shape: .cornered,
                                action: { presentReservePoolVehiclePicker(taskID: taskID, slotID: slot.id) }
                            )
                            .disabled(reservePoolBerthPreflightBusy || poolMutationLocked)
                            .guardianPointerOnHover()
                            .help("Switch the vehicle for another in your stable.")
                        }

                        if slot.hasFleetOrLegacyBinding {
                            missionLiveTriageActionRowCard(bodyCaption: "Run preflight") {
                                GuardianThemedButton(
                                    title: reservePoolBerthPreflightBusy ? "Running…" : "Run",
                                    accent: .primary,
                                    surface: .outline,
                                    size: .small,
                                    shape: .cornered,
                                    action: { runReservePoolBerthArmPreflight(taskID: taskID, slot: slot) }
                                )
                                .disabled(reservePoolBerthPreflightBusy || poolMutationLocked)
                                .guardianPointerOnHover()
                                .help("Run a one-shot arm preflight on the bound vehicle (outcome in a toast).")
                            }

                            missionLiveTriageActionRowCard(bodyCaption: "Drop vehicle") {
                                GuardianThemedButton(
                                    title: reservePoolBerthPreflightBusy ? "Busy…" : "Drop",
                                    accent: .danger,
                                    surface: .outline,
                                    size: .small,
                                    shape: .cornered,
                                    action: {
                                        clearReservePoolVehicleBinding(taskID: taskID, slotID: slot.id)
                                    }
                                )
                                .disabled(reservePoolBerthPreflightBusy || poolMutationLocked)
                                .guardianPointerOnHover()
                                .help("Remove the bound aircraft from this berth.")
                            }
                        }
                    } else {
                        Text("This task is disabled — change the pool in Mission Control setup when editing is allowed.")
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
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

    private func reservePoolBerthTaskEditingEnabled(taskID: UUID) -> Bool {
        guard let t = resolvedMission?.routeMacro.tasks.first(where: { $0.id == taskID }) else { return false }
        return t.enabled
    }

    private var reservePoolBerthPreflightBusy: Bool { reservePoolBerthPreflightFocus != nil }

    private func mcrReserveSwapOperationInFlight() -> Bool {
        MissionControlReservePoolMutationGate.swapOperationInFlight(lock: mcrFloatingReserveSwapLock)
    }

    private func mcrReservePoolSlotMutationLocked(taskID: UUID, slotID: UUID) -> Bool {
        MissionControlReservePoolMutationGate.reservePoolSlotMutationLocked(
            swapLock: mcrFloatingReserveSwapLock,
            berthPreflightTaskID: reservePoolBerthPreflightFocus?.taskID,
            berthPreflightSlotID: reservePoolBerthPreflightFocus?.slotID,
            taskID: taskID,
            slotID: slotID
        )
    }

    private func runReservePoolBerthArmPreflight(taskID: UUID, slot: MissionRunReservePoolSlot) {
        guard reservePoolBerthPreflightFocus == nil else {
            toastCenter.show("Arm preflight is already running on another berth.", style: .info)
            return
        }
        guard !mcrReservePoolSlotMutationLocked(taskID: taskID, slotID: slot.id) else {
            toastCenter.show("This berth is busy — wait for the reserve swap or preflight on it to finish.", style: .warning)
            return
        }
        let syn = MissionRunAssignment.syntheticForReservePool(slot: slot)
        guard let vehicleID = resolvedFleetStreamVehicleID(assignment: syn, fleetLink: fleetLink, sitl: sitl) else {
            toastCenter.show("No live vehicle link for this berth.", style: .warning)
            return
        }
        reservePoolBerthPreflightFocus = LiveReservePoolBerthFocus(taskID: taskID, slotID: slot.id)
        Task { @MainActor in
            defer { reservePoolBerthPreflightFocus = nil }
            let r = await controlStore.runSingleVehiclePreflightProbe(
                vehicleID: vehicleID,
                fleetLink: fleetLink,
                sitl: sitl,
                leaveArmed: true,
                allowDuringLiveMission: true,
                preflightAuditSource: "missionControl.preflightProbe.reservePoolBerth",
                telemetryGateMode: .none
            )
            if r.passed {
                toastCenter.show(r.detail, style: .success)
            } else {
                toastCenter.show(r.detail, style: .error)
            }
        }
    }

    /// Engage flow step 1 (v1): show **Stop Vehicle** (Park ± Loiter by class) when the slot can dispatch through MRE with a live bridge link; after PX4 park latch, **Resume** and **Live Drive** cards appear separately.
    private func missionLiveEngageStabilizeChromeEnabled(assignment: MissionRunAssignment) -> Bool {
        guard run.status == .running || run.status == .paused || run.status == .recovery else {
            return false
        }
        let token = (assignment.attachedFleetVehicleToken ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }
        return telemetryVehicleID(for: assignment) != nil
    }

    private func performOperatorEngageStabilize(
        assignment: MissionRunAssignment,
        kind: MissionRunEngageStabilizeDispatchKind
    ) {
        run.attachServices(fleetLink: fleetLink, sitl: sitl, generalSettings: generalSettings)
        let event = run.issueOperatorEngageStabilizeDispatch(
            assignment: assignment,
            kind: kind,
            fleetLink: fleetLink,
            sitl: sitl
        )
        onUpdate(run)
        let label = kind.operatorShortLabel
        switch event.level {
        case .info:
            toastCenter.show("Queued \(label) for \(assignment.slotName).", style: .info)
            missionLiveEngageStabilizeTelemetryWatch = MissionLiveEngageStabilizeTelemetryWatch(
                assignmentID: assignment.id,
                kind: kind,
                startedAt: Date()
            )
        case .warning:
            toastCenter.show("\(label): \(event.message)", style: .warning)
        case .error:
            toastCenter.show("\(label): \(event.message)", style: .error)
        }
    }

    private func performOperatorContinueMissionAfterPark(assignment: MissionRunAssignment) {
        guard let vid = telemetryVehicleID(for: assignment) else {
            toastCenter.show("No linked vehicle telemetry for this slot.", style: .warning)
            return
        }
        run.attachServices(fleetLink: fleetLink, sitl: sitl, generalSettings: generalSettings)
        let kind = MissionRunOperatorContinueMissionAfterParkDispatchKind.armModeMissionStart
        let event = run.issueOperatorContinueMissionAfterParkDispatch(
            assignment: assignment,
            kind: kind,
            fleetLink: fleetLink,
            sitl: sitl
        )
        onUpdate(run)
        let label = kind.operatorShortLabel
        switch event.level {
        case .info:
            fleetLink.clearMcrOperatorParkAwaitingContinue(vehicleID: vid)
            toastCenter.show("Queued \(label) for \(assignment.slotName).", style: .info)
        case .warning:
            toastCenter.show("\(label): \(event.message)", style: .warning)
        case .error:
            toastCenter.show("\(label): \(event.message)", style: .error)
        }
    }

    private func performOperatorEngageLiveDriveFromPark(assignment: MissionRunAssignment) {
        guard let vid = telemetryVehicleID(for: assignment) else {
            toastCenter.show("No linked vehicle telemetry for this slot.", style: .warning)
            return
        }
        guard fleetLink.mcrOperatorVehiclePhase(vehicleID: vid) == .operatorParkAwaitingContinue else {
            toastCenter.show("Live Drive is available after park completes.", style: .info)
            return
        }
        run.attachServices(fleetLink: fleetLink, sitl: sitl, generalSettings: generalSettings)
        _ = run.cancelPendingExecutorBatchesForOperatorLiveDriveEngage(assignment: assignment)
        run.noteOperatorLiveDriveHandoffActive(forAssignmentID: assignment.id)
        operatorPromptReviewFocus.requestLiveDriveEngageDrillIn(vehicleID: vid, missionRunID: run.id)
        onUpdate(run)
        toastCenter.show("Switched to Live Drive for this vehicle.", style: .info)
    }

    private func clearMissionLiveEngageStabilizeTelemetryWatch() {
        missionLiveEngageStabilizeTelemetryWatch = nil
    }

    /// Engage flow: non-blocking stabilize telemetry watch (``MissionRunEngageStabilizeTelemetryClassifier``).
    @ViewBuilder
    private func missionLiveEngageStabilizeTelemetryNotice(assignment: MissionRunAssignment) -> some View {
        if let watch = missionLiveEngageStabilizeTelemetryWatch, watch.assignmentID == assignment.id {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let now = context.date
                let vid = telemetryVehicleID(for: assignment)
                let hub = vid.flatMap { fleetLink.hubTelemetryByVehicleID[$0] }
                let lifecycle = vid.flatMap { fleetLink.vehicleStatus(forVehicleID: $0) }
                let operational = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: lifecycle, now: now)
                let maxAge: TimeInterval = {
                    guard let vid else { return MissionControlReserveSwapInPreflightGates.maxHubAgeSecondsLive }
                    return isSimulationVehicleID(vid)
                        ? MissionControlReserveSwapInPreflightGates.maxHubAgeSecondsSimulation
                        : MissionControlReserveSwapInPreflightGates.maxHubAgeSecondsLive
                }()
                let base = MissionRunEngageStabilizeTelemetryClassifier.evaluate(
                    kind: watch.kind,
                    hub: hub,
                    operational: operational,
                    now: now,
                    maxHubAgeSeconds: maxAge
                )
                let elapsed = now.timeIntervalSince(watch.startedAt)
                let verdict: MissionRunEngageStabilizeTelemetryVerdict = {
                    if elapsed > MissionRunEngageStabilizeTelemetryClassifier.operatorWaitTimeoutSeconds, base != .stable {
                        return .fault(
                            reason: "Timed out waiting for stable telemetry. Check the vehicle, link, and mode, then send \(watch.kind.operatorShortLabel) again."
                        )
                    }
                    return base
                }()
                let elapsedLabel = String(format: "%.0f", elapsed)

                switch verdict {
                case .stable:
                    GuardianInlineNotice(
                        kind: .success,
                        title: "Stabilized",
                        detail: "\(watch.kind.operatorShortLabel) criteria look satisfied (hub age \(elapsedLabel)s).",
                        trailing: {
                            GuardianThemedButton(
                                title: "Dismiss",
                                accent: .neutral,
                                surface: .outline,
                                size: .small,
                                shape: .cornered,
                                action: clearMissionLiveEngageStabilizeTelemetryWatch
                            )
                            .guardianPointerOnHover()
                        }
                    )
                case .pending(let reason):
                    GuardianInlineNotice(
                        kind: .informational,
                        title: "Watching telemetry",
                        detail: "\(reason) (\(elapsedLabel)s).",
                        trailing: {
                            GuardianThemedButton(
                                title: "Dismiss",
                                accent: .neutral,
                                surface: .outline,
                                size: .small,
                                shape: .cornered,
                                action: clearMissionLiveEngageStabilizeTelemetryWatch
                            )
                            .guardianPointerOnHover()
                        }
                    )
                case .fault(let reason):
                    GuardianInlineNotice(
                        kind: .warning,
                        title: "Stabilize check",
                        detail: reason,
                        trailing: {
                            GuardianThemedButton(
                                title: "Dismiss",
                                accent: .neutral,
                                surface: .outline,
                                size: .small,
                                shape: .cornered,
                                action: clearMissionLiveEngageStabilizeTelemetryWatch
                            )
                            .guardianPointerOnHover()
                        }
                    )
                }
            }
        }
    }

    /// MC-R triage: body-only ``GuardianCard`` with a single row — descriptive caption leading, compact action trailing (8pt stack spacing via ``GuardianSpacing`` `.xs` on the parent ``VStack``).
    @ViewBuilder
    private func missionLiveTriageActionRowCard<Trailing: View>(
        bodyCaption: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        GuardianCard(configuration: mcSetupGroupCardConfiguration, body: {
            HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                Text(bodyCaption)
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
            }
        })
    }

    /// MC-R assignment triage: body-only ``GuardianCard`` with capsule badges (semantic slot, neutral role + vehicle id), a full-width **Mission Control operator phase** line (``FleetMcrOperatorVehiclePhase``), then live status chips from ``FleetVehicleModel/liveStatusBadgeRow`` (or hub + operational model): arm / motion / mode, battery, AGL.
    @ViewBuilder
    private func missionLiveAssignmentTriageBadgesCard(
        assignment: MissionRunAssignment,
        rosterDevice: RosterDevice?
    ) -> some View {
        // Explicit `body:` avoids Swift picking the media+body or header+body convenience `init` overloads.
        GuardianCard(configuration: mcSetupGroupCardConfiguration, body: {
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                    if let rosterDevice {
                        missionLiveAssignmentTriageSlotCapsuleBadge(slot: rosterDevice.slot)
                        missionLiveAssignmentTriageNeutralCapsuleBadge(
                            title: RosterRoleCatalog.displayName(forBehaviorRoleID: rosterDevice.behaviorRoleID)
                        )
                    }
                    if let vid = telemetryVehicleID(for: assignment) {
                        let short = assignmentFleetDisplayShortID(assignment: assignment, rosterDevice: rosterDevice)
                        missionLiveAssignmentTriageVehicleIdCapsuleBadge(title: short)
                            .help("Bridge vehicle key: \(vid)")
                    } else {
                        missionLiveAssignmentTriageNeutralCapsuleBadge(title: "No bridge link")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let vid = telemetryVehicleID(for: assignment) {
                    let statusRow = fleetLink.vehicleModel(forVehicleID: vid)?.liveStatusBadgeRow
                        ?? FleetVehicleLiveStatusBadgeRow(
                            hub: fleetLink.hubTelemetry(forVehicleID: vid),
                            operational: fleetLink.vehicleOperationalModel(forVehicleID: vid)
                        )
                    let mcrPhase = fleetLink.mcrOperatorVehiclePhase(vehicleID: vid)
                    missionLiveAssignmentTriageMcrOperatorPhaseFullWidthBadge(phase: mcrPhase)
                        .help("Mission Control operator phase for this bridge vehicle.")
                    HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                        missionLiveAssignmentTriageActiveStateCapsuleBadge(
                            title: statusRow.arm.title,
                            isActive: statusRow.arm.isActive
                        )
                        missionLiveAssignmentTriageActiveStateCapsuleBadge(
                            title: statusRow.motion.title,
                            isActive: statusRow.motion.isActive
                        )
                        missionLiveAssignmentTriageActiveStateCapsuleBadge(
                            title: statusRow.mode.title,
                            isActive: statusRow.mode.isActive
                        )
                        missionLiveAssignmentTriageBatteryTrafficBadge(chip: statusRow.battery)
                        missionLiveAssignmentTriageNeutralCapsuleBadge(title: statusRow.altitude.title)
                            .help(statusRow.altitude.helpSummary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        })
    }

    private func missionLiveAssignmentTriageSlotSemanticColors(_ slot: MissionRosterSlotRole) -> (background: Color, foreground: Color) {
        switch slot {
        case .primary:
            return (GuardianSemanticColors.infoBackground, GuardianSemanticColors.infoForeground)
        case .wingman:
            return (GuardianSemanticColors.successBackground, GuardianSemanticColors.successForeground)
        case .reserve:
            return (GuardianSemanticColors.warningBackground, GuardianSemanticColors.warningForeground)
        }
    }

    @ViewBuilder
    private func missionLiveAssignmentTriageSlotCapsuleBadge(slot: MissionRosterSlotRole) -> some View {
        let pair = missionLiveAssignmentTriageSlotSemanticColors(slot)
        Text(slot.rawValue.capitalized)
            .font(GuardianTypography.font(.denseCaption10Semibold))
            .foregroundStyle(pair.foreground)
            .lineLimit(1)
            .padding(.horizontal, GuardianSpacing.chromeTightInset)
            .padding(.vertical, GuardianSpacing.titleStackTight)
            .background(pair.background)
            .clipShape(Capsule())
    }

    private func missionLiveAssignmentTriageMcrOperatorPhaseSemanticColors(
        _ phase: FleetMcrOperatorVehiclePhase
    ) -> (background: Color, foreground: Color) {
        switch phase {
        case .unknown:
            return (GuardianSemanticColors.neutralBadgeBackground, GuardianSemanticColors.neutralBadgeForeground)
        case .onMission:
            return (GuardianSemanticColors.infoBackground, GuardianSemanticColors.infoForeground)
        case .operatorParkAwaitingContinue:
            return (GuardianSemanticColors.warningBackground, GuardianSemanticColors.warningForeground)
        }
    }

    @ViewBuilder
    private func missionLiveAssignmentTriageMcrOperatorPhaseFullWidthBadge(phase: FleetMcrOperatorVehiclePhase) -> some View {
        let pair = missionLiveAssignmentTriageMcrOperatorPhaseSemanticColors(phase)
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

    @ViewBuilder
    private func missionLiveAssignmentTriageActiveStateCapsuleBadge(title: String, isActive: Bool) -> some View {
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

    @ViewBuilder
    private func missionLiveAssignmentTriageBatteryTrafficBadge(chip: FleetVehicleLiveStatusBadgeRow.BatteryChip) -> some View {
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

    @ViewBuilder
    private func missionLiveAssignmentTriageNeutralCapsuleBadge(title: String) -> some View {
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

    @ViewBuilder
    private func missionLiveAssignmentTriageVehicleIdCapsuleBadge(title: String) -> some View {
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

    /// Canonical short stream label (e.g. `UAV-V:1`), aligned with roster slot cards — not raw `sysid:` keys.
    private func assignmentFleetDisplayShortID(assignment: MissionRunAssignment, rosterDevice: RosterDevice?) -> String {
        guard let vid = telemetryVehicleID(for: assignment) else { return "" }
        if let model = fleetLink.vehicleModel(forVehicleID: vid) {
            return model.displayShortID
        }
        let rosterDeviceClass = rosterDevice?.vehicleClass ?? .unknown
        if let key = assignment.attachedFleetVehicleToken,
           let token = FleetMissionVehicleToken(storageKey: key),
           case .sitl(let uuid) = token,
           let inst = sitl.instances.first(where: { $0.id == uuid }) {
            let systemID = inst.stackInstanceIndex + 1
            return "\(inst.preset.fleetVehicleType.classCode):\(systemID)"
        }
        let prefix = "sysid:"
        if vid.hasPrefix(prefix), let n = Int(vid.dropFirst(prefix.count)) {
            return "\(rosterDeviceClass.classCode):\(n)"
        }
        let tail = vid.split(separator: ":").last.map(String.init) ?? vid
        return "\(rosterDeviceClass.classCode):\(tail)"
    }

    /// Resolved granular type for triage chrome (stamped model, SITL preset, then roster template).
    private func assignmentResolvedFleetVehicleType(
        assignment: MissionRunAssignment,
        rosterDevice: RosterDevice?
    ) -> FleetVehicleType {
        if let vid = telemetryVehicleID(for: assignment),
           let model = fleetLink.vehicleModel(forVehicleID: vid) {
            return model.data.vehicleType
        }
        if let key = assignment.attachedFleetVehicleToken,
           let token = FleetMissionVehicleToken(storageKey: key),
           case .sitl(let uuid) = token,
           let inst = sitl.instances.first(where: { $0.id == uuid }) {
            return inst.preset.fleetVehicleType
        }
        return rosterDevice?.vehicleClass ?? .unknown
    }

    /// **Loiter** stabilize is omitted for **UGV** assignment triage (park is sufficient).
    private func missionLiveAssignmentTriageStabilizeOffersLoiter(
        assignment: MissionRunAssignment,
        rosterDevice: RosterDevice?
    ) -> Bool {
        assignmentResolvedFleetVehicleType(assignment: assignment, rosterDevice: rosterDevice).universalClass != .ugv
    }

    /// In-card triage sheet for the selected task: state, wind-down, hero progress, read-only floating reserve pool strip, sidebar-style close.
    private func missionLiveTaskTriageInnerSheet(task: RoutePath, mission: Mission) -> some View {
        let taskIndex = mission.routeMacro.tasks.firstIndex(where: { $0.id == task.id }) ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            missionLiveOverlayHeader(
                title: task.name,
                subtitle: nil,
                titleMuted: !task.enabled
            ) {
                HStack(spacing: GuardianSpacing.xs) {
                    missionLiveOverlayHeaderGlyphButton(
                        systemImage: "mappin.and.ellipse",
                        help: "Show on map: fit this task's route, linked vehicles, and task map points"
                    ) {
                        focusLiveMapOnTaskTriage(task: task)
                    }
                    if !run.reservePool(forTaskID: task.id).entries.isEmpty,
                       run.status == .running || run.status == .paused || run.status == .recovery
                    {
                        let browsingReserves = liveReservePoolBrowseTaskID == task.id
                        missionLiveOverlayHeaderGlyphButton(
                            systemImage: "arrow.left.arrow.right",
                            help: browsingReserves
                                ? "Show task roster in the strip below (floating reserve browse off)."
                                : "Show this task’s floating reserve berths in the roster strip (tap a berth to manage).",
                            foreground: browsingReserves ? GuardianSemanticColors.successForeground : nil
                        ) {
                            setLiveReservePoolBrowseForTask(task.id, enabled: !browsingReserves)
                        }
                    }
                    missionLiveSidebarStyleCogButton {
                        presentTaskSettingsSidebar(task: task)
                    }
                    missionLiveSidebarStyleCloseButton {
                        focusLiveTask(nil)
                    }
                }
            }

            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                missionLiveTaskStateBanner(run.taskStateByTaskID[task.id] ?? .ready)
                    .padding(.top, GuardianSpacing.denseGutter)

                missionLiveTaskEndProtocolAcknowledgementBlock(task: task, compact: false)

                Group {
                    if run.status == .running {
                        TimelineView(.periodic(from: .now, by: 0.25)) { context in
                            missionLiveTaskTriageProgressCard(
                                task: task,
                                taskIndex: taskIndex,
                                mission: mission,
                                now: context.date
                            )
                        }
                    } else {
                        missionLiveTaskTriageProgressCard(
                            task: task,
                            taskIndex: taskIndex,
                            mission: mission,
                            now: Date()
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                if run.status == .running || run.status == .paused {
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        if missionLiveTaskWindDownSectionVisible(task: task, now: context.date) {
                            missionLiveTaskWindDownActionsSection(task: task, now: context.date)
                        }
                    }
                }
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

    /// Worst merged slot-state attention across this task’s roster rows (MC-R task list chip).
    private func missionLiveTaskSlotAttention(for task: RoutePath, mission: Mission) -> (severity: GuardianFeedbackSeverity, title: String)? {
        guard run.status == .running || run.status == .paused || run.status == .recovery else { return nil }
        let rows = run.assignments.filter { run.missionControlAssignmentBelongsToTask($0, task: task, mission: mission) }
        return MissionControlAssignmentSlotRosterAttention.worstAmong(assignments: rows)
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
                        if let slotAttention = missionLiveTaskSlotAttention(for: task, mission: mission) {
                            MissionControlRosterSlotAttentionCapsule(
                                severity: slotAttention.severity,
                                title: slotAttention.title
                            )
                        }
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
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(liveConsoleCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(liveConsoleCardStroke, lineWidth: 1)
                )
            VStack(spacing: GuardianSpacing.xs) {
                Image(systemName: "video")
                    .font(GuardianTypography.font(.heroGlyph30Medium))
                    .foregroundStyle(theme.textSecondary)
                Text("Camera view placeholder")
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    /// MC-R live map: **same shell as MCS** roster staging map (``rostersStagingMapBare``) — ``GuardianCard`` media + identical
    /// Leaflet bridge hooks (`onMapClick`, `onVehicleMarkerMoved`, hub-driven reconcile). Push payloads stay live-specific
    /// (``pushLiveOverviewMapModelFromMission`` / ``liveOverviewMapStructureIdentity``).
    private var missionLiveOverviewMap: some View {
        GuardianCard(
            configuration: mcSetupGroupCardConfiguration,
            media: {
                GuardianMapView(
                    model: mapModel,
                    toolbar: GuardianMapToolbarOptions(
                        mapResetAction: { _ in
                            fitLiveOverviewMapToVisibleMissionContent()
                        }
                    ),
                    contextMenuPolicy: GuardianMapContextMenuPolicy(
                        vehicleActions: [.followVehicle, .stopFollowingVehicle, .centerMarker],
                        waypointActions: [],
                        homeActions: [],
                        missionPointActions: []
                    ),
                    onMapClick: { _, _ in
                        clearLiveOverviewMapSelectionFromBackgroundTap()
                    },
                    onVehicleMarkerMoved: { markerID, lat, lon in
                        applySetupMarkerDrag(markerID: markerID, lat: lat, lon: lon)
                    },
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
                        toggleLiveRuntimeMissionPointSelectionFromMapPin(id)
                    },
                    onMissionPointMoved: { id, lat, lon in
                        _ = run.applyRuntimeMissionPointUpdate(id: id, source: "operator") {
                            $0.coordinate.lat = lat
                            $0.coordinate.lon = lon
                        }
                        onUpdate(run)
                    },
                    onVehicleTap: { ev in
                        guard let raw = ev.markerID else { return }
                        if let berth = MissionControlReservePoolMapMarkerID.decodeBerth(raw) {
                            focusLiveReservePoolBerth(
                                LiveReservePoolBerthFocus(taskID: berth.taskID, slotID: berth.slotID)
                            )
                            liveConsoleMediaTab = .map
                            return
                        }
                        guard let aid = UUID(uuidString: raw) else { return }
                        focusLiveAssignment(aid)
                    },
                    onTaskPathTap: { ev in
                        focusLiveTask(ev.taskPathID)
                    },
                    onViewportCenterChanged: { lat, lon in
                        liveRuntimeMissionMapViewportCenter = RouteCoordinate(lat: lat, lon: lon)
                    }
                )
                .task(id: liveOverviewMapStructureIdentity) {
                    pushLiveOverviewMapModelFromMission()
                    fitLiveOverviewMapToVisibleMissionContent()
                }
                .onChange(of: liveOverviewMapMarkerCoordinateDigest) { _ in
                    pushLiveOverviewMapMarkersOnly()
                }
                .onChange(of: focusedLiveAssignmentID) { _ in
                    // Selection is not part of ``liveOverviewMapMarkerCoordinateDigest``; still refresh markers for ring/label.
                    pushLiveOverviewMapMarkersOnly()
                }
                .onChange(of: fleetLink.hubTelemetry?.lastUpdate) { _ in
                    // Reconcile SIM drag overlays on every hub sample; marker moves use ``liveOverviewMapMarkerCoordinateDigest``.
                    reconcileSetupStagingSimDragOverlayWithHubTelemetry()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
    }

    /// MC-R live map polylines: when map isolation is on and a task is focused in triage, only that task’s path is drawn.
    private func liveOverviewMapTaskPathPayload(from mission: Mission) -> (coords: [[RouteCoordinate]], ids: [UUID]) {
        if let tid = liveOverviewMapFocusedTaskID,
           let task = mission.routeMacro.tasks.first(where: { $0.id == tid }) {
            return ([task.waypoints.map(\.coord)], [tid])
        }
        let tasks = mission.routeMacro.tasks
        return (tasks.map { $0.waypoints.map(\.coord) }, tasks.map(\.id))
    }

    /// MC-R live map roster strip: **assignment ids only** so fleet token / bridge stream changes (e.g. reserve swap-in) do not invalidate ``liveOverviewMapStructureIdentity``.
    private var liveOverviewRosterRowTopologySignature: String {
        filteredLiveRosterAssignments
            .map { $0.id.uuidString }
            .sorted()
            .joined(separator: ";")
    }

    /// MC-R live map floating reserve **berths** (`taskID|slotID` per row); omits fleet tokens and stream ids.
    private var liveOverviewReservePoolSlotTopologySignature: String {
        guard let mission = resolvedMission else { return "" }
        let taskIDs: [UUID] = {
            if let f = liveOverviewMapFocusedTaskID { return [f] }
            return mission.routeMacro.tasks.filter(\.enabled).map(\.id)
        }()
        var rows: [String] = []
        for tid in taskIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let pool = run.reservePool(forTaskID: tid)
            for slot in pool.entries.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                rows.append("\(tid.uuidString)|\(slot.id.uuidString)")
            }
        }
        return rows.joined(separator: ";")
    }

    /// Topology-only identity for the live overview map `.task(id:)` — excludes hub-driven lat/lon so
    /// telemetry does not rebuild Leaflet layers every tick (see ``liveOverviewMapMarkerCoordinateDigest``).
    private var liveOverviewMapStructureIdentity: LiveOverviewMapStructureIdentity {
        let mission = resolvedMission
        let pathPayload = mission.map { liveOverviewMapTaskPathPayload(from: $0) }
        let points = MissionPoint.filteredForMissionControlLiveMap(
            run.runtimeMissionPoints,
            focusedTaskID: liveOverviewMapFocusedTaskID
        )
        let topo = points
            .map { mp in
                let sel = liveRuntimeOverviewSelectedMissionPointID == mp.id ? "1" : "0"
                return "\(mp.id.uuidString)|\(mp.kind.rawValue)|\(mp.isClosed)|\(sel)"
            }
            .joined(separator: ";")
        let rosterTopo = liveOverviewRosterRowTopologySignature
        let poolTopo = liveOverviewReservePoolSlotTopologySignature
        return LiveOverviewMapStructureIdentity(
            missionID: mission?.id,
            homeCoord: mission?.routeMacro.home?.coord,
            allTasksCoords: pathPayload?.coords ?? [],
            taskPathIDs: pathPayload?.ids ?? [],
            focusedTaskID: liveOverviewMapFocusedTaskID,
            missionPointTopologySignature: topo,
            rosterSlotBindingSignature: rosterTopo + "§pool§" + poolTopo
        )
    }

    /// Quantized live coordinates for roster vehicles + runtime map points; drives marker-only pushes
    /// without invalidating ``liveOverviewMapStructureIdentity`` on every hub sample.
    private var liveOverviewMapMarkerCoordinateDigest: String {
        let pts = MissionPoint.filteredForMissionControlLiveMap(
            run.runtimeMissionPoints,
            focusedTaskID: liveOverviewMapFocusedTaskID
        )
            .map { mp in
                String(format: "%@:%.5f:%.5f", mp.id.uuidString, mp.coordinate.lat, mp.coordinate.lon)
            }
            .joined(separator: "|")
        let veh = missionLiveVehicleMarkers
            .map { m in
                let heading = m.headingDeg ?? 0
                return String(format: "%@:%.5f:%.5f:%.2f", m.id, m.lat, m.lon, heading)
            }
            .joined(separator: "|")
        return pts + "§" + veh
    }

    /// Fits the MC-R live overview map to home, visible paths, runtime map points, and **current** vehicle markers (``mapModel/focusMapFitBounds`` — not ``recenterNonce`` / default world zoom).
    private func fitLiveOverviewMapToVisibleMissionContent() {
        guard let mission = resolvedMission else { return }
        let pathPayload = liveOverviewMapTaskPathPayload(from: mission)
        let vehicleLL = missionLiveVehicleMarkers.map { ($0.lat, $0.lon) }
        let pts = MissionControlLiveMapFitCoordinates.liveOverviewMissionContentPoints(
            homeCoordinate: mission.routeMacro.home?.coord,
            taskPathCoordinates: pathPayload.coords,
            runtimeMissionPoints: run.runtimeMissionPoints,
            focusedTaskID: liveOverviewMapFocusedTaskID,
            vehicleMarkerLatLon: vehicleLL
        )
        guard !pts.isEmpty else { return }
        mapModel.focusMapFitBounds(points: pts)
    }

    /// Fits the MCS roster staging map to home, all task paths, template/runtime map points, and **current** roster vehicle markers (same bbox inputs as ``fitLiveOverviewMapToVisibleMissionContent()`` — not ``recenterNonce`` / default world zoom).
    private func fitSetupStagingMapToVisibleMissionContent() {
        guard let mission = resolvedMission else { return }
        let taskPathCoordinates = mission.routeMacro.tasks.map { $0.waypoints.map(\.coord) }
        let vehicleLL = setupStagingMapVehicleMarkers.map { ($0.lat, $0.lon) }
        let pts = MissionControlLiveMapFitCoordinates.liveOverviewMissionContentPoints(
            homeCoordinate: mission.routeMacro.home?.coord,
            taskPathCoordinates: taskPathCoordinates,
            runtimeMissionPoints: setupStagingMissionPointRowsForMap,
            focusedTaskID: nil,
            vehicleMarkerLatLon: vehicleLL
        )
        guard !pts.isEmpty else { return }
        mapModel.focusMapFitBounds(points: pts)
    }

    /// Full route + marker rebuild when mission topology, roster bindings, or map-point selection metadata changes.
    private func pushLiveOverviewMapModelFromMission() {
        if let mission = resolvedMission {
            let pathPayload = liveOverviewMapTaskPathPayload(from: mission)
            mapModel.routeGeometry = GuardianRouteMapGeometry(
                home: mission.routeMacro.home,
                allTasksCoords: pathPayload.coords,
                taskPathIDs: pathPayload.ids,
                selectedTaskWaypoints: [],
                selectedWaypointIndex: nil,
                headingPreview: nil,
                cameraPreview: nil,
                preserveView: true,
                isEditingTask: false,
                missionPointMarkers: missionLiveMissionPointMapMarkers,
                missionPointPlacementArmed: false,
                mcsReservePoolHomePlacementArmed: false
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

    /// Marker-only refresh for hub-driven movement (vehicles + dragged map points) without resetting polylines.
    private func pushLiveOverviewMapMarkersOnly() {
        guard resolvedMission != nil else {
            pushLiveOverviewMapModelFromMission()
            return
        }
        guard let mission = resolvedMission else { return }
        let expectedIDs = liveOverviewMapTaskPathPayload(from: mission).ids
        if mapModel.routeGeometry.taskPathIDs != expectedIDs {
            pushLiveOverviewMapModelFromMission()
            return
        }
        var geo = mapModel.routeGeometry
        geo.missionPointMarkers = missionLiveMissionPointMapMarkers
        mapModel.routeGeometry = geo
        mapModel.vehicleMarkers = missionLiveVehicleMarkers
        if let followID = mapModel.followedVehicleMarkerID,
           !missionLiveVehicleMarkers.contains(where: { $0.id == followID }) {
            mapModel.followedVehicleMarkerID = nil
        }
    }

    private var missionLiveMissionPointMapMarkers: [GuardianMissionPointMapMarker] {
        missionControlGuardianMissionPointMarkers(
            from: MissionPoint.filteredForMissionControlLiveMap(
                run.runtimeMissionPoints,
                focusedTaskID: liveOverviewMapFocusedTaskID
            ),
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
        let roster = missionLiveMapRosterAssignments.compactMap { assignment -> MapVehicleMarker? in
            guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
                  let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                  let lat = hub.latitudeDeg,
                  let lon = hub.longitudeDeg,
                  assignment.attachedFleetVehicleToken != nil
            else { return nil }
            let colorHex = fleetLink.mapColorHex(forVehicleID: vehicleID)
            let heading = hub.headingDeg ?? hub.yawDeg
            let accessibilityTitle: String? = {
                guard let pick = liveReserveSwapPick,
                      let mission = resolvedMission,
                      let tid = assignment.taskId ?? focusedLiveTaskID,
                      tid == pick.taskID
                else { return nil }
                let taskName = mission.routeMacro.tasks.first { $0.id == tid }?.name ?? "Task"
                if assignment.id == pick.vacancyAssignmentID {
                    return MissionRunReserveSwapAccessibilityCopy.rosterVacancyDuringReserveSwapPick(
                        taskName: taskName,
                        slotName: assignment.slotName
                    )
                }
                if let device = mission.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId }),
                   device.slot == .reserve {
                    return MissionRunReserveSwapAccessibilityCopy.rosterBenchReserveDuringReserveSwapPick(
                        taskName: taskName,
                        slotName: assignment.slotName
                    )
                }
                return nil
            }()
            return MapVehicleMarker(
                id: assignment.id.uuidString,
                lat: lat,
                lon: lon,
                label: assignment.slotName,
                colorHex: colorHex,
                imageDataURL: missionControlRosterMapMarkerImageDataURL(for: assignment),
                selected: focusedLiveAssignmentID == assignment.id,
                draggable: false,
                headingDeg: heading,
                accessibilityTitle: accessibilityTitle
            )
        }
        return roster + missionLiveFloatingReservePoolVehicleMarkers
    }

    /// MC-R live map: hub positions for **floating reserve** aircraft (fleet token + live telemetry only).
    private var missionLiveFloatingReservePoolVehicleMarkers: [MapVehicleMarker] {
        guard let mission = resolvedMission else { return [] }
        let taskIDs: [UUID] = {
            if let f = liveOverviewMapFocusedTaskID { return [f] }
            return mission.routeMacro.tasks.filter(\.enabled).map(\.id)
        }()
        var out: [MapVehicleMarker] = []
        for tid in taskIDs {
            let pool = run.reservePool(forTaskID: tid)
            for slot in pool.entries {
                guard slot.hasFleetOrLegacyBinding,
                      let rawTok = slot.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !rawTok.isEmpty
                else { continue }
                let syn = syntheticMissionRunAssignment(from: slot)
                guard let vehicleID = resolvedFleetStreamVehicleID(assignment: syn, fleetLink: fleetLink, sitl: sitl),
                      let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                      let lat = hub.latitudeDeg,
                      let lon = hub.longitudeDeg
                else { continue }
                let colorHex = fleetLink.mapColorHex(forVehicleID: vehicleID)
                let heading = hub.headingDeg ?? hub.yawDeg
                let taskName = mission.routeMacro.tasks.first { $0.id == tid }?.name ?? "Task"
                let swapPickOnTask = liveReserveSwapPick?.taskID == tid
                let markerEligible: Bool = {
                    guard let pick = liveReserveSwapPick else { return false }
                    return pick.taskID == tid && mcrLiveReserveSwapEligiblePoolSlotIDs.contains(slot.id)
                }()
                let browsingBerth = liveReservePoolBrowseTaskID == tid && focusedLiveReservePoolBerth?.slotID == slot.id
                let poolA11y = MissionRunReserveSwapAccessibilityCopy.floatingPoolMapMarker(
                    taskName: taskName,
                    berthLabel: slot.label,
                    swapPickActiveOnTask: swapPickOnTask,
                    markerIsEligiblePickTarget: markerEligible,
                    browsingThisBerthOnTask: browsingBerth
                )
                out.append(
                    MapVehicleMarker(
                        id: MissionControlReservePoolMapMarkerID.encode(taskID: tid, slotID: slot.id),
                        lat: lat,
                        lon: lon,
                        label: "\(slot.label) · pool",
                        colorHex: colorHex,
                        imageDataURL: missionControlRosterMapMarkerImageDataURL(for: syn),
                        selected: (liveReserveSwapPick?.taskID == tid && mcrLiveReserveSwapEligiblePoolSlotIDs.contains(slot.id))
                            || (liveReservePoolBrowseTaskID == tid && focusedLiveReservePoolBerth?.slotID == slot.id),
                        draggable: false,
                        selectionAttentionPulse: (liveReserveSwapPick?.taskID == tid && mcrLiveReserveSwapEligiblePoolSlotIDs.contains(slot.id))
                            || (liveReservePoolBrowseTaskID == tid && focusedLiveReservePoolBerth?.slotID == slot.id),
                        headingDeg: heading,
                        accessibilityTitle: poolA11y
                    )
                )
            }
        }
        return out
    }

    private var missionLiveVehicleStatusRow: some View {
        Group {
            if let pick = liveReserveSwapPick,
               run.status == .running || run.status == .paused || run.status == .recovery
            {
                let poolSlots = mcrLiveReserveSwapEligiblePoolSlotsOrdered
                if poolSlots.isEmpty {
                    let emptyCopy = run.floatingReservePoolPickStripEmptyOperatorCopy(
                        vacancyAssignmentID: pick.vacancyAssignmentID,
                        taskID: pick.taskID
                    ) ?? ("No eligible reserves", "Add or bind a class-compatible floating reserve on this task.")
                    MissionLiveVehicleHealthCard(
                        slotTitle: emptyCopy.title,
                        rosterSubtitle: emptyCopy.subtitle,
                        bracketedVehicleShortID: "—",
                        vehicleID: nil,
                        simulationImageBasenames: nil,
                        vehicleClassForBundledDeviceArt: .unknown,
                        vehicleModel: fleetLink.primaryVehicleOperationalModel(),
                        slotHeight: liveConsoleRosterCardHeight,
                        onTap: nil,
                        accessibilitySummary: MissionRunReserveSwapAccessibilityCopy.reserveSwapPickEmptyStrip(
                            title: emptyCopy.title,
                            subtitle: emptyCopy.subtitle
                        )
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let slotsPerColumn = liveConsoleRosterGridRows
                    let columnCount = max(1, (poolSlots.count + slotsPerColumn - 1) / slotsPerColumn)
                    let effectiveRows = MissionRunPrepLayout.liveConsoleColumnMajorGridRowCount(
                        itemCount: poolSlots.count,
                        slotsPerColumn: slotsPerColumn
                    )
                    Grid(
                        alignment: .topLeading,
                        horizontalSpacing: GuardianSpacing.denseGutter,
                        verticalSpacing: GuardianSpacing.denseGutter
                    ) {
                        ForEach(0 ..< effectiveRows, id: \.self) { row in
                            GridRow {
                                ForEach(0 ..< columnCount, id: \.self) { col in
                                    let index = col * slotsPerColumn + row
                                    Group {
                                        if index < poolSlots.count {
                                            missionLiveReservePoolSwapPickHealthCard(
                                                slot: poolSlots[index],
                                                pick: pick
                                            )
                                        } else {
                                            Color.clear
                                                .frame(maxWidth: .infinity, minHeight: liveConsoleRosterCardHeight, maxHeight: liveConsoleRosterCardHeight)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else if let browseTid = liveReservePoolBrowseTaskID,
                      run.status == .running || run.status == .paused || run.status == .recovery
            {
                let poolSlots = run.reservePool(forTaskID: browseTid).entries
                if poolSlots.isEmpty {
                    MissionLiveVehicleHealthCard(
                        slotTitle: "No reserve berths",
                        rosterSubtitle: "Add floating reserve slots in Mission Control setup.",
                        bracketedVehicleShortID: "—",
                        vehicleID: nil,
                        simulationImageBasenames: nil,
                        vehicleClassForBundledDeviceArt: .unknown,
                        vehicleModel: fleetLink.primaryVehicleOperationalModel(),
                        slotHeight: liveConsoleRosterCardHeight,
                        onTap: nil,
                        accessibilitySummary: MissionRunReserveSwapAccessibilityCopy.floatingPoolBrowseEmptyStrip()
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let slotsPerColumn = liveConsoleRosterGridRows
                    let columnCount = max(1, (poolSlots.count + slotsPerColumn - 1) / slotsPerColumn)
                    let effectiveRows = MissionRunPrepLayout.liveConsoleColumnMajorGridRowCount(
                        itemCount: poolSlots.count,
                        slotsPerColumn: slotsPerColumn
                    )
                    Grid(
                        alignment: .topLeading,
                        horizontalSpacing: GuardianSpacing.denseGutter,
                        verticalSpacing: GuardianSpacing.denseGutter
                    ) {
                        ForEach(0 ..< effectiveRows, id: \.self) { row in
                            GridRow {
                                ForEach(0 ..< columnCount, id: \.self) { col in
                                    let index = col * slotsPerColumn + row
                                    Group {
                                        if index < poolSlots.count {
                                            missionLiveReservePoolBrowseHealthCard(
                                                slot: poolSlots[index],
                                                taskID: browseTid
                                            )
                                        } else {
                                            Color.clear
                                                .frame(maxWidth: .infinity, minHeight: liveConsoleRosterCardHeight, maxHeight: liveConsoleRosterCardHeight)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                missionLiveVehicleStatusRowRosterGrid
            }
        }
    }

    private var missionLiveVehicleStatusRowRosterGrid: some View {
        let assignments = filteredLiveRosterAssignments
        return Group {
            if assignments.isEmpty {
                MissionLiveVehicleHealthCard(
                    slotTitle: "—",
                    rosterSubtitle: "—",
                    bracketedVehicleShortID: "—",
                    vehicleID: nil,
                    simulationImageBasenames: nil,
                    vehicleClassForBundledDeviceArt: .unknown,
                    vehicleModel: fleetLink.primaryVehicleOperationalModel(),
                    slotHeight: liveConsoleRosterCardHeight,
                    onTap: nil
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let slotsPerColumn = liveConsoleRosterGridRows
                let columnCount = max(1, (assignments.count + slotsPerColumn - 1) / slotsPerColumn)
                let effectiveRows = MissionRunPrepLayout.liveConsoleColumnMajorGridRowCount(
                    itemCount: assignments.count,
                    slotsPerColumn: slotsPerColumn
                )
                Grid(
                    alignment: .topLeading,
                    horizontalSpacing: GuardianSpacing.denseGutter,
                    verticalSpacing: GuardianSpacing.denseGutter
                ) {
                    ForEach(0 ..< effectiveRows, id: \.self) { row in
                        GridRow {
                            ForEach(0 ..< columnCount, id: \.self) { col in
                                let index = col * slotsPerColumn + row
                                Group {
                                    if index < assignments.count {
                                        missionLiveVehicleHealthCard(for: assignments[index])
                                    } else {
                                        Color.clear
                                            .frame(maxWidth: .infinity, minHeight: liveConsoleRosterCardHeight, maxHeight: liveConsoleRosterCardHeight)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func missionLiveVehicleHealthCard(for assignment: MissionRunAssignment) -> some View {
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
        let shortRaw = assignmentFleetDisplayShortID(assignment: assignment, rosterDevice: device)
        let bracketed = shortRaw.isEmpty ? "—" : "[\(shortRaw)]"
        let missionLiveShowsSlotBadge = run.status == .running || run.status == .paused || run.status == .recovery
        let mergedSlot = MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: assignment.effectiveSlotLifecycleLanes)
        let slotAttention: (GuardianFeedbackSeverity, String)? = missionLiveShowsSlotBadge
            ? mergedSlot.missionControlRosterBadgeSeverity.map { ($0, mergedSlot.displayTitle) }
            : nil
        let reserveSwapStripAccessibilitySummary: String? = {
            guard let pick = liveReserveSwapPick,
                  let mission = resolvedMission,
                  let tid = assignment.taskId ?? focusedLiveTaskID,
                  tid == pick.taskID
            else { return nil }
            let taskName = mission.routeMacro.tasks.first { $0.id == tid }?.name ?? "Task"
            if assignment.id == pick.vacancyAssignmentID {
                return MissionRunReserveSwapAccessibilityCopy.rosterVacancyDuringReserveSwapPick(
                    taskName: taskName,
                    slotName: assignment.slotName
                )
            }
            if let device = mission.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId }),
               device.slot == .reserve {
                return MissionRunReserveSwapAccessibilityCopy.rosterBenchReserveDuringReserveSwapPick(
                    taskName: taskName,
                    slotName: assignment.slotName
                )
            }
            return nil
        }()
        MissionLiveVehicleHealthCard(
            slotTitle: assignment.slotName,
            rosterSubtitle: rosterRoleSubtitle(device),
            bracketedVehicleShortID: bracketed,
            vehicleID: vehicleID,
            simulationImageBasenames: simulationImageBasenamesForAssignment(assignment, sitl: sitl),
            vehicleClassForBundledDeviceArt: deviceArtVehicleClass,
            vehicleModel: vehicleID.map { fleetLink.vehicleOperationalModel(forVehicleID: $0) }
                ?? FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil),
            slotHeight: liveConsoleRosterCardHeight,
            onTap: {
                focusLiveAssignment(assignment.id)
            },
            slotAttention: slotAttention,
            accessibilitySummary: reserveSwapStripAccessibilitySummary
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func missionLiveReservePoolBrowseHealthCard(slot: MissionRunReservePoolSlot, taskID: UUID) -> some View {
        let syn = syntheticMissionRunAssignment(from: slot)
        let vehicleID = telemetryVehicleID(for: syn)
        let deviceArtVehicleClass: FleetVehicleType = {
            if let vid = vehicleID, let model = fleetLink.vehicleModel(forVehicleID: vid) {
                return model.data.vehicleType
            }
            return .unknown
        }()
        let shortRaw = assignmentFleetDisplayShortID(assignment: syn, rosterDevice: nil)
        let bracketed = shortRaw.isEmpty ? "—" : "[\(shortRaw)]"
        let taskName = resolvedMission?.routeMacro.tasks.first { $0.id == taskID }?.name ?? "Task"
        MissionLiveVehicleHealthCard(
            slotTitle: slot.label,
            rosterSubtitle: "Floating reserve",
            bracketedVehicleShortID: bracketed,
            vehicleID: vehicleID,
            simulationImageBasenames: simulationImageBasenamesForAssignment(syn, sitl: sitl),
            vehicleClassForBundledDeviceArt: deviceArtVehicleClass,
            vehicleModel: vehicleID.map { fleetLink.vehicleOperationalModel(forVehicleID: $0) }
                ?? FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil),
            slotHeight: liveConsoleRosterCardHeight,
            onTap: {
                focusLiveReservePoolBerth(LiveReservePoolBerthFocus(taskID: taskID, slotID: slot.id))
            },
            slotAttention: nil,
            reservePoolPickerChrome: true,
            tapHelp: "Open floating reserve berth",
            accessibilitySummary: MissionRunReserveSwapAccessibilityCopy.floatingPoolStripBrowseCandidate(
                taskName: taskName,
                berthLabel: slot.label,
                aircraftShortID: bracketed
            )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func missionLiveReservePoolSwapPickHealthCard(slot: MissionRunReservePoolSlot, pick: LiveReserveSwapPickContext) -> some View {
        let syn = syntheticMissionRunAssignment(from: slot)
        let vehicleID = telemetryVehicleID(for: syn)
        let deviceArtVehicleClass: FleetVehicleType = {
            if let vid = vehicleID, let model = fleetLink.vehicleModel(forVehicleID: vid) {
                return model.data.vehicleType
            }
            return .unknown
        }()
        let shortRaw = assignmentFleetDisplayShortID(assignment: syn, rosterDevice: nil)
        let bracketed = shortRaw.isEmpty ? "—" : "[\(shortRaw)]"
        let taskName = resolvedMission?.routeMacro.tasks.first { $0.id == pick.taskID }?.name ?? "Task"
        MissionLiveVehicleHealthCard(
            slotTitle: slot.label,
            rosterSubtitle: "Floating reserve",
            bracketedVehicleShortID: bracketed,
            vehicleID: vehicleID,
            simulationImageBasenames: simulationImageBasenamesForAssignment(syn, sitl: sitl),
            vehicleClassForBundledDeviceArt: deviceArtVehicleClass,
            vehicleModel: vehicleID.map { fleetLink.vehicleOperationalModel(forVehicleID: $0) }
                ?? FleetVehicleOperationalModel(hub: nil, lifecycleStatus: nil),
            slotHeight: liveConsoleRosterCardHeight,
            onTap: {
                guard !mcrReserveSwapOperationInFlight() else {
                    toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapChecksRunning, style: .info)
                    return
                }
                guard !mcrReservePoolSlotMutationLocked(taskID: pick.taskID, slotID: slot.id) else {
                    toastCenter.show(MissionRunReserveSwapOperatorCopy.toastBerthBusyWaitArmPreflightBeforeSwap, style: .warning)
                    return
                }
                presentedRunConfirm = .reserveSwapPoolPick(
                    vacancyAssignmentID: pick.vacancyAssignmentID,
                    taskID: pick.taskID,
                    poolSlotID: slot.id
                )
            },
            slotAttention: nil,
            reservePoolPickerChrome: true,
            accessibilitySummary: MissionRunReserveSwapAccessibilityCopy.floatingPoolStripSwapPickCandidate(
                taskName: taskName,
                berthLabel: slot.label,
                aircraftShortID: bracketed
            ),
            accessibilityHint: "Opens a confirmation; arm checks run before the roster changes."
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func beginMcrReserveSwapPick(for assignment: MissionRunAssignment) {
        guard let mission = resolvedMission else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastMissionTemplateUnavailable, style: .warning)
            return
        }
        let tid = assignment.taskId ?? focusedLiveTaskID
        guard let tid else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastRosterSlotNotBoundToTask, style: .warning)
            return
        }
        guard run.assignmentsBoundToMissionTask(taskID: tid).contains(where: { $0.id == assignment.id }) else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastSlotNotOnTaskRoster, style: .warning)
            return
        }
        let aff = floatingReserveSwapAffordance(assignment: assignment, mission: mission, taskID: tid)
        guard aff.enabled else {
            toastCenter.show(aff.blockedReason.isEmpty ? MissionRunReserveSwapOperatorCopy.toastNoFloatingReserveForSlotFallback : aff.blockedReason, style: .warning)
            return
        }
        guard !mcrReserveSwapOperationInFlight() else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapStillRunningWaitHub, style: .info)
            return
        }
        bottomPromptCenter.dismiss()
        liveReservePoolBrowseTaskID = nil
        focusedLiveReservePoolBerth = nil
        liveReserveSwapPick = LiveReserveSwapPickContext(vacancyAssignmentID: assignment.id, taskID: tid)
    }

    private func cancelMcrReserveSwapPick() {
        if mcrReserveSwapOperationInFlight() {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapInProgressWaitHub, style: .info)
            return
        }
        bottomPromptCenter.dismiss()
        liveReserveSwapPick = nil
        presentedRunConfirm = nil
    }

    /// Body copy for the MC-R **bottom prompt** when reserve swap-in arm probe fails (not ``GuardianConfirm``).
    private func reserveSwapPreflightFailurePromptMessage(
        detail: String,
        remediation: PreflightFailureRemediationAdvice?
    ) -> String {
        var s = "Reserve swap-in checks did not pass.\n\n" + MissionRunReserveSwapOperatorCopy.reserveSwapPreflightFailurePrologue + "\n\n" + detail
        if let r = remediation {
            s += "\n\n" + r.summary
            if !r.steps.isEmpty {
                s += "\n" + r.steps.map { "• \($0)" }.joined(separator: "\n")
            }
        }
        s += "\n\nUse Cancel to leave the swap, Switch to pick another pool row, or Inspect to open Vehicle Inspector. Tap the same pool row again to retry after fixing the aircraft."
        return s
    }

    private func presentReserveSwapPreflightFailureBottomPrompt(
        taskID: UUID,
        poolSlotID: UUID,
        detail: String,
        remediation: PreflightFailureRemediationAdvice?
    ) {
        let message = reserveSwapPreflightFailurePromptMessage(detail: detail, remediation: remediation)
        bottomPromptCenter.presentTripleChoice(
            message,
            style: .warning,
            cancelTitle: "Cancel",
            switchTitle: "Switch",
            inspectTitle: "Inspect",
            onCancel: {
                cancelMcrReserveSwapPick()
            },
            onSwitchPoolRow: {},
            onOpenVehicleInspector: {
                guard let slot = run.reservePool(forTaskID: taskID).entries.first(where: { $0.id == poolSlotID }) else {
                    return
                }
                let syn = MissionRunAssignment.syntheticForReservePool(slot: slot)
                presentRosterCalibrationSheet(for: syn)
            }
        )
    }

    @MainActor
    private func runMcrFloatingReservePoolSwapAfterReservePreflight(
        vacancyAssignmentID: UUID,
        taskID: UUID,
        poolSlotID: UUID,
        triggerSource: String = "operator.missionControlRunning.reserveSwap"
    ) async {
        guard !mcrReserveSwapOperationInFlight() else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapAlreadyRunning, style: .info)
            return
        }
        guard MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: run.sessionPhase) else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapBlockedSessionPhase, style: .warning)
            return
        }
        guard let slot = run.reservePool(forTaskID: taskID).entries.first(where: { $0.id == poolSlotID }) else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastPoolBerthNoLongerOnTask, style: .warning)
            return
        }
        let synthetic = MissionRunAssignment.syntheticForReservePool(slot: slot)
        guard let vehicleID = resolvedFleetStreamVehicleID(assignment: synthetic, fleetLink: fleetLink, sitl: sitl) else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastNoLiveReserveLink, style: .warning)
            return
        }
        guard !MissionControlReservePoolMutationGate.reservePoolSlotMutationLocked(
            swapLock: nil,
            berthPreflightTaskID: reservePoolBerthPreflightFocus?.taskID,
            berthPreflightSlotID: reservePoolBerthPreflightFocus?.slotID,
            taskID: taskID,
            slotID: poolSlotID
        ) else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastBerthArmPreflightRunningBeforeSwap, style: .warning)
            return
        }
        let poolCorrelation = MissionRunReserveRecipeRunnerCorrelation.floatingPoolReserve(
            missionRunID: run.id,
            missionTaskID: taskID,
            vacancyAssignmentID: vacancyAssignmentID,
            poolSlot: slot,
            vehicleID: vehicleID
        )
        mcrFloatingReserveSwapLock = MissionControlReservePoolMutationGate.SwapOperationLock(
            vacancyAssignmentID: vacancyAssignmentID,
            taskID: taskID,
            poolSlotID: poolSlotID
        )
        defer { mcrFloatingReserveSwapLock = nil }
        run.appendReserveSwapPipelinePhaseLog(
            phase: MissionRunReserveSwapPipelinePhase.pickReserve,
            passed: true,
            correlation: poolCorrelation,
            detail: "Floating pool berth confirmed for swap-in."
        )
        let probe = await controlStore.runSingleVehiclePreflightProbe(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl,
            leaveArmed: true,
            allowDuringLiveMission: true,
            preflightAuditSource: "missionControl.preflightProbe.reserveSwapIn",
            telemetryGateMode: .reserveSwapIn
        )
        guard probe.passed else {
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.swapTimeChecks,
                passed: false,
                correlation: poolCorrelation,
                detail: probe.detail
            )
            presentReserveSwapPreflightFailureBottomPrompt(
                taskID: taskID,
                poolSlotID: poolSlotID,
                detail: probe.detail,
                remediation: probe.remediationAdvice
            )
            return
        }
        run.appendReserveSwapPipelinePhaseLog(
            phase: MissionRunReserveSwapPipelinePhase.swapTimeChecks,
            passed: true,
            correlation: poolCorrelation,
            detail: "Telemetry gates and arm probe passed."
        )

        let outcome = run.swapRosterAssignmentWithFloatingReservePoolSlot(
            assignmentID: vacancyAssignmentID,
            taskID: taskID,
            poolSlotID: poolSlotID,
            triggerSource: triggerSource
        )
        liveReserveSwapPick = nil
        switch outcome {
        case .success:
            if let mission = resolvedMission {
                let fleet = buildMissionPickableVehicles(fleetLink: fleetLink, sitl: sitl)
                controlStore.recompileMissionControlPlanAfterFloatingReserveSwap(
                    run: run,
                    mission: mission,
                    fleetVehicles: fleet
                )
                run.beginPostCommitReserveSwapHandoffPipeline(
                    correlation: poolCorrelation,
                    triggerSource: triggerSource
                )
            }
            onUpdate(run)
            focusLiveAssignment(nil)
            toastCenter.show(
                triggerSource.contains("autoExecutor")
                    ? MissionRunReserveSwapOperatorCopy.toastFloatingReserveAutoSwappedOntoRoster
                    : MissionRunReserveSwapOperatorCopy.toastFloatingReserveSwappedOntoRoster,
                style: .success
            )
        case .noEligiblePoolSlots:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: poolCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastNoEligibleFloatingReserveForTask, style: .warning)
        case .assignmentNotFound:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: poolCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastRosterSlotNotFoundOnRun, style: .error)
        case .assignmentNotBoundToTask:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: poolCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastRosterSlotNotOnSelectedTask, style: .warning)
        case .identicalFleetBindingNoOp:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: poolCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastEveryPoolAircraftMatchesRosterBinding, style: .info)
        case .noClassCompatiblePoolSlots:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: poolCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastNoPoolClassMatchForRosterSlot, style: .warning)
        case .returnRejected(let r):
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: poolCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapReturnRejected(r), style: .error)
        case .poolClearFailed:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: poolCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapPoolClearFailed, style: .error)
        case .pickRejectedDuplicateOrStaleBinding:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: poolCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapPickRejectedStale, style: .warning)
        case .poolSlotNotEligible:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: poolCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastPoolBerthNotAvailableForRosterSlot, style: .warning)
        case .blockedBySessionPhase:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: poolCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.floatingPoolSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapBlockedSessionPhase, style: .warning)
        }
    }

    /// MC-R **autonomous** fixed template reserve swap-in: arm probe on the **reserve** row, then ``MissionRunEnvironment/swapRosterVacancyWithFixedTemplateReserveAssignment``.
    @MainActor
    private func runMcrFixedTemplateReserveSwapAfterReservePreflight(
        vacancyAssignmentID: UUID,
        reserveAssignment: MissionRunAssignment,
        taskID: UUID
    ) async {
        guard !mcrReserveSwapOperationInFlight() else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapAlreadyRunning, style: .info)
            return
        }
        guard MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: run.sessionPhase) else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapBlockedSessionPhase, style: .warning)
            return
        }
        guard let vehicleID = resolvedFleetStreamVehicleID(assignment: reserveAssignment, fleetLink: fleetLink, sitl: sitl) else {
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastNoLiveReserveAutoSwapSkipped, style: .warning)
            return
        }
        let fixedCorrelation = MissionRunReserveRecipeRunnerCorrelation.fixedRosterReserve(
            missionRunID: run.id,
            missionTaskID: taskID,
            vacancyAssignmentID: vacancyAssignmentID,
            reserveAssignment: reserveAssignment,
            vehicleID: vehicleID
        )
        mcrFloatingReserveSwapLock = MissionControlReservePoolMutationGate.SwapOperationLock(
            vacancyAssignmentID: vacancyAssignmentID,
            taskID: taskID,
            poolSlotID: nil
        )
        defer { mcrFloatingReserveSwapLock = nil }
        run.appendReserveSwapPipelinePhaseLog(
            phase: MissionRunReserveSwapPipelinePhase.pickReserve,
            passed: true,
            correlation: fixedCorrelation,
            detail: "Fixed template reserve row confirmed for autonomous swap-in."
        )
        let probe = await controlStore.runSingleVehiclePreflightProbe(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl,
            leaveArmed: true,
            allowDuringLiveMission: true,
            preflightAuditSource: "missionControl.preflightProbe.reserveSwapIn",
            telemetryGateMode: .reserveSwapIn
        )
        guard probe.passed else {
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.swapTimeChecks,
                passed: false,
                correlation: fixedCorrelation,
                detail: probe.detail
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveAutoSwapSkippedPreflight, style: .info)
            return
        }
        run.appendReserveSwapPipelinePhaseLog(
            phase: MissionRunReserveSwapPipelinePhase.swapTimeChecks,
            passed: true,
            correlation: fixedCorrelation,
            detail: "Telemetry gates and arm probe passed."
        )

        let outcome = run.swapRosterVacancyWithFixedTemplateReserveAssignment(
            vacancyAssignmentID: vacancyAssignmentID,
            reserveAssignmentID: reserveAssignment.id,
            taskID: taskID,
            triggerSource: "operator.missionControlRunning.reserveSwap.autoExecutor"
        )
        liveReserveSwapPick = nil
        switch outcome {
        case .success:
            if let mission = resolvedMission {
                let fleet = buildMissionPickableVehicles(fleetLink: fleetLink, sitl: sitl)
                controlStore.recompileMissionControlPlanAfterFloatingReserveSwap(
                    run: run,
                    mission: mission,
                    fleetVehicles: fleet,
                    planCompileSource: MissionRunReserveSwapPlanRecompilationPolicy.fixedRosterReserveSwapPlanCompileSource
                )
                run.beginPostCommitReserveSwapHandoffPipeline(
                    correlation: fixedCorrelation,
                    triggerSource: "operator.missionControlRunning.reserveSwap.autoExecutor"
                )
            }
            onUpdate(run)
            focusLiveAssignment(nil)
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastFloatingReserveAutoSwappedOntoRoster, style: .success)
        case .assignmentNotFound:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: fixedCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.fixedRosterSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastRosterSlotNotFoundOnRun, style: .error)
        case .assignmentNotBoundToTask:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: fixedCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.fixedRosterSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastRosterSlotNotOnSelectedTask, style: .warning)
        case .reserveNotEligibleForVacancy:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: fixedCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.fixedRosterSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastFixedReserveNotAvailableForRosterSlot, style: .warning)
        case .identicalFleetBindingNoOp:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: fixedCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.fixedRosterSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastEveryReserveMatchesRosterBinding, style: .info)
        case .pickRejectedDuplicateOrStaleBinding:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: fixedCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.fixedRosterSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveAutoSwapAbortedPickRejected, style: .warning)
        case .blockedBySessionPhase:
            run.appendReserveSwapPipelinePhaseLog(
                phase: MissionRunReserveSwapPipelinePhase.rosterCommit,
                passed: false,
                correlation: fixedCorrelation,
                detail: MissionRunReserveSwapOperatorCopy.fixedRosterSwapRosterCommitFailureDetail(outcome)
            )
            toastCenter.show(MissionRunReserveSwapOperatorCopy.toastReserveSwapBlockedSessionPhase, style: .warning)
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

                    GuardianNeutralBorderedButton(
                        systemImage: "doc.on.doc",
                        help: "Copy log",
                        action: { copyLiveLogToPasteboard() }
                    )
                    .disabled(liveLogEventsFiltered.isEmpty)

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
                                        MissionRunLiveLogEventRow(
                                            event: event,
                                            run: run,
                                            mission: resolvedMission,
                                            fleetLink: fleetLink,
                                            sitl: sitl
                                        )
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

    private var operatorMissionRunIsolateLiveMapBinding: Binding<Bool> {
        Binding(
            get: { run.operatorDisplaySettings.isolateLiveMapToSelectedTask },
            set: { newValue in
                var s = run.operatorDisplaySettings
                s.isolateLiveMapToSelectedTask = newValue
                run.operatorDisplaySettings = s
                onUpdate(run)
            }
        )
    }

    private var operatorMissionRunResetSimOnCompleteBinding: Binding<Bool> {
        Binding(
            get: { run.operatorDisplaySettings.resetSimToStartPoseOnSuccessfulComplete },
            set: { newValue in
                var s = run.operatorDisplaySettings
                s.resetSimToStartPoseOnSuccessfulComplete = newValue
                run.operatorDisplaySettings = s
                onUpdate(run)
            }
        )
    }

    private var operatorMissionRunSimBatteryDrainBinding: Binding<SimBatteryDrainRate> {
        Binding(
            get: { run.operatorDisplaySettings.simBatteryDrainRateDuringRun },
            set: { newValue in
                var s = run.operatorDisplaySettings
                s.simBatteryDrainRateDuringRun = newValue
                run.operatorDisplaySettings = s
                onUpdate(run)
            }
        )
    }

    /// Per-run Mission Run settings (cloned from app defaults at run create) — MCS Setup → **Settings** card and MC‑R **Settings** drawer.
    private var mcSetupMissionRunAppSettingsMirrorFormBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            mcSetupSettingsRow(
                title: "Isolate map to selected task",
                description:
                    "Hide all non-task mission data from the map when a task is selected."
            ) {
                Toggle(
                    "",
                    isOn: operatorMissionRunIsolateLiveMapBinding
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(minWidth: 44, alignment: .trailing)
            }
            mcSetupRowDivider
            mcSetupSettingsRow(
                title: "SIM battery drain while run executes",
                description:
                    "Slow, normal, fast, or none for simulated vehicles bound to this run while it is executing. None leaves pack model static."
            ) {
                Picker("SIM battery drain while run executes", selection: operatorMissionRunSimBatteryDrainBinding) {
                    ForEach(SimBatteryDrainRate.missionRunPickerCases, id: \.self) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 160, alignment: .trailing)
                .accessibilityLabel("SIM battery drain while run executes")
            }
            mcSetupRowDivider
            mcSetupSettingsRow(
                title: "Reset SIMs when run completes",
                description:
                    "Reset all SIM vehicles to their default start pose when a run completes."
            ) {
                Toggle(
                    "",
                    isOn: operatorMissionRunResetSimOnCompleteBinding
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(minWidth: 44, alignment: .trailing)
            }
        }
    }

    /// MCS **Setup → Settings** tab: same labels as **App Settings → Missions → Mission Run**, bound to **this run’s** ``MissionRunEnvironment/operatorDisplaySettings`` (see ``SettingsView/missionsPane`` for app defaults).
    private var setupSettingsTabContent: some View {
        GuardianCard(
            configuration: mcSetupGroupCardConfiguration,
            header: { mcSetupGroupCardTitle("Settings") },
            body: {
                mcSetupMissionRunAppSettingsMirrorFormBody
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
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

            if rostersSidebarListTab == .tasks, fleetLink.isSimulateEnabled {
                GuardianThemedButton(
                    title: "SIM cleanup",
                    accent: .primary,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: { requestManualMissionRunSimCleanup() }
                )
                .disabled(run.isMissionRunSimCleanupPassRunning)
                .help(
                    "Park every in-scope Guardian SIM for this run, clear uploaded missions on those vehicles, optionally restore captured start poses when \"Reset SIMs when run completes\" is on for this run, then charge SIM batteries to full. Same steps as after Mark Completed."
                )
                .guardianPointerOnHover()
            }

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
        let indices = run.assignments.indices.filter { run.missionControlAssignmentBelongsToTask(run.assignments[$0], task: task, mission: mission) }
        let filled = indices.filter { run.assignments[$0].hasFleetOrLegacyAssignment }.count
        let emptyRosterSlotCount = indices.count - filled
        let rows = run.missionControlTaskRosterOrderedSlotAssignmentIndices(task: task, mission: mission)
        let eligiblePoolHomeReapply = MCSReservePoolHomeStagingMapEligibility.eligibleSitlReservePoolSlotCount(
            entries: run.reservePool(forTaskID: task.id).entries,
            sitl: sitl,
            fleetLink: fleetLink
        )
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

                Menu {
                    Button {
                        toggleMCSReservePoolHomePlacementFromTaskHeader(task: task)
                    } label: {
                        Label(
                            "Set reserve pool home",
                            systemImage: mcsReservePoolHomePlacementTaskID == task.id ? "checkmark.circle" : "mappin.and.ellipse"
                        )
                    }
                    Button {
                        reapplyMCSReservePoolBulkHomeFromOverflowMenu(task: task)
                    } label: {
                        Label("Reapply reserve pool home", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(run.reservePoolBulkSimHome(forTaskID: task.id) == nil || eligiblePoolHomeReapply == 0)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .guardianPointerOnHover()
                .controlSize(.small)
                .disabled(!task.enabled || !fleetLink.isSimulateEnabled)
                .opacity((!task.enabled || !fleetLink.isSimulateEnabled) ? 0.48 : 1)
                .help(mcsReservePoolHomeOverflowMenuHelp(task: task))
            }

            if expanded {
                VStack(alignment: .leading, spacing: MissionRunPrepLayout.rosterGridSpacing) {
                    rostersOrderedSlotsList(rows: rows, mission: mission, taskID: task.id)
                    taskFloatingReservePoolStrip(task: task)
                }
            }
        }
    }

    @ViewBuilder
    private func rostersOrderedSlotsList(
        rows: [(assignmentIndex: Int, indent: Int)],
        mission: Mission?,
        taskID: UUID?
    ) -> some View {
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
                    rostersOrderedSlotsList(rows: rows, mission: mission, taskID: nil)
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
                    VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                            Text("Abort preference chain")
                                .font(GuardianTypography.font(.subsectionTitleSemibold))
                                .foregroundStyle(theme.textPrimary)
                            Text(
                                "Mission-wide default when a task or roster slot does not override. Tactics are tried in order; the first one the planner can bind is used."
                            )
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        MissionRunPreferentialAbortPolicyEditor(chain: missionAbortPreferenceChainBinding, showFootnote: true)
                        mcSetupRowDivider
                        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                            Text("Complete preference chain")
                                .font(GuardianTypography.font(.subsectionTitleSemibold))
                                .foregroundStyle(theme.textPrimary)
                            Text(
                                "Mission-wide default for recovery wind-down when a task or roster slot does not override. Use None alone for no automatic wind-down command."
                            )
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        MissionRunPreferentialCompletePolicyEditor(chain: missionCompletePreferenceChainBinding, showFootnote: true)
                        mcSetupRowDivider
                        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                            Text("Reserve swap preference chain")
                                .font(GuardianTypography.font(.subsectionTitleSemibold))
                                .foregroundStyle(theme.textPrimary)
                            Text(
                                "Mission-wide default for displaced-active wind-down after a reserve swap-in when a task or roster slot does not override. Same tactic shapes as complete recovery; use None alone for no automatic wind-down command."
                            )
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        MissionRunPreferentialReserveSwapPolicyEditor(chain: missionReserveSwapPreferenceChainBinding, showFootnote: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                        Text("Mission defaults unavailable")
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(
                            "This run’s mission is not in the library (or failed to load). Add or restore the mission to edit mission policy defaults."
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

    private var missionAbortPreferenceChainBinding: Binding<[MissionRunAbortTactic]> {
        Binding(
            get: {
                let chain = missionStore.missions.first(where: { $0.id == run.missionId })?
                    .routeMacro.rules.missionAbortPreferenceChain
                    ?? []
                return MissionRunAbortTactic.normalizedPreferenceChain(chain)
            },
            set: { newValue in
                _ = run.updateMissionAbortPreferenceChain(newValue, credential: localOperatorCredential)
                syncRunFromStore()
                onUpdate(run)
            }
        )
    }

    private var missionCompletePreferenceChainBinding: Binding<[MissionRunCompleteTactic]> {
        Binding(
            get: {
                let chain = missionStore.missions.first(where: { $0.id == run.missionId })?
                    .routeMacro.rules.missionCompletePreferenceChain
                    ?? []
                return MissionRunCompleteTactic.normalizedPreferenceChain(chain)
            },
            set: { newValue in
                _ = run.updateMissionCompletePreferenceChain(newValue, credential: localOperatorCredential)
                syncRunFromStore()
                onUpdate(run)
            }
        )
    }

    private var missionReserveSwapPreferenceChainBinding: Binding<[MissionRunReserveSwapTactic]> {
        Binding(
            get: {
                let chain = missionStore.missions.first(where: { $0.id == run.missionId })?
                    .routeMacro.rules.missionReserveSwapPreferenceChain
                    ?? []
                return MissionRunReserveSwapTactic.normalizedPreferenceChain(chain)
            },
            set: { newValue in
                _ = run.updateMissionReserveSwapPreferenceChain(newValue, credential: localOperatorCredential)
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

    private func requestManualMissionRunSimCleanup() {
        guard run.canScheduleMissionRunSimCleanupNow() else {
            toastCenter.show("No Guardian SITLs in scope for SIM cleanup right now.", style: .info)
            return
        }
        run.scheduleMissionRunSimCleanupIfNeeded()
    }

    /// Setup **Tasks** tab: staging map in a media-only ``GuardianCard`` (matches accordion column chrome).
    private var rostersStagingMapBare: some View {
        GuardianCard(
            configuration: mcSetupGroupCardConfiguration,
            media: {
                VStack(spacing: 0) {
                    if run.isMissionRunSimCleanupPassRunning {
                        GuardianInlineNotice(
                            kind: .informational,
                            title: "Mission Control is resetting the mission run to presets",
                            detail: "SIM cleanup is running on connected simulators. This line clears when the pass finishes.",
                            trailing: {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        )
                        .padding(.horizontal, GuardianSpacing.denseGutter)
                        .padding(.vertical, GuardianSpacing.xs)
                    }
                    if let tid = mcsReservePoolHomePlacementTaskID,
                       let mission = resolvedMission,
                       let task = mission.routeMacro.tasks.first(where: { $0.id == tid }) {
                        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                            Text(
                                "Tap the map to place eligible reserve pool SIMs for \(task.name)."
                            )
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            GuardianThemedButton(
                                title: "Cancel",
                                accent: .danger,
                                surface: .outline,
                                size: .small,
                                shape: .cornered,
                                action: { disarmMCSReservePoolHomePlacement() }
                            )
                            .guardianPointerOnHover()
                            .help("Stop placing reserve pool home on the map")
                        }
                        .padding(.horizontal, GuardianSpacing.denseGutter)
                        .padding(.vertical, GuardianSpacing.xs)
                        .background(GuardianSemanticColors.infoBackground)
                    }
                    GuardianMapView(
                        model: mapModel,
                        toolbar: GuardianMapToolbarOptions(
                            mapResetAction: { _ in
                                fitSetupStagingMapToVisibleMissionContent()
                            }
                        ),
                        contextMenuPolicy: GuardianMapContextMenuPolicy(
                            vehicleActions: [],
                            waypointActions: [],
                            homeActions: [],
                            missionPointActions: rostersSidebarListTab == .points ? [.deleteMissionPoint] : []
                        ),
                        onMapClick: { lat, lon in
                            if mcsReservePoolHomePlacementTaskID != nil {
                                Task { @MainActor in
                                    await applyMCSReservePoolHomePlacementFromStagingMapClick(lat: lat, lon: lon)
                                }
                                return
                            }
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
                            guard let raw = ev.markerID else { return }
                            if let berth = MissionControlReservePoolMapMarkerID.decodeBerth(raw) {
                                disarmMCSReservePoolHomePlacement()
                                toggleStagingReservePoolBerthMapSelection(taskID: berth.taskID, slotID: berth.slotID)
                                rosterSetupExpandedTaskIDs.insert(berth.taskID)
                                return
                            }
                            guard let aid = UUID(uuidString: raw) else { return }
                            toggleStagingVehicleMapSelection(assignmentId: aid)
                        },
                        onTaskPathTap: { ev in
                            setupStagingMapSelectedTaskPathID = ev.taskPathID
                            setupRostersSelectedMissionPointID = nil
                            setupSelectedAssignmentId = nil
                            clearStagingReservePoolBerthSelection()
                            clearAllSetupStagingReservePoolSimDragOverlays()
                            clearAllSetupStagingSimDragOverlays()
                            dismissSetupRostersMissionPointDrawerIfNeeded()
                            disarmMCSReservePoolHomePlacement()
                        },
                        onViewportCenterChanged: { lat, lon in
                            setupRostersMapViewportCenter = RouteCoordinate(lat: lat, lon: lon)
                        }
                    )
                    .task(id: setupStagingMapStructureIdentity) {
                        pushSetupStagingMapModelFromMissionTemplate()
                        fitSetupStagingMapToVisibleMissionContent()
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onExitCommand {
                    if mcsReservePoolHomePlacementTaskID != nil {
                        disarmMCSReservePoolHomePlacement()
                    }
                }
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
            selectedStagingRosterAssignmentID: setupSelectedAssignmentId,
            mcsReservePoolHomePlacementTaskID: mcsReservePoolHomePlacementTaskID,
            stagingReservePoolBerthSelectionSignature: setupSelectedReservePoolBerthSignature
        )
    }

    private var setupSelectedReservePoolBerthSignature: String {
        guard let t = setupSelectedReservePoolTaskID, let s = setupSelectedReservePoolSlotID else { return "" }
        return "\(t.uuidString)|\(s.uuidString)"
    }

    /// Quantized lat/lon for mission map points + roster vehicle markers; drives marker-only pushes without churning `.task(id:)`.
    private var setupStagingMapMarkerCoordinateDigest: String {
        let pts = setupStagingMissionPointRowsForMap
            .map { mp in
                String(format: "%@:%.5f:%.5f", mp.id.uuidString, mp.coordinate.lat, mp.coordinate.lon)
            }
            .joined(separator: "|")
        let veh = setupStagingMapVehicleMarkers
            .map { m in
                String(format: "%@:%.5f:%.5f:%@", m.id, m.lat, m.lon, m.pendingSimSync ? "1" : "0")
            }
            .joined(separator: "|")
        return pts + "§" + veh + "§poolSel:" + setupSelectedReservePoolBerthSignature
    }

    /// Clears mission-point / task-path / roster-vehicle / pool-berth map selection after a map background tap (same policy as mutual exclusivity elsewhere).
    private func clearStagingSetupMapSelectionFromBackgroundTap() {
        disarmMCSReservePoolHomePlacement()
        setupRostersSelectedMissionPointID = nil
        setupStagingMapSelectedTaskPathID = nil
        setupSelectedAssignmentId = nil
        clearStagingReservePoolBerthSelection()
        // Match roster SIM drag policy: optimistic pool / roster pose overlays stay until hub sustains or timeout.
        dismissSetupRostersMissionPointDrawerIfNeeded()
    }

    /// Drives ``onChange`` so pool-home arm clears when the mission template disappears or the target task is disabled/removed (``MCSReservePoolMapToDo.md`` Phase G).
    private var mcsReservePoolHomeArmLifecycleToken: String {
        guard let tid = mcsReservePoolHomePlacementTaskID else { return "" }
        guard let mission = resolvedMission else { return "lost" }
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == tid }) else { return "missing_task" }
        return "\(mission.id.uuidString)|\(tid.uuidString)|\(task.enabled ? 1 : 0)"
    }

    private func syncMCSReservePoolHomePlacementWithMissionTemplateIfNeeded() {
        guard mcsReservePoolHomePlacementTaskID != nil else { return }
        guard MCSReservePoolHomePlacementTemplateGuard.shouldDisarmPoolHomeArm(
            armedTaskID: mcsReservePoolHomePlacementTaskID,
            mission: resolvedMission
        ) else { return }
        disarmMCSReservePoolHomePlacement()
        pushSetupStagingMapMarkersOnly()
    }

    // MARK: - MCS reserve pool home (staging map)

    /// Clears pool-home arm and preview cursor only (no fleet I/O).
    private func disarmMCSReservePoolHomePlacement() {
        mcsReservePoolHomePlacementTaskID = nil
        mcsReservePoolHomePlacementCursorCoordinate = nil
    }

    /// Clears competing MCS staging-map chrome before arming pool-home placement (``MCSReservePoolMapToDo.md`` Phase A).
    private func clearMCSStagingMapExclusiveSelectionForReservePoolHomeArm() {
        setupRostersSelectedMissionPointID = nil
        setupStagingMapSelectedTaskPathID = nil
        setupSelectedAssignmentId = nil
        clearStagingReservePoolBerthSelection()
        clearAllSetupStagingSimDragOverlays()
        clearAllSetupStagingReservePoolSimDragOverlays()
        dismissSetupRostersMissionPointDrawerIfNeeded()
        var geo = mapModel.routeGeometry
        geo.missionPointPlacementArmed = false
        mapModel.routeGeometry = geo
    }

    /// Arms **Set reserve pool home** for ``taskID`` after clearing competing map selections (no fleet I/O).
    private func armMCSReservePoolHomePlacement(taskID: UUID) {
        clearMCSStagingMapExclusiveSelectionForReservePoolHomeArm()
        mcsReservePoolHomePlacementCursorCoordinate = nil
        mcsReservePoolHomePlacementTaskID = taskID
    }

    /// Task header overflow: **Set reserve pool home** — arms staging-map pool placement, or disarms when already armed for the same task (``MCSReservePoolMapToDo.md`` Phase B).
    private func toggleMCSReservePoolHomePlacementFromTaskHeader(task: MissionTask) {
        guard task.enabled else { return }
        guard fleetLink.isSimulateEnabled else {
            toastCenter.show("Turn on simulation in Vehicles before using reserve pool map placement.", style: .warning)
            return
        }
        let tid = task.id
        if mcsReservePoolHomePlacementTaskID == tid {
            disarmMCSReservePoolHomePlacement()
            return
        }
        let n = MCSReservePoolHomeStagingMapEligibility.eligibleSitlReservePoolSlotCount(
            entries: run.reservePool(forTaskID: tid).entries,
            sitl: sitl,
            fleetLink: fleetLink
        )
        guard n > 0 else {
            toastCenter.show(
                "No ready SIM reserve berths. Attach a simulator to at least one floating reserve slot, then try again.",
                style: .warning
            )
            return
        }
        armMCSReservePoolHomePlacement(taskID: tid)
    }

    private func mcsReservePoolHomeOverflowMenuHelp(task: MissionTask) -> String {
        if !task.enabled {
            return "Enable this task in task settings first."
        }
        if !fleetLink.isSimulateEnabled {
            return "Turn on simulation in Vehicles to use this action."
        }
        return "Task overflow menu — set or reapply a common map pose for floating reserve SIMs, or drag selected pool markers individually."
    }

    private func applyMCSReservePoolHomePlacementFromStagingMapClick(lat: Double, lon: Double) async {
        guard let tid = mcsReservePoolHomePlacementTaskID else { return }
        let taskLabel = resolvedMission?.routeMacro.tasks.first(where: { $0.id == tid })?.name
        let sent = await applyReservePoolHomeSimBatchForTask(taskID: tid, lat: lat, lon: lon)
        disarmMCSReservePoolHomePlacement()
        pushSetupStagingMapModelFromMissionTemplate()
        fitSetupStagingMapToVisibleMissionContent()
        reconcileSetupStagingSimDragOverlayWithHubTelemetry()
        if sent > 0 {
            run.setReservePoolBulkSimHome(RouteCoordinate(lat: lat, lon: lon), forTaskID: tid)
        }
        run.systems.logging.appendLogEvent(
            level: sent > 0 ? .info : .warning,
            taskID: tid,
            taskLabel: taskLabel,
            templateKey: MissionRunLogTemplateKey.mcsReservePoolHomeMapBatch,
            templateParams: [
                "sent": String(sent),
                "latDeg": String(format: "%.6f", lat),
                "lonDeg": String(format: "%.6f", lon),
                "modeNote": "",
            ]
        )
        if sent > 0 {
            toastCenter.show(
                "Placement sent for \(sent) reserve pool SIM\(sent == 1 ? "" : "s"). Positions update on the map as telemetry catches up.",
                style: .info
            )
            scheduleDeferredSetupStagingMapFitAfterReservePoolHomeApply()
        } else {
            toastCenter.show(
                "No pool SIMs received this placement. Check that floating reserve berths still have attached simulators.",
                style: .warning
            )
        }
    }

    /// Overflow **Reapply reserve pool home**: repeats the last bulk hub coordinate for any **new** eligible pool SIMs (same coordinate as last map placement).
    private func reapplyMCSReservePoolBulkHomeFromOverflowMenu(task: MissionTask) {
        guard task.enabled else { return }
        guard fleetLink.isSimulateEnabled else {
            toastCenter.show("Turn on simulation in Vehicles before using reserve pool map placement.", style: .warning)
            return
        }
        guard let coord = run.reservePoolBulkSimHome(forTaskID: task.id) else {
            toastCenter.show("Set reserve pool home on the map once first — there is no saved hub to reapply.", style: .warning)
            return
        }
        let tid = task.id
        let n = MCSReservePoolHomeStagingMapEligibility.eligibleSitlReservePoolSlotCount(
            entries: run.reservePool(forTaskID: tid).entries,
            sitl: sitl,
            fleetLink: fleetLink
        )
        guard n > 0 else {
            toastCenter.show(
                "No ready SIM reserve berths. Attach a simulator to at least one floating reserve slot, then try again.",
                style: .warning
            )
            return
        }
        let taskLabel = task.name
        let lat = coord.lat
        let lon = coord.lon
        Task { @MainActor in
            let sent = await applyReservePoolHomeSimBatchForTask(taskID: tid, lat: lat, lon: lon)
            pushSetupStagingMapModelFromMissionTemplate()
            fitSetupStagingMapToVisibleMissionContent()
            reconcileSetupStagingSimDragOverlayWithHubTelemetry()
            run.systems.logging.appendLogEvent(
                level: sent > 0 ? .info : .warning,
                taskID: tid,
                taskLabel: taskLabel,
                templateKey: MissionRunLogTemplateKey.mcsReservePoolHomeMapBatch,
                templateParams: [
                    "sent": String(sent),
                    "latDeg": String(format: "%.6f", lat),
                    "lonDeg": String(format: "%.6f", lon),
                    "modeNote": " (reapply)",
                ]
            )
            if sent > 0 {
                toastCenter.show(
                    "Reapplied hub to \(sent) reserve pool SIM\(sent == 1 ? "" : "s"). Positions update on the map as telemetry catches up.",
                    style: .info
                )
                scheduleDeferredSetupStagingMapFitAfterReservePoolHomeApply()
            } else {
                toastCenter.show(
                    "No pool SIMs received this placement. Check that floating reserve berths still have attached simulators.",
                    style: .warning
                )
            }
        }
    }

    /// Immediate fit already ran; hub-backed marker coords may update shortly after ``applySimState`` — refit once.
    private func scheduleDeferredSetupStagingMapFitAfterReservePoolHomeApply() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(MCSReservePoolHomeStagingMapTiming.postBatchFitDelaySeconds))
            guard resolvedMission != nil else { return }
            pushSetupStagingMapModelFromMissionTemplate()
            fitSetupStagingMapToVisibleMissionContent()
            reconcileSetupStagingSimDragOverlayWithHubTelemetry()
        }
    }

    /// Encoded pool marker ids eligible for bulk / reapply ``applySimState`` (stable hub + known stack).
    private func eligibleReservePoolHomeEncodedMarkerIDs(for taskID: UUID) -> [String] {
        var ids: [String] = []
        for slot in run.reservePool(forTaskID: taskID).entries {
            guard MCSReservePoolHomeStagingMapEligibility.isEligibleSitlReservePoolSlot(
                slot: slot,
                sitl: sitl,
                fleetLink: fleetLink
            ) else { continue }
            guard let key = slot.attachedFleetVehicleToken,
                  let token = FleetMissionVehicleToken(storageKey: key),
                  case .sitl(let sitlInstanceID) = token,
                  let inst = sitl.instances.first(where: { $0.id == sitlInstanceID })
            else { continue }
            let systemID = inst.stackInstanceIndex + 1
            let vehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
            let stack = fleetLink.hubTelemetry(forVehicleID: vehicleID)?.autopilotStack
                ?? fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.telemetry?.autopilotStack
                ?? .unknown
            guard stack != .unknown else { continue }
            ids.append(MissionControlReservePoolMapMarkerID.encode(taskID: taskID, slotID: slot.id))
        }
        return ids
    }

    /// Sequential ``FleetLinkService/applySimState`` for each eligible pool SITL on ``taskID`` (``MCSReservePoolMapToDo.md`` Phase D).
    /// Installs the same optimistic ``MissionRunStagingSimDragOverlay`` per berth as roster SITL drags so ``pendingSimSync`` spinners stay up until hub telemetry sustains at the target pose (not only until ``applySimState`` returns).
    private func applyReservePoolHomeSimBatchForTask(taskID: UUID, lat: Double, lon: Double) async -> Int {
        let encodedTargets = eligibleReservePoolHomeEncodedMarkerIDs(for: taskID)
        let targetCoord = RouteCoordinate(lat: lat, lon: lon)
        if !encodedTargets.isEmpty {
            let startedAt = Date()
            await MainActor.run {
                for enc in encodedTargets {
                    setupStagingReservePoolSimDragCoordByEncodedMarkerID[enc] = MissionRunStagingSimDragOverlay(
                        coordinate: targetCoord,
                        startedAt: startedAt,
                        hubAgreesSince: nil
                    )
                    scheduleSetupStagingReservePoolSimDragTimeoutReconcile(for: enc)
                }
                pushSetupStagingMapMarkersOnly()
                reconcileSetupStagingSimDragOverlayWithHubTelemetry()
            }
        }
        var count = 0
        for slot in run.reservePool(forTaskID: taskID).entries {
            guard MCSReservePoolHomeStagingMapEligibility.isEligibleSitlReservePoolSlot(
                slot: slot,
                sitl: sitl,
                fleetLink: fleetLink
            ) else { continue }
            guard let key = slot.attachedFleetVehicleToken,
                  let token = FleetMissionVehicleToken(storageKey: key),
                  case .sitl(let sitlInstanceID) = token
            else { continue }
            guard let inst = sitl.instances.first(where: { $0.id == sitlInstanceID }) else { continue }
            let systemID = inst.stackInstanceIndex + 1
            let vehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
            let stack = fleetLink.hubTelemetry(forVehicleID: vehicleID)?.autopilotStack
                ?? fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.telemetry?.autopilotStack
                ?? .unknown
            guard stack != .unknown else { continue }
            let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
            let alt = hub?.absoluteAltM ?? hub?.altitudeAmslM
            let yaw = Float(hub?.headingDeg ?? hub?.yawDeg ?? 0)
            let state = FleetSimState(
                latitudeDeg: lat,
                longitudeDeg: lon,
                absoluteAltitudeM: alt,
                yawDeg: yaw,
                batteryVoltageV: nil,
                ardupilotSimBattCapAh: nil,
                px4SimBatDrain: nil
            )
            await fleetLink.applySimState(
                vehicleID: vehicleID,
                state: state,
                autopilotStack: stack,
                source: "mcs.reserve_pool_home_map"
            )
            count += 1
        }
        return count
    }

    private func dismissLiveRuntimeMissionPointEditDrawerIfNeeded() {
        guard liveRuntimeMissionPointDrawerEditingID != nil else { return }
        liveRuntimeMissionPointDrawerEditingID = nil
        appDrawer.dismiss()
    }

    /// MC-R live map: same background-tap deselection contract as MCS staging map (``clearStagingSetupMapSelectionFromBackgroundTap``).
    private func clearLiveOverviewMapSelectionFromBackgroundTap() {
        liveRuntimeOverviewSelectedMissionPointID = nil
        focusedLiveTaskID = nil
        focusedLiveAssignmentID = nil
        dismissLiveRuntimeMissionPointEditDrawerIfNeeded()
    }

    /// Roster staging map: toggle floating-reserve pool berth selection (SIM ring + drag when eligible); clears roster / point / path map selection.
    private func toggleStagingReservePoolBerthMapSelection(taskID: UUID, slotID: UUID) {
        disarmMCSReservePoolHomePlacement()
        if setupSelectedReservePoolTaskID == taskID, setupSelectedReservePoolSlotID == slotID {
            setupSelectedReservePoolTaskID = nil
            setupSelectedReservePoolSlotID = nil
        } else {
            if setupSelectedReservePoolTaskID != taskID || setupSelectedReservePoolSlotID != slotID {
                clearAllSetupStagingReservePoolSimDragOverlays()
            }
            setupSelectedAssignmentId = nil
            clearAllSetupStagingSimDragOverlays()
            setupRostersSelectedMissionPointID = nil
            setupStagingMapSelectedTaskPathID = nil
            dismissSetupRostersMissionPointDrawerIfNeeded()
            setupSelectedReservePoolTaskID = taskID
            setupSelectedReservePoolSlotID = slotID
        }
    }

    /// Roster staging map: toggle which assignment is selected for vehicle ring + SIM drag (clears point / task-path map selection).
    private func toggleStagingVehicleMapSelection(assignmentId: UUID) {
        disarmMCSReservePoolHomePlacement()
        if setupSelectedAssignmentId == assignmentId {
            setupSelectedAssignmentId = nil
        } else {
            clearStagingReservePoolBerthSelection()
            clearAllSetupStagingReservePoolSimDragOverlays()
            setupRostersSelectedMissionPointID = nil
            setupStagingMapSelectedTaskPathID = nil
            dismissSetupRostersMissionPointDrawerIfNeeded()
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

    private func stagingReservePoolHubCoordinateForEncodedPoolMarker(_ encodedMarkerID: String) -> RouteCoordinate? {
        guard let berth = MissionControlReservePoolMapMarkerID.decodeBerth(encodedMarkerID),
              let mission = resolvedMission,
              let task = mission.routeMacro.tasks.first(where: { $0.id == berth.taskID }),
              task.enabled,
              let slot = run.reservePool(forTaskID: berth.taskID).entries.first(where: { $0.id == berth.slotID })
        else { return nil }
        return stagingReservePoolHubCoordinate(taskID: berth.taskID, slot: slot)
    }

    private func stagingReservePoolHubCoordinate(taskID: UUID, slot: MissionRunReservePoolSlot) -> RouteCoordinate? {
        let syn = syntheticMissionRunAssignment(from: slot)
        guard let vehicleID = resolvedFleetStreamVehicleID(assignment: syn, fleetLink: fleetLink, sitl: sitl),
              let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else { return nil }
        return RouteCoordinate(lat: lat, lon: lon)
    }

    private func cancelSetupStagingSimDragTimeoutReconcileTask(for assignmentId: UUID) {
        setupStagingSimDragTimeoutReconcileTasks[assignmentId]?.cancel()
        setupStagingSimDragTimeoutReconcileTasks.removeValue(forKey: assignmentId)
    }

    private func cancelAllSetupStagingSimDragTimeoutReconcileTasks() {
        for t in setupStagingSimDragTimeoutReconcileTasks.values { t.cancel() }
        setupStagingSimDragTimeoutReconcileTasks.removeAll()
    }

    private func removeSetupStagingSimDragOverlay(for assignmentId: UUID) {
        cancelSetupStagingSimDragTimeoutReconcileTask(for: assignmentId)
        setupStagingSimDragCoordByAssignmentID.removeValue(forKey: assignmentId)
    }

    private func clearAllSetupStagingSimDragOverlays() {
        cancelAllSetupStagingSimDragTimeoutReconcileTasks()
        setupStagingSimDragCoordByAssignmentID.removeAll()
    }

    private func clearStagingReservePoolBerthSelection() {
        setupSelectedReservePoolTaskID = nil
        setupSelectedReservePoolSlotID = nil
    }

    private func cancelSetupStagingReservePoolSimDragTimeoutReconcileTask(for encodedMarkerID: String) {
        setupStagingReservePoolSimDragTimeoutReconcileTasks[encodedMarkerID]?.cancel()
        setupStagingReservePoolSimDragTimeoutReconcileTasks.removeValue(forKey: encodedMarkerID)
    }

    private func cancelAllSetupStagingReservePoolSimDragTimeoutReconcileTasks() {
        for t in setupStagingReservePoolSimDragTimeoutReconcileTasks.values { t.cancel() }
        setupStagingReservePoolSimDragTimeoutReconcileTasks.removeAll()
    }

    private func removeSetupStagingReservePoolSimDragOverlay(for encodedMarkerID: String) {
        cancelSetupStagingReservePoolSimDragTimeoutReconcileTask(for: encodedMarkerID)
        setupStagingReservePoolSimDragCoordByEncodedMarkerID.removeValue(forKey: encodedMarkerID)
    }

    private func clearAllSetupStagingReservePoolSimDragOverlays() {
        cancelAllSetupStagingReservePoolSimDragTimeoutReconcileTasks()
        setupStagingReservePoolSimDragCoordByEncodedMarkerID.removeAll()
    }

    private func scheduleSetupStagingReservePoolSimDragTimeoutReconcile(for encodedMarkerID: String) {
        cancelSetupStagingReservePoolSimDragTimeoutReconcileTask(for: encodedMarkerID)
        setupStagingReservePoolSimDragTimeoutReconcileTasks[encodedMarkerID] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(MissionControlSetupSimDragOverlayPolicy.pendingSyncTimeoutSeconds))
            guard !Task.isCancelled else { return }
            reconcileSetupStagingReservePoolSimDragOverlaysWithHubTelemetry()
            setupStagingReservePoolSimDragTimeoutReconcileTasks.removeValue(forKey: encodedMarkerID)
        }
    }

    private func scheduleSetupStagingSimDragTimeoutReconcile(for assignmentId: UUID) {
        cancelSetupStagingSimDragTimeoutReconcileTask(for: assignmentId)
        setupStagingSimDragTimeoutReconcileTasks[assignmentId] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(MissionControlSetupSimDragOverlayPolicy.pendingSyncTimeoutSeconds))
            guard !Task.isCancelled else { return }
            reconcileSetupStagingSimDragOverlayWithHubTelemetry()
            setupStagingSimDragTimeoutReconcileTasks.removeValue(forKey: assignmentId)
        }
    }

    /// Drops SIM drag optimistic coords once hub **stably** reflects the same pose (see ``MissionControlSetupSimDragOverlayPolicy/hubAgreesSustainSeconds``) or the pending-sync timeout elapses.
    private func reconcileSetupStagingSimDragOverlayWithHubTelemetry() {
        reconcileSetupStagingRosterSimDragOverlaysWithHubTelemetry()
        reconcileSetupStagingReservePoolSimDragOverlaysWithHubTelemetry()
    }

    private func reconcileSetupStagingRosterSimDragOverlaysWithHubTelemetry() {
        guard !setupStagingSimDragCoordByAssignmentID.isEmpty else { return }
        let now = Date()
        var next = setupStagingSimDragCoordByAssignmentID
        var toRemove: [UUID] = []
        for aid in Array(next.keys) {
            guard var pending = next[aid] else { continue }
            if MissionControlSetupSimDragOverlayPolicy.shouldClearOverlayByTimeout(overlayStartedAt: pending.startedAt, now: now) {
                toRemove.append(aid)
                continue
            }
            let hub = stagingSimHubCoordinate(forAssignmentId: aid)
            guard let h = hub else {
                pending.hubAgreesSince = nil
                next[aid] = pending
                continue
            }
            let matches = MissionControlSetupSimDragOverlayPolicy.hubMatches(
                pendingCoordinate: pending.coordinate,
                hubCoordinate: h
            )
            pending.hubAgreesSince = MissionControlSetupSimDragOverlayPolicy.updatedHubAgreesSince(
                hubMatchesPending: matches,
                previous: pending.hubAgreesSince,
                now: now
            )
            if matches,
               MissionControlSetupSimDragOverlayPolicy.isSustainedHubAgreement(hubAgreesSince: pending.hubAgreesSince, now: now)
            {
                toRemove.append(aid)
            } else {
                next[aid] = pending
            }
        }
        for aid in toRemove {
            next.removeValue(forKey: aid)
            cancelSetupStagingSimDragTimeoutReconcileTask(for: aid)
        }
        if next != setupStagingSimDragCoordByAssignmentID {
            setupStagingSimDragCoordByAssignmentID = next
        }
    }

    private func reconcileSetupStagingReservePoolSimDragOverlaysWithHubTelemetry() {
        guard !setupStagingReservePoolSimDragCoordByEncodedMarkerID.isEmpty else { return }
        let now = Date()
        var next = setupStagingReservePoolSimDragCoordByEncodedMarkerID
        var toRemove: [String] = []
        for enc in Array(next.keys) {
            guard var pending = next[enc] else { continue }
            if MissionControlSetupSimDragOverlayPolicy.shouldClearOverlayByTimeout(overlayStartedAt: pending.startedAt, now: now) {
                toRemove.append(enc)
                continue
            }
            let hub = stagingReservePoolHubCoordinateForEncodedPoolMarker(enc)
            guard let h = hub else {
                pending.hubAgreesSince = nil
                next[enc] = pending
                continue
            }
            let matches = MissionControlSetupSimDragOverlayPolicy.hubMatches(
                pendingCoordinate: pending.coordinate,
                hubCoordinate: h
            )
            pending.hubAgreesSince = MissionControlSetupSimDragOverlayPolicy.updatedHubAgreesSince(
                hubMatchesPending: matches,
                previous: pending.hubAgreesSince,
                now: now
            )
            if matches,
               MissionControlSetupSimDragOverlayPolicy.isSustainedHubAgreement(hubAgreesSince: pending.hubAgreesSince, now: now)
            {
                toRemove.append(enc)
            } else {
                next[enc] = pending
            }
        }
        for enc in toRemove {
            next.removeValue(forKey: enc)
            cancelSetupStagingReservePoolSimDragTimeoutReconcileTask(for: enc)
        }
        if next != setupStagingReservePoolSimDragCoordByEncodedMarkerID {
            setupStagingReservePoolSimDragCoordByEncodedMarkerID = next
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
                missionPointPlacementArmed: false,
                mcsReservePoolHomePlacementArmed: mcsReservePoolHomePlacementTaskID != nil
            )
        } else {
            mapModel.routeGeometry = .empty
        }
        mapModel.vehicleMarkers = setupStagingMapVehicleMarkers
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
        geo.mcsReservePoolHomePlacementArmed = mcsReservePoolHomePlacementTaskID != nil
        mapModel.routeGeometry = geo
        mapModel.vehicleMarkers = setupStagingMapVehicleMarkers
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
        disarmMCSReservePoolHomePlacement()
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
        disarmMCSReservePoolHomePlacement()
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
        clearAllSetupStagingSimDragOverlays()
        setupStagingMapSelectedTaskPathID = nil
        setupRostersMapPointsListScrollTargetRow = newID
        setupRostersMapPointsListScrollEpoch &+= 1
        toastCenter.show("Map point added — drag the pin on the map to move it", style: .success)
    }

    private func openSetupRostersMissionPointEditDrawer(missionPointID: UUID) {
        guard resolvedMission?.missionPoints.contains(where: { $0.id == missionPointID }) == true else { return }
        disarmMCSReservePoolHomePlacement()
        setupSelectedAssignmentId = nil
        clearAllSetupStagingSimDragOverlays()
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
        disarmMCSReservePoolHomePlacement()
        if setupRostersSelectedMissionPointID == missionPointID {
            setupRostersSelectedMissionPointID = nil
            if setupRostersMissionPointDrawerEditingID == missionPointID {
                setupRostersMissionPointDrawerEditingID = nil
                appDrawer.dismiss()
            }
        } else {
            setupSelectedAssignmentId = nil
            clearStagingReservePoolBerthSelection()
            clearAllSetupStagingSimDragOverlays()
            clearAllSetupStagingReservePoolSimDragOverlays()
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
                    let now = Date()
                    let hubCoord = stagingSimHubCoordinate(forAssignmentId: assignment.id)
                    let hubOk = hubCoord.map {
                        MissionControlSetupSimDragOverlayPolicy.hubMatches(
                            pendingCoordinate: optimistic.coordinate,
                            hubCoordinate: $0
                        )
                    } ?? false
                    let sustained = MissionControlSetupSimDragOverlayPolicy.isSustainedHubAgreement(
                        hubAgreesSince: optimistic.hubAgreesSince,
                        now: now
                    )
                    let pendingSimSync = !hubOk || !sustained
                    return MapVehicleMarker(
                        id: assignment.id.uuidString,
                        lat: optimistic.coordinate.lat,
                        lon: optimistic.coordinate.lon,
                        label: "\(label) (SIM)",
                        colorHex: colorHex,
                        imageDataURL: imageDataURL,
                        selected: selected,
                        draggable: selected,
                        headingDeg: heading,
                        pendingSimSync: pendingSimSync
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

    /// MCS **Rosters › Tasks** staging map: hub-backed markers for **floating reserve pool** SIMs (``MissionControlReservePoolMapMarkerID``); draggable when selected and SITL-eligible.
    private var setupStagingFloatingReservePoolVehicleMarkers: [MapVehicleMarker] {
        guard let mission = resolvedMission else { return [] }
        var out: [MapVehicleMarker] = []
        for task in mission.routeMacro.tasks where task.enabled {
            let tid = task.id
            let pool = run.reservePool(forTaskID: tid)
            for slot in pool.entries {
                guard slot.hasFleetOrLegacyBinding,
                      let rawTok = slot.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !rawTok.isEmpty
                else { continue }
                let encoded = MissionControlReservePoolMapMarkerID.encode(taskID: tid, slotID: slot.id)
                let syn = syntheticMissionRunAssignment(from: slot)
                guard let vehicleID = resolvedFleetStreamVehicleID(assignment: syn, fleetLink: fleetLink, sitl: sitl),
                      let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID),
                      let hubLat = hub.latitudeDeg,
                      let hubLon = hub.longitudeDeg
                else { continue }
                let eligible = MCSReservePoolHomeStagingMapEligibility.isEligibleSitlReservePoolSlot(
                    slot: slot,
                    sitl: sitl,
                    fleetLink: fleetLink
                )
                let selected = setupSelectedReservePoolTaskID == tid && setupSelectedReservePoolSlotID == slot.id
                let colorHex = fleetLink.mapColorHex(forVehicleID: vehicleID)
                let heading = hub.headingDeg ?? hub.yawDeg
                let taskName = task.name
                let poolA11y = MissionRunReserveSwapAccessibilityCopy.floatingPoolMapMarker(
                    taskName: taskName,
                    berthLabel: slot.label,
                    swapPickActiveOnTask: false,
                    markerIsEligiblePickTarget: false,
                    browsingThisBerthOnTask: false
                )
                let lat: Double
                let lon: Double
                let pendingSimSync: Bool
                if let optimistic = setupStagingReservePoolSimDragCoordByEncodedMarkerID[encoded] {
                    lat = optimistic.coordinate.lat
                    lon = optimistic.coordinate.lon
                    let hubCoord = RouteCoordinate(lat: hubLat, lon: hubLon)
                    let now = Date()
                    let hubOk = MissionControlSetupSimDragOverlayPolicy.hubMatches(
                        pendingCoordinate: optimistic.coordinate,
                        hubCoordinate: hubCoord
                    )
                    let sustained = MissionControlSetupSimDragOverlayPolicy.isSustainedHubAgreement(
                        hubAgreesSince: optimistic.hubAgreesSince,
                        now: now
                    )
                    pendingSimSync = !hubOk || !sustained
                } else {
                    lat = hubLat
                    lon = hubLon
                    pendingSimSync = false
                }
                out.append(
                    MapVehicleMarker(
                        id: encoded,
                        lat: lat,
                        lon: lon,
                        label: "\(slot.label) · pool",
                        colorHex: colorHex,
                        imageDataURL: missionControlRosterMapMarkerImageDataURL(for: syn),
                        selected: selected,
                        draggable: selected && eligible,
                        headingDeg: heading,
                        pendingSimSync: pendingSimSync,
                        accessibilityTitle: poolA11y
                    )
                )
            }
        }
        return out
    }

    /// Roster assignment markers plus floating-reserve pool hub markers for the MCS staging map.
    private var setupStagingMapVehicleMarkers: [MapVehicleMarker] {
        setupVehicleMarkers + setupStagingFloatingReservePoolVehicleMarkers
    }

    /// **SITL-only:** applies dragged lat/lon to the bound sim via ``FleetLinkService/applySimState`` (SIM_OPOS_* / SIH_LOC_*).
    private func applySetupMarkerDrag(markerID: String, lat: Double, lon: Double) {
        if let berth = MissionControlReservePoolMapMarkerID.decodeBerth(markerID) {
            applyStagingReservePoolMarkerDrag(taskID: berth.taskID, slotID: berth.slotID, lat: lat, lon: lon)
            return
        }
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

        disarmMCSReservePoolHomePlacement()
        clearStagingReservePoolBerthSelection()
        clearAllSetupStagingReservePoolSimDragOverlays()

        let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
        let alt = hub?.absoluteAltM ?? hub?.altitudeAmslM
        let yaw = Float(hub?.headingDeg ?? hub?.yawDeg ?? 0)

        setupRostersSelectedMissionPointID = nil
        setupStagingMapSelectedTaskPathID = nil
        dismissSetupRostersMissionPointDrawerIfNeeded()
        setupSelectedAssignmentId = aid

        let sent = RouteCoordinate(lat: lat, lon: lon)
        setupStagingSimDragCoordByAssignmentID[aid] = MissionRunStagingSimDragOverlay(
            coordinate: sent,
            startedAt: Date(),
            hubAgreesSince: nil
        )
        scheduleSetupStagingSimDragTimeoutReconcile(for: aid)

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
            // `applySimState` ends with `reflectAppliedSimStateInHubTelemetry`, but MAVSDK can still deliver one or
            // more **stale** position samples afterward — the overlay stays up until hub agrees for
            // `MissionControlSetupSimDragOverlayPolicy.hubAgreesSustainSeconds` (or the 10s cap).
            await fleetLink.applySimState(
                vehicleID: vehicleID,
                state: state,
                autopilotStack: stack,
                source: "mcs.setup_map_drag"
            )
            reconcileSetupStagingSimDragOverlayWithHubTelemetry()
        }
    }

    /// **Pool SITL:** staging-map drag for a selected floating-reserve berth (``MissionControlReservePoolMapMarkerID``).
    private func applyStagingReservePoolMarkerDrag(taskID: UUID, slotID: UUID, lat: Double, lon: Double) {
        guard let slot = run.reservePool(forTaskID: taskID).entries.first(where: { $0.id == slotID }) else { return }
        guard MCSReservePoolHomeStagingMapEligibility.isEligibleSitlReservePoolSlot(
            slot: slot,
            sitl: sitl,
            fleetLink: fleetLink
        ) else { return }
        guard let key = slot.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: key),
              case .sitl(let sitlInstanceID) = token,
              let inst = sitl.instances.first(where: { $0.id == sitlInstanceID })
        else { return }
        let systemID = inst.stackInstanceIndex + 1
        let vehicleID = fleetLink.vehicleID(forSystemID: systemID) ?? "sysid:\(systemID)"
        let stack = fleetLink.hubTelemetry(forVehicleID: vehicleID)?.autopilotStack
            ?? fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.telemetry?.autopilotStack
            ?? .unknown
        guard stack != .unknown else { return }

        disarmMCSReservePoolHomePlacement()

        setupRostersSelectedMissionPointID = nil
        setupStagingMapSelectedTaskPathID = nil
        dismissSetupRostersMissionPointDrawerIfNeeded()
        setupSelectedAssignmentId = nil
        clearAllSetupStagingSimDragOverlays()

        setupSelectedReservePoolTaskID = taskID
        setupSelectedReservePoolSlotID = slotID

        let encoded = MissionControlReservePoolMapMarkerID.encode(taskID: taskID, slotID: slotID)
        let coord = RouteCoordinate(lat: lat, lon: lon)
        setupStagingReservePoolSimDragCoordByEncodedMarkerID[encoded] = MissionRunStagingSimDragOverlay(
            coordinate: coord,
            startedAt: Date(),
            hubAgreesSince: nil
        )
        scheduleSetupStagingReservePoolSimDragTimeoutReconcile(for: encoded)

        let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
        let alt = hub?.absoluteAltM ?? hub?.altitudeAmslM
        let yaw = Float(hub?.headingDeg ?? hub?.yawDeg ?? 0)
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
                source: "mcs.reserve_pool_marker_drag"
            )
            reconcileSetupStagingSimDragOverlayWithHubTelemetry()
        }
        run.setReservePoolBulkSimHome(coord, forTaskID: taskID)
    }

    private var setupMapBoundsSignature: String {
        let roster = run.assignments
            .compactMap { assignment -> String? in
                guard let token = assignment.attachedFleetVehicleToken else { return nil }
                return "\(assignment.id.uuidString)|\(token)"
            }
            .sorted()
            .joined(separator: ";")
        let pool = setupStagingReservePoolFleetBindingSignature
        if pool.isEmpty { return roster }
        return roster + "§pool§" + pool
    }

    /// Enabled-task floating reserve berths + fleet tokens (MCS staging map pool markers + ``setupStagingMapStructureIdentity``).
    private var setupStagingReservePoolFleetBindingSignature: String {
        guard let mission = resolvedMission else { return "" }
        var rows: [String] = []
        for task in mission.routeMacro.tasks where task.enabled {
            let tid = task.id
            for slot in run.reservePool(forTaskID: tid).entries.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                let tok = slot.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                rows.append("\(tid.uuidString)|\(slot.id.uuidString)|\(tok)")
            }
        }
        return rows.sorted().joined(separator: ";")
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

    // MARK: - Floating reserve pool (MCS roster accordion)

    @ViewBuilder
    private func taskFloatingReservePoolStrip(task: MissionTask) -> some View {
        let tid = task.id
        let pool = run.reservePool(forTaskID: tid)
        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
            Text("Floating reserves")
                .font(GuardianTypography.font(.denseCaption12Medium))
                .foregroundStyle(theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: MissionRunPrepLayout.rosterGridSpacing) {
                    ForEach(pool.entries) { slot in
                        reservePoolSlotRow(taskID: tid, slot: slot, taskEnabled: task.enabled)
                    }
                    Button {
                        appendEmptyReservePoolSlot(taskID: tid)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(GuardianTypography.font(.windowHeading16Semibold))
                            .foregroundStyle(task.enabled ? GuardianSemanticColors.infoForeground : theme.textTertiary)
                            .frame(width: MissionRunPrepLayout.rosterSlotIconSize, height: MissionRunPrepLayout.rosterSlotIconSize)
                    }
                    .buttonStyle(GuardianPointerPlainButtonStyle())
                    .disabled(!task.enabled)
                    .help("Add reserve pool slot")
                }
                .padding(.vertical, 2)
            }
        }
        .opacity(task.enabled ? 1 : 0.5)
    }

    private func reservePoolSlotRow(taskID: UUID, slot: MissionRunReservePoolSlot, taskEnabled: Bool) -> some View {
        let duplicate = reservePoolDuplicateFleetBindingWarning(taskID: taskID, slot: slot)
        let syn = syntheticMissionRunAssignment(from: slot)
        return VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
            if let duplicate {
                Text(duplicate)
                    .font(GuardianTypography.font(.denseCaption10Semibold))
                    .foregroundStyle(GuardianSemanticColors.warningForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ZStack(alignment: .topTrailing) {
                reservePoolSlotCard(taskID: taskID, slot: slot, syntheticAssignment: syn, taskEnabled: taskEnabled)
                    .frame(width: MissionRunPrepLayout.reservePoolSlotCardWidth)
                if taskEnabled {
                    Button {
                        removeReservePoolSlotFromTask(taskID: taskID, slotID: slot.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(GuardianPointerPlainButtonStyle())
                    .help("Remove this reserve slot")
                    .offset(x: 6, y: -4)
                }
            }
        }
    }

    private func reservePoolSlotCard(
        taskID: UUID,
        slot: MissionRunReservePoolSlot,
        syntheticAssignment syn: MissionRunAssignment,
        taskEnabled: Bool
    ) -> some View {
        let detailLine = resolvedRosterVehicleSecondaryLine(assignment: syn, fleetLink: fleetLink, sitl: sitl)
        let basenames = simulationImageBasenamesForAssignment(syn, sitl: sitl)
        let slotFilled = slot.hasFleetOrLegacyBinding
        let batterySummary: FleetVehicleOperationalModel.BatterySummary? = {
            guard let vid = telemetryVehicleID(for: syn) else { return nil }
            return fleetLink.vehicleOperationalModel(forVehicleID: vid).battery
        }()
        let infoVehicleID = telemetryVehicleID(for: syn)
        let rosterDeviceClass: FleetVehicleType = .unknown
        let deviceArtVehicleClass: FleetVehicleType = {
            guard slotFilled,
                  let vid = telemetryVehicleID(for: syn),
                  let model = fleetLink.vehicleModel(forVehicleID: vid)
            else { return rosterDeviceClass }
            return model.data.vehicleType
        }()
        let fleetDisplayShortID: String? = {
            guard slotFilled, telemetryVehicleID(for: syn) != nil else { return nil }
            let s = assignmentFleetDisplayShortID(assignment: syn, rosterDevice: nil)
            return s.isEmpty ? nil : s
        }()
        return MissionControlRosterSlotCard(
            title: slot.label,
            subtitle: "Floating reserve",
            vehicleClassForBundledDeviceArt: deviceArtVehicleClass,
            isAttached: slotFilled,
            assignedVehicleDetail: detailLine,
            rosterBatterySummary: batterySummary,
            assignedFleetIsSimulation: rosterAssignmentFleetIsSimulation(syn),
            autopilotStack: rosterAutopilotStack(for: syn),
            simulationImageBasenames: basenames,
            lifecycleStatus: rosterLifecycleStatus(for: syn),
            fleetDisplayShortID: fleetDisplayShortID,
            isSelectedForSetupMap: setupSelectedReservePoolTaskID == taskID && setupSelectedReservePoolSlotID == slot.id,
            onSelectForSetupMap: {
                toggleStagingReservePoolBerthMapSelection(taskID: taskID, slotID: slot.id)
            },
            onChooseVehicle: {
                guard taskEnabled else { return }
                guard !mcrReservePoolSlotMutationLocked(taskID: taskID, slotID: slot.id) else {
                    toastCenter.show("This berth is busy — wait for the reserve swap or preflight on it to finish.", style: .warning)
                    return
                }
                disarmMCSReservePoolHomePlacement()
                setupRostersSelectedMissionPointID = nil
                setupStagingMapSelectedTaskPathID = nil
                dismissSetupRostersMissionPointDrawerIfNeeded()
                clearAllSetupStagingSimDragOverlays()
                setupSelectedAssignmentId = nil
                setupSelectedReservePoolTaskID = taskID
                setupSelectedReservePoolSlotID = slot.id
                presentReservePoolVehiclePicker(taskID: taskID, slotID: slot.id)
            },
            onRemoveVehicle: {
                guard taskEnabled else { return }
                guard !mcrReservePoolSlotMutationLocked(taskID: taskID, slotID: slot.id) else {
                    toastCenter.show("This berth is busy — wait for the reserve swap or preflight on it to finish.", style: .warning)
                    return
                }
                clearReservePoolVehicleBinding(taskID: taskID, slotID: slot.id)
            },
            onCalibration: infoVehicleID == nil
                ? nil
                : {
                    presentRosterCalibrationSheet(for: syn)
                },
            simulateSystemOn: fleetLink.isSimulateEnabled,
            onPickAndAssignSim: fleetLink.isSimulateEnabled && taskEnabled && !slotFilled
                && !mcrReservePoolSlotMutationLocked(taskID: taskID, slotID: slot.id)
                ? { presentReservePoolSimPicker(taskID: taskID, slotID: slot.id) }
                : nil,
            showsWorkingOverlay: false,
            onOpenSettings: nil
        )
        .disabled(!taskEnabled)
    }

    private func syntheticMissionRunAssignment(from slot: MissionRunReservePoolSlot) -> MissionRunAssignment {
        MissionRunAssignment(
            id: slot.id,
            rosterDeviceId: slot.id,
            slotName: slot.label,
            attachedDevice: slot.attachedDevice,
            attachedFleetVehicleToken: slot.attachedFleetVehicleToken
        )
    }

    private func appendEmptyReservePoolSlot(taskID: UUID) {
        let ord = run.reservePool(forTaskID: taskID).entries.count + 1
        let slot = MissionRunReservePoolSlot(label: "Reserve \(ord)", attachedDevice: "")
        run.appendReservePoolSlot(slot, forTaskID: taskID)
        onUpdate(run)
    }

    private func removeReservePoolSlotFromTask(taskID: UUID, slotID: UUID) {
        guard !mcrReservePoolSlotMutationLocked(taskID: taskID, slotID: slotID) else {
            toastCenter.show("This berth is busy — wait for the reserve swap or preflight on it to finish.", style: .warning)
            return
        }
        _ = run.removeReservePoolSlot(id: slotID, forTaskID: taskID)
        onUpdate(run)
    }

    private func clearReservePoolVehicleBinding(taskID: UUID, slotID: UUID) {
        guard !mcrReservePoolSlotMutationLocked(taskID: taskID, slotID: slotID) else {
            toastCenter.show("This berth is busy — wait for the reserve swap or preflight on it to finish.", style: .warning)
            return
        }
        guard let cur = run.reservePool(forTaskID: taskID).entries.first(where: { $0.id == slotID }) else { return }
        let cleared = MissionRunReservePoolSlot(
            id: slotID,
            label: cur.label,
            attachedFleetVehicleToken: nil,
            attachedDevice: ""
        )
        _ = run.replaceReservePoolSlot(id: slotID, forTaskID: taskID, with: cleared)
        onUpdate(run)
    }

    private func applyFleetVehicleToReservePoolSlot(
        vehicle: MissionPickableFleetVehicle,
        taskID: UUID,
        slotID: UUID
    ) {
        guard !mcrReservePoolSlotMutationLocked(taskID: taskID, slotID: slotID) else {
            toastCenter.show("This berth is busy — wait for the reserve swap or preflight on it to finish.", style: .warning)
            return
        }
        guard let cur = run.reservePool(forTaskID: taskID).entries.first(where: { $0.id == slotID }) else { return }
        let next = MissionRunReservePoolSlot(
            id: slotID,
            label: cur.label,
            attachedFleetVehicleToken: vehicle.token.storageKey,
            attachedDevice: vehicle.title
        )
        _ = run.replaceReservePoolSlot(id: slotID, forTaskID: taskID, with: next)
        onUpdate(run)
    }

    private func presentReservePoolVehiclePicker(taskID: UUID, slotID: UUID) {
        guard !mcrReservePoolSlotMutationLocked(taskID: taskID, slotID: slotID) else {
            toastCenter.show("This berth is busy — wait for the reserve swap or preflight on it to finish.", style: .warning)
            return
        }
        let anim = rosterPickerSpring
        appDrawer.present(
            title: nil,
            preferredWidth: 420,
            scrimTapDismisses: true,
            animation: anim
        ) {
            MissionRosterVehiclePickerSidebar(
                vehicles: buildMissionPickableVehicles(fleetLink: fleetLink, sitl: sitl),
                rowIsEnabled: { reservePoolFleetPickDisabledReason($0, taskID: taskID, slotID: slotID) == nil },
                rowDisabledReason: { reservePoolFleetPickDisabledReason($0, taskID: taskID, slotID: slotID) },
                onSelect: { v in
                    applyFleetVehicleToReservePoolSlot(vehicle: v, taskID: taskID, slotID: slotID)
                    onUpdate(run)
                    appDrawer.dismiss(animation: anim)
                },
                onClose: {
                    appDrawer.dismiss(animation: anim)
                }
            )
        }
    }

    private func presentReservePoolSimPicker(taskID: UUID, slotID: UUID) {
        guard !mcrReservePoolSlotMutationLocked(taskID: taskID, slotID: slotID) else {
            toastCenter.show("This berth is busy — wait for the reserve swap or preflight on it to finish.", style: .warning)
            return
        }
        disarmMCSReservePoolHomePlacement()
        setupRostersSelectedMissionPointID = nil
        setupStagingMapSelectedTaskPathID = nil
        dismissSetupRostersMissionPointDrawerIfNeeded()
        clearAllSetupStagingSimDragOverlays()
        setupSelectedAssignmentId = nil
        setupSelectedReservePoolTaskID = taskID
        setupSelectedReservePoolSlotID = slotID
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
                    let beforeIDs = Set(sitl.instances.map(\.id))
                    sitl.spawn(
                        preset: preset,
                        platform: rosterSimSidebarSpawnPlatform,
                        defaults: generalSettings.simSpawnDefaults
                    )
                    guard let inst = sitl.instances.first(where: { !beforeIDs.contains($0.id) }) else {
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
                    if reservePoolFleetPickDisabledReason(pickable, taskID: taskID, slotID: slotID) == nil {
                        applyFleetVehicleToReservePoolSlot(vehicle: pickable, taskID: taskID, slotID: slotID)
                        appDrawer.dismiss(animation: anim)
                    } else {
                        appDrawer.dismiss(animation: anim)
                    }
                },
                onClose: {
                    appDrawer.dismiss(animation: anim)
                }
            )
        }
    }

    private func reservePoolFleetPickDisabledReason(
        _ vehicle: MissionPickableFleetVehicle,
        taskID: UUID,
        slotID: UUID
    ) -> String? {
        if mcrReservePoolSlotMutationLocked(taskID: taskID, slotID: slotID) {
            return "This berth is busy (reserve swap or preflight in progress)"
        }
        let key = vehicle.token.storageKey
        let pool = run.reservePool(forTaskID: taskID)
        if pool.entries.first(where: { $0.id == slotID })?.attachedFleetVehicleToken == key { return nil }
        if controlStore.isFleetVehicleLockedByOtherLiveMission(tokenKey: key, excludingRunId: run.id) {
            return "In use by another live mission"
        }
        if run.assignments.contains(where: { $0.attachedFleetVehicleToken == key }) {
            return "Already assigned to a roster slot on this run"
        }
        for (tid, p) in run.reservePoolByTaskID {
            for e in p.entries {
                if tid == taskID && e.id == slotID { continue }
                if e.attachedFleetVehicleToken == key { return "Already used in the reserve pool" }
            }
        }
        return nil
    }

    private func reservePoolDuplicateFleetBindingWarning(taskID: UUID, slot: MissionRunReservePoolSlot) -> String? {
        guard let key = slot.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        for (tid, p) in run.reservePoolByTaskID {
            for e in p.entries {
                if tid == taskID && e.id == slot.id { continue }
                if e.attachedFleetVehicleToken == key { return "This vehicle is bound more than once on this run." }
            }
        }
        if run.assignments.contains(where: { $0.attachedFleetVehicleToken == key }) {
            return "This vehicle is bound more than once on this run."
        }
        return nil
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
            guard slotFilled, telemetryVehicleID(for: a) != nil else { return nil }
            return assignmentFleetDisplayShortID(assignment: a, rosterDevice: device)
        }()
        let deviceArtVehicleClass: FleetVehicleType = {
            guard slotFilled,
                  let vid = telemetryVehicleID(for: a),
                  let model = fleetLink.vehicleModel(forVehicleID: vid)
            else { return rosterDeviceClass }
            return model.data.vehicleType
        }()
        let missionLiveShowsSlotBadge = run.status == .running || run.status == .paused || run.status == .recovery
        let mergedSlotDisplay = MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: a.effectiveSlotLifecycleLanes)
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
                disarmMCSReservePoolHomePlacement()
                setupRostersSelectedMissionPointID = nil
                setupStagingMapSelectedTaskPathID = nil
                dismissSetupRostersMissionPointDrawerIfNeeded()
                clearAllSetupStagingSimDragOverlays()
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
            },
            missionControlShowsSlotStateBadge: missionLiveShowsSlotBadge,
            missionControlMergedSlotDisplayState: mergedSlotDisplay
        )
    }

    /// Whether to show the floating-reserve swap control on an **attached** roster row, and operator copy when it is disabled.
    private func floatingReserveSwapAffordance(
        assignment: MissionRunAssignment,
        mission: Mission?,
        taskID: UUID?
    ) -> (showBlockedControl: Bool, enabled: Bool, blockedReason: String) {
        guard assignment.hasFleetOrLegacyAssignment,
              mission != nil,
              let tid = taskID ?? assignment.taskId
        else {
            return (false, false, "")
        }
        if !MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: run.sessionPhase) {
            return (true, false, MissionRunReserveSwapOperatorCopy.toastReserveSwapBlockedSessionPhase)
        }
        let classOK = run.availableReservePoolEntries(
            forTaskID: tid,
            classCompatibleWithAssignmentId: assignment.id
        )
        if !classOK.isEmpty {
            return (false, true, "")
        }
        let base = run.availableReservePoolEntries(forTaskID: tid, classCompatibleWithAssignmentId: nil)
        if base.isEmpty {
            return (true, false, "No eligible floating reserve on this task.")
        }
        let expected = run.expectedFleetVehicleClassForRosterAssignment(assignment)
        return (
            true,
            false,
            "No floating reserve matches this slot's template class (\(expected.classCode) · \(expected.displayName))."
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
        removeSetupStagingSimDragOverlay(for: assignmentId)
    }

    private func clearFleetVehicle(assignmentId: UUID) {
        guard let idx = run.assignments.firstIndex(where: { $0.id == assignmentId }) else { return }
        run.assignments[idx].attachedFleetVehicleToken = nil
        run.assignments[idx].attachedDevice = ""
        removeSetupStagingSimDragOverlay(for: assignmentId)
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
