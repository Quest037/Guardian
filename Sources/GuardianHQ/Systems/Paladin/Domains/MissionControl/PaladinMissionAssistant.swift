import Foundation

/// Paladin-specific event wrapper. Internally materializes a `MissionRunEvent` with
/// `speaker == .paladin` so Mission Control remains the canonical mission runner.
struct PaladinEvent: Identifiable, Equatable {
    let missionRunEvent: MissionRunEvent

    var id: UUID { missionRunEvent.id }

    init(_ missionRunEvent: MissionRunEvent) {
        self.missionRunEvent = MissionRunEvent(
            id: missionRunEvent.id,
            at: missionRunEvent.at,
            level: missionRunEvent.level,
            taskID: missionRunEvent.taskID,
            taskLabel: missionRunEvent.taskLabel,
            speaker: .paladin,
            message: missionRunEvent.message,
            templateKey: missionRunEvent.templateKey,
            templateParams: missionRunEvent.templateParams
        )
    }

    init(
        id: UUID = UUID(),
        at: Date = Date(),
        level: MissionRunEventLevel = .info,
        taskID: UUID? = nil,
        taskLabel: String? = nil,
        message: String,
        templateKey: String? = nil,
        templateParams: [String: String] = [:]
    ) {
        self.missionRunEvent = MissionRunEvent(
            id: id,
            at: at,
            level: level,
            taskID: taskID,
            taskLabel: taskLabel,
            speaker: .paladin,
            message: message,
            templateKey: templateKey,
            templateParams: templateParams
        )
    }
}

struct PaladinIssuedCommand: Equatable {
    let missionRunIssuedCommand: MissionRunIssuedCommand

    init(
        assignmentID: UUID,
        slotName: String,
        vehicleTokenKey: String,
        command: FleetVehicleCommand
    ) {
        missionRunIssuedCommand = MissionRunIssuedCommand(
            assignmentID: assignmentID,
            slotName: slotName,
            vehicleTokenKey: vehicleTokenKey,
            command: command,
            issuer: .assistant,
            issuerKey: MissionRunCommandIssuerKey.paladin,
            category: .paladin
        )
    }
}

@MainActor
final class PaladinMissionAssistant {
    static let assistantKey = "paladin.missionAssistant"

    let runID: UUID
    weak var missionControlStore: MissionControlStore?
    var missionControlObserverToken: UUID?

    init(runID: UUID) {
        self.runID = runID
    }

    /// Raises a swap-in-reserve operator prompt when the store token has ``MissionRunObserverPermissions/act``.
    @discardableResult
    func raiseSwapInReservePrompt(primaryAssignmentID: UUID, reserveAssignmentID: UUID) -> Bool {
        guard let store = missionControlStore, let token = missionControlObserverToken else { return false }
        return store.raiseOperatorPromptSwapInReserve(
            runID: runID,
            primaryAssignmentID: primaryAssignmentID,
            reserveAssignmentID: reserveAssignmentID,
            issuerKey: MissionRunCommandIssuerKey.paladin,
            observerToken: token
        )
    }

    func engageRunStart(
        run: MissionRunEnvironment,
        context: MissionRunStartContext
    ) {
        guard run.id == runID else { return }
        guard run.compiledPlan != nil else { return }
        run.systems.logging.appendLogEvent(
            level: .info,
            speaker: .paladin,
            message: "Paladin execution started.",
            templateKey: PaladinLogTemplateKey.executionStarted
        )
        let ctx = MissionRunExecutionContext(
            mission: context.mission,
            fleetLink: context.fleetLink,
            sitl: context.sitl,
            missionProvider: { [missionsProvider = context.missionsProvider, run] in
                missionsProvider().first { $0.id == run.missionId }
            }
        )
        run.captureExecutionContext(ctx)
        _ = run.systems.executor.startExecution(context: ctx)
        UserNotificationService.shared.notifyPaladinExecutionStarted(
            runID: runID,
            missionName: run.missionName
        )
    }
}
