import Foundation

/// Paladin-specific event wrapper. Internally materializes a ``MissionRunEvent`` with
/// `speaker == .assistant(key: PaladinMissionAssistant.assistantKey)` so run logs show
/// assistant-authored lines distinctly from Mission Control. The display name (`Paladin`) is
/// resolved by ``MissionRunAssistantRegistry`` at render time, so other assistants plug in the
/// same way without changing renderers.
///
/// New Paladin-authored lines must supply a ``MissionRunLogTemplateKey`` / catalog id via
/// ``init(id:at:level:taskID:taskLabel:templateKey:templateParams:)`` so ``message`` is
/// resolved from ``StructuredLogTemplateCatalog`` (same rules as MC run logging).
struct PaladinEvent: Identifiable, Equatable {
    let missionRunEvent: MissionRunEvent

    var id: UUID { missionRunEvent.id }

    /// Re-wraps an existing run event as Paladin-spoken. When `missionRunEvent` has a
    /// ``MissionRunEvent/templateKey``, ``message`` is re-materialized from the catalog so it
    /// stays aligned with export defaults; otherwise preserves stored ``MissionRunEvent/message``
    /// (legacy rows only).
    init(_ missionRunEvent: MissionRunEvent) {
        if let key = missionRunEvent.templateKey {
            self.missionRunEvent = MissionRunEvent(
                level: missionRunEvent.level,
                taskID: missionRunEvent.taskID,
                taskLabel: missionRunEvent.taskLabel,
                speaker: .assistant(key: PaladinMissionAssistant.assistantKey),
                templateKey: key,
                templateParams: missionRunEvent.templateParams,
                id: missionRunEvent.id,
                at: missionRunEvent.at
            )
        } else {
            self.missionRunEvent = MissionRunEvent(
                id: missionRunEvent.id,
                at: missionRunEvent.at,
                level: missionRunEvent.level,
                taskID: missionRunEvent.taskID,
                taskLabel: missionRunEvent.taskLabel,
                speaker: .assistant(key: PaladinMissionAssistant.assistantKey),
                message: missionRunEvent.message,
                templateKey: nil,
                templateParams: missionRunEvent.templateParams
            )
        }
    }

    /// Catalog-backed Paladin line (`message` from ``StructuredLogTemplateCatalog``).
    init(
        id: UUID = UUID(),
        at: Date = Date(),
        level: MissionRunEventLevel = .info,
        taskID: UUID? = nil,
        taskLabel: String? = nil,
        templateKey: String,
        templateParams: [String: String] = [:]
    ) {
        self.missionRunEvent = MissionRunEvent(
            level: level,
            taskID: taskID,
            taskLabel: taskLabel,
            speaker: .assistant(key: PaladinMissionAssistant.assistantKey),
            templateKey: templateKey,
            templateParams: templateParams,
            id: id,
            at: at
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
/// Per-run Mission Control assistant. Task **attempting** (``MissionRunEnvironment/taskAttemptingByTaskID`` / ``MissionTaskAttemptState``) co-refreshes with ``taskStateByTaskID``; read that map when Paladin needs protocol intent distinct from settled ``MissionTaskState``.
final class PaladinMissionAssistant {
    /// RGB card **background** for Paladin-originated **operator prompts** (MC-R / Decisions). Owned by the plugin — Mission Control must never hardcode this value.
    nonisolated static let operatorPromptCardBackgroundHex6 = "b996d3"

    /// Plain string constant — `nonisolated` so non-MainActor sites (e.g. ``PaladinEvent`` initializers)
    /// can reference the canonical assistant key without crossing actor boundaries.
    nonisolated static let assistantKey = "paladin.missionAssistant"
    /// Display name used by ``MissionRunAssistantRegistry`` for `[Paladin]` log prefixes and
    /// `@paladin` target mentions in MC-R rows / plain-text export.
    nonisolated static let assistantDisplayName = "Paladin"

    /// Idempotently publishes Paladin's identity to ``MissionRunAssistantRegistry`` and registers
    /// Paladin-owned ``MissionRunLogTemplateKey`` patterns with ``StructuredLogTemplateCatalog`` so
    /// log renderers resolve `.assistant(key: assistantKey)` events to a `[Paladin]` prefix and
    /// every Paladin-emitted templateKey resolves to its catalog wording — all without core code
    /// having to know about Paladin. Called from ``init(runID:)`` so any code path that constructs
    /// a Paladin assistant ensures both profile and templates are registered.
    static func registerProfile() {
        guard GuardianPluginRegistry.shared.isPluginEnabled(.paladin) else { return }
        MissionRunAssistantRegistry.shared.register(
            MissionRunAssistantProfile(key: assistantKey, displayName: assistantDisplayName)
        )
        PaladinLogTemplateCatalog.registerTemplates()
    }

    let runID: UUID
    weak var missionControlStore: MissionControlStore?
    var missionControlObserverToken: UUID?

    init(runID: UUID) {
        self.runID = runID
        Self.registerProfile()
    }

    /// **Headless:** forwards a fixed-reserve → active swap proposal to ``MissionControlStore`` (no UI). Mission Control
    /// may show an MC-R engagement prompt when rules of engagement require operator consent; requires ``MissionRunObserverPermissions/act``.
    @discardableResult
    func raiseSwapInReservePrompt(primaryAssignmentID: UUID, reserveAssignmentID: UUID) -> Bool {
        guard let store = missionControlStore, let token = missionControlObserverToken else { return false }
        return store.raiseOperatorPromptSwapInReserve(
            runID: runID,
            primaryAssignmentID: primaryAssignmentID,
            reserveAssignmentID: reserveAssignmentID,
            issuerKey: MissionRunCommandIssuerKey.paladin,
            operatorPromptDisplaySource: .assistant(
                pluginID: GuardianPluginID.paladin.rawValue,
                displayName: Self.assistantDisplayName,
                operatorPromptBackgroundHex: Self.operatorPromptCardBackgroundHex6
            ),
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
            speaker: .assistant(key: PaladinMissionAssistant.assistantKey),
            templateKey: MissionRunLogTemplateKey.paladinExecutionStarted
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
