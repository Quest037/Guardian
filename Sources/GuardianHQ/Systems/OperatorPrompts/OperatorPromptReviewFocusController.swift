import Foundation

// MARK: - OperatorPromptReviewFocusController

/// Applies ``OperatorPromptReviewSurface`` decisions from the Decisions drawer: switches ``AppSection`` and seeds
/// drill-in state consumed by ``MissionControlView`` / ``LiveDriveView``.
@MainActor
final class OperatorPromptReviewFocusController: ObservableObject {

    /// When non-nil, ``RootView`` should assign ``AppSection`` then call ``consumePendingPrimarySection()``.
    @Published private(set) var pendingPrimarySection: AppSection?

    /// Drill-in for Mission Control — ``MissionControlView`` sets ``selectedRunID`` then calls ``consumeMissionControlDrillIn()``.
    @Published private(set) var pendingMissionControlRunID: UUID?
    @Published private(set) var pendingMissionControlMissionTaskID: UUID?
    /// When set with a live run drill-in (e.g. Live Drive **Return to Mission**), MC‑R opens the roster vehicle overlay for this assignment id.
    @Published private(set) var pendingMissionControlLiveAssignmentID: UUID?

    /// Live Drive vehicle selection — ``LiveDriveView`` calls ``LiveDriveStore/selectVehicle`` then ``consumeLiveDriveFocus()`` (vehicle id only).
    @Published private(set) var pendingLiveDriveVehicleID: String?
    /// MC‑R Engage / Decisions drill-in: mission run for Live Drive prompt logging until session starts or ``consumePendingLiveDriveMissionRunDrillIn()`` runs.
    @Published private(set) var pendingLiveDriveMissionRunID: UUID?

    init() {}

    /// Resolves ``OperatorPromptReviewSurfaceResolver`` for `event`, dismisses the drawer, then mutates navigation state.
    func requestReviewFocus(for event: OperatorPromptEvent, dismissDrawer: () -> Void) {
        guard let surface = OperatorPromptReviewSurfaceResolver.resolve(for: event) else { return }
        dismissDrawer()
        switch surface {
        case .missionControlRun(let runID, let missionTaskID):
            pendingLiveDriveVehicleID = nil
            pendingLiveDriveMissionRunID = nil
            pendingMissionControlRunID = runID
            pendingMissionControlMissionTaskID = missionTaskID
            pendingMissionControlLiveAssignmentID = nil
            pendingPrimarySection = .missionControl

        case .liveDriveSession(let vehicleID, let missionRunID):
            pendingMissionControlRunID = nil
            pendingMissionControlMissionTaskID = nil
            pendingMissionControlLiveAssignmentID = nil
            pendingLiveDriveVehicleID = vehicleID
            pendingLiveDriveMissionRunID = missionRunID
            pendingPrimarySection = .liveDrive

        case .pluginSurface(let namespace, let parameters):
            pendingPrimarySection = nil
            pendingMissionControlRunID = nil
            pendingMissionControlMissionTaskID = nil
            pendingMissionControlLiveAssignmentID = nil
            pendingLiveDriveVehicleID = nil
            pendingLiveDriveMissionRunID = nil
            OperatorPromptReviewPluginNavigation.post(applicationNamespace: namespace, parameters: parameters)
        }
    }

    func consumePendingPrimarySection() {
        pendingPrimarySection = nil
    }

    func consumeMissionControlDrillIn() {
        pendingMissionControlRunID = nil
        pendingMissionControlMissionTaskID = nil
        pendingMissionControlLiveAssignmentID = nil
    }

    /// Clears only the pending vehicle id after ``LiveDriveStore/selectVehicle`` applies the drill-in (``pendingLiveDriveMissionRunID`` stays for prompt host until consumed).
    func consumeLiveDriveFocus() {
        pendingLiveDriveVehicleID = nil
    }

    /// Clears MC‑R → Live Drive mission run drill-in context (e.g. after mission session ends or streaming setup fails).
    func consumePendingLiveDriveMissionRunDrillIn() {
        pendingLiveDriveMissionRunID = nil
    }

    /// Mission Control running → Live Drive: switch primary section and seed vehicle selection (see ``README.md`` — Live Drive control session).
    func requestLiveDriveEngageDrillIn(vehicleID: String, missionRunID: UUID?) {
        pendingMissionControlRunID = nil
        pendingMissionControlMissionTaskID = nil
        pendingMissionControlLiveAssignmentID = nil
        pendingLiveDriveVehicleID = vehicleID
        pendingLiveDriveMissionRunID = missionRunID
        pendingPrimarySection = .liveDrive
    }

    /// Live Drive → Mission Control: open the run that owns this vehicle’s roster row (optional task focus for MC‑R triage).
    /// - When ``liveAssignmentID`` is set, MC‑R should focus that roster row (vehicle overlay) after the run UI is live.
    func requestMissionControlReturnDrillIn(runID: UUID, missionTaskID: UUID?, liveAssignmentID: UUID? = nil) {
        pendingLiveDriveVehicleID = nil
        pendingLiveDriveMissionRunID = nil
        pendingMissionControlRunID = runID
        pendingMissionControlMissionTaskID = missionTaskID
        pendingMissionControlLiveAssignmentID = liveAssignmentID
        pendingPrimarySection = .missionControl
    }
}
