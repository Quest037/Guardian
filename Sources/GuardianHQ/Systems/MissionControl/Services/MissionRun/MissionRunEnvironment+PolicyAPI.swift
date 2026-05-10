import Foundation

/// Public ``MissionRunEnvironment`` APIs for editing run-affecting policies and Rules-of-Engagement.
///
/// All entry points are credential-gated by ``MissionRunPolicyAuthoritySubsystem``. Mission and per-task
/// edits route through ``MissionRunEnvironment/missionTemplatePersister`` so that downstream stores
/// (``MissionStore``) remain the source of truth for the mission template; assignment and engagement
/// edits live on the run environment itself.
extension MissionRunEnvironment {

    // MARK: - Mission-level

    @discardableResult
    func updateMissionAbortPolicy(
        _ policy: MissionRunAbortPolicy,
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
        mission.routeMacro.rules.missionAbortPolicy = policy
        applyMissionTemplateMutation(mission)
        logPolicyEditApplied(scope: scope, credential: credential, value: policy.setupMenuLabel)
        return .allowed
    }

    @discardableResult
    func updateMissionCompletePolicy(
        _ policy: MissionRunCompletePolicy,
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
        mission.routeMacro.rules.missionCompletePolicy = policy
        applyMissionTemplateMutation(mission)
        logPolicyEditApplied(scope: scope, credential: credential, value: policy.setupMenuLabel)
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

    // MARK: - Task-level

    @discardableResult
    func updateTaskAbortPolicyOverride(
        taskID: UUID,
        _ policy: MissionRunAbortPolicy?,
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
        mission.routeMacro.tasks[idx].abortPolicyOverride = policy
        applyMissionTemplateMutation(mission)
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: policy?.setupMenuLabel ?? "Inherit"
        )
        return .allowed
    }

    @discardableResult
    func updateTaskCompletePolicyOverride(
        taskID: UUID,
        _ policy: MissionRunCompletePolicy?,
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
        mission.routeMacro.tasks[idx].completePolicyOverride = policy
        applyMissionTemplateMutation(mission)
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: policy?.setupMenuLabel ?? "Inherit"
        )
        return .allowed
    }

    // MARK: - Assignment-level

    @discardableResult
    func updateAssignmentAbortPolicy(
        assignmentID: UUID,
        _ policy: MissionRunAbortPolicy?,
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
        assignments[idx].policies.abort = policy
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: policy?.setupMenuLabel ?? "Inherit"
        )
        return .allowed
    }

    @discardableResult
    func updateAssignmentCompletePolicy(
        assignmentID: UUID,
        _ policy: MissionRunCompletePolicy?,
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
        assignments[idx].policies.complete = policy
        logPolicyEditApplied(
            scope: scope,
            credential: credential,
            value: policy?.setupMenuLabel ?? "Inherit"
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
        case .missionAbortPolicy, .missionCompletePolicy, .missionEngagementRules:
            return .missionControl
        case .taskAbortPolicyOverride(let id), .taskCompletePolicyOverride(let id):
            let name = template?.routeMacro.tasks.first(where: { $0.id == id })?.name ?? "Task"
            return .task(id: id, name: name)
        case .assignmentAbortPolicy(let id), .assignmentCompletePolicy(let id):
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
        case .taskAbortPolicyOverride(let id), .taskCompletePolicyOverride(let id):
            return id
        case .assignmentAbortPolicy(let id), .assignmentCompletePolicy(let id):
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
        case .missionAbortPolicy: return "Mission abort policy"
        case .missionCompletePolicy: return "Mission complete policy"
        case .missionEngagementRules: return "Rules of engagement"
        case .taskAbortPolicyOverride: return "Task abort policy override"
        case .taskCompletePolicyOverride: return "Task complete policy override"
        case .assignmentAbortPolicy: return "Slot abort policy"
        case .assignmentCompletePolicy: return "Slot complete policy"
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
