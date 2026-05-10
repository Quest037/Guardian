import Foundation

@MainActor
final class PaladinMissionControlDomain: MissionControlRunObserver {
    private weak var missionControlStore: MissionControlStore?
    private var observerToken: UUID?
    /// Token for ``MissionControlStore/enqueueMissionRunCommandBatch`` / cancel APIs (requires `.manageExecutionQueue`).
    var missionControlObserverToken: UUID? { observerToken }
    private var assistantsByRunID: [UUID: PaladinMissionAssistant] = [:]

    func connect(to store: MissionControlStore) {
        if missionControlStore === store { return }
        if let previousStore = missionControlStore, let token = observerToken {
            previousStore.unregisterRunObserver(token: token)
        }
        missionControlStore = store
        observerToken = store.registerRunObserver(
            self,
            permissions: [.observe, .act, .manageExecutionQueue, .handoff]
        )
        for run in store.runs {
            attachAssistant(to: run)
        }
    }

    func missionControlStore(
        _ store: MissionControlStore,
        didCreate run: MissionRunEnvironment,
        permissions: MissionRunObserverPermissions
    ) {
        guard permissions.contains(.observe) else { return }
        attachAssistant(to: run)
    }

    func missionControlStore(
        _ store: MissionControlStore,
        didStart run: MissionRunEnvironment,
        context: MissionRunStartContext,
        permissions: MissionRunObserverPermissions
    ) {
        guard permissions.contains(.observe) else { return }
        _ = context
        _ = attachAssistant(to: run)
    }

    func missionControlStore(
        _ store: MissionControlStore,
        willDelete run: MissionRunEnvironment,
        permissions: MissionRunObserverPermissions
    ) {
        guard permissions.contains(.observe) else { return }
        detachAssistant(from: run)
    }

    @discardableResult
    private func attachAssistant(to run: MissionRunEnvironment) -> PaladinMissionAssistant {
        if let existing = assistantsByRunID[run.id] {
            existing.missionControlStore = missionControlStore
            existing.missionControlObserverToken = observerToken
            run.installAssistant(existing, key: PaladinMissionAssistant.assistantKey)
            return existing
        }
        let assistant = PaladinMissionAssistant(runID: run.id)
        assistant.missionControlStore = missionControlStore
        assistant.missionControlObserverToken = observerToken
        assistantsByRunID[run.id] = assistant
        run.installAssistant(assistant, key: PaladinMissionAssistant.assistantKey)
        return assistant
    }

    private func detachAssistant(from run: MissionRunEnvironment) {
        if let assistant = assistantsByRunID[run.id] {
            assistant.missionControlStore = nil
            assistant.missionControlObserverToken = nil
        }
        run.removeAssistant(forKey: PaladinMissionAssistant.assistantKey)
        assistantsByRunID.removeValue(forKey: run.id)
    }
}
