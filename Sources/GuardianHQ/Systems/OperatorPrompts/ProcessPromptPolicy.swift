import Foundation

// MARK: - ProcessPromptPolicy

/// Ordered list of delivery-target *templates* the operator-prompt router fans an
/// event through. The policy describes which channels a process **wants**;
/// runtime availability and operator-presence filtering land in the router
/// itself (Stage D follow-up).
///
/// ## Resolution flow
///
/// 1. Publisher emits an ``OperatorPromptEvent`` carrying an
///    ``OperatorPromptTarget``.
/// 2. Router looks up the policy for `event.origin` (via
///    ``ProcessPromptPolicy/default(for:)`` or an injected override).
/// 3. Router calls ``resolveTargets(for:)`` which walks `entries` in order,
///    binds each template to a concrete ``OperatorPromptDeliveryTarget`` using
///    the event's addressing, and skips templates the event can't satisfy
///    (e.g. MCR panel skipped when `target.missionRunID == nil`).
/// 4. Router checks runtime availability (panel mounted, OOA permission, operator
///    presence) and picks the **first available** as the primary; remaining
///    addressable targets become mirrors.
/// 5. When ``mirrorToInbox`` is `true`, ``OperatorPromptDeliveryTarget/inAppInbox``
///    is appended last so every prompt is reviewable from the universal drawer.
///
/// ## Why entries don't carry addressing
///
/// The policy is declared at registration time — long before any specific event
/// exists. Targets like `mcrPromptPanel(missionRunID:)` need an id only the
/// event carries, so entries are *channel selectors* and binding happens at
/// resolve time. This keeps policies stable across runs while still producing
/// fully-addressed targets per event.
///
/// ## Inbox is implicit, not an entry
///
/// `inAppInbox` is the always-on archive sink (see
/// ``OperatorPromptDeliveryTarget/isUniversalArchive``). Surfacing it as a
/// policy flag rather than an entry keeps entry lists focused on operator-facing
/// channels and makes "every prompt is reviewable" a uniform guarantee instead
/// of a per-policy concern.
struct ProcessPromptPolicy: Equatable, Sendable {

    /// Ordered channel preferences. Router fans the event through these in
    /// declared order; first runtime-available entry is the primary, rest are
    /// mirrors.
    let entries: [Entry]

    /// Whether ``OperatorPromptDeliveryTarget/inAppInbox`` is appended as the
    /// final mirror. Defaults to `true` so every prompt is archivable; set to
    /// `false` only for system-internal prompts that must not be persisted to
    /// the universal inbox (none defined at v1 — this is an extension hook).
    let mirrorToInbox: Bool

    init(entries: [Entry], mirrorToInbox: Bool = true) {
        self.entries = entries
        self.mirrorToInbox = mirrorToInbox
    }

    // MARK: - Entry

    /// Channel template without addressing. Resolved against an event's
    /// ``OperatorPromptTarget`` at routing time.
    ///
    /// Closed v1 set — adding a new entry requires a matching
    /// ``OperatorPromptDeliveryTarget`` case and binding logic in
    /// ``ProcessPromptPolicy/resolveTargets(for:)``.
    enum Entry: Equatable, Hashable, Sendable {

        /// Bind to ``OperatorPromptDeliveryTarget/mcrPromptPanel(missionRunID:)``
        /// using the event's `missionRunID`. Skipped when the event has none.
        case mcrPanel

        /// Bind to ``OperatorPromptDeliveryTarget/liveDrivePromptPanel(missionRunID:vehicleID:)``
        /// using whichever of `missionRunID` / `affectedVehicleID` the event
        /// carries. Skipped when the event has neither.
        case liveDrivePanel

        /// Bind to ``OperatorPromptDeliveryTarget/vehicleInspectorWizardPanel(vehicleID:recipeRunID:)``
        /// using the event's `affectedVehicleID` (required) and `recipeRunID`
        /// (optional). Skipped when the event has no vehicle id.
        case vehicleInspectorWizard

        /// Bind unconditionally to ``OperatorPromptDeliveryTarget/persistentToast``.
        case persistentToast

        /// Bind unconditionally to
        /// ``OperatorPromptDeliveryTarget/userNotification(style:)`` with the
        /// declared style. Router gates actual delivery on operator-presence
        /// heuristics (Stage D follow-up) so the app does not double-notify when
        /// the operator is on a contextual panel.
        case userNotification(style: OperatorPromptUserNotificationStyle)
    }

    // MARK: - Resolution

    /// Concrete delivery targets this policy wants for `event`. Order is
    /// preserved: addressable entries appear in the order they were declared;
    /// entries that cannot be addressed (e.g. MCR panel when the event has no
    /// `missionRunID`) are dropped. When ``mirrorToInbox`` is `true`, the
    /// inbox target is appended last.
    ///
    /// This is **pure** — no runtime state, no router state, no operator
    /// presence. The router layer applies availability filtering on top of the
    /// returned list.
    func resolveTargets(for event: OperatorPromptEvent) -> [OperatorPromptDeliveryTarget] {
        var out: [OperatorPromptDeliveryTarget] = []
        for entry in entries {
            if let bound = Self.bind(entry: entry, to: event.target) {
                out.append(bound)
            }
        }
        if mirrorToInbox {
            out.append(.inAppInbox)
        }
        return out
    }

    /// Bind a single entry template to a concrete delivery target using
    /// `eventTarget`. Returns `nil` when the entry's required addressing is
    /// absent from the event.
    private static func bind(
        entry: Entry,
        to eventTarget: OperatorPromptTarget
    ) -> OperatorPromptDeliveryTarget? {
        switch entry {
        case .mcrPanel:
            guard let runID = eventTarget.missionRunID else { return nil }
            return .mcrPromptPanel(missionRunID: runID)

        case .liveDrivePanel:
            let runID = eventTarget.missionRunID
            let vehicleID = eventTarget.affectedVehicleID
            // LiveDrive refuses fully-unaddressed targets; match the type
            // catalogue rule by requiring at least one discriminator.
            guard runID != nil || vehicleID != nil else { return nil }
            return .liveDrivePromptPanel(missionRunID: runID, vehicleID: vehicleID)

        case .vehicleInspectorWizard:
            guard let vehicleID = eventTarget.affectedVehicleID else { return nil }
            return .vehicleInspectorWizardPanel(
                vehicleID: vehicleID,
                recipeRunID: eventTarget.recipeRunID
            )

        case .persistentToast:
            return .persistentToast

        case .userNotification(let style):
            return .userNotification(style: style)
        }
    }
}

// MARK: - Default policies per origin

extension ProcessPromptPolicy {

    /// Sensible default policy for an ``OperatorPromptOrigin`` kind. The router
    /// uses these unless an injected `policyProvider` returns a process-specific
    /// override.
    ///
    /// - `recipeEscalation` — wizard → MCR → LiveDrive → toast → banner.
    ///   Wizard first because if a recipe wizard is running, that's where the
    ///   operator is focused.
    /// - `mreEngagementAsk` — MCR → LiveDrive → toast → mcrCriticalReturn.
    ///   MRE asking permission for `rtl` / `land` / `forceDisarm` /
    ///   `swapInReserve` needs operator attention back at MCR; the OOA variant
    ///   is the time-sensitive alert that pulls them back.
    /// - `mreEngagementHandoff` — LiveDrive → MCR → mcrCriticalReturn. Handoff
    ///   asks the operator to drive; LiveDrive is the takeover surface.
    /// - `freeform` — MCR → LiveDrive → wizard → toast → banner. Broad
    ///   coverage; specialised publishers should declare a tailored policy
    ///   rather than rely on the freeform default.
    static func `default`(for origin: OperatorPromptOrigin) -> ProcessPromptPolicy {
        switch origin {
        case .recipeEscalation:
            return ProcessPromptPolicy(entries: [
                .vehicleInspectorWizard,
                .mcrPanel,
                .liveDrivePanel,
                .persistentToast,
                .userNotification(style: .banner),
            ])

        case .mreEngagementAsk:
            return ProcessPromptPolicy(entries: [
                .mcrPanel,
                .liveDrivePanel,
                .persistentToast,
                .userNotification(style: .mcrCriticalReturn),
            ])

        case .mreEngagementHandoff:
            return ProcessPromptPolicy(entries: [
                .liveDrivePanel,
                .mcrPanel,
                .userNotification(style: .mcrCriticalReturn),
            ])

        case .freeform:
            return ProcessPromptPolicy(entries: [
                .mcrPanel,
                .liveDrivePanel,
                .vehicleInspectorWizard,
                .persistentToast,
                .userNotification(style: .banner),
            ])
        }
    }
}
