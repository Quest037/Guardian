import Combine
import Foundation

// MARK: - OperatorPromptCenter

/// Stateful Stage D host: ``OperatorPromptRouter`` availability from registered UI hosts,
/// mounts each ``OperatorPromptRoutingDecision/dispatched`` target, and bridges
/// ``OperatorPromptResumptionChannel/awaitAnswer(for:)``.
///
/// Production publishers should use ``OperatorPromptCenter/shared`` and ``awaitAnswer(for:)``.
@MainActor
final class OperatorPromptCenter: ObservableObject {

    // MARK: Shared

    static let shared = OperatorPromptCenter(
        router: OperatorPromptRouter.shared,
        resumption: OperatorPromptResumptionChannel.shared
    )

    // MARK: Published surfaces

    /// In-app Decisions drawer (``OperatorPromptDeliveryTarget/inAppInbox``).
    @Published private(set) var inboxPrompts: [OperatorPromptEvent] = []

    /// MC-R bottom strip for the given mission run id (``OperatorPromptDeliveryTarget/mcrPromptPanel``).
    @Published private(set) var activeMCRPromptsByMissionRunID: [UUID: [OperatorPromptEvent]] = [:]

    /// Live Drive bottom strip (``OperatorPromptDeliveryTarget/liveDrivePromptPanel``).
    @Published private(set) var activeLiveDrivePrompts: [OperatorPromptEvent] = []

    /// Sticky top-leading (primary content column) window chips (``OperatorPromptDeliveryTarget/persistentToast``).
    /// Omitted when the same event is already dispatched to MC-R or Live Drive so the operator is not doubled up.
    @Published private(set) var persistentOperatorToastPrompts: [OperatorPromptEvent] = []

    // MARK: Host registry (router availability)

    /// Mission runs whose MC-R prompt strip is currently on-screen.
    private var mcrPromptHostMissionRunIDs: Set<UUID> = []

    /// Live Drive host: vehicle always set when active; mission run id set when that vehicle is engaged on a live run.
    private var liveDrivePromptHostVehicleID: String?
    private var liveDrivePromptHostMissionRunID: UUID?

    private let router: OperatorPromptRouter
    private let resumption: OperatorPromptResumptionChannel

    // MARK: Init

    init(router: OperatorPromptRouter, resumption: OperatorPromptResumptionChannel) {
        self.router = router
        self.resumption = resumption
    }

    // MARK: Session wiring

    func prepareOperatorPromptRoutingSession() {
        router.availabilityProbe = { [weak self] target in
            guard let self else { return OperatorPromptRouter.defaultAvailabilityProbe(target) }
            return self.evaluateDeliveryAvailability(for: target)
        }
    }

    /// Router probe: inbox and persistent operator toast always on; MC-R / Live Drive match registered hosts.
    func evaluateDeliveryAvailability(for target: OperatorPromptDeliveryTarget) -> Bool {
        switch target {
        case .inAppInbox:
            return true
        case .mcrPromptPanel(let missionRunID):
            return mcrPromptHostMissionRunIDs.contains(missionRunID)
        case .liveDrivePromptPanel(let runID, let vehicleID):
            guard let hostVehicle = liveDrivePromptHostVehicleID else { return false }
            if let vehicleID, vehicleID != hostVehicle { return false }
            if let runID {
                guard let hostRun = liveDrivePromptHostMissionRunID, hostRun == runID else { return false }
            }
            return true
        case .persistentToast:
            return true
        case .userNotification, .vehicleInspectorWizardPanel:
            return false
        }
    }

    // MARK: Host registration (SwiftUI onAppear / onDisappear)

    /// Call from ``MissionRunOperatorRecipePromptBanner`` (or any MC-R surface that can show recipe prompts).
    func setMCRPromptPanelHostActive(_ active: Bool, missionRunID: UUID) {
        if active {
            mcrPromptHostMissionRunIDs.insert(missionRunID)
        } else {
            mcrPromptHostMissionRunIDs.remove(missionRunID)
            clearMCRSurfacePrompts(missionRunID: missionRunID)
        }
    }

    /// Call from Live Drive when the tab is visible and a control session + vehicle context apply.
    /// Pass `isActive: false` (or `vehicleID: nil`) to clear.
    func setLiveDrivePromptPanelHostContext(isActive: Bool, missionRunID: UUID?, vehicleID: String?) {
        guard isActive, let vehicleID, !vehicleID.isEmpty else {
            liveDrivePromptHostVehicleID = nil
            liveDrivePromptHostMissionRunID = nil
            activeLiveDrivePrompts = []
            return
        }
        liveDrivePromptHostVehicleID = vehicleID
        liveDrivePromptHostMissionRunID = missionRunID
    }

    // MARK: Queries

    func activeMCRPrompts(forMissionRunID runID: UUID) -> [OperatorPromptEvent] {
        activeMCRPromptsByMissionRunID[runID] ?? []
    }

    // MARK: Publisher API

    func awaitAnswer(for event: OperatorPromptEvent) async -> OperatorPromptAnswer {
        if event.isExpired() {
            return await resumption.awaitAnswer(for: event)
        }

        let decision = router.route(event)
        mountDispatchedPrompts(event, decision: decision)

        let expiry = scheduleExpiry(for: event)
        defer {
            expiry.cancel()
            unmountPromptFromAllSurfaces(promptID: event.id)
        }

        return await resumption.awaitAnswer(for: event)
    }

    @discardableResult
    func submitAnswer(_ answer: OperatorPromptAnswer) -> Bool {
        let ok = resumption.submit(answer)
        if ok { unmountPromptFromAllSurfaces(promptID: answer.promptID) }
        return ok
    }

    @discardableResult
    func resolveExpiry(for event: OperatorPromptEvent) -> Bool {
        let ok = resumption.resolveExpiry(for: event)
        if ok { unmountPromptFromAllSurfaces(promptID: event.id) }
        return ok
    }

    // MARK: Mount / unmount

    private func mountDispatchedPrompts(_ event: OperatorPromptEvent, decision: OperatorPromptRoutingDecision) {
        let skipPersistentToastBecauseStripHostsHavePrompt = Self.dispatchedIncludesMCRorLiveDrive(
            decision.dispatched
        )
        for target in decision.dispatched {
            switch target {
            case .inAppInbox:
                registerInbox(event)
            case .mcrPromptPanel(let missionRunID):
                var list = activeMCRPromptsByMissionRunID[missionRunID] ?? []
                appendUniquePrompt(&list, event: event)
                var mcrCopy = activeMCRPromptsByMissionRunID
                mcrCopy[missionRunID] = list
                activeMCRPromptsByMissionRunID = mcrCopy
            case .liveDrivePromptPanel(_, _):
                var list = activeLiveDrivePrompts
                appendUniquePrompt(&list, event: event)
                activeLiveDrivePrompts = list
            case .persistentToast:
                guard !skipPersistentToastBecauseStripHostsHavePrompt else { break }
                var toastList = persistentOperatorToastPrompts
                appendUniquePrompt(&toastList, event: event)
                persistentOperatorToastPrompts = toastList
            case .userNotification, .vehicleInspectorWizardPanel:
                break
            }
        }
    }

    /// When MC-R or Live Drive already carries this dispatch list, skip mounting the sticky toast for the same event
    /// so the operator is not shown duplicate chrome. (Vehicle Inspector wizard is not a mounted Stage D surface yet.)
    private static func dispatchedIncludesMCRorLiveDrive(_ dispatched: [OperatorPromptDeliveryTarget]) -> Bool {
        dispatched.contains {
            switch $0 {
            case .mcrPromptPanel, .liveDrivePromptPanel:
                return true
            case .vehicleInspectorWizardPanel, .inAppInbox, .persistentToast, .userNotification:
                return false
            }
        }
    }

    private func appendUniquePrompt(_ list: inout [OperatorPromptEvent], event: OperatorPromptEvent) {
        if list.contains(where: { $0.id == event.id }) { return }
        list.append(event)
    }

    private func registerInbox(_ event: OperatorPromptEvent) {
        var list = inboxPrompts
        appendUniquePrompt(&list, event: event)
        inboxPrompts = list
    }

    private func unmountPromptFromAllSurfaces(promptID: UUID) {
        inboxPrompts.removeAll { $0.id == promptID }
        persistentOperatorToastPrompts.removeAll { $0.id == promptID }
        activeLiveDrivePrompts.removeAll { $0.id == promptID }
        var mcrCopy = activeMCRPromptsByMissionRunID
        for (key, list) in mcrCopy {
            let filtered = list.filter { $0.id != promptID }
            if filtered.isEmpty {
                mcrCopy.removeValue(forKey: key)
            } else {
                mcrCopy[key] = filtered
            }
        }
        activeMCRPromptsByMissionRunID = mcrCopy
    }

    private func clearMCRSurfacePrompts(missionRunID: UUID) {
        var copy = activeMCRPromptsByMissionRunID
        copy.removeValue(forKey: missionRunID)
        activeMCRPromptsByMissionRunID = copy
    }

    private func scheduleExpiry(for event: OperatorPromptEvent) -> Task<Void, Never> {
        let remaining = event.expiresAt.timeIntervalSinceNow
        if remaining <= 0 {
            return Task { @MainActor [weak self] in
                _ = self?.resumption.resolveExpiry(for: event)
            }
        }
        let cappedSeconds = min(max(remaining, 0.001), 86_400.0)
        let ns = UInt64(cappedSeconds * 1_000_000_000.0)
        return Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            _ = self.resumption.resolveExpiry(for: event)
        }
    }
}
