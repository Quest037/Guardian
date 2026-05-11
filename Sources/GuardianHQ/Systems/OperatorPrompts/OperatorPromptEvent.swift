import Foundation

// MARK: - OperatorPromptEvent

/// App-wide operator-prompt event. The unified payload every Guardian process emits
/// when it needs the operator to acknowledge, confirm, pick, or abort something.
///
/// Stage D's `OperatorPromptCenter` accepts events through a single publish surface;
/// `OperatorPromptRouter` decides which delivery channels carry the event (contextual
/// panel, top-bar notifications drawer, OOA `UserNotificationService`).
///
/// The shape **mirrors the recipe-runner escalation contract** (see
/// ``FleetRecipeEscalationEvent``) so a recipe escalation can be lifted into a prompt
/// without losing information — the wrapped event is stored under
/// ``OperatorPromptOrigin/recipeEscalation`` and the prompt event carries the closed
/// resumption verbs (``FleetRecipeResumptionVerb``) directly as its transport.
///
/// ## Addressing
///
/// ``OperatorPromptEvent/target`` is a first-class addressing payload (mission run,
/// mission task, squad, roster slot, assignment, vehicle, recipe run, plugin). The
/// router compares it to the current panel's context to decide delivery; the drawer
/// row uses it to render the addressing stamp; the audit log indexes on it. Without
/// `target` the operator gets a prompt with no idea what it's about, which is why
/// every publisher should fill in as much of it as it knows.
///
/// ## Rich context
///
/// ``OperatorPromptEvent/contextFacts`` is an ordered list of operator-readable
/// `(label, value)` pairs the publisher attaches so the operator has the facts they
/// need to decide — e.g. for swap-in-reserve: primary slot, primary battery, reserve
/// readiness, wingmen list, expected mission impact. The generic renderer paints
/// these as grouped lines with emphasis-driven colours; specialised UI surfaces
/// (Stage E wizard, MCR panel) can opt to render richer chrome using the same data.
///
/// ## Custom options on top of closed verbs
///
/// Every option the operator sees ultimately resolves to one of the four closed
/// resumption verbs. Custom options are **labelled choices** the publisher supplies
/// — each option carries a stable id (for source-side branching), a human label, a
/// role (`confirm | neutral | cancel` driving button colour), an underlying verb
/// (for recipe-runner control-flow), an optional per-option `summary` line that
/// tells the operator the consequence of that choice, and an optional payload. When
/// `options` is `nil` the UI synthesises a standard button set from `allowedVerbs`
/// (see ``OperatorPromptOption/standardOptions(forAllowedVerbs:)``) so back-compat
/// with existing escalation matchers is automatic.
///
/// ## Remember-this-choice
///
/// `policyKey` gates the "remember for this mission" checkbox. When non-nil, the
/// publisher consults a per-run `OperatorDecisionCache` *before* publishing — a
/// cached hit auto-resolves without UI. The cache and the consumer of the
/// `remember` flag (the RoE / engagement-disposition learner) land in follow-up
/// work; this type just plumbs the flag.
///
/// ## Timeout
///
/// Every prompt has a hard deadline. When `Date() >= expiresAt` the router auto-
/// resolves with `.timeoutAborted` (the answer's verb is `.abort` if allowed, else
/// the first `allowedVerbs` entry). Default budget is five minutes; publishers
/// override per event when warranted.
struct OperatorPromptEvent: Identifiable, Equatable, Sendable {

    /// Default time-to-respond before the router auto-aborts a prompt (5 minutes).
    static let defaultTimeout: TimeInterval = 5 * 60

    /// Stable identifier — used to address the prompt across delivery channels and
    /// to correlate the resulting ``OperatorPromptAnswer``.
    let id: UUID

    /// Who published this prompt and why. Routing decisions branch on this.
    let origin: OperatorPromptOrigin

    /// Where this prompt lives in the app's domain — mission run, task, squad, slot,
    /// vehicle, recipe run, plugin. Used by the router to filter delivery to the
    /// operator's current focus, by the drawer to render the addressing stamp, and
    /// by the audit log to index resolved prompts.
    let target: OperatorPromptTarget

    /// Severity drives chrome (icon + banner colour) on every delivery channel.
    /// Reuses ``GuardianFeedbackSeverity`` so the existing toast / bottom-prompt /
    /// inline-notice catalogue stays the single source of truth.
    let severity: GuardianFeedbackSeverity

    /// Single-line headline shown on every channel (drawer row, panel header,
    /// macOS notification title).
    let title: String

    /// Multi-line body. May be empty for terse confirmations whose title is
    /// self-explanatory.
    let body: String

    /// Ordered list of `(label, value)` operator-readable facts the publisher
    /// attaches so the operator has the data they need to decide. Generic
    /// renderers paint these as grouped lines; specialised UI may opt to render
    /// richer chrome from the same facts. Empty by default for prompts that need
    /// no extra context beyond `title` + `body`.
    let contextFacts: [OperatorPromptContextFact]

    /// Custom options to present to the operator. `nil` means "synthesise a
    /// standard button set from `allowedVerbs`" (see ``effectiveOptions``).
    let options: [OperatorPromptOption]?

    /// Closed transport — the resumption verbs the publisher will accept back.
    /// For recipe escalations this comes straight from the matcher's
    /// `allowedVerbs`; for MRE `.ask` permission prompts it's
    /// `[.acknowledge, .abort]` (Yes / No); for informational status banners it's
    /// `[.acknowledge]`.
    let allowedVerbs: [FleetRecipeResumptionVerb]

    /// Policy key for the publisher-side `OperatorDecisionCache`. When non-nil the
    /// UI shows a "remember this choice" checkbox; when checked, the answer's
    /// `remember` flag is true and the publisher records `(policyKey →
    /// selectedOptionID)` for the lifetime of the current run / session. Nil
    /// hides the checkbox.
    let policyKey: String?

    /// When this prompt was created.
    let createdAt: Date

    /// Hard deadline. `Date() >= expiresAt` triggers `.timeoutAborted` resolution.
    let expiresAt: Date

    init(
        id: UUID = UUID(),
        origin: OperatorPromptOrigin,
        target: OperatorPromptTarget = .unspecified,
        severity: GuardianFeedbackSeverity,
        title: String,
        body: String,
        contextFacts: [OperatorPromptContextFact] = [],
        options: [OperatorPromptOption]? = nil,
        allowedVerbs: [FleetRecipeResumptionVerb],
        policyKey: String? = nil,
        createdAt: Date = Date(),
        timeout: TimeInterval = OperatorPromptEvent.defaultTimeout
    ) {
        self.id = id
        self.origin = origin
        self.target = target
        self.severity = severity
        self.title = title
        self.body = body
        self.contextFacts = contextFacts
        self.options = options
        self.allowedVerbs = allowedVerbs
        self.policyKey = policyKey
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(max(0, timeout))
    }

    /// The option list the UI should render. Returns `options` when the publisher
    /// supplied custom options; otherwise synthesises a standard button set from
    /// `allowedVerbs` so v1 callers (every existing recipe escalation matcher)
    /// keep working without custom options authoring.
    var effectiveOptions: [OperatorPromptOption] {
        if let options, !options.isEmpty { return options }
        return OperatorPromptOption.standardOptions(forAllowedVerbs: allowedVerbs)
    }

    /// Whether the remember-this-choice checkbox should be shown for this event.
    /// Hidden when no `policyKey` is set because there is no cache to record into.
    var allowsRememberChoice: Bool { policyKey != nil }

    /// `true` once `expiresAt` has passed (callers check this before publishing
    /// late deliveries or applying late operator input).
    func isExpired(at now: Date = Date()) -> Bool { now >= expiresAt }
}

// MARK: - OperatorPromptOrigin

/// Where the prompt came from, and what context the router can use to route it.
///
/// New origins are added when a new class of publisher comes online; v1 covers
/// recipe-runner escalations (Stage B contract), MRE engagement dispositions
/// (`.ask` and `.handoff`), and an open `freeform` slot for plugins and migrated
/// status banners. The router branches on this to choose which contextual panels
/// accept the event and what wording to use for OOA notifications.
///
/// Origin describes **who is asking**; ``OperatorPromptTarget`` describes
/// **what the prompt is about**. The two are orthogonal — a recipe-escalation
/// origin running inside a mission task carries both: origin says "recipe runner
/// V is escalating step S", target says "mission run R, task T, squad S, slot
/// P, vehicle V".
enum OperatorPromptOrigin: Equatable, Sendable {

    /// Lifted from a Layer 2 recipe-runner escalation. The wrapped event carries
    /// the full step + reason + last-response context for the UI.
    case recipeEscalation(event: FleetRecipeEscalationEvent)

    /// MRE asked the operator for permission to take an engagement action
    /// (rtl / land / forceDisarm / swapInReserve) under disposition `.ask`.
    case mreEngagementAsk(runID: UUID, action: MissionRunEngagementAction)

    /// MRE requested an operator handoff for an engagement action under
    /// disposition `.handoff`. Distinct from `.ask` because the operator is taking
    /// over rather than just granting permission.
    case mreEngagementHandoff(runID: UUID, action: MissionRunEngagementAction)

    /// Open slot for plugin and migrated status-banner publishers. The `source`
    /// string is namespace-qualified (e.g. `"missionRun.gracefulStop"`,
    /// `"liveDrive.takeoverRequested"`, `"plugin.paladin.swapInReserveCheck"`)
    /// and feeds router branching. Plugins are required to use their plugin id
    /// as the prefix (Stage F namespace claims enforce this once they land).
    case freeform(source: String)
}

// MARK: - OperatorPromptTarget

/// First-class addressing for an ``OperatorPromptEvent``. The router, drawer,
/// audit log, and `OperatorDecisionCache` all read this — not the origin's
/// associated values — so addressing logic is uniform across every publisher.
///
/// All fields are optional because not every prompt addresses every dimension:
/// a freeform plugin status banner may address only `pluginID`; a recipe
/// escalation always addresses `recipeRunID` and `affectedVehicleID` and may
/// also address mission / squad / slot when the recipe is running inside a
/// mission task; an MRE engagement ask always addresses `missionRunID` and may
/// also address `missionTaskID` / `squad` / slot when the action is scoped to
/// a particular squad or slot.
///
/// Squad is identified by its **primary** roster device (or assignment / vehicle)
/// because Guardian's roster model assigns wingmen and reserves to a primary —
/// the primary is the squad leader. See ``OperatorPromptSquadContext``.
struct OperatorPromptTarget: Equatable, Hashable, Sendable {

    /// ``MissionRunEnvironment/id`` — addresses the whole mission run.
    let missionRunID: UUID?

    /// ``MissionTask/id`` — addresses the task inside that run.
    let missionTaskID: UUID?

    /// Squad context (primary + wingmen + reserves) when the prompt is squad-
    /// scoped. Squad is identified by its primary; wingmen and reserves are
    /// recorded so the renderer can show the full squad composition.
    let squad: OperatorPromptSquadContext?

    /// ``RosterDevice/id`` of the slot this prompt is most directly about.
    /// May be the primary, a wingman, or a reserve — distinct from
    /// `squad.primaryRosterDeviceID` when the prompt targets a non-primary
    /// member of the squad (e.g. a wingman calibration prompt).
    let affectedRosterSlotID: UUID?

    /// ``MissionRunAssignment/id`` of the assignment the prompt is about.
    /// One per `(run, roster device)`; carries the vehicle binding the run owns.
    let affectedAssignmentID: UUID?

    /// ``FleetVehicleModel/vehicleId`` of the vehicle this prompt is about.
    /// May be set without `affectedAssignmentID` for Fleet-only prompts
    /// (e.g. a Vehicle Inspector calibration outside of any mission run).
    let affectedVehicleID: String?

    /// Recipe run that produced this prompt, when the prompt is a recipe
    /// escalation. Always set on `recipeEscalation` origins; otherwise nil.
    let recipeRunID: FleetRecipeRunID?

    /// ``GuardianPluginID/rawValue`` of the plugin that published this prompt.
    /// Only set for plugin-origin prompts; Stage F namespace claims will
    /// enforce that the publisher's plugin id matches.
    let pluginID: String?

    init(
        missionRunID: UUID? = nil,
        missionTaskID: UUID? = nil,
        squad: OperatorPromptSquadContext? = nil,
        affectedRosterSlotID: UUID? = nil,
        affectedAssignmentID: UUID? = nil,
        affectedVehicleID: String? = nil,
        recipeRunID: FleetRecipeRunID? = nil,
        pluginID: String? = nil
    ) {
        self.missionRunID = missionRunID
        self.missionTaskID = missionTaskID
        self.squad = squad
        self.affectedRosterSlotID = affectedRosterSlotID
        self.affectedAssignmentID = affectedAssignmentID
        self.affectedVehicleID = affectedVehicleID
        self.recipeRunID = recipeRunID
        self.pluginID = pluginID
    }

    /// Sentinel value used when a publisher genuinely has nothing addressable
    /// (e.g. an app-wide informational banner). Routing falls back to the
    /// universal drawer; the addressing stamp is suppressed.
    static let unspecified = OperatorPromptTarget()

    /// `true` when every field is `nil`. The router treats unspecified targets
    /// as "universal drawer only" — no contextual panel match is possible
    /// without at least one addressing field.
    var isUnspecified: Bool {
        missionRunID == nil
            && missionTaskID == nil
            && squad == nil
            && affectedRosterSlotID == nil
            && affectedAssignmentID == nil
            && affectedVehicleID == nil
            && recipeRunID == nil
            && pluginID == nil
    }

    /// Whether `other` matches the dimensions this target specifies. Returns
    /// `true` when every non-nil field in `self` equals the corresponding field
    /// in `other`; nil fields in `self` are wildcards. Used by the router to
    /// match a panel's context filter against a published prompt's target.
    ///
    /// - Note: This is **directional** — `self` is the filter (the panel's
    ///   declared context), `other` is the prompt's target. Filter fields that
    ///   are nil accept anything; non-nil filter fields must match exactly.
    func matches(_ other: OperatorPromptTarget) -> Bool {
        if let v = missionRunID, v != other.missionRunID { return false }
        if let v = missionTaskID, v != other.missionTaskID { return false }
        if let v = squad?.primaryRosterDeviceID,
           v != other.squad?.primaryRosterDeviceID { return false }
        if let v = affectedRosterSlotID, v != other.affectedRosterSlotID { return false }
        if let v = affectedAssignmentID, v != other.affectedAssignmentID { return false }
        if let v = affectedVehicleID, v != other.affectedVehicleID { return false }
        if let v = recipeRunID, v != other.recipeRunID { return false }
        if let v = pluginID, v != other.pluginID { return false }
        return true
    }
}

// MARK: - OperatorPromptSquadContext

/// Squad addressing for an ``OperatorPromptTarget``. Squad is the set of slots
/// attached to a single primary roster device (Guardian's roster model — see
/// ``MissionRosterSlotRole``: `primary | wingman | reserve`).
///
/// The primary is the squad leader; wingmen follow the primary; reserves stand
/// in when a primary or wingman is replaced. Identifying the squad by its
/// primary is canonical because every wingman / reserve has
/// `leaderRosterDeviceId == primary.id`.
struct OperatorPromptSquadContext: Equatable, Hashable, Sendable {

    /// ``RosterDevice/id`` of the primary that anchors this squad.
    let primaryRosterDeviceID: UUID

    /// ``MissionRunAssignment/id`` of the run-level binding for the primary,
    /// when one exists. Nil for prompts raised in setup before assignments are
    /// created.
    let primaryAssignmentID: UUID?

    /// ``FleetVehicleModel/vehicleId`` currently bound to the primary slot, when
    /// one exists. Nil until a fleet vehicle is attached.
    let primaryVehicleID: String?

    /// ``RosterDevice/id`` list of wingmen attached to this primary
    /// (`slot == .wingman && leaderRosterDeviceId == primaryRosterDeviceID`).
    /// Empty when the primary has no wingmen.
    let wingmanRosterDeviceIDs: [UUID]

    /// ``RosterDevice/id`` list of reserves attached to this primary
    /// (`slot == .reserve && leaderRosterDeviceId == primaryRosterDeviceID`).
    /// Empty when the primary has no reserves.
    let reserveRosterDeviceIDs: [UUID]

    init(
        primaryRosterDeviceID: UUID,
        primaryAssignmentID: UUID? = nil,
        primaryVehicleID: String? = nil,
        wingmanRosterDeviceIDs: [UUID] = [],
        reserveRosterDeviceIDs: [UUID] = []
    ) {
        self.primaryRosterDeviceID = primaryRosterDeviceID
        self.primaryAssignmentID = primaryAssignmentID
        self.primaryVehicleID = primaryVehicleID
        self.wingmanRosterDeviceIDs = wingmanRosterDeviceIDs
        self.reserveRosterDeviceIDs = reserveRosterDeviceIDs
    }
}

// MARK: - OperatorPromptContextFact

/// One operator-readable fact attached to a prompt. Renders as a `(label, value)`
/// line with optional grouping and emphasis. The publisher composes a list of
/// these to give the operator the data they need to decide.
///
/// Example for swap-in-reserve:
/// ```
/// [
///   OperatorPromptContextFact(label: "Mission run", value: "Hawkeye-3", group: "Where"),
///   OperatorPromptContextFact(label: "Task", value: "Sweep South", group: "Where"),
///   OperatorPromptContextFact(label: "Primary slot", value: "Alpha-1 (Skywarden α)", group: "Where"),
///   OperatorPromptContextFact(label: "Primary battery", value: "8% (critical)", emphasis: .error, group: "State"),
///   OperatorPromptContextFact(label: "Reserve readiness", value: "Preflight passed 2 min ago", emphasis: .success, group: "State"),
///   OperatorPromptContextFact(label: "Expected impact", value: "+45 sec, no task miss", group: "Impact"),
/// ]
/// ```
struct OperatorPromptContextFact: Equatable, Hashable, Sendable, Codable {

    /// Short label shown beside the value (e.g. "Primary battery").
    let label: String

    /// The displayable value (e.g. "8% (critical)"). Always operator-readable;
    /// never a raw id or machine token — those belong on ``OperatorPromptTarget``.
    let value: String

    /// Severity / tone of this fact. Drives text colour (or chip background)
    /// in the generic renderer. Defaults to `.normal`.
    let emphasis: OperatorPromptContextFactEmphasis

    /// Optional SF Symbol name to render alongside the value. The renderer
    /// applies it with the emphasis-derived tint.
    let icon: String?

    /// Optional grouping label so the renderer can section facts visually
    /// (e.g. "Where", "State", "Impact"). When nil the fact renders in the
    /// default ungrouped section.
    let group: String?

    init(
        label: String,
        value: String,
        emphasis: OperatorPromptContextFactEmphasis = .normal,
        icon: String? = nil,
        group: String? = nil
    ) {
        self.label = label
        self.value = value
        self.emphasis = emphasis
        self.icon = icon
        self.group = group
    }
}

// MARK: - OperatorPromptContextFactEmphasis

/// Emphasis level for an ``OperatorPromptContextFact``. Drives colour and icon
/// tint in the generic renderer, and (later) the audit log's text style.
enum OperatorPromptContextFactEmphasis: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    /// Plain text. Default for descriptive facts.
    case normal
    /// Muted / secondary text. Use for low-importance context.
    case caption
    /// Green — successful / healthy / ready states.
    case success
    /// Orange — caution / approaching limit.
    case warning
    /// Red — critical / failure / over-limit.
    case error
}

// MARK: - OperatorPromptOption

/// A labelled choice presented to the operator. Each option carries a stable id
/// (so the publisher can branch deterministically on which choice was picked), a
/// human label, a UI role (driving button colour per workspace semantic-color
/// rule), an underlying ``FleetRecipeResumptionVerb`` (the closed transport every
/// resolution flows through), an optional per-option `summary` line that tells
/// the operator the consequence of picking this choice, and an optional payload
/// of typed extra data.
struct OperatorPromptOption: Identifiable, Equatable, Sendable {

    /// Stable identifier. Publisher-defined and never localised. Branching on
    /// this is the contract — the human label is presentation-only and may be
    /// translated or reworded freely.
    let id: String

    /// Localised display text shown on the button.
    let humanLabel: String

    /// Optional one-line description of what this option does, surfaced under
    /// the button text so the operator can see the consequence of the choice
    /// before committing. Use for non-obvious effects (e.g. "Land Alpha-1 at
    /// home, deploy R-2 immediately"). Nil for trivial yes/no.
    let summary: String?

    /// Semantic role — blue for `.confirm`, red for `.cancel`, default for
    /// `.neutral`. Wires into the workspace's app-wide button-color rule.
    let role: OperatorPromptOptionRole

    /// Underlying resumption verb consumed by the recipe runner (and by any other
    /// process that branches on the closed verb set).
    let verb: FleetRecipeResumptionVerb

    /// Optional typed payload the publisher attaches for branching beyond the
    /// option id (e.g. retry-after delay, target-coordinate, swap-target id).
    let payload: [String: OperatorPromptOptionPayloadValue]?

    init(
        id: String,
        humanLabel: String,
        summary: String? = nil,
        role: OperatorPromptOptionRole,
        verb: FleetRecipeResumptionVerb,
        payload: [String: OperatorPromptOptionPayloadValue]? = nil
    ) {
        self.id = id
        self.humanLabel = humanLabel
        self.summary = summary
        self.role = role
        self.verb = verb
        self.payload = payload
    }
}

// MARK: - OperatorPromptOptionRole

/// Semantic role used to colour the option's button per the app-wide button-color
/// rule (`.confirm` blue, `.cancel` red, `.neutral` default).
enum OperatorPromptOptionRole: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    case confirm
    case neutral
    case cancel
}

// MARK: - OperatorPromptOptionPayloadValue

/// Typed payload value attached to an ``OperatorPromptOption``. Closed v1 set
/// (string / integer / double / bool) — same shape as ``FleetCommandResponsePayload``
/// scalars so payload values can round-trip between recipe responses and prompt
/// option payloads without lossy conversion.
enum OperatorPromptOptionPayloadValue: Equatable, Hashable, Sendable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
}

// MARK: - OperatorPromptAnswer

/// The resolved answer produced when the operator picks an option, when the
/// publisher consults a remembered choice from `OperatorDecisionCache`, or when
/// the prompt times out.
///
/// The runner consumes only `verb`; the publisher consumes `selectedOptionID`
/// for source-specific branching; the prompt log consumes the whole record for
/// audit and (later) the RoE learner.
struct OperatorPromptAnswer: Equatable, Sendable {

    /// The prompt this answer resolves.
    let promptID: UUID

    /// Identifier of the option the operator chose. Matches an entry in
    /// ``OperatorPromptEvent/effectiveOptions``. For timeouts where no option
    /// is preserved, see ``OperatorPromptOption/timeoutOptionID``.
    let selectedOptionID: String

    /// Closed transport verb — the recipe runner (and any other verb-driven
    /// consumer) reads this and ignores the rest.
    let verb: FleetRecipeResumptionVerb

    /// `true` when the operator ticked "remember this choice". Consumed by the
    /// publisher's `OperatorDecisionCache` to short-circuit future prompts with
    /// the same `policyKey` for the lifetime of the current run / session.
    let remember: Bool

    /// Why this answer landed — operator-chose vs cache-hit vs timeout.
    let resolution: OperatorPromptResolutionSource

    /// When the answer was produced.
    let answeredAt: Date

    init(
        promptID: UUID,
        selectedOptionID: String,
        verb: FleetRecipeResumptionVerb,
        remember: Bool,
        resolution: OperatorPromptResolutionSource,
        answeredAt: Date = Date()
    ) {
        self.promptID = promptID
        self.selectedOptionID = selectedOptionID
        self.verb = verb
        self.remember = remember
        self.resolution = resolution
        self.answeredAt = answeredAt
    }
}

// MARK: - OperatorPromptResolutionSource

/// Why a prompt's answer was produced. The audit log (and the eventual RoE
/// learner) consults this to weight remembered choices appropriately — a
/// timeout-aborted decision is not training data, a cache-hit is a replay of a
/// previous decision (already trained), and an operator choice is the live
/// signal.
enum OperatorPromptResolutionSource: String, Equatable, Hashable, Sendable, Codable, CaseIterable {

    /// The operator clicked an option in a delivery channel.
    case operatorChose

    /// The publisher consulted `OperatorDecisionCache` for the prompt's
    /// `policyKey` and short-circuited without ever publishing UI.
    case rememberedFromCache

    /// The prompt was published but no operator input arrived before
    /// ``OperatorPromptEvent/expiresAt``. Router synthesised an abort answer
    /// (or the first ``OperatorPromptEvent/allowedVerbs`` entry when `.abort` is
    /// not in the allowed set).
    case timeoutAborted
}

// MARK: - Standard option synthesis

extension OperatorPromptOption {

    /// Sentinel id used on synthesised options so callers can distinguish
    /// publisher-supplied option ids from defaults.
    static func standardID(for verb: FleetRecipeResumptionVerb) -> String {
        "verb.\(verb.rawValue)"
    }

    /// Sentinel id used on the synthesised "timeout" answer when the prompt
    /// expires without an operator choice.
    static let timeoutOptionID: String = "verb.timeout"

    /// Standard "Acknowledge" option — `.confirm` role + ``FleetRecipeResumptionVerb/acknowledge``.
    static func standardAcknowledge(label: String = "Acknowledge", summary: String? = nil) -> OperatorPromptOption {
        OperatorPromptOption(
            id: standardID(for: .acknowledge),
            humanLabel: label,
            summary: summary,
            role: .confirm,
            verb: .acknowledge
        )
    }

    /// Standard "Retry" option — `.neutral` role + ``FleetRecipeResumptionVerb/retry``.
    static func standardRetry(label: String = "Retry", summary: String? = nil) -> OperatorPromptOption {
        OperatorPromptOption(
            id: standardID(for: .retry),
            humanLabel: label,
            summary: summary,
            role: .neutral,
            verb: .retry
        )
    }

    /// Standard "Skip" option — `.neutral` role + ``FleetRecipeResumptionVerb/skip``.
    static func standardSkip(label: String = "Skip", summary: String? = nil) -> OperatorPromptOption {
        OperatorPromptOption(
            id: standardID(for: .skip),
            humanLabel: label,
            summary: summary,
            role: .neutral,
            verb: .skip
        )
    }

    /// Standard "Abort" option — `.cancel` role + ``FleetRecipeResumptionVerb/abort``.
    static func standardAbort(label: String = "Abort", summary: String? = nil) -> OperatorPromptOption {
        OperatorPromptOption(
            id: standardID(for: .abort),
            humanLabel: label,
            summary: summary,
            role: .cancel,
            verb: .abort
        )
    }

    /// Synthesises a default option list from `allowedVerbs`. Used whenever a
    /// publisher does not author its own custom options — keeps the closed
    /// resumption verb contract intact while still rendering operator-readable
    /// buttons with the right semantic colours.
    ///
    /// Ordering is fixed (confirm-first → neutrals → cancel) so identical prompt
    /// shapes always render their buttons in the same order across delivery
    /// channels.
    static func standardOptions(forAllowedVerbs verbs: [FleetRecipeResumptionVerb]) -> [OperatorPromptOption] {
        let unique = Set(verbs)
        let ordering: [FleetRecipeResumptionVerb] = [.acknowledge, .retry, .skip, .abort]
        return ordering.compactMap { verb in
            guard unique.contains(verb) else { return nil }
            switch verb {
            case .acknowledge: return .standardAcknowledge()
            case .retry: return .standardRetry()
            case .skip: return .standardSkip()
            case .abort: return .standardAbort()
            }
        }
    }
}

// MARK: - Recipe-escalation construction helper

extension OperatorPromptEvent {

    /// Lift a recipe-runner escalation event into a prompt event with default
    /// title / body / severity derived from the reason, plus an auto-populated
    /// ``OperatorPromptTarget`` carrying the recipe run id and the vehicle id
    /// the recipe is targeting.
    ///
    /// The runner's `FleetRecipeEscalationHandler` calls into the prompt center
    /// with this constructor (Stage D wiring) so a recipe escalation becomes an
    /// operator prompt without losing any of the escalation contract data — the
    /// wrapped `FleetRecipeEscalationEvent` is preserved on the origin so the UI
    /// can render the step path, the last response, and the reason kind without
    /// re-discovering them.
    ///
    /// **Mission context.** The recipe runner itself doesn't know about
    /// missions, so `target` only auto-fills `recipeRunID` + `affectedVehicleID`.
    /// Callers that *do* know the recipe is running inside a mission task (Stage
    /// E wizard, MRE, plugin) supply the rest by passing an explicit `target`
    /// override. Passing a non-nil `target` replaces the auto-populated one in
    /// full — merge on the caller side if you want a partial override.
    ///
    /// **Context facts.** Two facts are auto-attached for every recipe
    /// escalation so the operator always sees what's escalating:
    /// `Recipe` (the top-level recipe name) and `Step` (the escalating step id).
    /// Additional facts can be supplied via `contextFacts`; auto-attached facts
    /// always precede caller-supplied facts so the recipe context always renders
    /// first.
    ///
    /// Callers can supply explicit `title` / `body` / `severity` / `options` /
    /// `policyKey` to override the derived defaults when domain-specific
    /// phrasing matters.
    init(
        fromRecipeEscalation event: FleetRecipeEscalationEvent,
        target overrideTarget: OperatorPromptTarget? = nil,
        title overrideTitle: String? = nil,
        body overrideBody: String? = nil,
        severity overrideSeverity: GuardianFeedbackSeverity? = nil,
        contextFacts extraFacts: [OperatorPromptContextFact] = [],
        options: [OperatorPromptOption]? = nil,
        policyKey: String? = nil,
        createdAt: Date = Date(),
        timeout: TimeInterval = OperatorPromptEvent.defaultTimeout
    ) {
        let derived = OperatorPromptEvent.defaultsFor(reason: event.reason)
        let derivedTarget = OperatorPromptTarget(
            affectedVehicleID: event.vehicleID,
            recipeRunID: event.runID
        )
        let recipeFacts: [OperatorPromptContextFact] = [
            OperatorPromptContextFact(
                label: "Recipe",
                value: event.recipe.rawValue,
                emphasis: .normal,
                group: "Recipe"
            ),
            OperatorPromptContextFact(
                label: "Step",
                value: event.stepID.rawValue,
                emphasis: .normal,
                group: "Recipe"
            ),
        ]
        self.init(
            origin: .recipeEscalation(event: event),
            target: overrideTarget ?? derivedTarget,
            severity: overrideSeverity ?? derived.severity,
            title: overrideTitle ?? derived.title,
            body: overrideBody ?? derived.body,
            contextFacts: recipeFacts + extraFacts,
            options: options,
            allowedVerbs: event.allowedVerbs,
            policyKey: policyKey,
            createdAt: createdAt,
            timeout: timeout
        )
    }

    /// Default `(severity, title, body)` triple for a recipe escalation reason.
    /// Body is intentionally generic — the real UI surface (Stage E wizard, MCR
    /// panel) renders the step + last response on its own; the body here is the
    /// drawer-row / OOA-notification fallback that has no other context.
    private static func defaultsFor(reason: FleetRecipeEscalationReason) -> (severity: GuardianFeedbackSeverity, title: String, body: String) {
        switch reason {
        case .operatorActionRequired(let kind):
            return (
                .warning,
                "Operator action required",
                "Recipe is waiting for: \(kind.rawValue)."
            )
        case .unrecoverableFailure(let kind):
            return (
                .error,
                "Recipe failed",
                "Reason: \(kind.rawValue)."
            )
        case .confirmation(let kind):
            return (
                .info,
                "Confirmation needed",
                "Recipe needs confirmation: \(kind.rawValue)."
            )
        }
    }
}
