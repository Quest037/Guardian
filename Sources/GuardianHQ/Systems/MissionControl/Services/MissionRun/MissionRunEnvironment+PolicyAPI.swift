import Foundation

/// Public ``MissionRunEnvironment`` APIs for editing run-affecting policies and Rules-of-Engagement.
///
/// All entry points are credential-gated by ``MissionRunPolicyAuthoritySubsystem``. Mutations that change
/// fields stored on the **mission template** (``Mission/routeMacro`` — mission-level preferential chains,
/// per-task tactic overrides, ``MissionTask/betweenCycles``, etc.) call ``applyMissionTemplateMutation``, which
/// prefers ``missionTemplatePersister`` (``MissionRunDetailView`` installs this on ``onAppear`` for the shared
/// MCS + MC‑R drill-in: ``MissionControlStore/updateRun`` after ``updateTemplate``) and otherwise updates the
/// template on the run only. Assignment-level preference chains, run geofence augmentation, and engagement rules
/// mutate ``MissionRunEnvironment`` state without ``applyMissionTemplateMutation``.
extension MissionRunEnvironment {

    // MARK: - Mission-level

    @discardableResult
    func updateMissionAbortPreferenceChain(
        _ chain: [MissionRunAbortTactic],
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.missionAbortPolicy
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard var mission = template else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .missionUnavailable)
            return .denied(.missionUnavailable)
        }
        let normalized = MissionRunAbortTactic.normalizedPreferenceChain(chain)
        mission.routeMacro.rules.missionAbortPreferenceChain = normalized
        applyMissionTemplateMutation(mission)
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: MissionRunAbortTactic.summarizedForLogging(normalized)
        )
        return .allowed
    }

    @discardableResult
    func updateMissionCompletePreferenceChain(
        _ chain: [MissionRunCompleteTactic],
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.missionCompletePolicy
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard var mission = template else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .missionUnavailable)
            return .denied(.missionUnavailable)
        }
        let normalized = MissionRunCompleteTactic.normalizedPreferenceChain(chain)
        mission.routeMacro.rules.missionCompletePreferenceChain = normalized
        applyMissionTemplateMutation(mission)
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: MissionRunCompleteTactic.summarizedForLogging(normalized)
        )
        return .allowed
    }

    @discardableResult
    func updateMissionReserveSwapPreferenceChain(
        _ chain: [MissionRunReserveSwapTactic],
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.missionReserveSwapPolicy
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard var mission = template else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .missionUnavailable)
            return .denied(.missionUnavailable)
        }
        let normalized = MissionRunReserveSwapTactic.normalizedPreferenceChain(chain)
        mission.routeMacro.rules.missionReserveSwapPreferenceChain = normalized
        applyMissionTemplateMutation(mission)
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: MissionRunReserveSwapTactic.summarizedForLogging(normalized)
        )
        return .allowed
    }

    @discardableResult
    func updateMissionEngagementRules(
        _ rules: MissionRunEngagementRules,
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.missionEngagementRules
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        policies.engagement = rules
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: "\(rules.perAction.count) override(s)"
        )
        return .allowed
    }

    @discardableResult
    func updateMissionEngagementDisposition(
        action: MissionRunEngagementAction,
        disposition: MissionRunEngagementDisposition,
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.missionEngagementRules
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        var rules = policies.engagement
        var perAction = rules.perAction
        if disposition == .autonomous {
            perAction.removeValue(forKey: action)
        } else {
            perAction[action] = MissionRunEngagementRule(disposition: disposition)
        }
        rules.perAction = perAction
        policies.engagement = rules
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: "\(action.setupLabel) → \(disposition.setupMenuLabel)"
        )
        return .allowed
    }

    // MARK: - Run geofence augmentation (run envelope only)

    @discardableResult
    func updateMissionGeofenceAugmentation(
        _ fences: [MissionGeofence],
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.missionGeofenceAugmentation
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        var next = policies
        next.missionGeofenceAugmentation = fences
        policies = next
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: MissionRunGeofencePolicyResolution.summarizedFenceIDsForLogging(fences)
        )
        return .allowed
    }

    @discardableResult
    func updateTaskGeofenceAugmentation(
        taskID: UUID,
        _ fences: [MissionGeofence],
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.taskGeofenceAugmentation(taskID: taskID)
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard let mission = template else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .missionUnavailable)
            return .denied(.missionUnavailable)
        }
        guard mission.routeMacro.tasks.contains(where: { $0.id == taskID }) else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .taskNotFound)
            return .denied(.taskNotFound)
        }
        var copy = taskGeofenceAugmentationsByTaskID
        if fences.isEmpty {
            copy.removeValue(forKey: taskID)
        } else {
            copy[taskID] = fences
        }
        taskGeofenceAugmentationsByTaskID = copy
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: MissionRunGeofencePolicyResolution.summarizedFenceIDsForLogging(fences)
        )
        return .allowed
    }

    @discardableResult
    func updateAssignmentGeofenceAugmentation(
        assignmentID: UUID,
        _ fences: [MissionGeofence],
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.assignmentGeofenceAugmentation(assignmentID: assignmentID)
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard let idx = assignments.firstIndex(where: { $0.id == assignmentID }) else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .assignmentNotFound)
            return .denied(.assignmentNotFound)
        }
        assignments[idx].policies.geofenceAugmentation = fences
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: MissionRunGeofencePolicyResolution.summarizedFenceIDsForLogging(fences)
        )
        return .allowed
    }

    // MARK: - Task-level

    @discardableResult
    func updateTaskAbortPreferenceChainOverride(
        taskID: UUID,
        _ chain: [MissionRunAbortTactic]?,
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.taskAbortPolicyOverride(taskID: taskID)
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard var mission = template else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .missionUnavailable)
            return .denied(.missionUnavailable)
        }
        guard let idx = mission.routeMacro.tasks.firstIndex(where: { $0.id == taskID }) else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .taskNotFound)
            return .denied(.taskNotFound)
        }
        let logValue: String
        if let chain, !chain.isEmpty {
            let normalized = MissionRunAbortTactic.normalizedPreferenceChain(chain)
            mission.routeMacro.tasks[idx].abortPreferenceChainOverride = normalized
            logValue = MissionRunAbortTactic.summarizedForLogging(normalized)
        } else {
            mission.routeMacro.tasks[idx].abortPreferenceChainOverride = nil
            logValue = "Inherit"
        }
        applyMissionTemplateMutation(mission)
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: logValue
        )
        return .allowed
    }

    @discardableResult
    func updateTaskCompletePreferenceChainOverride(
        taskID: UUID,
        _ chain: [MissionRunCompleteTactic]?,
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.taskCompletePolicyOverride(taskID: taskID)
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard var mission = template else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .missionUnavailable)
            return .denied(.missionUnavailable)
        }
        guard let idx = mission.routeMacro.tasks.firstIndex(where: { $0.id == taskID }) else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .taskNotFound)
            return .denied(.taskNotFound)
        }
        let logValue: String
        if let chain, !chain.isEmpty {
            let normalized = MissionRunCompleteTactic.normalizedPreferenceChain(chain)
            mission.routeMacro.tasks[idx].completePreferenceChainOverride = normalized
            logValue = MissionRunCompleteTactic.summarizedForLogging(normalized)
        } else {
            mission.routeMacro.tasks[idx].completePreferenceChainOverride = nil
            logValue = "Inherit"
        }
        applyMissionTemplateMutation(mission)
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: logValue
        )
        return .allowed
    }

    @discardableResult
    func updateTaskReserveSwapPreferenceChainOverride(
        taskID: UUID,
        _ chain: [MissionRunReserveSwapTactic]?,
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.taskReserveSwapPolicyOverride(taskID: taskID)
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard var mission = template else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .missionUnavailable)
            return .denied(.missionUnavailable)
        }
        guard let idx = mission.routeMacro.tasks.firstIndex(where: { $0.id == taskID }) else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .taskNotFound)
            return .denied(.taskNotFound)
        }
        let logValue: String
        if let chain, !chain.isEmpty {
            let normalized = MissionRunReserveSwapTactic.normalizedPreferenceChain(chain)
            mission.routeMacro.tasks[idx].reserveSwapPreferenceChainOverride = normalized
            logValue = MissionRunReserveSwapTactic.summarizedForLogging(normalized)
        } else {
            mission.routeMacro.tasks[idx].reserveSwapPreferenceChainOverride = nil
            logValue = "Inherit"
        }
        applyMissionTemplateMutation(mission)
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: logValue
        )
        return .allowed
    }

    @discardableResult
    func updateTaskBetweenCyclesAction(
        taskID: UUID,
        _ action: MissionTaskBetweenCyclesAction,
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.taskBetweenCyclesAction(taskID: taskID)
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard var mission = template else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .missionUnavailable)
            return .denied(.missionUnavailable)
        }
        guard let idx = mission.routeMacro.tasks.firstIndex(where: { $0.id == taskID }) else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .taskNotFound)
            return .denied(.taskNotFound)
        }
        mission.routeMacro.tasks[idx].betweenCycles = action
        applyMissionTemplateMutation(mission)
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: action.displayTitle
        )
        return .allowed
    }

    // MARK: - Assignment-level

    @discardableResult
    func updateAssignmentAbortPreferenceChain(
        assignmentID: UUID,
        _ chain: [MissionRunAbortTactic]?,
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.assignmentAbortPolicy(assignmentID: assignmentID)
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard let idx = assignments.firstIndex(where: { $0.id == assignmentID }) else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .assignmentNotFound)
            return .denied(.assignmentNotFound)
        }
        let logValue: String
        if let chain, !chain.isEmpty {
            let normalized = MissionRunAbortTactic.normalizedPreferenceChain(chain)
            assignments[idx].policies.abortPreferenceChain = normalized
            logValue = MissionRunAbortTactic.summarizedForLogging(normalized)
        } else {
            assignments[idx].policies.abortPreferenceChain = nil
            logValue = "Inherit"
        }
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: logValue
        )
        return .allowed
    }

    @discardableResult
    func updateAssignmentCompletePreferenceChain(
        assignmentID: UUID,
        _ chain: [MissionRunCompleteTactic]?,
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.assignmentCompletePolicy(assignmentID: assignmentID)
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard let idx = assignments.firstIndex(where: { $0.id == assignmentID }) else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .assignmentNotFound)
            return .denied(.assignmentNotFound)
        }
        let logValue: String
        if let chain, !chain.isEmpty {
            let normalized = MissionRunCompleteTactic.normalizedPreferenceChain(chain)
            assignments[idx].policies.completePreferenceChain = normalized
            logValue = MissionRunCompleteTactic.summarizedForLogging(normalized)
        } else {
            assignments[idx].policies.completePreferenceChain = nil
            logValue = "Inherit"
        }
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: logValue
        )
        return .allowed
    }

    @discardableResult
    func updateAssignmentReserveSwapPreferenceChain(
        assignmentID: UUID,
        _ chain: [MissionRunReserveSwapTactic]?,
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        let scope = MissionRunPolicyEditScope.assignmentReserveSwapPolicy(assignmentID: assignmentID)
        let decision = systems.policyAuthority.evaluate(scope, credential: credential)
        guard decision.isAllowed else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: denialReason(decision) ?? .permissionDenied)
            return decision
        }
        guard let idx = assignments.firstIndex(where: { $0.id == assignmentID }) else {
            logPolicyEditDenied(scope: scope, credential: credential, reason: .assignmentNotFound)
            return .denied(.assignmentNotFound)
        }
        let logValue: String
        if let chain, !chain.isEmpty {
            let normalized = MissionRunReserveSwapTactic.normalizedPreferenceChain(chain)
            assignments[idx].policies.reserveSwapPreferenceChain = normalized
            logValue = MissionRunReserveSwapTactic.summarizedForLogging(normalized)
        } else {
            assignments[idx].policies.reserveSwapPreferenceChain = nil
            logValue = "Inherit"
        }
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: logValue
        )
        return .allowed
    }

    // MARK: - Helpers

    private func applyMissionTemplateMutation(_ mission: Mission) {
        if let persister = missionTemplatePersister {
            persister(mission)
        } else {
            updateTemplate(mission)
        }
    }

    private func denialReason(_ decision: MissionRunPolicyEditDecision) -> MissionRunPolicyEditDenialReason? {
        if case .denied(let reason) = decision { return reason }
        return nil
    }

    private func logPolicyEditApplied(
        scope: MissionRunPolicyEditScope,
        credential: MissionRunPolicyEditCredential,
        value: String
    ) {
        systems.logging.appendLogEvent(
            level: .info,
            taskID: scopeTaskID(scope),
            taskLabel: scopeTaskLabel(scope),
            speaker: speaker(for: credential),
            target: target(for: scope),
            templateKey: MissionRunLogTemplateKey.policyAuthorityEditApplied,
            templateParams: [
                "scope": scopeDisplayLabel(scope),
                "value": value,
                "issuer": credential.issuer.rawValue,
                "issuerKey": credential.issuerKey,
            ]
        )
    }

    private func logPolicyEditDenied(
        scope: MissionRunPolicyEditScope,
        credential: MissionRunPolicyEditCredential,
        reason: MissionRunPolicyEditDenialReason
    ) {
        systems.logging.appendLogEvent(
            level: .warning,
            taskID: scopeTaskID(scope),
            taskLabel: scopeTaskLabel(scope),
            speaker: speaker(for: credential),
            target: target(for: scope),
            templateKey: MissionRunLogTemplateKey.policyAuthorityEditDenied,
            templateParams: [
                "scope": scopeDisplayLabel(scope),
                "reason": reason.displayLabel,
                "issuer": credential.issuer.rawValue,
                "issuerKey": credential.issuerKey,
            ]
        )
    }

    /// Structural addressee for a policy / RoE edit event: the entity whose policy was changed.
    /// Mission-level + engagement edits address ``MissionRunEventTarget/missionControl`` (the runtime
    /// owner). Task and slot edits address the specific task or slot so MCR rows render `@<name>`
    /// in the canonical color and link to the matching overlay.
    private func target(for scope: MissionRunPolicyEditScope) -> MissionRunEventTarget {
        switch scope {
        case .missionAbortPolicy, .missionCompletePolicy, .missionEngagementRules, .missionReserveSwapPolicy, .missionGeofenceAugmentation:
            return .missionControl
        case .taskAbortPolicyOverride(let id), .taskCompletePolicyOverride(let id), .taskReserveSwapPolicyOverride(let id), .taskBetweenCyclesAction(let id), .taskGeofenceAugmentation(let id):
            let name = template?.routeMacro.tasks.first(where: { $0.id == id })?.name ?? "Task"
            return .task(id: id, name: name)
        case .assignmentAbortPolicy(let id), .assignmentCompletePolicy(let id), .assignmentReserveSwapPolicy(let id), .assignmentGeofenceAugmentation(let id):
            return .slot(id: id)
        }
    }

    private func speaker(for credential: MissionRunPolicyEditCredential) -> MissionRunEventSpeaker {
        switch credential.issuer {
        case .operator:
            return .operator(displayName: credential.displayName)
        case .missionControl:
            return .missionControl
        case .assistant:
            return .assistant(key: credential.issuerKey)
        }
    }

    /// Task that owns this scope, if any. Slot scopes resolve through
    /// ``MissionRunPolicyResolution/resolvedTaskId(for:mission:)`` so MCR rows render the
    /// `[<TaskName>]` wrapper for slot edits the same way they do for task edits.
    private func scopeTaskID(_ scope: MissionRunPolicyEditScope) -> UUID? {
        switch scope {
        case .taskAbortPolicyOverride(let id), .taskCompletePolicyOverride(let id), .taskReserveSwapPolicyOverride(let id), .taskBetweenCyclesAction(let id), .taskGeofenceAugmentation(let id):
            return id
        case .assignmentAbortPolicy(let id), .assignmentCompletePolicy(let id), .assignmentReserveSwapPolicy(let id), .assignmentGeofenceAugmentation(let id):
            guard let assignment = assignments.first(where: { $0.id == id }) else { return nil }
            return MissionRunPolicyResolution.resolvedTaskId(for: assignment, mission: template)
        default:
            return nil
        }
    }

    private func scopeTaskLabel(_ scope: MissionRunPolicyEditScope) -> String? {
        guard let taskID = scopeTaskID(scope), let mission = template else { return nil }
        return mission.routeMacro.tasks.first(where: { $0.id == taskID })?.name
    }

    /// Human label that fills `{{scope}}` in policy-authority log templates. Pure narrative —
    /// addressee is now structural (see ``target(for:)``) so the body no longer embeds a mention.
    private func scopeDisplayLabel(_ scope: MissionRunPolicyEditScope) -> String {
        switch scope {
        case .missionAbortPolicy: return "Mission abort preference chain"
        case .missionCompletePolicy: return "Mission complete preference chain"
        case .missionEngagementRules: return "Rules of engagement"
        case .missionReserveSwapPolicy: return "Mission reserve swap preference chain"
        case .taskAbortPolicyOverride: return "Task abort policy override"
        case .taskCompletePolicyOverride: return "Task complete policy override"
        case .taskReserveSwapPolicyOverride: return "Task reserve swap policy override"
        case .taskBetweenCyclesAction: return "Task between-cycles action"
        case .assignmentAbortPolicy: return "Slot abort policy"
        case .assignmentCompletePolicy: return "Slot complete policy"
        case .assignmentReserveSwapPolicy: return "Slot reserve swap policy"
        case .missionGeofenceAugmentation: return "Mission run geofence augmentation"
        case .taskGeofenceAugmentation: return "Task run geofence augmentation"
        case .assignmentGeofenceAugmentation: return "Slot run geofence augmentation"
        }
    }
}

extension MissionRunPolicyEditDenialReason {
    var displayLabel: String {
        switch self {
        case .permissionDenied: return "permission denied"
        case .missionUnavailable: return "mission unavailable"
        case .taskNotFound: return "task not found"
        case .assignmentNotFound: return "assignment not found"
        }
    }
}
