import Foundation

// MARK: - OperatorPromptDeliveryTarget

/// Closed catalogue of the surfaces ``OperatorPromptRouter`` is allowed to dispatch
/// to. One enum case per physical delivery channel; each case carries the
/// addressing the channel needs to find its actual UI host (mission run id for
/// the MCR panel, vehicle id for the Vehicle Inspector wizard, etc.).
///
/// ## Roles
///
/// Targets fall into two roles:
///
/// - **Contextual** (`mcrPromptPanel`, `liveDrivePromptPanel`,
///   `vehicleInspectorWizardPanel`) — bound to a UI surface the operator is
///   currently focused on. Address fields are required so the router can match
///   the channel to a specific live host and skip it when no matching host is
///   mounted.
/// - **Broadcast** (`persistentToast`, `userNotification`, `inAppInbox`) — surface
///   the prompt without a specific contextual host. The toast and OOA
///   notification fire as fallbacks when no contextual target accepted; the
///   inbox is the always-on archive every prompt is also written to.
///
/// ## Router contract
///
/// 1. ``ProcessPromptPolicy`` resolves an ordered list of targets for a given
///    `(origin, target)` pair.
/// 2. For each target the router checks ``accepts(eventTarget:)`` to confirm the
///    channel's addressing is satisfied by the event's
///    ``OperatorPromptTarget``. Unsatisfied contextual targets are skipped.
/// 3. The router then checks availability (panel currently mounted, OOA
///    permission granted, operator presence) — implemented in Stage D's router
///    item.
/// 4. The first available target is the **primary**; remaining targets are
///    **mirrors** for cross-surface visibility (e.g. the inbox always mirrors).
///
/// ## Extending the catalogue
///
/// New top-level surfaces require:
/// 1. A new enum case here with the minimum addressing it needs.
/// 2. A new ``Kind`` rawValue for audit logging.
/// 3. An ``accepts(eventTarget:)`` clause.
/// 4. A renderer + binding in the router (Stage D follow-up).
///
/// Plugins do **not** add new targets — they publish prompts that flow through
/// the existing targets. A future stage may relax this, but v1 keeps the
/// delivery surface count finite so audit-log shape is stable.
enum OperatorPromptDeliveryTarget: Equatable, Hashable, Sendable {

    /// Mission Control Running prompt panel. Bound to a specific mission run;
    /// the router only picks this target when the active MCR window is showing
    /// the same run.
    case mcrPromptPanel(missionRunID: UUID)

    /// LiveDrive HUD prompt panel. Matches either the active mission run id or
    /// the currently-driven vehicle id, because LiveDrive sessions may be tied
    /// to a mission task or to a free-flight session without a run.
    case liveDrivePromptPanel(missionRunID: UUID? = nil, vehicleID: String? = nil)

    /// Vehicle Inspector wizard prompt panel. Bound to a specific vehicle id;
    /// when `recipeRunID` is set the channel only accepts events from that
    /// recipe run (Stage E wizard isolates per-run prompts so unrelated
    /// escalations don't leak into the wizard chrome).
    case vehicleInspectorWizardPanel(vehicleID: String, recipeRunID: FleetRecipeRunID? = nil)

    /// Sticky in-app toast (top-leading in the primary content column) that does not auto-dismiss. Distinct from
    /// ``ToastCenter`` (ephemeral). The toast carries title + severity; clicking
    /// it opens the prompt in the inbox so the operator can resolve it without
    /// fishing through the drawer.
    case persistentToast

    /// macOS `UNUserNotificationCenter` banner / alert. Used when the operator
    /// is out-of-app or when the prompt is critical enough to require OS-level
    /// surfacing. Style controls banner vs alert chrome.
    case userNotification(style: OperatorPromptUserNotificationStyle = .banner)

    /// Universal app-wide drawer inbox (the existing ``AppDrawer`` panel).
    /// Every prompt also flows here as a side-channel archive — the inbox is
    /// the always-on mirror so operators can revisit prompts that resolved or
    /// missed them while focused elsewhere.
    case inAppInbox
}

// MARK: - Kind

extension OperatorPromptDeliveryTarget {

    /// String-backed discriminator used by the audit log, telemetry, and any
    /// serialised routing rules. Stable across releases (do not rename
    /// rawValues without a migration plan).
    enum Kind: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
        case mcrPromptPanel
        case liveDrivePromptPanel
        case vehicleInspectorWizardPanel
        case persistentToast
        case userNotification
        case inAppInbox
    }

    /// Discriminator for this target's case. Always defined — adding a new
    /// case to ``OperatorPromptDeliveryTarget`` requires adding a matching
    /// rawValue to ``Kind``.
    var kind: Kind {
        switch self {
        case .mcrPromptPanel: return .mcrPromptPanel
        case .liveDrivePromptPanel: return .liveDrivePromptPanel
        case .vehicleInspectorWizardPanel: return .vehicleInspectorWizardPanel
        case .persistentToast: return .persistentToast
        case .userNotification: return .userNotification
        case .inAppInbox: return .inAppInbox
        }
    }
}

// MARK: - Role flags

extension OperatorPromptDeliveryTarget {

    /// `true` when this target is bound to a specific UI host (a panel that
    /// must be on-screen for the channel to deliver). Contextual targets are
    /// checked against the event's addressing in ``accepts(eventTarget:)``.
    var isContextual: Bool {
        switch self {
        case .mcrPromptPanel, .liveDrivePromptPanel, .vehicleInspectorWizardPanel:
            return true
        case .persistentToast, .userNotification, .inAppInbox:
            return false
        }
    }

    /// `true` when this target is intended as a **broadcast fallback** — fires
    /// without requiring a specific operator presence. The router uses this
    /// alongside ``isContextual`` to keep policy lists explicit about which
    /// targets are "always-on" sinks vs "only when operator is here" surfaces.
    var isBroadcast: Bool { !isContextual }

    /// `true` when this target surfaces *outside* the app process (macOS OS-level
    /// notifications). Routing keeps these last in fallback policies and gates
    /// them on operator-presence heuristics so the app does not double-notify
    /// when the operator is actively looking at a contextual panel.
    var isOutOfApp: Bool {
        switch self {
        case .userNotification: return true
        case .mcrPromptPanel, .liveDrivePromptPanel, .vehicleInspectorWizardPanel,
             .persistentToast, .inAppInbox:
            return false
        }
    }

    /// `true` when this target is the universal archive sink. Every event is
    /// mirrored to the inbox regardless of contextual delivery; the router
    /// reserves this in its mirror list and never treats it as a primary
    /// target.
    var isUniversalArchive: Bool {
        if case .inAppInbox = self { return true }
        return false
    }
}

// MARK: - Addressing match

extension OperatorPromptDeliveryTarget {

    /// Whether this delivery target's addressing is satisfied by an event's
    /// ``OperatorPromptTarget``. Contextual targets require matching id fields;
    /// broadcast targets always accept.
    ///
    /// LiveDrive matches when **either** the run id **or** the vehicle id
    /// matches the event's target — a LiveDrive session is identified by
    /// vehicle, and an active LiveDrive bound to a mission run carries the run
    /// id too. Setting both fields on the target tightens the match to require
    /// both.
    ///
    /// Vehicle Inspector requires the vehicle id to match; when the target
    /// also specifies a recipe run id, the event's `recipeRunID` must match
    /// that run too. A vehicle-inspector target with `recipeRunID == nil`
    /// accepts any recipe run for the vehicle.
    func accepts(eventTarget: OperatorPromptTarget) -> Bool {
        switch self {
        case .mcrPromptPanel(let runID):
            return eventTarget.missionRunID == runID

        case .liveDrivePromptPanel(let runID, let vehicleID):
            // Both `nil` → channel claims no addressing; never matches. Stage
            // D's router defends against constructing this case but the type
            // catalogue stays strict to avoid silent broadcast leaks.
            if runID == nil, vehicleID == nil { return false }
            if let runID, runID != eventTarget.missionRunID { return false }
            if let vehicleID, vehicleID != eventTarget.affectedVehicleID { return false }
            return true

        case .vehicleInspectorWizardPanel(let vehicleID, let recipeRunID):
            guard eventTarget.affectedVehicleID == vehicleID else { return false }
            if let recipeRunID {
                return eventTarget.recipeRunID == recipeRunID
            }
            return true

        case .persistentToast, .userNotification, .inAppInbox:
            return true
        }
    }
}

// MARK: - OperatorPromptUserNotificationStyle

/// Chrome / urgency variant for the ``OperatorPromptDeliveryTarget/userNotification(style:)``
/// channel. Drives the underlying `UNNotificationContent` interruption level and
/// sound, and (later) the wording template the channel renders.
enum OperatorPromptUserNotificationStyle: String, Equatable, Hashable, Sendable, Codable, CaseIterable {

    /// Standard banner / list / sound. Used for routine operator prompts the
    /// operator can pick up at their convenience.
    case banner

    /// Time-sensitive "get back to MCR" alert variant. Used when a live
    /// mission requires the operator's attention and they have left the
    /// Mission Control surface — the notification pulls focus back into the
    /// MCR canvas on tap.
    case mcrCriticalReturn
}
