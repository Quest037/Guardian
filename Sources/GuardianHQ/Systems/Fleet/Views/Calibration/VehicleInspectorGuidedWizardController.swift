import Foundation
import SwiftUI

// MARK: - Controller

/// Drives the Vehicle Inspector **guided calibration wizard**: ordered catalogue steps for
/// systems that are not `.green`, auto-run with optional countdown advance, Wait → manual Continue.
@MainActor
final class VehicleInspectorGuidedWizardController: ObservableObject {

    struct Step: Identifiable, Equatable {
        let id: UUID
        let systemID: FleetCalibrationSystemID
        let descriptor: FleetRecipeDescriptor
    }

    /// Countdown before auto-advancing after a **successful** recipe (operator can tap **Wait**).
    static let postSuccessCountdownSeconds: TimeInterval = 5
    /// Duration of one **crossfade** between the inspector step stack and the full-panel empty state (step fades out while empty fades in over the same interval — **5s** per direction, matching operator pacing).
    static let wizardPanelCrossfadeSeconds: TimeInterval = 5
    /// Hold on the empty-state screen after the crossfade completes so the operator can read the copy.
    static let wizardEmptyStateDwellSeconds: TimeInterval = 3.5

    @Published private(set) var isActive: Bool = false
    @Published private(set) var steps: [Step] = []
    @Published private(set) var currentIndex: Int = 0
    /// Header gradient fill: completed steps / max(stepCount, 1).
    @Published private(set) var headerProgress: CGFloat = 0
    @Published private(set) var isRunningCatalogueRecipe: Bool = false
    /// `true` during the full guided **empty-state theatre** (crossfade out → dwell → crossfade in) before ``FleetRecipeRunner`` starts the step recipe.
    @Published private(set) var isPreparingCurrentStep: Bool = false
    /// Opacities for the current guided step’s inspector body (only the active wizard system reads non-default values).
    @Published private(set) var wizardStepPanelOpacity: CGFloat = 1
    @Published private(set) var wizardEmptyPanelOpacity: CGFloat = 0
    @Published private(set) var wizardEmptyStateHeadline: String = ""
    @Published private(set) var wizardEmptyStateSubtitle: String = ""
    /// After a successful run, `true` while countdown or manual gate is shown before the next step.
    @Published private(set) var interStepGateActive: Bool = false
    @Published private(set) var requiresManualContinue: Bool = false
    @Published private(set) var countdownRemaining: TimeInterval = 0
    @Published private(set) var countdownTotal: TimeInterval = VehicleInspectorGuidedWizardController.postSuccessCountdownSeconds
    /// Bump to animate swipe-style content changes between steps.
    @Published var contentTransitionEpoch: Int = 0

    private var countdownTask: Task<Void, Never>?
    private weak var toastCenter: ToastCenter?

    var currentStep: Step? {
        guard currentIndex >= 0, currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    var currentSystemID: FleetCalibrationSystemID? { currentStep?.systemID }

    /// Primary headline on the guided empty-state panel before each recipe run.
    static func operatorEmptyStateHeadline(for systemID: FleetCalibrationSystemID) -> String {
        let title = FleetCalibrationExtensionRegistry.definition(for: systemID).title
        return "Beginning calibration for \(title)…"
    }

    /// Back-compat alias for tests / call sites that referenced the older copy shape.
    static func operatorNarrationBeforeRecipe(for systemID: FleetCalibrationSystemID) -> String {
        operatorEmptyStateHeadline(for: systemID)
    }

    func attachToastCenter(_ center: ToastCenter) {
        toastCenter = center
    }

    /// Builds a queue from **non-green** calibration markers, prefers **error** before **warning**,
    /// and picks the first parameter-free **Calibrate** catalogue row that is not VI-blocked for live mission.
    static func buildSteps(
        calibrationItems: [FleetCalibrationItem],
        isLiveMissionRecipeLocked: Bool
    ) -> [Step] {
        let sorted = calibrationItems.sorted { lhs, rhs in
            switch (lhs.status, rhs.status) {
            case (.error, .warning), (.error, .green), (.error, _):
                return true
            case (.warning, .green):
                return true
            case (.warning, .error):
                return false
            default:
                if lhs.status != rhs.status { return lhs.status.rawValue < rhs.status.rawValue }
                return lhs.id.rawValue < rhs.id.rawValue
            }
        }

        let nonGreen = sorted.filter { $0.status != .green }
        var built: [Step] = []
        for item in nonGreen {
            let resolved = FleetTelemetryFieldCatalog.resolveDescriptors(
                forSystem: item.id,
                against: FleetRecipesCatalogue.shared
            )
            guard let descriptor = resolved.calibrate.first(where: { d in
                d.parameters.isEmpty
                    && !d.vehicleInspectorLaunchBlockedDuringLiveMission(isVehicleInLiveMission: isLiveMissionRecipeLocked)
            })
            else { continue }
            built.append(Step(id: UUID(), systemID: item.id, descriptor: descriptor))
        }
        return built
    }

    /// Starts the guided queue built by ``buildSteps(calibrationItems:isLiveMissionRecipeLocked:)``.
    func start(
        vehicle: FleetVehicleModel,
        calibrationItems: [FleetCalibrationItem],
        recipeFleetLink: FleetLinkService?,
        isLiveMissionRecipeLocked: Bool
    ) {
        guard let link = recipeFleetLink else {
            toastCenter?.show("Connect this vehicle on the fleet link to run the guided wizard.", style: .warning, duration: 4)
            return
        }
        guard !FleetRecipeRunner.shared.hasActiveRun(forVehicleID: vehicle.data.vehicleID) else {
            toastCenter?.show("Finish or cancel the running procedure before starting the guided wizard.", style: .warning, duration: 4.5)
            return
        }

        let built = Self.buildSteps(
            calibrationItems: calibrationItems,
            isLiveMissionRecipeLocked: isLiveMissionRecipeLocked
        )

        guard !built.isEmpty else {
            toastCenter?.show(
                "Nothing in the guided queue — all markers are green, or every procedure is locked for this vehicle state.",
                style: .info,
                duration: 4.5
            )
            return
        }

        resetForNewStart()
        steps = built
        currentIndex = 0
        isActive = true
        recomputeHeaderProgress()
        contentTransitionEpoch &+= 1
        interStepGateActive = false
        requiresManualContinue = false
        cancelCountdown()

        Task { @MainActor in
            await self.runCurrentStepAuto(vehicle: vehicle, fleetLink: link, isLiveMissionRecipeLocked: isLiveMissionRecipeLocked)
        }
    }

    /// Ends the wizard and cancels any in-flight catalogue run for `vehicleID`.
    func stop(vehicleID: String, fleetLink: FleetLinkService?, silent: Bool = false) {
        cancelCountdown()
        if FleetRecipeRunner.shared.hasActiveRun(forVehicleID: vehicleID) {
            _ = FleetRecipeRunner.shared.cancel(vehicleID: vehicleID)
        }
        if isActive, !silent {
            toastCenter?.show("Guided wizard stopped.", style: .info, duration: 2.5)
        }
        isActive = false
        steps = []
        currentIndex = 0
        isRunningCatalogueRecipe = false
        isPreparingCurrentStep = false
        wizardStepPanelOpacity = 1
        wizardEmptyPanelOpacity = 0
        wizardEmptyStateHeadline = ""
        wizardEmptyStateSubtitle = ""
        interStepGateActive = false
        requiresManualContinue = false
        countdownRemaining = 0
        headerProgress = 0
    }

    func tapWait() {
        guard interStepGateActive, !requiresManualContinue else { return }
        cancelCountdown()
        requiresManualContinue = true
        countdownRemaining = 0
    }

    func tapContinueToNext(vehicle: FleetVehicleModel, fleetLink: FleetLinkService, isLiveMissionRecipeLocked: Bool) {
        guard isActive else { return }
        guard interStepGateActive else { return }
        interStepGateActive = false
        requiresManualContinue = false
        cancelCountdown()
        advanceToNextOrFinish(vehicle: vehicle, fleetLink: fleetLink, isLiveMissionRecipeLocked: isLiveMissionRecipeLocked)
    }

    // MARK: - Private

    private func recomputeHeaderProgress() {
        guard isActive, !steps.isEmpty else {
            headerProgress = 0
            return
        }
        // Fill reflects position in the guided sequence (1-based so the first active step shows partial fill).
        headerProgress = CGFloat(min(currentIndex + 1, steps.count)) / CGFloat(steps.count)
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func restoreWizardPanelToStepVisible() {
        withAnimation(.easeInOut(duration: 0.35)) {
            wizardStepPanelOpacity = 1
            wizardEmptyPanelOpacity = 0
        }
        wizardEmptyStateHeadline = ""
        wizardEmptyStateSubtitle = ""
    }

    private func emptyStateCopy(for step: Step) -> (headline: String, subtitle: String) {
        let headline = Self.operatorEmptyStateHeadline(for: step.systemID)
        if currentIndex == 0, steps.count > 1 {
            return (
                headline,
                "\(steps.count) guided calibration steps in this run. Nothing runs until this screen fades away and the inspector returns."
            )
        }
        if currentIndex > 0 {
            return (
                headline,
                "The wizard is moving to the next system. Use this pause to reset mentally before the catalogue procedure starts."
            )
        }
        return (
            headline,
            "When the inspector fades back in, the guided procedure starts automatically unless you tap Stop."
        )
    }

    private func performPreRecipePanelTheatre(for step: Step) async {
        let (headline, subtitle) = emptyStateCopy(for: step)
        guard isActive, currentStep?.id == step.id else { return }

        isPreparingCurrentStep = true
        wizardEmptyStateHeadline = headline
        wizardEmptyStateSubtitle = subtitle

        withAnimation(.easeInOut(duration: Self.wizardPanelCrossfadeSeconds)) {
            wizardStepPanelOpacity = 0
            wizardEmptyPanelOpacity = 1
        }
        try? await Task.sleep(nanoseconds: UInt64(Self.wizardPanelCrossfadeSeconds * 1_000_000_000))
        guard isActive, currentStep?.id == step.id else {
            isPreparingCurrentStep = false
            restoreWizardPanelToStepVisible()
            return
        }

        try? await Task.sleep(nanoseconds: UInt64(Self.wizardEmptyStateDwellSeconds * 1_000_000_000))
        guard isActive, currentStep?.id == step.id else {
            isPreparingCurrentStep = false
            restoreWizardPanelToStepVisible()
            return
        }

        withAnimation(.easeInOut(duration: Self.wizardPanelCrossfadeSeconds)) {
            wizardEmptyPanelOpacity = 0
            wizardStepPanelOpacity = 1
        }
        try? await Task.sleep(nanoseconds: UInt64(Self.wizardPanelCrossfadeSeconds * 1_000_000_000))
        guard isActive, currentStep?.id == step.id else {
            isPreparingCurrentStep = false
            restoreWizardPanelToStepVisible()
            return
        }

        wizardEmptyStateHeadline = ""
        wizardEmptyStateSubtitle = ""
        isPreparingCurrentStep = false
    }

    private func runCurrentStepAuto(
        vehicle: FleetVehicleModel,
        fleetLink: FleetLinkService,
        isLiveMissionRecipeLocked: Bool
    ) async {
        guard isActive, let step = currentStep else { return }
        let vid = vehicle.data.vehicleID
        guard !step.descriptor.vehicleInspectorLaunchBlockedDuringLiveMission(isVehicleInLiveMission: isLiveMissionRecipeLocked) else {
            toastCenter?.show(
                "This step is locked for the Vehicle Inspector while the vehicle is in a live mission. Stop the wizard or run safe procedures manually.",
                style: .warning,
                duration: 5
            )
            scheduleInterStepAfterOutcome(success: false, vehicle: vehicle, fleetLink: fleetLink, isLiveMissionRecipeLocked: isLiveMissionRecipeLocked)
            return
        }

        await performPreRecipePanelTheatre(for: step)
        guard isActive, currentStep?.id == step.id else { return }

        isRunningCatalogueRecipe = true
        interStepGateActive = false
        requiresManualContinue = false

        let source = "vehicleInspector.guidedWizard.\(step.systemID.rawValue)"
        let escalationHandler = FleetRecipeRunner.shared.vehicleInspectorWizardEscalationHandler(for: vid)
        let outcome = await FleetRecipeRunner.shared.run(
            recipe: step.descriptor.name,
            parameters: .empty,
            vehicleID: vid,
            source: source,
            fleetLink: fleetLink,
            allowDuringLiveMission: false,
            escalationHandler: escalationHandler
        )

        isRunningCatalogueRecipe = false

        let toast = FleetRecipeOutcomeOperatorToast.presentation(
            recipeHumanLabel: step.descriptor.humanLabel,
            outcome: outcome
        )
        toastCenter?.show(toast.message, style: toast.style, duration: toast.duration)

        let historyResult = VehicleInspectorRecipeRunHistoryMapper.preflightShapedResult(
            outcome: outcome,
            recipeHumanLabel: step.descriptor.humanLabel,
            calibrationSystemID: step.systemID
        )
        fleetLink.recordRecipeRun(
            vehicleID: vid,
            source: source,
            kind: .vehicleInspectorCatalogueRecipe,
            outcome: historyResult
        )

        let success: Bool
        if case .succeeded = outcome { success = true } else { success = false }
        scheduleInterStepAfterOutcome(success: success, vehicle: vehicle, fleetLink: fleetLink, isLiveMissionRecipeLocked: isLiveMissionRecipeLocked)
    }

    private func scheduleInterStepAfterOutcome(
        success: Bool,
        vehicle: FleetVehicleModel,
        fleetLink: FleetLinkService,
        isLiveMissionRecipeLocked: Bool
    ) {
        guard isActive else { return }

        if success, currentIndex + 1 < steps.count {
            interStepGateActive = true
            requiresManualContinue = false
            countdownTotal = Self.postSuccessCountdownSeconds
            countdownRemaining = countdownTotal
            cancelCountdown()
            countdownTask = Task { @MainActor in
                let start = Date()
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(start)
                    let left = max(0, Self.postSuccessCountdownSeconds - elapsed)
                    self.countdownRemaining = left
                    if left <= 0 { break }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if self.requiresManualContinue { return }
                }
                guard !Task.isCancelled else { return }
                guard self.isActive, self.interStepGateActive, !self.requiresManualContinue else { return }
                self.finishInterStepAndAdvance(vehicle: vehicle, fleetLink: fleetLink, isLiveMissionRecipeLocked: isLiveMissionRecipeLocked)
            }
        } else if success {
            // Last step succeeded — wizard complete.
            toastCenter?.show("Guided wizard finished.", style: .success, duration: 3)
            stop(vehicleID: vehicle.data.vehicleID, fleetLink: fleetLink, silent: true)
        } else {
            // Failure: require manual continue to acknowledge before retry / same step advance policy.
            interStepGateActive = true
            requiresManualContinue = true
            countdownRemaining = 0
        }
    }

    private func finishInterStepAndAdvance(
        vehicle: FleetVehicleModel,
        fleetLink: FleetLinkService,
        isLiveMissionRecipeLocked: Bool
    ) {
        interStepGateActive = false
        requiresManualContinue = false
        cancelCountdown()
        advanceToNextOrFinish(vehicle: vehicle, fleetLink: fleetLink, isLiveMissionRecipeLocked: isLiveMissionRecipeLocked)
    }

    private func advanceToNextOrFinish(
        vehicle: FleetVehicleModel,
        fleetLink: FleetLinkService,
        isLiveMissionRecipeLocked: Bool
    ) {
        guard isActive else { return }
        currentIndex += 1
        recomputeHeaderProgress()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            contentTransitionEpoch &+= 1
        }
        if currentIndex >= steps.count {
            toastCenter?.show("Guided wizard finished.", style: .success, duration: 3)
            stop(vehicleID: vehicle.data.vehicleID, fleetLink: fleetLink, silent: true)
            return
        }
        Task { @MainActor in
            await self.runCurrentStepAuto(vehicle: vehicle, fleetLink: fleetLink, isLiveMissionRecipeLocked: isLiveMissionRecipeLocked)
        }
    }

    private func resetForNewStart() {
        cancelCountdown()
        isActive = false
        steps = []
        currentIndex = 0
        isRunningCatalogueRecipe = false
        isPreparingCurrentStep = false
        wizardStepPanelOpacity = 1
        wizardEmptyPanelOpacity = 0
        wizardEmptyStateHeadline = ""
        wizardEmptyStateSubtitle = ""
        interStepGateActive = false
        requiresManualContinue = false
        countdownRemaining = 0
        headerProgress = 0
    }
}
