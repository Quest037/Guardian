import AppKit
import SwiftUI

/// Reusable calibration canvas — **diagram uses the top 50%** of the tab (image + leader lines + spacer below),
/// with a **bottom inspector sheet** in a `ZStack` (half height when collapsed, full height when open). The
/// sheet header carries the system title and status line so the body is not a duplicate title card. Chevron
/// compact down collapses to half height (disabled while a procedure runs); chevron compact up expands again.
/// Spring animation matches Mission Control live Tasks triage. Preflight banner stays above the stack.
struct VehicleCalibrationView: View {
    let vehicle: FleetVehicleModel
    /// Inert embeds pass a dedicated instance (never started); the Vehicle Inspector modal passes a shared controller for **Start / Stop** in the modal header and inter-step **Wait / Continue** in the active panel.
    @ObservedObject private var guidedWizard: VehicleInspectorGuidedWizardController
    /// When set (e.g. from ``VehicleCalibrationModal`` / ``LiveVehicleCalibrationView``), the calibration
    /// tab resolves directory recipes per selected system and shows one **Run** launcher per recipe,
    /// wired to ``FleetRecipeRunner``.
    let recipeFleetLink: FleetLinkService?
    /// When `true`, recipes whose ``FleetRecipeRiskTier`` is not ``safeInLiveMission`` cannot be
    /// started from the inspector (same live-mission gate as the modal **Recipe locked** header);
    /// ``FleetRecipeRunner`` still enforces the gate on dispatch.
    let isLiveMissionRecipeLocked: Bool
    /// Banner block rendered above the canvas (preflight running / last result, or nothing). Pass an
    /// `EmptyView()` (or omit) for views that do not run preflight (e.g. simple inline embeds).
    @ViewBuilder var preflightBanner: () -> AnyView

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var fleetRecipeRunner = FleetRecipeRunner.shared
    @State private var selectedSystemID: FleetCalibrationSystemID?

    /// Bottom inspector sheet: half height when collapsed, full height when a marker is selected or a recipe needs focus.
    @State private var calibrationInspectorSheetExpanded = false

    /// Avoid mounting ``VehicleInspectorProcedureProgressBanner`` for very short runs (sub-second flash);
    /// the Run row spinner + toast still reflect progress immediately.
    @State private var debouncedWizardProcedureBanner: FleetRecipeWizardProgressSnapshot?
    @State private var wizardProcedureBannerDebounceTask: Task<Void, Never>?

    private enum WizardInspectorChrome {
        static let procedureBannerDebounceNanoseconds: UInt64 = 320_000_000
    }

    init(
        vehicle: FleetVehicleModel,
        guidedWizard: VehicleInspectorGuidedWizardController,
        recipeFleetLink: FleetLinkService? = nil,
        isLiveMissionRecipeLocked: Bool = false,
        @ViewBuilder preflightBanner: @escaping () -> AnyView = { AnyView(EmptyView()) }
    ) {
        self.vehicle = vehicle
        self._guidedWizard = ObservedObject(wrappedValue: guidedWizard)
        self.recipeFleetLink = recipeFleetLink
        self.isLiveMissionRecipeLocked = isLiveMissionRecipeLocked
        self.preflightBanner = preflightBanner
    }

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var items: [FleetCalibrationItem] {
        calibrationItemsMergingLiveInspectorRun(
            base: vehicle.collections.calibration.items,
            vehicleID: vehicle.data.vehicleID
        )
    }

    /// Telemetry-backed calibration items, with the **active** Vehicle Inspector catalogue recipe’s
    /// system marker merged to `.warning` and live step copy while ``FleetRecipeRunner`` has a run.
    private func calibrationItemsMergingLiveInspectorRun(
        base: [FleetCalibrationItem],
        vehicleID: String
    ) -> [FleetCalibrationItem] {
        guard fleetRecipeRunner.hasActiveRun(forVehicleID: vehicleID),
              let topName = fleetRecipeRunner.activeTopLevelRecipeName(forVehicleID: vehicleID),
              let systemID = FleetTelemetryFieldCatalog.calibrationSystemID(forTelemetryDirectoryRecipe: topName),
              let idx = base.firstIndex(where: { $0.id == systemID })
        else {
            return base
        }

        let progress = fleetRecipeRunner.wizardProgressByVehicleID[vehicleID]
        let title = progress?.recipeHumanTitle.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activity = progress?.activityLine.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let message: String = {
            if !title.isEmpty, !activity.isEmpty { return "\(title): \(activity)" }
            if !title.isEmpty { return title }
            if !activity.isEmpty { return activity }
            return "Procedure in progress…"
        }()

        let stepDetail = progress.map { "Step \($0.stepOrdinal) of \($0.stepTotal)" }

        var out = base
        let original = out[idx]
        out[idx] = FleetCalibrationItem(
            id: original.id,
            status: .warning,
            message: message,
            technicalDetail: stepDetail,
            remediationAdvice: nil
        )
        return out
    }

    private var selectedItem: FleetCalibrationItem? {
        selectedSystemID.flatMap { id in items.first { $0.id == id } }
    }

    /// Same spring recipe as Mission Control live **Tasks** triage overlays (`MissionControlSetupView`).
    private var calibrationInspectorSheetSpring: Animation {
        .spring(response: 0.42, dampingFraction: 0.86)
    }

    private var calibrationRecipeProcedureActive: Bool {
        let vid = vehicle.data.vehicleID
        return fleetRecipeRunner.hasActiveRun(forVehicleID: vid)
            || fleetRecipeRunner.wizardEscalationByVehicleID[vid] != nil
    }

    /// When the sheet is fully expanded with a selection, the map sits underneath and should not steal taps.
    private var calibrationDiagramAllowsHitTesting: Bool {
        let sheetExpandedLike = calibrationInspectorSheetExpanded || guidedWizard.isActive
        return !(sheetExpandedLike && selectedSystemID != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
            preflightBanner()
            GeometryReader { geo in
                let totalH = max(geo.size.height, 1)
                let totalW = geo.size.width
                let diagramBandH = totalH * 0.5
                /// Breathing room between diagram and action panel when collapsed (`GuardianSpacing.denseGutter` = 10pt).
                let diagramSheetGutter = GuardianSpacing.denseGutter
                let collapsedSheetH = max(totalH * 0.5 - diagramSheetGutter, 140)
                let sheetExpandedLike = calibrationInspectorSheetExpanded || guidedWizard.isActive
                let sheetH = sheetExpandedLike ? totalH : collapsedSheetH
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        calibrationDiagramContent(size: CGSize(width: totalW, height: diagramBandH))
                            .frame(width: totalW, height: diagramBandH, alignment: .top)
                        Spacer(minLength: 0)
                            .frame(width: totalW, height: diagramBandH)
                    }
                    .frame(width: totalW, height: totalH, alignment: .top)
                    .allowsHitTesting(calibrationDiagramAllowsHitTesting)

                    calibrationInspectorBottomSheet(totalWidth: totalW, sheetHeight: sheetH)
                }
                .animation(calibrationInspectorSheetSpring, value: calibrationInspectorSheetExpanded)
                .animation(calibrationInspectorSheetSpring, value: guidedWizard.isActive)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if calibrationRecipeProcedureActive {
                calibrationInspectorSheetExpanded = true
            }
        }
        .onChange(of: guidedWizard.currentSystemID) { newID in
            if let newID {
                selectedSystemID = newID
                withAnimation(calibrationInspectorSheetSpring) {
                    calibrationInspectorSheetExpanded = true
                }
            }
        }
        .onChange(of: guidedWizard.isActive) { active in
            if active {
                if let id = guidedWizard.currentSystemID {
                    selectedSystemID = id
                }
                withAnimation(calibrationInspectorSheetSpring) {
                    calibrationInspectorSheetExpanded = true
                }
            }
        }
        .onChange(of: selectedSystemID) { newValue in
            wizardProcedureBannerDebounceTask?.cancel()
            wizardProcedureBannerDebounceTask = nil
            debouncedWizardProcedureBanner = nil
            if newValue != nil {
                withAnimation(calibrationInspectorSheetSpring) {
                    calibrationInspectorSheetExpanded = true
                }
            }
        }
        .onChange(of: calibrationRecipeProcedureActive) { active in
            if active {
                withAnimation(calibrationInspectorSheetSpring) {
                    calibrationInspectorSheetExpanded = true
                }
            }
        }
    }

    private func collapseCalibrationInspectorSheetIfAllowed() {
        guard !calibrationRecipeProcedureActive else { return }
        guard !guidedWizard.isActive else { return }
        withAnimation(calibrationInspectorSheetSpring) {
            calibrationInspectorSheetExpanded = false
        }
    }

    private func expandCalibrationInspectorSheet() {
        withAnimation(calibrationInspectorSheetSpring) {
            calibrationInspectorSheetExpanded = true
        }
    }

    private func syncDebouncedWizardProcedureBanner(vehicleID: String, latest: FleetRecipeWizardProgressSnapshot?) {
        wizardProcedureBannerDebounceTask?.cancel()
        wizardProcedureBannerDebounceTask = nil

        guard let latest else {
            debouncedWizardProcedureBanner = nil
            return
        }

        if let shown = debouncedWizardProcedureBanner, shown.runID == latest.runID {
            debouncedWizardProcedureBanner = latest
            return
        }

        debouncedWizardProcedureBanner = nil
        let expectedRunID = latest.runID
        wizardProcedureBannerDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: WizardInspectorChrome.procedureBannerDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            guard let current = FleetRecipeRunner.shared.wizardProgressByVehicleID[vehicleID],
                  current.runID == expectedRunID else { return }
            debouncedWizardProcedureBanner = current
        }
    }

    private func calibrationDiagramContent(size: CGSize) -> some View {
        let imageSide = min(size.width * 0.59, size.height * 0.80)
        let imageRect = CGRect(
            x: (size.width - imageSide) / 2,
            y: (size.height - imageSide) / 2,
            width: imageSide,
            height: imageSide
        )

        let vid = vehicle.data.vehicleID
        let wizardStep = fleetRecipeRunner.wizardProgressByVehicleID[vid]?.stepOrdinal

        return ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(theme.backgroundRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(theme.borderSubtle.opacity(0.8), lineWidth: 1)
                )

            SimulationDeviceThumbnail(imageBasenames: vehicle.data.vehicleType.defaultSimulationDeviceImageBasenames)
                .frame(width: imageSide, height: imageSide)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .guardianDropShadow(GuardianElevation.inspectorPanel)
                .position(x: imageRect.midX, y: imageRect.midY)

            if items.isEmpty {
                emptyCalibrationOverlay
            } else {
                ForEach(items) { item in
                    markerLine(for: item, imageRect: imageRect, size: size)
                }

                ForEach(items) { item in
                    markerLabel(for: item, size: size)
                }
            }
        }
        .animation(calibrationInspectorSheetSpring, value: wizardStep)
    }

    private func calibrationInspectorBottomSheet(totalWidth: CGFloat, sheetHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            calibrationInspectorSheetChrome
            Divider()
            calibrationInspectorSheetBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: totalWidth, height: sheetHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.backgroundElevated)
                .shadow(color: theme.overlayScrim.opacity(0.22), radius: 10, y: -2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.borderSubtle.opacity(0.85), lineWidth: 1)
        )
    }

    private var calibrationInspectorSheetChrome: some View {
        let title: String = {
            if let id = selectedSystemID,
               let item = items.first(where: { $0.id == id }) {
                return FleetCalibrationExtensionRegistry.definition(for: item.id).title
            }
            return "Calibration"
        }()

        return HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
            if let item = selectedItem {
                Image(systemName: FleetCalibrationExtensionRegistry.definition(for: item.id).iconSystemName)
                    .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                    .foregroundStyle(calibrationColor(for: item.status))
            }

            HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xsTight) {
                Text(title)
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)

                if let item = selectedItem {
                    Text(item.message)
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(calibrationColor(for: item.status))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if calibrationInspectorSheetExpanded || guidedWizard.isActive {
                Button {
                    collapseCalibrationInspectorSheetIfAllowed()
                } label: {
                    Image(systemName: "chevron.compact.down")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(minWidth: GuardianChromeSize.small.controlOuterHeight, minHeight: GuardianChromeSize.small.controlOuterHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .guardianPointerOnHover()
                .disabled(calibrationRecipeProcedureActive || guidedWizard.isActive)
                .opacity((calibrationRecipeProcedureActive || guidedWizard.isActive) ? 0.38 : 1)
                .help({
                    if guidedWizard.isActive { return "Stop the guided wizard in the header to hide the panel" }
                    if calibrationRecipeProcedureActive { return "Finish or cancel the procedure before hiding the panel" }
                    return "Show calibration map"
                }())
                .accessibilityLabel("Show calibration map")
            } else if selectedSystemID != nil {
                Button {
                    expandCalibrationInspectorSheet()
                } label: {
                    Image(systemName: "chevron.compact.up")
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(minWidth: GuardianChromeSize.small.controlOuterHeight, minHeight: GuardianChromeSize.small.controlOuterHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .guardianPointerOnHover()
                .help("Expand details")
                .accessibilityLabel("Expand details")
            }
        }
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .padding(.vertical, GuardianSpacing.sm)
    }

    @ViewBuilder
    private var calibrationInspectorSheetBody: some View {
        if let selectedItem {
            selectedInspectorScrollContent(for: selectedItem)
        } else {
            unselectedInspectorScrollBody
        }
    }

    private var emptyCalibrationOverlay: some View {
        VStack(spacing: GuardianSpacing.xs) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(GuardianTypography.relativeFixed(size: 24, weight: .semibold, relativeTo: .title2))
                .foregroundStyle(theme.textTertiary)
            Text("No calibration telemetry yet")
                .font(GuardianTypography.font(.subsectionTitleSemibold))
                .foregroundStyle(theme.textPrimary)
            Text("Calibration markers appear as the vehicle reports health and sensor data.")
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textTertiary)
        }
        .multilineTextAlignment(.center)
        .padding(GuardianSpacing.sectionStack)
        .background(theme.backgroundElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
    }

    private func markerLine(for item: FleetCalibrationItem, imageRect: CGRect, size: CGSize) -> some View {
        let anchor = FleetCalibrationAnchorCatalog.anchor(for: item.id, vehicleType: vehicle.data.vehicleType)
        let start = CGPoint(
            x: imageRect.minX + (imageRect.width * anchor.imageAnchor.x),
            y: imageRect.minY + (imageRect.height * anchor.imageAnchor.y)
        )
        let end = CGPoint(x: size.width * anchor.labelPoint.x, y: size.height * anchor.labelPoint.y)
        let selected = selectedSystemID == item.id

        return ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(calibrationColor(for: item.status).opacity(selected ? 0.96 : 0.72), lineWidth: selected ? 3 : 2)

            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(Color.clear, lineWidth: 16)
            .contentShape(Path { path in
                path.move(to: start)
                path.addLine(to: end)
            })
            .onTapGesture {
                selectedSystemID = item.id
            }
            .cursorPointer()

            Circle()
                .fill(calibrationColor(for: item.status))
                .frame(width: selected ? 10 : 8, height: selected ? 10 : 8)
                .position(start)
        }
    }

    private func markerLabel(for item: FleetCalibrationItem, size: CGSize) -> some View {
        let definition = FleetCalibrationExtensionRegistry.definition(for: item.id)
        let anchor = FleetCalibrationAnchorCatalog.anchor(for: item.id, vehicleType: vehicle.data.vehicleType)
        let selected = selectedSystemID == item.id

        return Button {
            selectedSystemID = item.id
        } label: {
            HStack(spacing: GuardianSpacing.xsTight) {
                Circle()
                    .fill(calibrationColor(for: item.status))
                    .frame(width: 8, height: 8)
                Image(systemName: definition.iconSystemName)
                    .font(GuardianTypography.font(.denseCaption10Semibold))
                Text(definition.title)
                    .font(GuardianTypography.font(.formFieldLabel))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
            .padding(.horizontal, GuardianSpacing.denseGutter)
            .padding(.vertical, GuardianSpacing.chromeTightInset)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.backgroundElevated)
                    if selected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(calibrationColor(for: item.status).opacity(0.22))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(calibrationColor(for: item.status).opacity(selected ? 0.75 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
        .cursorPointer()
        .position(x: size.width * anchor.labelPoint.x, y: size.height * anchor.labelPoint.y)
    }

    /// Scrollable body for the bottom sheet when no calibration marker is selected.
    private var unselectedInspectorScrollBody: some View {
        ScrollView {
            HStack(alignment: .top, spacing: GuardianSpacing.md) {
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    HStack(spacing: GuardianSpacing.xs) {
                        Image(systemName: "cursorarrow.click.2")
                            .font(GuardianTypography.font(.sectionHeadingSemibold))
                            .foregroundStyle(theme.textTertiary)
                        Text("Select a calibration marker")
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(theme.textPrimary)
                    }
                    Text("Click any line or label to inspect its message, remediation advice, and future manual calibration controls.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VehicleOverviewDigest(vehicle: vehicle)
                    .frame(width: 260)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, GuardianSpacing.xs)
            .padding(GuardianSpacing.cardBodyInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func wizardGuidedPanelCrossfadeApplies(for item: FleetCalibrationItem) -> Bool {
        guidedWizard.isActive && guidedWizard.currentSystemID == item.id
    }

    private func wizardInspectorStepOpacity(for item: FleetCalibrationItem) -> CGFloat {
        guard wizardGuidedPanelCrossfadeApplies(for: item) else { return 1 }
        return guidedWizard.wizardStepPanelOpacity
    }

    private func wizardInspectorEmptyOpacity(for item: FleetCalibrationItem) -> CGFloat {
        guard wizardGuidedPanelCrossfadeApplies(for: item) else { return 0 }
        return guidedWizard.wizardEmptyPanelOpacity
    }

    private func selectedInspectorScrollContent(for item: FleetCalibrationItem) -> some View {
        let vid = vehicle.data.vehicleID
        let wizardProgress = fleetRecipeRunner.wizardProgressByVehicleID[vid]
        let wizardEscalation = fleetRecipeRunner.wizardEscalationByVehicleID[vid]
        let controls = FleetCalibrationExtensionRegistry.controls(for: item.id, vehicle: vehicle, item: item)
        let telemetryFields = FleetTelemetryFieldCatalog.fields(forSystem: item.id)
        let resolvedRecipes = FleetTelemetryFieldCatalog.resolveDescriptors(
            forSystem: item.id,
            against: FleetRecipesCatalogue.shared
        )

        return ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                    if let detail = item.technicalDetail, !detail.isEmpty {
                        Text(detail)
                            .font(GuardianTypography.font(.telemetryMono11Regular))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let progress = debouncedWizardProcedureBanner {
                        VehicleInspectorProcedureProgressBanner(
                            snapshot: progress,
                            showsAwaitingPromptPlaceholder: wizardEscalation == nil,
                            onCancel: {
                                _ = fleetRecipeRunner.cancel(runID: progress.runID)
                            }
                        )
                    }

                    if let escalation = wizardEscalation {
                        VehicleInspectorProcedureEscalationBanner(
                            snapshot: escalation,
                            vehicleID: vid
                        )
                    }

                    VehicleInspectorGuidedWizardInterStepChrome(
                        guidedWizard: guidedWizard,
                        activeSystemID: item.id,
                        vehicle: vehicle,
                        recipeFleetLink: recipeFleetLink,
                        isLiveMissionRecipeLocked: isLiveMissionRecipeLocked
                    )

                    SystemRecipeWizardLaunchers(
                        systemID: item.id,
                        vehicle: vehicle,
                        recipeFleetLink: recipeFleetLink,
                        isLiveMissionRecipeLocked: isLiveMissionRecipeLocked,
                        wizardLocksCatalogueRuns: guidedWizard.isActive
                    )
                    .id(item.id)

                    HStack(alignment: .top, spacing: GuardianSpacing.md) {
                        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                            if let advice = item.remediationAdvice {
                                PreflightProbeRemediationBlock(advice: advice)
                            } else {
                                Text("No remediation needed.")
                                    .font(GuardianTypography.font(.denseFootnoteRegular))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        SystemTelemetryColumn(
                            fields: telemetryFields,
                            hub: vehicle.data.telemetry
                        )
                        .frame(width: 260, alignment: .topLeading)
                    }

                    if resolvedRecipes.isEmpty, !controls.isEmpty {
                        HStack(spacing: GuardianSpacing.xs) {
                            ForEach(Array(controls.enumerated()), id: \.offset) { _, control in
                                control
                            }
                        }
                        .padding(.top, GuardianSpacing.micro)
                    }
                }
                .padding(GuardianSpacing.cardBodyInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .id(guidedWizard.isActive ? "\(item.id.rawValue)|\(guidedWizard.contentTransitionEpoch)" : item.id.rawValue)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
            }
            .opacity(Double(wizardInspectorStepOpacity(for: item)))

            if wizardGuidedPanelCrossfadeApplies(for: item) {
                WizardGuidedCalibrationEmptyState(
                    headline: guidedWizard.wizardEmptyStateHeadline,
                    subtitle: guidedWizard.wizardEmptyStateSubtitle
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(Double(wizardInspectorEmptyOpacity(for: item)))
                .allowsHitTesting(guidedWizard.wizardEmptyPanelOpacity > 0.02)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: guidedWizard.contentTransitionEpoch)
        .onAppear {
            syncDebouncedWizardProcedureBanner(vehicleID: vid, latest: wizardProgress)
        }
        .onChange(of: wizardProgress) { newProgress in
            syncDebouncedWizardProcedureBanner(vehicleID: vid, latest: newProgress)
        }
    }

    private func calibrationColor(for status: FleetCalibrationStatus) -> Color {
        switch status {
        case .green:
            return GuardianSemanticColors.successStroke
        case .warning:
            return GuardianSemanticColors.warningStroke
        case .error:
            return GuardianSemanticColors.dangerStroke
        }
    }
}

// MARK: - Per-system telemetry column

/// Right column inside the selected calibration system's status block. Renders the catalogued
/// fields for that system as `label  value` rows. When the system has zero catalogued fields, or
/// when every catalogued field returns `nil` against the live hub, shows a neutral placeholder.
private struct SystemTelemetryColumn: View {
    let fields: [FleetTelemetryFieldCatalog.Field]
    let hub: FleetHubVehicleTelemetry?

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var rows: [(id: String, label: String, value: String)] {
        guard let hub else { return [] }
        return fields.compactMap { field in
            guard let v = field.format(hub) else { return nil }
            return (field.id, field.displayLabel, v)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            HStack(spacing: GuardianSpacing.xsTight) {
                Image(systemName: "waveform")
                    .font(GuardianTypography.font(.denseCaption10Semibold))
                    .foregroundStyle(theme.textTertiary)
                Text("Live telemetry")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textTertiary)
                    .textCase(.uppercase)
            }

            if rows.isEmpty {
                Text("No additional telemetry fields available")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                    ForEach(rows, id: \.id) { row in
                        HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xs) {
                            Text(row.label)
                                .font(GuardianTypography.font(.formFieldLabel))
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 110, alignment: .leading)
                            Text(row.value)
                                .font(GuardianTypography.font(.telemetryMono11Regular))
                                .foregroundStyle(theme.textPrimary.opacity(0.95))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(.vertical, GuardianSpacing.xsTight)
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Guided calibration wizard (Vehicle Inspector modal)

/// Full-panel empty state: large spinner, headline, supporting line — used while the guided wizard crossfades the inspector before each catalogue run.
@MainActor
private struct WizardGuidedCalibrationEmptyState: View {
    let headline: String
    let subtitle: String

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: GuardianSpacing.lg) {
            Spacer(minLength: 0)
            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.85)
            Text(headline.isEmpty ? " " : headline)
                .font(GuardianTypography.font(.subsectionTitleSemibold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, GuardianSpacing.cardBodyInset)
            Text(subtitle.isEmpty ? " " : subtitle)
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, GuardianSpacing.sectionStack)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundBase.opacity(colorScheme == .dark ? 0.92 : 0.98))
    }
}

/// Countdown, **Wait** → manual **Continue**, and copy while the guided wizard pauses between steps.
@MainActor
private struct VehicleInspectorGuidedWizardInterStepChrome: View {
    @ObservedObject var guidedWizard: VehicleInspectorGuidedWizardController
    let activeSystemID: FleetCalibrationSystemID
    let vehicle: FleetVehicleModel
    let recipeFleetLink: FleetLinkService?
    let isLiveMissionRecipeLocked: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var appliesHere: Bool {
        guidedWizard.isActive
            && guidedWizard.interStepGateActive
            && guidedWizard.currentSystemID == activeSystemID
    }

    var body: some View {
        if appliesHere {
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                HStack(spacing: GuardianSpacing.xsTight) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(GuardianTypography.font(.denseCaption10Semibold))
                        .foregroundStyle(theme.textTertiary)
                    Text("Guided wizard")
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(theme.textTertiary)
                        .textCase(.uppercase)
                }

                if guidedWizard.requiresManualContinue {
                    Text("Continue when you are ready for the next guided step.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    GeometryReader { geo in
                        let denom = max(guidedWizard.countdownTotal, 0.001)
                        let fraction = CGFloat(guidedWizard.countdownRemaining / denom)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(theme.backgroundElevated)
                            Capsule()
                                .fill(GuardianSemanticColors.successStroke.opacity(0.9))
                                .frame(width: max(4, geo.size.width * fraction))
                        }
                    }
                    .frame(height: 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Time until next guided step")
                    .accessibilityValue("\(max(0, Int(ceil(guidedWizard.countdownRemaining)))) seconds")

                    Text("Next step in \(max(0, Int(ceil(guidedWizard.countdownRemaining))))s — tap Wait if you need more time.")
                        .font(GuardianTypography.font(.denseCaption10Semibold))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: GuardianSpacing.sm) {
                    if !guidedWizard.requiresManualContinue {
                        GuardianThemedButton(
                            title: "Wait",
                            accent: .primary,
                            surface: .outline,
                            size: .small,
                            shape: .cornered,
                            action: { guidedWizard.tapWait() }
                        )
                        .guardianPointerOnHover()
                    }

                    if guidedWizard.requiresManualContinue, let link = recipeFleetLink {
                        GuardianPrimaryProminentButton(title: "Continue") {
                            guidedWizard.tapContinueToNext(
                                vehicle: vehicle,
                                fleetLink: link,
                                isLiveMissionRecipeLocked: isLiveMissionRecipeLocked
                            )
                        }
                        .guardianPointerOnHover()
                    }
                }
            }
            .padding(GuardianSpacing.sm)
            .background(theme.backgroundRaised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.borderSubtle.opacity(0.65), lineWidth: 1)
            )
        }
    }
}

/// Modal header control: **Start** (progress stripe in header) becomes **Stop** while the wizard runs.
@MainActor
private struct VehicleInspectorGuidedWizardStartStopHeader: View {
    @ObservedObject var controller: VehicleInspectorGuidedWizardController
    @ObservedObject private var fleetRecipeRunner = FleetRecipeRunner.shared
    let vehicle: FleetVehicleModel
    let calibrationItems: [FleetCalibrationItem]
    let recipeFleetLink: FleetLinkService?
    let isLiveMissionRecipeLocked: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var vid: String { vehicle.data.vehicleID }

    private var startDisabled: Bool {
        if controller.isActive { return false }
        if recipeFleetLink == nil { return true }
        return fleetRecipeRunner.hasActiveRun(forVehicleID: vid)
    }

    var body: some View {
        if controller.isActive {
            GuardianThemedButton(
                title: "Stop",
                accent: .danger,
                surface: .solid,
                size: .small,
                shape: .cornered,
                action: {
                    controller.stop(vehicleID: vid, fleetLink: recipeFleetLink, silent: false)
                }
            )
            .guardianPointerOnHover()
            .help("End the guided wizard and cancel any running catalogue procedure for this vehicle.")
        } else {
            Button {
                controller.start(
                    vehicle: vehicle,
                    calibrationItems: calibrationItems,
                    recipeFleetLink: recipeFleetLink,
                    isLiveMissionRecipeLocked: isLiveMissionRecipeLocked
                )
            } label: {
                let stripeWidth = 112 * CGFloat(controller.headerProgress)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.backgroundRaised)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(GuardianSemanticColors.successStroke.opacity(0.88))
                        .frame(width: max(0, stripeWidth))
                        .frame(maxHeight: .infinity)
                    Text("Start")
                        .font(GuardianTypography.font(.denseCaption10Semibold))
                        .foregroundStyle(GuardianSemanticColors.infoForeground)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 112, height: GuardianChromeSize.small.controlOuterHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(GuardianSemanticColors.infoForeground.opacity(0.45), lineWidth: 1)
                )
            }
            .buttonStyle(GuardianPointerPlainButtonStyle())
            .guardianPointerOnHover()
            .disabled(startDisabled)
            .opacity(startDisabled ? 0.45 : 1)
            .fixedSize(horizontal: true, vertical: false)
            .help(
                startDisabled
                    ? "Connect the fleet link and ensure no other procedure is running."
                    : "Start guided calibration for every non-green system that has a parameter-free Calibrate recipe."
            )
        }
    }
}

// MARK: - System recipe wizard launchers (Stage E)

/// One **Run** control per directory-listed recipe for the selected calibration system. Drives
/// ``FleetRecipeRunner`` with inline wizard escalation via ``FleetRecipeRunner/vehicleInspectorWizardEscalationHandler(for:)``.
@MainActor
private struct SystemRecipeWizardLaunchers: View {
    let systemID: FleetCalibrationSystemID
    let vehicle: FleetVehicleModel
    let recipeFleetLink: FleetLinkService?
    let isLiveMissionRecipeLocked: Bool
    /// When the Vehicle Inspector **guided wizard** is active, manual **Run** rows stay disabled so the wizard owns sequencing.
    var wizardLocksCatalogueRuns: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var toastCenter: ToastCenter
    @ObservedObject private var fleetRecipeRunner = FleetRecipeRunner.shared

    /// Shown until ``FleetRecipeRunner/activeTopLevelRecipeNameByVehicleID`` catches up (next frame / install).
    @State private var optimisticallyRunningRecipe: FleetRecipeName?

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var vehicleID: String { vehicle.data.vehicleID }

    private var effectiveRunningRecipe: FleetRecipeName? {
        fleetRecipeRunner.activeTopLevelRecipeNameByVehicleID[vehicleID] ?? optimisticallyRunningRecipe
    }

    private var resolved: FleetTelemetryFieldCatalog.ResolvedSystemRecipes {
        FleetTelemetryFieldCatalog.resolveDescriptors(
            forSystem: systemID,
            against: FleetRecipesCatalogue.shared
        )
    }

    var body: some View {
        let r = resolved
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            HStack(spacing: GuardianSpacing.xsTight) {
                Image(systemName: "wand.and.stars")
                    .font(GuardianTypography.font(.denseCaption10Semibold))
                    .foregroundStyle(theme.textTertiary)
                Text("Available procedures")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textTertiary)
                    .textCase(.uppercase)
            }

            if r.isEmpty {
                Text("No catalogued procedures for this system yet.")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if recipeFleetLink == nil {
                    Text("Connect this vehicle on the fleet link to run procedures from here.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                recipeSection(
                    title: "Calibrate",
                    iconSystemName: "slider.horizontal.3",
                    tint: GuardianSemanticColors.infoForeground,
                    descriptors: r.calibrate
                )

                recipeSection(
                    title: "Fix",
                    iconSystemName: "wrench.and.screwdriver",
                    tint: GuardianSemanticColors.warningStroke,
                    descriptors: r.errorFix
                )
            }
        }
        .padding(.vertical, GuardianSpacing.xsTight)
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func recipeSection(
        title: String,
        iconSystemName: String,
        tint: Color,
        descriptors: [FleetRecipeDescriptor]
    ) -> some View {
        if descriptors.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                HStack(spacing: GuardianSpacing.xsTight) {
                    Image(systemName: iconSystemName)
                        .font(GuardianTypography.font(.denseCaption10Semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.top, GuardianSpacing.xxs)

                ForEach(descriptors, id: \.name) { descriptor in
                    recipeLauncherRow(descriptor: descriptor, sectionTint: tint)
                }
            }
        }
    }

    private func recipeLauncherRow(descriptor: FleetRecipeDescriptor, sectionTint: Color) -> some View {
        let busy = effectiveRunningRecipe != nil
        let isThisRun = effectiveRunningRecipe == descriptor.name
        let needsParams = !descriptor.parameters.isEmpty
        let liveLocked = descriptor.vehicleInspectorLaunchBlockedDuringLiveMission(isVehicleInLiveMission: isLiveMissionRecipeLocked)
        let noLink = recipeFleetLink == nil
        let wizardLock = wizardLocksCatalogueRuns && !isThisRun
        let disabled = (busy && !isThisRun) || needsParams || liveLocked || noLink || wizardLock

        return HStack(alignment: .top, spacing: GuardianSpacing.sm) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(sectionTint.opacity(0.55))
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                Text(descriptor.humanLabel)
                    .font(GuardianTypography.font(.inlineNoticeTitle))
                    .foregroundStyle(theme.textPrimary)
                Text(descriptor.humanDescription)
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if needsParams {
                    Text("This procedure needs parameters — collection UI is not wired yet.")
                        .font(GuardianTypography.font(.denseCaption10Semibold))
                        .foregroundStyle(GuardianSemanticColors.warningStroke)
                        .fixedSize(horizontal: false, vertical: true)
                } else if liveLocked {
                    Text("Locked — this vehicle’s stream is in an active Mission Control run (matches the Recipe locked header).")
                        .font(GuardianTypography.font(.denseCaption10Semibold))
                        .foregroundStyle(GuardianSemanticColors.warningStroke)
                        .fixedSize(horizontal: false, vertical: true)
                } else if wizardLock {
                    Text("The guided calibration wizard is running. Use Wait and Continue in the panel above, or tap Stop in the header.")
                        .font(GuardianTypography.font(.denseCaption10Semibold))
                        .foregroundStyle(GuardianSemanticColors.infoForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: GuardianSpacing.sm)

            Group {
                if isThisRun {
                    HStack(spacing: GuardianSpacing.xsTight) {
                        ProgressView()
                            .controlSize(.small)
                            .progressViewStyle(.circular)
                        Text("Running…")
                            .font(GuardianTypography.font(.denseCaption10Semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .frame(minWidth: 88, minHeight: GuardianChromeSize.small.controlOuterHeight, alignment: .center)
                    .padding(.horizontal, GuardianSpacing.xsTight)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.backgroundElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme.borderSubtle.opacity(0.75), lineWidth: 1)
                    )
                } else {
                    GuardianPrimaryProminentButton(title: "Run") {
                        run(descriptor)
                    }
                    .guardianPointerOnHover()
                }
            }
            .disabled(disabled && !isThisRun)
            .opacity(disabled && !isThisRun ? 0.45 : 1)
        }
        .padding(GuardianSpacing.sm)
        .background(theme.backgroundRaised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.borderSubtle.opacity(0.65), lineWidth: 1)
        )
        .help("Catalog ID: \(descriptor.name.rawValue)")
    }

    private func run(_ descriptor: FleetRecipeDescriptor) {
        guard let link = recipeFleetLink else {
            toastCenter.show("Fleet link unavailable — cannot start this procedure.", style: .error, duration: 4)
            return
        }
        guard descriptor.parameters.isEmpty else { return }
        guard !descriptor.vehicleInspectorLaunchBlockedDuringLiveMission(isVehicleInLiveMission: isLiveMissionRecipeLocked) else { return }
        if effectiveRunningRecipe != nil {
            toastCenter.show(
                "Another procedure is still running for this vehicle. Cancel it in the banner above, or wait for it to finish.",
                style: .warning,
                duration: 4.5
            )
            return
        }

        let source = "vehicleInspector.recipe.\(systemID.rawValue)"
        optimisticallyRunningRecipe = descriptor.name
        Task { @MainActor in
            defer { optimisticallyRunningRecipe = nil }
            // Let SwiftUI commit the next frame before we enter the runner; otherwise a long
            // first hop on the main actor can leave Run rows looking idle until work yields.
            await Task.yield()

            let vid = vehicle.data.vehicleID
            let escalationHandler = FleetRecipeRunner.shared.vehicleInspectorWizardEscalationHandler(for: vid)
            let outcome = await FleetRecipeRunner.shared.run(
                recipe: descriptor.name,
                parameters: .empty,
                vehicleID: vid,
                source: source,
                fleetLink: link,
                allowDuringLiveMission: false,
                escalationHandler: escalationHandler
            )

            let toast = FleetRecipeOutcomeOperatorToast.presentation(
                recipeHumanLabel: descriptor.humanLabel,
                outcome: outcome
            )
            toastCenter.show(toast.message, style: toast.style, duration: toast.duration)

            let historyResult = VehicleInspectorRecipeRunHistoryMapper.preflightShapedResult(
                outcome: outcome,
                recipeHumanLabel: descriptor.humanLabel,
                calibrationSystemID: systemID
            )
            link.recordRecipeRun(
                vehicleID: vid,
                source: source,
                kind: .vehicleInspectorCatalogueRecipe,
                outcome: historyResult
            )
        }
    }
}

// MARK: - Procedure run progress (Stage E wizard chrome)

/// Pinned strip while ``FleetRecipeRunner`` has live progress for this vehicle — step index,
/// current activity line, placeholder for future operator prompts, and cancel.
private struct VehicleInspectorProcedureProgressBanner: View {
    let snapshot: FleetRecipeWizardProgressSnapshot
    var showsAwaitingPromptPlaceholder: Bool = true
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                HStack(spacing: GuardianSpacing.xsTight) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Procedure in progress")
                        .font(GuardianTypography.font(.formFieldLabel))
                        .foregroundStyle(theme.textTertiary)
                        .textCase(.uppercase)
                }
                Spacer(minLength: 0)
                GuardianThemedButton(
                    title: "Cancel",
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: onCancel
                )
                .guardianPointerOnHover()
            }

            Text(snapshot.recipeHumanTitle)
                .font(GuardianTypography.font(.subsectionTitleSemibold))
                .foregroundStyle(theme.textPrimary)

            Text("Step \(snapshot.stepOrdinal) of \(snapshot.stepTotal)")
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textSecondary)

            Text(snapshot.activityLine)
                .font(GuardianTypography.font(.telemetryMono11Regular))
                .foregroundStyle(theme.textPrimary.opacity(0.92))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if showsAwaitingPromptPlaceholder {
                Text("When a step needs your input, choices appear in the panel below.")
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(GuardianSpacing.denseGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.backgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(GuardianSemanticColors.infoForeground.opacity(0.35), lineWidth: 1)
                )
        )
    }
}

/// Layer 2 escalation strip: human reason copy plus resumption verbs for the active wizard run.
private struct VehicleInspectorProcedureEscalationBanner: View {
    let snapshot: FleetRecipeWizardEscalationSnapshot
    let vehicleID: String

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var borderAccent: Color {
        switch snapshot.feedbackSeverity {
        case .warning:
            return GuardianSemanticColors.warningStroke
        case .error:
            return GuardianSemanticColors.dangerStroke
        case .info, .success:
            return GuardianSemanticColors.infoForeground
        }
    }

    private var orderedVerbs: [FleetRecipeResumptionVerb] {
        let allowed = Set(snapshot.allowedVerbs)
        let order: [FleetRecipeResumptionVerb] = [.acknowledge, .retry, .skip, .abort]
        return order.filter { allowed.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            HStack(spacing: GuardianSpacing.xsTight) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(GuardianTypography.font(.denseCaption10Semibold))
                    .foregroundStyle(borderAccent)
                Text("Needs your input")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textTertiary)
                    .textCase(.uppercase)
            }

            Text(snapshot.headline)
                .font(GuardianTypography.font(.subsectionTitleSemibold))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(snapshot.detail)
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            FlowWizardVerbButtons(verbs: orderedVerbs, vehicleID: vehicleID)
        }
        .padding(GuardianSpacing.denseGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.backgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(borderAccent.opacity(0.45), lineWidth: 1)
                )
        )
    }
}

/// Wraps verb buttons so they flow on narrow inspector widths without stretching full-width rows awkwardly.
private struct FlowWizardVerbButtons: View {
    let verbs: [FleetRecipeResumptionVerb]
    let vehicleID: String

    private func submit(_ verb: FleetRecipeResumptionVerb) {
        _ = FleetRecipeRunner.shared.submitWizardEscalationVerb(vehicleID: vehicleID, verb: verb)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GuardianSpacing.xsTight) {
                ForEach(verbs, id: \.self) { verb in
                    wizardVerbButton(verb)
                }
            }
            VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                ForEach(verbs, id: \.self) { verb in
                    wizardVerbButton(verb)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func wizardVerbButton(_ verb: FleetRecipeResumptionVerb) -> some View {
        switch verb {
        case .acknowledge, .retry:
            GuardianPrimaryProminentButton(title: verb.wizardButtonTitle) {
                submit(verb)
            }
            .guardianPointerOnHover()
        case .skip:
            GuardianThemedButton(
                title: verb.wizardButtonTitle,
                accent: .neutral,
                surface: .outline,
                size: .small,
                shape: .cornered,
                action: { submit(verb) }
            )
            .guardianPointerOnHover()
        case .abort:
            GuardianThemedButton(
                title: verb.wizardButtonTitle,
                accent: .danger,
                surface: .outline,
                size: .small,
                shape: .cornered,
                action: { submit(verb) }
            )
            .guardianPointerOnHover()
        }
    }
}

// MARK: - Vehicle overview digest

/// Compact at-a-glance digest shown when no calibration marker is selected. Surfaces the same
/// fields the old `VehicleTelemetryInfoSheet` Summary mode rendered, but as a always-on right
/// column so the modal is useful immediately on open instead of requiring a click.
private struct VehicleOverviewDigest: View {
    let vehicle: FleetVehicleModel

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var rows: [(label: String, value: String)] {
        let t = vehicle.data.telemetry
        let battery = vehicle.collections.operational.battery
        let gps = vehicle.collections.operational.gps
        let lifecycle = vehicle.collections.lifecycleStatus
        var out: [(String, String)] = [
            ("Short ID", vehicle.displayShortID),
            ("Class", vehicle.data.vehicleType.displayName),
            ("Autopilot", t?.autopilotStack.displayName ?? "—"),
            ("State", lifecycle.shortLabel),
            ("Mode", (t?.flightMode.isEmpty == false) ? (t?.flightMode ?? "—") : "—"),
            ("Armed", (t?.isArmed ?? false) ? "Yes" : "No"),
            ("Battery", battery.percent0to100.map { "\(Int(round($0)))%" } ?? "—"),
            ("GPS", gps.titleText.replacingOccurrences(of: "GPS ", with: "")),
        ]
        if let lat = t?.latitudeDeg, let lon = t?.longitudeDeg, lat.isFinite, lon.isFinite {
            out.append(("Position", String(format: "%.5f, %.5f", lat, lon)))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            HStack(spacing: GuardianSpacing.xsTight) {
                Image(systemName: "rectangle.dashed")
                    .font(GuardianTypography.font(.denseCaption10Semibold))
                    .foregroundStyle(theme.textTertiary)
                Text("Vehicle overview")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textTertiary)
                    .textCase(.uppercase)
            }
            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                ForEach(rows, id: \.label) { row in
                    HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xs) {
                        Text(row.label)
                            .font(GuardianTypography.font(.formFieldLabel))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 90, alignment: .leading)
                        Text(row.value)
                            .font(GuardianTypography.font(.telemetryMono11Regular))
                            .foregroundStyle(theme.textPrimary.opacity(0.95))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(GuardianSpacing.denseGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.backgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.borderSubtle.opacity(0.8), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preflight banner

/// Banner shown above the canvas summarising the most recent **recipe-run / probe** outcome on the FVM
/// (arm probe, Vehicle Inspector catalogue **Run**, or the in-flight preflight probe). Uses theme palette
/// colours so it reads correctly in both light and dark modes; failure cases reuse ``PreflightProbeRemediationBlock`` when advice is present.
struct VehicleCalibrationPreflightBanner: View {
    let entry: RecipeRunHistoryEntry?
    let isRunning: Bool
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        if isRunning {
            runningBlock
        } else if let entry {
            resultBlock(entry: entry)
        } else {
            EmptyView()
        }
    }

    private var runningBlock: some View {
        bannerShell(strokeColor: GuardianSemanticColors.warningStroke, tint: GuardianSemanticColors.warningStroke) {
            HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                    Text("Running preflight check…")
                        .font(GuardianTypography.font(.subsectionTitleSemibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Sending arm command and watching the autopilot response.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func recipeRunBannerHeadline(entry: RecipeRunHistoryEntry) -> String {
        switch entry.kind {
        case .vehicleInspectorCatalogueRecipe:
            return entry.outcome.passed ? "Procedure finished" : "Procedure failed"
        case .preflightArmProbe, .pluginOther:
            return entry.outcome.passed ? "Preflight passed" : "Preflight failed"
        }
    }

    private func resultBlock(entry: RecipeRunHistoryEntry) -> some View {
        let stroke = entry.outcome.passed
            ? GuardianSemanticColors.successStroke
            : GuardianSemanticColors.dangerStroke

        return bannerShell(strokeColor: stroke, tint: stroke) {
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.denseGutter) {
                    Image(systemName: entry.outcome.passed ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                        .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                        .foregroundStyle(stroke)
                    VStack(alignment: .leading, spacing: GuardianSpacing.micro) {
                        Text(recipeRunBannerHeadline(entry: entry))
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(headerSubtitle(entry: entry))
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(GuardianTypography.font(.formFieldLabel))
                            .foregroundStyle(theme.textTertiary)
                            .padding(GuardianSpacing.xsTight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(GuardianPointerPlainButtonStyle())
                    .help("Dismiss result")
                }

                if !entry.outcome.passed, let advice = entry.outcome.remediationAdvice {
                    PreflightProbeRemediationBlock(advice: advice)
                } else if !entry.outcome.detail.isEmpty {
                    Text(entry.outcome.detail)
                        .font(GuardianTypography.font(.telemetryMono11Regular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func headerSubtitle(entry: RecipeRunHistoryEntry) -> String {
        let relative = Self.relativeFormatter.localizedString(for: entry.recordedAt, relativeTo: Date())
        let detail: String
        if entry.outcome.passed {
            if entry.kind == .vehicleInspectorCatalogueRecipe {
                detail = entry.outcome.detail
            } else {
                detail = "Arm probe completed"
            }
        } else {
            detail = entry.outcome.remediationAdvice?.summary ?? entry.outcome.detail
        }
        return "\(detail) · \(relative)"
    }

    @ViewBuilder
    private func bannerShell<Inner: View>(
        strokeColor: Color,
        tint: Color,
        @ViewBuilder content: () -> Inner
    ) -> some View {
        content()
            .padding(GuardianSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.backgroundRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(tint.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(strokeColor.opacity(0.5), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Telemetry tab

/// Telemetry tab in the Vehicle Inspector. Chip strip + free-text search + grouped list rendered
/// off ``FleetTelemetryFieldCatalog``. Anything not catalogued falls through to the synthetic
/// "Other" chip via `FleetTelemetryFieldCatalog.unknownFields(in:)` so completeness is preserved.
struct VehicleTelemetryTabView: View {
    let vehicle: FleetVehicleModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeChip: FleetTelemetryFieldCatalog.Group? = nil
    @State private var searchText: String = ""

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            controlsBar
            Divider().opacity(0.2)
            ScrollView {
                VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                    if visibleSections.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleSections, id: \.id) { section in
                            sectionView(section)
                        }
                    }
                }
                .padding(.vertical, GuardianSpacing.xxs)
            }
        }
    }

    private var controlsBar: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
            HStack(spacing: GuardianSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textTertiary)
                TextField("Search fields", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textPrimary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(GuardianPointerPlainButtonStyle())
                }
            }
            .padding(.horizontal, GuardianSpacing.denseGutter)
            .padding(.vertical, GuardianSpacing.xsTight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.backgroundElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(theme.borderSubtle.opacity(0.7), lineWidth: 1)
                    )
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GuardianSpacing.xsTight) {
                    chip(label: "All", icon: "square.grid.2x2", group: nil)
                    ForEach(FleetTelemetryFieldCatalog.Group.allCases) { group in
                        chip(label: group.displayLabel, icon: group.iconSystemName, group: group)
                    }
                }
                .padding(.horizontal, GuardianSpacing.hairlineStack)
            }
        }
    }

    private func chip(
        label: String,
        icon: String,
        group: FleetTelemetryFieldCatalog.Group?
    ) -> some View {
        let active = activeChip == group
        return Button {
            activeChip = group
        } label: {
            HStack(spacing: GuardianSpacing.stackDense) {
                Image(systemName: icon)
                    .font(GuardianTypography.font(.denseCaption10Semibold))
                Text(label)
                    .font(GuardianTypography.font(.formFieldLabel))
            }
            .padding(.horizontal, GuardianSpacing.denseGutter)
            .padding(.vertical, GuardianSpacing.stackDense)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(active ? Color.blue.opacity(0.18) : theme.backgroundElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(active ? Color.blue.opacity(0.7) : theme.borderSubtle.opacity(0.7), lineWidth: 1)
                    )
            )
            .foregroundStyle(active ? Color.blue : theme.textSecondary)
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text("No telemetry matches that filter")
                .font(GuardianTypography.font(.subsectionTitleSemibold))
                .foregroundStyle(theme.textPrimary)
            Text("Clear the search box, pick another chip, or wait for the autopilot to start streaming the requested fields.")
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(GuardianSpacing.cardBodyInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised, in: RoundedRectangle(cornerRadius: 12))
    }

    private struct Section: Identifiable {
        let id: String
        let title: String
        let icon: String
        let rows: [(id: String, label: String, value: String)]
    }

    private var visibleSections: [Section] {
        let hub = vehicle.data.telemetry ?? .empty
        let normalisedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var sections: [Section] = []

        for group in FleetTelemetryFieldCatalog.Group.allCases where group != .other {
            if let chipGroup = activeChip, chipGroup != group { continue }
            let groupFields = FleetTelemetryFieldCatalog.all.filter { $0.group == group }
            let rows: [(String, String, String)] = groupFields.compactMap { field in
                guard let v = field.format(hub) else { return nil }
                if !normalisedQuery.isEmpty,
                   !field.id.lowercased().contains(normalisedQuery),
                   !field.displayLabel.lowercased().contains(normalisedQuery) {
                    return nil
                }
                return (field.id, field.displayLabel, v)
            }
            if rows.isEmpty { continue }
            sections.append(Section(
                id: group.rawValue,
                title: group.displayLabel,
                icon: group.iconSystemName,
                rows: rows
            ))
        }

        if activeChip == nil || activeChip == .other {
            let unknowns = FleetTelemetryFieldCatalog.unknownFields(in: vehicle.data.telemetry ?? .empty)
            let filtered = unknowns.filter { row in
                guard !normalisedQuery.isEmpty else { return true }
                return row.id.lowercased().contains(normalisedQuery)
                    || row.displayLabel.lowercased().contains(normalisedQuery)
            }
            if !filtered.isEmpty {
                sections.append(Section(
                    id: FleetTelemetryFieldCatalog.Group.other.rawValue,
                    title: FleetTelemetryFieldCatalog.Group.other.displayLabel,
                    icon: FleetTelemetryFieldCatalog.Group.other.iconSystemName,
                    rows: filtered.map { ($0.id, $0.displayLabel, $0.value) }
                ))
            }
        }

        return sections
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            HStack(spacing: GuardianSpacing.xsTight) {
                Image(systemName: section.icon)
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textTertiary)
                Text(section.title)
                    .font(GuardianTypography.font(.inlineNoticeTitle))
                    .foregroundStyle(theme.textPrimary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                ForEach(section.rows, id: \.id) { row in
                    HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.denseGutter) {
                        Text(row.label)
                            .font(GuardianTypography.font(.telemetryMono12Semibold))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 240, alignment: .leading)
                        Text(row.value)
                            .font(GuardianTypography.relativeFixed(size: 12, weight: .regular, design: .monospaced, relativeTo: .caption))
                            .foregroundStyle(theme.textPrimary.opacity(0.95))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(GuardianSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Live wrappers

/// Live wrapper that resolves a fresh ``FleetVehicleModel`` from ``FleetLinkService`` on every
/// render so calibration views update automatically as telemetry arrives. Falls back to the
/// caller-supplied model when the link does not (yet) hold the vehicle (e.g. the row was
/// constructed locally inside the Vehicles grid before the bridge attached a sysid).
///
/// When this embed shows catalogue **Run** launchers, set ``isLiveMissionRecipeLocked`` from
/// ``MissionControlStore/isVehicleStreamUsedInLiveMission(vehicleID:fleetLink:sitl:)`` so the
/// live-mission gate matches ``VehicleCalibrationModal`` (defaults to `false` for simple embeds).
struct LiveVehicleCalibrationView: View {
    @ObservedObject var fleetLink: FleetLinkService
    let vehicleID: String
    let fallback: FleetVehicleModel?
    var isLiveMissionRecipeLocked: Bool = false

    @StateObject private var guidedWizardEmbedStub = VehicleInspectorGuidedWizardController()

    var body: some View {
        VehicleCalibrationView(
            vehicle: resolvedVehicle,
            guidedWizard: guidedWizardEmbedStub,
            recipeFleetLink: fleetLink,
            isLiveMissionRecipeLocked: isLiveMissionRecipeLocked
        )
    }

    private var resolvedVehicle: FleetVehicleModel {
        if let live = fleetLink.vehicleModel(forVehicleID: vehicleID) {
            return live
        }
        if let fallback {
            return fallback
        }
        return FleetVehicleModel(vehicleID: vehicleID)
    }
}

struct VehicleCalibrationInlineView: View {
    @ObservedObject var fleetLink: FleetLinkService
    let vehicleID: String
    let fallback: FleetVehicleModel?

    init(fleetLink: FleetLinkService, vehicleID: String, fallback: FleetVehicleModel? = nil) {
        self.fleetLink = fleetLink
        self.vehicleID = vehicleID
        self.fallback = fallback
    }

    var body: some View {
        LiveVehicleCalibrationView(fleetLink: fleetLink, vehicleID: vehicleID, fallback: fallback)
    }
}

/// "Vehicle Inspector" modal — segmented Calibration / Telemetry tabs. Calibration is the default
/// every time it opens; the Run preflight header button is only meaningful in the Calibration tab
/// so it is hidden on the Telemetry tab.
///
/// Persists recipe-run / probe outcomes on the FVM ring (capped at ``FleetVehicleModel/recipeRunHistoryCap``)
/// via ``FleetLinkService/recordRecipeRun`` (arm probe: ``RecipeRunHistoryKind/preflightArmProbe``) so re-opens
/// show the previous outcome and the canvas keeps the failed-system marker red until the next run replaces it or the operator dismisses the banner.
struct VehicleCalibrationModal: View {
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var controlStore: MissionControlStore
    @ObservedObject var sitl: SitlService
    let vehicleID: String
    let fallback: FleetVehicleModel?
    /// When non-`nil` (in-window ``VehicleInspectorHostOverlay``), **Close** calls this instead of ``EnvironmentValues/dismiss``.
    private let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toastCenter: ToastCenter
    @StateObject private var vehicleInspectorGuidedWizard = VehicleInspectorGuidedWizardController()
    @State private var isRunningPreflight = false
    @State private var activeTab: InspectorTab = .calibration

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case calibration = "Calibration"
        case telemetry = "Telemetry"
        var id: String { rawValue }
    }

    init(
        fleetLink: FleetLinkService,
        controlStore: MissionControlStore,
        sitl: SitlService,
        vehicleID: String,
        fallback: FleetVehicleModel? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.fleetLink = fleetLink
        self.controlStore = controlStore
        self.sitl = sitl
        self.vehicleID = vehicleID
        self.fallback = fallback
        self.onClose = onClose
    }

    private func closeInspector() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var resolvedVehicle: FleetVehicleModel {
        if let live = fleetLink.vehicleModel(forVehicleID: vehicleID) { return live }
        if let fallback { return fallback }
        return FleetVehicleModel(vehicleID: vehicleID)
    }

    private var latestRecipeRun: RecipeRunHistoryEntry? {
        resolvedVehicle.functions.recipeRunHistory.first
    }

    /// `true` when this vehicle's stream is currently bound to a `.running` / `.paused` / `.recovery`
    /// Mission Control run. Mirrors the gate in `MissionControlStore.runSingleVehiclePreflightProbe`
    /// and drives the modal **Recipe locked** header plus disabled catalogue **Run** rows for
    /// recipes whose ``FleetRecipeRiskTier`` is not ``FleetRecipeRiskTier/safeInLiveMission`` before the runner would refuse the call.
    private var isVehicleInLiveMission: Bool {
        controlStore.isVehicleStreamUsedInLiveMission(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    var body: some View {
        Modal(
            title: "Vehicle Inspector",
            subtitle: subtitle,
            headerActions: {
                Picker("", selection: $activeTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)

                if activeTab == .calibration {
                    VehicleInspectorGuidedWizardStartStopHeader(
                        controller: vehicleInspectorGuidedWizard,
                        vehicle: resolvedVehicle,
                        calibrationItems: resolvedVehicle.collections.calibration.items,
                        recipeFleetLink: fleetLink,
                        isLiveMissionRecipeLocked: isVehicleInLiveMission
                    )
                    preflightHeaderButton
                }

                GuardianThemedButton(
                    title: "Close",
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: { closeInspector() }
                )
                .keyboardShortcut(.cancelAction)
            },
            bodyContent: {
                Group {
                    switch activeTab {
                    case .calibration:
                        VehicleCalibrationView(
                            vehicle: resolvedVehicle,
                            guidedWizard: vehicleInspectorGuidedWizard,
                            recipeFleetLink: fleetLink,
                            isLiveMissionRecipeLocked: isVehicleInLiveMission,
                            preflightBanner: {
                                AnyView(
                                    VehicleCalibrationPreflightBanner(
                                        entry: latestRecipeRun,
                                        isRunning: isRunningPreflight,
                                        onDismiss: {
                                            fleetLink.clearRecipeRuns(vehicleID: vehicleID)
                                        }
                                    )
                                )
                            }
                        )
                    case .telemetry:
                        VehicleTelemetryTabView(vehicle: resolvedVehicle)
                    }
                }
            }
        )
        .frame(minWidth: 880, idealWidth: 900, maxWidth: 920, minHeight: 620, idealHeight: 680, maxHeight: 720)
        .onAppear {
            vehicleInspectorGuidedWizard.attachToastCenter(toastCenter)
        }
        .onDisappear {
            vehicleInspectorGuidedWizard.stop(vehicleID: vehicleID, fleetLink: fleetLink, silent: true)
        }
    }

    @ViewBuilder
    private var preflightHeaderButton: some View {
        if isRunningPreflight {
            GuardianThemedButton(
                accent: .primary,
                surface: .solid,
                size: .small,
                shape: .cornered,
                isEnabled: false,
                action: {},
                label: {
                    HStack(spacing: GuardianSpacing.xsTight) {
                        ProgressView().controlSize(.small)
                        Text("Running…")
                    }
                }
            )
        } else if isVehicleInLiveMission {
            GuardianThemedButton(
                accent: .warning,
                surface: .outline,
                size: .small,
                shape: .cornered,
                isEnabled: false,
                action: {},
                label: {
                    HStack(spacing: GuardianSpacing.xsTight) {
                        Image(systemName: "lock.shield.fill")
                        Text("Recipe locked")
                    }
                }
            )
            .help("This vehicle is bound to an active Mission Control run. Arm preflight and catalogue recipes that are not safe-in-live-mission stay disabled until that run ends.")
        } else if let entry = latestRecipeRun, entry.kind == .preflightArmProbe {
            GuardianThemedButton(
                accent: entry.outcome.passed ? .success : .danger,
                surface: .outline,
                size: .small,
                shape: .cornered,
                action: runPreflight,
                label: {
                    HStack(spacing: GuardianSpacing.xsTight) {
                        Image(systemName: entry.outcome.passed ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                        Text("Re-run preflight")
                    }
                }
            )
            .help("Run another preflight arm probe")
        } else {
            GuardianThemedButton(
                accent: .primary,
                surface: .solid,
                size: .small,
                shape: .cornered,
                action: runPreflight,
                label: {
                    HStack(spacing: GuardianSpacing.xsTight) {
                        Image(systemName: "checkmark.shield")
                        Text("Run preflight")
                    }
                }
            )
            .help("Run a one-shot arm preflight probe and overlay the result on the calibration canvas.")
        }
    }

    private func runPreflight() {
        guard !isRunningPreflight else { return }
        guard !isVehicleInLiveMission else { return }
        isRunningPreflight = true
        Task { @MainActor in
            let result = await controlStore.runSingleVehiclePreflightProbe(
                vehicleID: vehicleID,
                fleetLink: fleetLink,
                sitl: sitl
            )
            fleetLink.recordRecipeRun(
                vehicleID: vehicleID,
                source: "calibrationModal.manual",
                kind: .preflightArmProbe,
                outcome: result
            )
            isRunningPreflight = false
        }
    }

    private var subtitle: String? {
        let vehicle = fleetLink.vehicleModel(forVehicleID: vehicleID) ?? fallback
        return vehicle?.displayShortID
    }
}

/// Full-window dimmed host for ``VehicleCalibrationModal`` **inside the main window** (not ``View/sheet``), so
/// window-level toasts and other shell layers can paint above this chrome.
struct VehicleInspectorHostOverlay<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ZStack {
            theme.overlayScrim
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    content()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { onDismiss() }
    }
}

struct VehicleCalibrationSidebarPanel: View {
    @ObservedObject var fleetLink: FleetLinkService
    let vehicleID: String
    let fallback: FleetVehicleModel?

    init(fleetLink: FleetLinkService, vehicleID: String, fallback: FleetVehicleModel? = nil) {
        self.fleetLink = fleetLink
        self.vehicleID = vehicleID
        self.fallback = fallback
    }

    var body: some View {
        LiveVehicleCalibrationView(fleetLink: fleetLink, vehicleID: vehicleID, fallback: fallback)
            .padding(GuardianSpacing.cardBodyInset)
    }
}

// MARK: - Cursor pointer modifier

private struct PointerCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                guard !isHovering else { return }
                NSCursor.pointingHand.push()
                isHovering = true
            } else if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
    }
}

private extension View {
    func cursorPointer() -> some View {
        modifier(PointerCursorModifier())
    }
}
