import Foundation

// MARK: - Edit credential

/// Identifies the actor performing a policy / Rules-of-Engagement edit on a ``MissionRunEnvironment``.
struct MissionRunPolicyEditCredential: Equatable {
    let issuer: MissionRunCommandIssuer
    /// Stable issuer id (e.g. ``MissionRunCommandIssuerKey/localOperator``, ``MissionRunCommandIssuerKey/paladin``).
    let issuerKey: String
    /// Human display name for log prefixes (operator callsign for ``MissionRunCommandIssuer/operator``).
    /// Empty / `nil` falls back to a generic `[Operator]` prefix.
    let displayName: String?

    init(
        issuer: MissionRunCommandIssuer,
        issuerKey: String,
        displayName: String? = nil
    ) {
        self.issuer = issuer
        self.issuerKey = issuerKey
        self.displayName = displayName
    }

    /// Local operator credential without a callsign; prefer
    /// ``localOperator(callsign:)`` from UI sites that have access to ``GeneralSettingsStore``.
    static let localOperator = MissionRunPolicyEditCredential(
        issuer: .operator,
        issuerKey: MissionRunCommandIssuerKey.localOperator,
        displayName: nil
    )

    /// Convenience for UI sites that pass the operator's `GeneralSettingsStore.callsign` for prefixing.
    static func localOperator(callsign: String?) -> MissionRunPolicyEditCredential {
        MissionRunPolicyEditCredential(
            issuer: .operator,
            issuerKey: MissionRunCommandIssuerKey.localOperator,
            displayName: callsign
        )
    }
}

// MARK: - Edit scopes

/// Categories for MRE policy / Rules-of-Engagement writes that the authority subsystem permissions on.
enum MissionRunPolicyEditScopeCategory: String, CaseIterable, Hashable {
    /// Mission-wide ``RouteRules/missionAbortPreferenceChain`` and per-task ``MissionTask/abortPreferenceChainOverride``.
    case abortPolicy
    /// Mission-wide ``RouteRules/missionCompletePreferenceChain`` and per-task ``MissionTask/completePreferenceChainOverride``.
    case completePolicy
    /// Mission-wide ``RouteRules/missionReserveSwapPreferenceChain`` and per-task ``MissionTask/reserveSwapPreferenceChainOverride``.
    case reserveSwapPolicy
    /// Per-assignment ``MissionRunAssignmentPolicies`` (abort / complete / reserve swap).
    case assignmentPolicy
    /// Run-level ``MissionRunEngagementRules``.
    case engagementRules
    /// ``MissionTask/betweenCycles`` (Return to Launch / Loiter / Park) for repeating tasks — mission template mutation on the run.
    case taskBetweenCycles
    /// Run-only **additional** geofence regions (``MissionRunPolicies/missionGeofenceAugmentation``, per-task map on ``MissionRunEnvironment``, ``MissionRunAssignmentPolicies/geofenceAugmentation``).
    case geofencePolicy
}

/// What a single MRE policy / Rules-of-Engagement edit targets.
enum MissionRunPolicyEditScope: Equatable, Hashable {
    case missionAbortPolicy
    case missionCompletePolicy
    case missionReserveSwapPolicy
    case missionEngagementRules
    case taskAbortPolicyOverride(taskID: UUID)
    case taskCompletePolicyOverride(taskID: UUID)
    case taskReserveSwapPolicyOverride(taskID: UUID)
    case taskBetweenCyclesAction(taskID: UUID)
    case assignmentAbortPolicy(assignmentID: UUID)
    case assignmentCompletePolicy(assignmentID: UUID)
    case assignmentReserveSwapPolicy(assignmentID: UUID)
    case missionGeofenceAugmentation
    case taskGeofenceAugmentation(taskID: UUID)
    case assignmentGeofenceAugmentation(assignmentID: UUID)

    var category: MissionRunPolicyEditScopeCategory {
        switch self {
        case .missionAbortPolicy, .taskAbortPolicyOverride:
            return .abortPolicy
        case .missionCompletePolicy, .taskCompletePolicyOverride:
            return .completePolicy
        case .missionReserveSwapPolicy, .taskReserveSwapPolicyOverride:
            return .reserveSwapPolicy
        case .taskBetweenCyclesAction:
            return .taskBetweenCycles
        case .assignmentAbortPolicy, .assignmentCompletePolicy, .assignmentReserveSwapPolicy:
            return .assignmentPolicy
        case .missionEngagementRules:
            return .engagementRules
        case .missionGeofenceAugmentation, .taskGeofenceAugmentation, .assignmentGeofenceAugmentation:
            return .geofencePolicy
        }
    }
}

// MARK: - Permission decision

/// Why a policy / Rules-of-Engagement write was rejected by ``MissionRunPolicyAuthoritySubsystem``.
enum MissionRunPolicyEditDenialReason: Equatable {
    case permissionDenied
    case missionUnavailable
    case taskNotFound
    case assignmentNotFound
}

enum MissionRunPolicyEditDecision: Equatable {
    case allowed
    case denied(MissionRunPolicyEditDenialReason)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

// MARK: - Authority subsystem

/// Per-run gate for MRE policy and Rules-of-Engagement writes.
///
/// Default rule: the local operator (``MissionRunCommandIssuerKey/localOperator``) and Mission
/// Control automation (``MissionRunCommandIssuer/missionControl``) may edit any scope. Other
/// issuers (e.g. Paladin) start with no edit permission and must be granted scopes via
/// ``grantPermission(_:forIssuerKey:)``.
@MainActor
final class MissionRunPolicyAuthoritySubsystem {
    weak var environment: MissionRunEnvironment?

    /// Issuer keys that bypass the per-category grant table (operator-class actors).
    private var operatorClassIssuerKeys: Set<String> = [MissionRunCommandIssuerKey.localOperator]
    /// Per-issuer scope-category allowlist for non-operator actors.
    private var grantedCategoriesByIssuerKey: [String: Set<MissionRunPolicyEditScopeCategory>] = [:]

    /// Marks an issuer key as operator-class (full edit access). Operators default to allowed.
    func registerOperatorIssuerKey(_ issuerKey: String) {
        operatorClassIssuerKeys.insert(issuerKey)
    }

    /// Removes operator-class status (does not affect per-category grants).
    func unregisterOperatorIssuerKey(_ issuerKey: String) {
        operatorClassIssuerKeys.remove(issuerKey)
    }

    /// Grants one or more categories of policy / RoE edits to an assistant or other non-operator actor.
    func grantPermission(
        _ categories: Set<MissionRunPolicyEditScopeCategory>,
        forIssuerKey issuerKey: String
    ) {
        var current = grantedCategoriesByIssuerKey[issuerKey] ?? []
        current.formUnion(categories)
        grantedCategoriesByIssuerKey[issuerKey] = current
    }

    func revokePermission(
        _ categories: Set<MissionRunPolicyEditScopeCategory>,
        forIssuerKey issuerKey: String
    ) {
        guard var current = grantedCategoriesByIssuerKey[issuerKey] else { return }
        current.subtract(categories)
        if current.isEmpty {
            grantedCategoriesByIssuerKey.removeValue(forKey: issuerKey)
        } else {
            grantedCategoriesByIssuerKey[issuerKey] = current
        }
    }

    func revokeAllPermissions(forIssuerKey issuerKey: String) {
        grantedCategoriesByIssuerKey.removeValue(forKey: issuerKey)
        operatorClassIssuerKeys.remove(issuerKey)
    }

    func grantedCategories(forIssuerKey issuerKey: String) -> Set<MissionRunPolicyEditScopeCategory> {
        if isOperatorClass(credential: MissionRunPolicyEditCredential(issuer: .operator, issuerKey: issuerKey)) {
            return Set(MissionRunPolicyEditScopeCategory.allCases)
        }
        return grantedCategoriesByIssuerKey[issuerKey] ?? []
    }

    /// Gate check used by every MRE policy / RoE write API.
    func evaluate(
        _ scope: MissionRunPolicyEditScope,
        credential: MissionRunPolicyEditCredential
    ) -> MissionRunPolicyEditDecision {
        if isOperatorClass(credential: credential) {
            return .allowed
        }
        let categories = grantedCategoriesByIssuerKey[credential.issuerKey] ?? []
        return categories.contains(scope.category) ? .allowed : .denied(.permissionDenied)
    }

    func canEdit(
        _ scope: MissionRunPolicyEditScope,
        credential: MissionRunPolicyEditCredential
    ) -> Bool {
        evaluate(scope, credential: credential).isAllowed
    }

    private func isOperatorClass(credential: MissionRunPolicyEditCredential) -> Bool {
        switch credential.issuer {
        case .operator, .missionControl:
            return true
        case .assistant:
            return operatorClassIssuerKeys.contains(credential.issuerKey)
        }
    }
}

// MARK: - Log template keys (policy authority)

extension MissionRunLogTemplateKey {
    static let policyAuthorityEditApplied = "missioncontrol.mre.policy.edit_applied"
    static let policyAuthorityEditDenied = "missioncontrol.mre.policy.edit_denied"
}
