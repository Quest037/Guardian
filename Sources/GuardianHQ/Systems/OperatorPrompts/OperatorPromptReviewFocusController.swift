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

    /// Live Drive vehicle selection — ``LiveDriveView`` calls ``LiveDriveStore/selectVehicle`` then ``consumeLiveDriveFocus()``.
    @Published private(set) var pendingLiveDriveVehicleID: String?
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
            pendingPrimarySection = .missionControl

        case .liveDriveSession(let vehicleID, let missionRunID):
            pendingMissionControlRunID = nil
            pendingMissionControlMissionTaskID = nil
            pendingLiveDriveVehicleID = vehicleID
            pendingLiveDriveMissionRunID = missionRunID
            pendingPrimarySection = .liveDrive

        case .pluginSurface(let namespace, let parameters):
            pendingPrimarySection = nil
            pendingMissionControlRunID = nil
            pendingMissionControlMissionTaskID = nil
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
    }

    func consumeLiveDriveFocus() {
        pendingLiveDriveVehicleID = nil
        pendingLiveDriveMissionRunID = nil
    }
}
