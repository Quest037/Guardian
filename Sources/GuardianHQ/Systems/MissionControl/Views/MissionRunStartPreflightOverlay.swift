import SwiftUI

/// Full-bleed Mission Control setup overlay: arm-probe every roster slot (grouped by task), triage failures, auto-start on full pass.
struct MissionRunStartPreflightOverlay: View {
    @ObservedObject var run: MissionRunEnvironment
    let mission: Mission?
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let controlStore: MissionControlStore
    let contentSpring: Animation
    let resolveTelemetryVehicleID: (MissionRunAssignment) -> String?
    /// MCS staging-map drag poses (merged with any pending launch overrides before geofence gate + arm probes).
    let launchCoordinateOverrides: [UUID: RouteCoordinate]
    let onSuccess: () -> Void
    let onAbandonWithoutStart: () -> Void
    let onDismiss: () -> Void
    let onOpenVehicleInspector: (MissionRunAssignment) -> Void
    let onSwapVehicle: (UUID) -> Void
    @Binding var postVehiclePickPreflightAssignmentId: UUID?

    @Environment(\.colorScheme) private var colorScheme

    @State private var rowByAssignmentID: [UUID: MissionRunPreflightSlotRow] = [:]
    @State private var initialSweepRunning = false
    @State private var activeRetryAssignmentIDs: Set<UUID> = []
    /// Slots covered by header **Retry Failed** (each card shows a blocking spinner until bulk finishes).
    @State private var bulkRetryFailedCoveringAssignmentIDs: Set<UUID> = []
    @State private var vehicleIDsArmedDuringProbe: [String] = []
    /// Short delay before roster probes start: show a blocking spinner so the overlay never feels idle.
    @State private var preflightGateDelayActive = true
    /// When true, arm probes are skipped until every slot is outside exclusion geofences.
    @State private var startRunGeofenceBlocked = false

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var effectiveMission: Mission? { mission ?? run.template }

    private var sections: [MissionRunPreflightUIProbeSection] {
        run.orderedStartRunPreflightProbeSections(mission: effectiveMission)
    }

    private var flattenedTargets: [MissionRunPreflightUITarget] {
        sections.flatMap(\.targets)
    }

    private var allRequiredPassed: Bool {
        guard !flattenedTargets.isEmpty else { return false }
        for t in flattenedTargets {
            guard let row = rowByAssignmentID[t.assignment.id], row.phase == .passed else { return false }
        }
        return true
    }

    private var hasFailedSlots: Bool {
        flattenedTargets.contains { rowByAssignmentID[$0.assignment.id]?.phase == .failed }
    }

    private var retryAllFailedEnabled: Bool {
        !preflightGateDelayActive
            && !initialSweepRunning
            && activeRetryAssignmentIDs.isEmpty
            && bulkRetryFailedCoveringAssignmentIDs.isEmpty
            && hasFailedSlots
            && !allRequiredPassed
    }

    private var closeEnabled: Bool {
        !preflightGateDelayActive
            && !initialSweepRunning
            && activeRetryAssignmentIDs.isEmpty
            && bulkRetryFailedCoveringAssignmentIDs.isEmpty
            && !allRequiredPassed
    }

    private var footerSummary: (icon: String, title: String, tint: Color)? {
        if startRunGeofenceBlocked {
            return (
                "xmark.octagon.fill",
                "Start run blocked — move vehicles out of exclusion geofences, then retry.",
                GuardianSemanticColors.dangerStroke
            )
        }
        if initialSweepRunning || !activeRetryAssignmentIDs.isEmpty || !bulkRetryFailedCoveringAssignmentIDs.isEmpty {
            return ("ellipsis.circle", "Running arm checks on roster vehicles", GuardianSemanticColors.infoForeground)
        }
        if allRequiredPassed {
            return ("checkmark.circle.fill", "All checks passed — starting run…", GuardianSemanticColors.successStroke)
        }
        if flattenedTargets.contains(where: { rowByAssignmentID[$0.assignment.id]?.phase == .failed }) {
            return ("exclamationmark.triangle.fill", "One or more vehicles failed — triage below, then retry or swap.", GuardianSemanticColors.warningStroke)
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.overlayScrim
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                preflightChromeHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                        if let footerSummary {
                            HStack(spacing: GuardianSpacing.sm) {
                                Image(systemName: footerSummary.icon)
                                    .foregroundStyle(footerSummary.tint)
                                Text(footerSummary.title)
                                    .font(GuardianTypography.font(.denseCaption12Medium))
                                    .foregroundStyle(theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.bottom, GuardianSpacing.xxs)
                        }

                        ForEach(sections) { section in
                            taskSectionView(section)
                        }
                    }
                    .padding(.horizontal, GuardianCardLayout.defaultBodyPadding)
                    .padding(.vertical, GuardianSpacing.denseGutter)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(theme.backgroundRaised)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay {
                if preflightGateDelayActive {
                    preflightGateDelayOverlay
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            preflightGateDelayActive = true
            // Let the overlay paint before arming probes (telemetry subscription work can lag first frame).
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.2)) {
                preflightGateDelayActive = false
            }
            seedRowsPending()
            await runInitialSweep()
        }
        .onChange(of: postVehiclePickPreflightAssignmentId) { newValue in
            guard let aid = newValue else { return }
            postVehiclePickPreflightAssignmentId = nil
            Task { await probeSingleAssignment(assignmentId: aid) }
        }
    }

    private var preflightGateDelayOverlay: some View {
        ZStack {
            theme.backgroundRaised.opacity(colorScheme == .dark ? 0.78 : 0.86)
            VStack(spacing: GuardianSpacing.md) {
                ProgressView()
                    .controlSize(.regular)
                Text("Preparing roster checks.")
                    .font(GuardianTypography.font(.denseCaption12Medium))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(GuardianSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing roster checks")
    }

    private var preflightChromeHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                    Text("Mission Preflight")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text("Roster arm checks before start. Floating reserves are checked when you swap one in during the run.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: GuardianSpacing.xs) {
                    if hasFailedSlots, !allRequiredPassed {
                        GuardianThemedButton(
                            title: "Retry Failed",
                            accent: .primary,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            isEnabled: retryAllFailedEnabled,
                            action: {
                                Task { await retryAllFailedAssignments() }
                            }
                        )
                    }

                    GuardianThemedButton(
                        title: "Close",
                        accent: .danger,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        isEnabled: closeEnabled,
                        action: {
                            disarmPreflightArmsThenAbandon()
                            withAnimation(contentSpring) {
                                onDismiss()
                            }
                            onAbandonWithoutStart()
                        }
                    )
                    .keyboardShortcut(.cancelAction)
                }
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

    private func taskSectionView(_ section: MissionRunPreflightUIProbeSection) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            Text(section.title)
                .font(GuardianTypography.font(.subsectionTitleSemibold))
                .foregroundStyle(section.titleMuted ? theme.textSecondary : theme.textPrimary)
                .lineLimit(2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: GuardianSpacing.sm) {
                    ForEach(section.targets, id: \.assignment.id) { target in
                        preflightVehicleCard(target: target)
                    }
                }
                .padding(.vertical, GuardianSpacing.xxs)
            }
        }
    }

    private func preflightVehicleCard(target: MissionRunPreflightUITarget) -> some View {
        let assignment = target.assignment
        let row = rowByAssignmentID[assignment.id]
            ?? MissionRunPreflightSlotRow(
                identity: target.identity,
                slotName: target.displayTitle,
                phase: .pending,
                detail: "Waiting…"
            )
        let device = effectiveMission?.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId })
        let subtitle = rosterRoleSubtitle(device)
        let vehicleClass = deviceArtVehicleClass(assignment: assignment, rosterDeviceClass: device?.vehicleClass ?? .unknown)
        let basenames = simulationImageBasenamesForAssignment(assignment, sitl: sitl)
        let shortID = fleetBracketLabel(assignment: assignment, device: device)
        let borderTint = preflightCardBorderTint(for: row.phase)
        let cardRetrySpinning = assignmentCardShowsRetrySpinner(assignmentId: assignment.id)

        return ZStack {
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                HStack(alignment: .top, spacing: GuardianSpacing.sm) {
                    vehicleThumbnail(vClass: vehicleClass, basenames: basenames)
                        .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                        Text(assignment.slotName)
                            .font(GuardianTypography.font(.inlineNoticeTitle))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2)
                        Text(subtitle)
                            .font(GuardianTypography.font(.denseCaption10Regular))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                        Text(shortID)
                            .font(GuardianTypography.font(.telemetryMono10Semibold))
                            .foregroundStyle(theme.textPrimary.opacity(0.92))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(row.detail)
                    .font(GuardianTypography.font(.telemetryMono10Regular))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if row.phase == .failed, let advice = row.remediationAdvice {
                    PreflightProbeRemediationBlock(advice: advice)
                }

                HStack(spacing: GuardianSpacing.xs) {
                    GuardianThemedButton(
                        title: "Retry",
                        accent: .primary,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        isEnabled: !initialSweepRunning
                            && !activeRetryAssignmentIDs.contains(assignment.id)
                            && !bulkRetryFailedCoveringAssignmentIDs.contains(assignment.id),
                        action: {
                            Task { await probeSingleAssignment(assignmentId: assignment.id) }
                        }
                    )

                    GuardianThemedButton(
                        title: "Swap",
                        accent: .neutral,
                        surface: .outline,
                        size: .small,
                        shape: .cornered,
                        isEnabled: !initialSweepRunning && !cardRetrySpinning,
                        action: { onSwapVehicle(assignment.id) }
                    )

                    if resolveTelemetryVehicleID(assignment) != nil {
                        GuardianThemedButton(
                            title: "Inspector",
                            accent: .neutral,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            isEnabled: !initialSweepRunning && !cardRetrySpinning,
                            action: { onOpenVehicleInspector(assignment) }
                        )
                    }
                }
            }
            .padding(GuardianSpacing.cardBodyInset)
            .allowsHitTesting(!cardRetrySpinning)

            if cardRetrySpinning {
                ZStack {
                    RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.38))
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous))
                .allowsHitTesting(true)
                .zIndex(1)
            }
        }
        .frame(width: 220, alignment: .topLeading)
        .background(theme.backgroundElevated.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                .strokeBorder(borderTint, lineWidth: 2)
        )
    }

    private func assignmentCardShowsRetrySpinner(assignmentId: UUID) -> Bool {
        activeRetryAssignmentIDs.contains(assignmentId)
            || bulkRetryFailedCoveringAssignmentIDs.contains(assignmentId)
    }

    private func rosterRoleSubtitle(_ device: RosterDevice?) -> String {
        guard let device else { return "—" }
        return "\(device.slot.rawValue) · \(device.behaviorRoleID)"
    }

    private func deviceArtVehicleClass(assignment: MissionRunAssignment, rosterDeviceClass: FleetVehicleType) -> FleetVehicleType {
        guard assignment.hasFleetOrLegacyAssignment,
              let vid = resolveTelemetryVehicleID(assignment),
              let model = fleetLink.vehicleModel(forVehicleID: vid)
        else { return rosterDeviceClass }
        return model.data.vehicleType
    }

    private func fleetBracketLabel(assignment: MissionRunAssignment, device: RosterDevice?) -> String {
        guard let vid = resolveTelemetryVehicleID(assignment) else { return "[—]" }
        if let model = fleetLink.vehicleModel(forVehicleID: vid) {
            return "[\(model.displayShortID)]"
        }
        let rosterDeviceClass = device?.vehicleClass ?? .unknown
        if let key = assignment.attachedFleetVehicleToken,
           let token = FleetMissionVehicleToken(storageKey: key),
           case .sitl(let uuid) = token,
           let inst = sitl.instances.first(where: { $0.id == uuid }) {
            return "[\(inst.preset.fleetVehicleType.classCode):\(inst.mavlinkSystemID)]"
        }
        let prefix = "sysid:"
        if vid.hasPrefix(prefix), let n = Int(vid.dropFirst(prefix.count)) {
            return "[\(rosterDeviceClass.classCode):\(n)]"
        }
        let tail = vid.split(separator: ":").last.map(String.init) ?? vid
        return "[\(rosterDeviceClass.classCode):\(tail)]"
    }

    private func vehicleThumbnail(vClass: FleetVehicleType, basenames: [String]?) -> some View {
        let names: [String] = {
            if let basenames, !basenames.isEmpty { return basenames }
            return vClass.defaultSimulationDeviceImageBasenames
        }()
        return ZStack {
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
            SimulationDeviceThumbnail(imageBasenames: names)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(GuardianSpacing.titleStackTight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func preflightCardBorderTint(for phase: MissionRunPreflightSlotPhase) -> Color {
        switch phase {
        case .pending: return theme.borderSubtle
        case .testing: return GuardianSemanticColors.infoForeground.opacity(0.55)
        case .passed: return GuardianSemanticColors.successStroke.opacity(0.75)
        case .failed: return GuardianSemanticColors.dangerStroke.opacity(0.85)
        }
    }

    private func seedRowsPending() {
        var next: [UUID: MissionRunPreflightSlotRow] = [:]
        for t in flattenedTargets {
            next[t.assignment.id] = MissionRunPreflightSlotRow(
                identity: t.identity,
                slotName: t.displayTitle,
                phase: .pending,
                detail: "Waiting…"
            )
        }
        rowByAssignmentID = next
    }

    /// Returns `true` when start run must not proceed (violations seeded on affected slots).
    @MainActor
    private func applyStartRunExclusionGeofenceGate() -> Bool {
        guard let mission = effectiveMission else {
            startRunGeofenceBlocked = false
            return false
        }
        let violations = MissionControlStartRunGeofenceValidationUtilities.exclusionViolations(
            run: run,
            mission: mission,
            fleetLink: fleetLink,
            launchCoordinateOverrides: launchCoordinateOverrides,
            resolveVehicleID: resolveTelemetryVehicleID
        )
        guard !violations.isEmpty else {
            startRunGeofenceBlocked = false
            return false
        }
        startRunGeofenceBlocked = true
        let violationIDs = Set(violations.map(\.assignmentID))
        var next = rowByAssignmentID
        for violation in violations {
            let identity = MissionRunPreflightSlotIdentity.rosterAssignment(violation.assignmentID)
            next[violation.assignmentID] = MissionRunPreflightSlotRow(
                identity: identity,
                slotName: violation.slotDisplayName,
                phase: .failed,
                detail: MissionControlStartRunGeofenceValidationUtilities.failureDetail(for: violation),
                remediationAdvice: MissionControlStartRunGeofenceValidationUtilities.startRunInsideExclusionRemediation
            )
        }
        for target in flattenedTargets where !violationIDs.contains(target.assignment.id) {
            next[target.assignment.id] = MissionRunPreflightSlotRow(
                identity: target.identity,
                slotName: target.displayTitle,
                phase: .pending,
                detail: "Waiting — resolve exclusion conflicts on other slots first."
            )
        }
        rowByAssignmentID = next
        return true
    }

    @MainActor
    private func runInitialSweep() async {
        if applyStartRunExclusionGeofenceGate() { return }
        initialSweepRunning = true
        defer { initialSweepRunning = false }

        for t in flattenedTargets {
            guard let assignment = run.assignments.first(where: { $0.id == t.assignment.id }) else { continue }
            await applyProbeResult(assignment: assignment, identity: t.identity)
        }

        if allRequiredPassed {
            onSuccess()
            withAnimation(contentSpring) {
                onDismiss()
            }
        }
    }

    @MainActor
    private func probeSingleAssignment(assignmentId: UUID) async {
        guard let assignment = run.assignments.first(where: { $0.id == assignmentId }) else { return }
        if applyStartRunExclusionGeofenceGate() { return }
        activeRetryAssignmentIDs.insert(assignmentId)
        defer { activeRetryAssignmentIDs.remove(assignmentId) }
        let identity = MissionRunPreflightSlotIdentity.rosterAssignment(assignmentId)
        await applyProbeResult(assignment: assignment, identity: identity)
        if allRequiredPassed {
            onSuccess()
            withAnimation(contentSpring) {
                onDismiss()
            }
        }
    }

    @MainActor
    private func retryAllFailedAssignments() async {
        if applyStartRunExclusionGeofenceGate() { return }
        let failedIds = flattenedTargets.compactMap { target -> UUID? in
            guard rowByAssignmentID[target.assignment.id]?.phase == .failed else { return nil }
            return target.assignment.id
        }
        guard !failedIds.isEmpty else { return }

        bulkRetryFailedCoveringAssignmentIDs = Set(failedIds)
        defer { bulkRetryFailedCoveringAssignmentIDs.removeAll() }

        for id in failedIds {
            guard let assignment = run.assignments.first(where: { $0.id == id }) else { continue }
            let identity = MissionRunPreflightSlotIdentity.rosterAssignment(id)
            await applyProbeResult(assignment: assignment, identity: identity)
            if allRequiredPassed {
                onSuccess()
                withAnimation(contentSpring) {
                    onDismiss()
                }
                return
            }
        }
    }

    @MainActor
    private func applyProbeResult(assignment: MissionRunAssignment, identity: MissionRunPreflightSlotIdentity) async {
        let outcome = await controlStore.runStartRunPreflightProbeForTarget(
            identity: identity,
            displayTitle: assignment.slotName,
            assignment: assignment,
            fleetLink: fleetLink,
            sitl: sitl
        )
        rowByAssignmentID[assignment.id] = outcome.row
        if let vid = outcome.vehicleIDArmedDuringProbe {
            if !vehicleIDsArmedDuringProbe.contains(vid) {
                vehicleIDsArmedDuringProbe.append(vid)
            }
        }
    }

    private func disarmPreflightArmsThenAbandon() {
        for vehicleID in vehicleIDsArmedDuringProbe {
            _ = fleetLink.executeVehicleCommand(
                vehicleID: vehicleID,
                command: .disarm,
                source: "missionControl.preflightAbandon",
                category: .missionControl,
                onCommandOutcome: nil
            )
        }
        vehicleIDsArmedDuringProbe = []
    }
}
