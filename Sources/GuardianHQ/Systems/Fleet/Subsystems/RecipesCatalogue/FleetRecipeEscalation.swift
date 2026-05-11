import Foundation

// MARK: - Resumption verbs (closed)

/// Verbs the operator (or upstream process) may use to resume a recipe that has
/// escalated. Locked closed set per Stage B item 5.
///
/// The runner only respects verbs that the escalating matcher declared
/// (`allowedVerbs:`) — a matcher that allows only `[.acknowledge, .abort]` cannot
/// be resumed with `.retry`, even if the operator UI exposes the button.
enum FleetRecipeResumptionVerb: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    /// Operator saw the escalation and confirmed they understand. Recipe proceeds
    /// to the next step as if the escalating matcher had `.continueToNextStep`.
    case acknowledge
    /// Re-execute the escalating step from scratch (subject to its retry policy).
    case retry
    /// Skip the escalating step entirely and proceed to the next.
    case skip
    /// Abort the recipe with a `failed(...)` outcome attributed to the escalating step.
    case abort
}

// MARK: - Reason kinds (extensible string-backed namespaces)

/// Operator-action kind requested by an `operatorActionRequired` escalation.
///
/// String-backed extensible namespace (`Notification.Name`-style) so plugins can
/// declare their own kinds without forcing a core enum change. The Stage D prompt
/// router maps these strings to UI affordances; the recipe runner is agnostic.
struct FleetRecipeOperatorActionKind: Hashable, Sendable, Codable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    // Curated v1 seed set. Stage C calibration recipes will draw from this list;
    // adding more kinds is a non-breaking change.
    static let rotateDrone = FleetRecipeOperatorActionKind(rawValue: "rotateDrone")
    static let holdStill = FleetRecipeOperatorActionKind(rawValue: "holdStill")
    static let placeOnLevelSurface = FleetRecipeOperatorActionKind(rawValue: "placeOnLevelSurface")
    static let pointNorth = FleetRecipeOperatorActionKind(rawValue: "pointNorth")
    static let connectExternalSensor = FleetRecipeOperatorActionKind(rawValue: "connectExternalSensor")
    static let removeMagneticInterference = FleetRecipeOperatorActionKind(rawValue: "removeMagneticInterference")
    static let restartVehicle = FleetRecipeOperatorActionKind(rawValue: "restartVehicle")
    static let moveOutdoors = FleetRecipeOperatorActionKind(rawValue: "moveOutdoors")
}

/// Unrecoverable-failure kind reported by an `unrecoverableFailure` escalation.
/// Same string-backed extensibility pattern.
struct FleetRecipeUnrecoverableFailureKind: Hashable, Sendable, Codable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    static let calibrationDidNotConverge = FleetRecipeUnrecoverableFailureKind(rawValue: "calibrationDidNotConverge")
    static let preflightHardFailure = FleetRecipeUnrecoverableFailureKind(rawValue: "preflightHardFailure")
    static let vehicleOffline = FleetRecipeUnrecoverableFailureKind(rawValue: "vehicleOffline")
    static let persistentAutopilotError = FleetRecipeUnrecoverableFailureKind(rawValue: "persistentAutopilotError")
    static let configurationMismatch = FleetRecipeUnrecoverableFailureKind(rawValue: "configurationMismatch")
}

/// Confirmation-prompt kind reported by a `confirmation` escalation.
/// Same string-backed extensibility pattern.
struct FleetRecipeConfirmationKind: Hashable, Sendable, Codable, RawRepresentable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    static let confirmGroundOnlyAction = FleetRecipeConfirmationKind(rawValue: "confirmGroundOnlyAction")
    static let confirmIrreversibleAction = FleetRecipeConfirmationKind(rawValue: "confirmIrreversibleAction")
    static let confirmInLiveMission = FleetRecipeConfirmationKind(rawValue: "confirmInLiveMission")
    static let confirmAcceptCalibrationResult = FleetRecipeConfirmationKind(rawValue: "confirmAcceptCalibrationResult")
}

// MARK: - Reason (closed top-level shape, extensible per-kind)

/// Why the recipe is escalating. Top-level shape is closed (the three cases below
/// match Stage B item 5 verbatim); the kinds inside each case are string-backed
/// and extensible so plugins can author new ones without core changes.
enum FleetRecipeEscalationReason: Equatable, Hashable, Sendable {
    /// Recipe needs the operator to do something physical (rotate the drone, etc.).
    case operatorActionRequired(kind: FleetRecipeOperatorActionKind)
    /// Recipe has hit a state it can't recover from on its own.
    case unrecoverableFailure(kind: FleetRecipeUnrecoverableFailureKind)
    /// Recipe needs explicit operator yes/no before proceeding.
    case confirmation(kind: FleetRecipeConfirmationKind)
}

// MARK: - Codable

extension FleetRecipeEscalationReason: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind
        case operatorKind
        case failureKind
        case confirmationKind
    }

    private enum Kind: String, Codable {
        case operatorActionRequired
        case unrecoverableFailure
        case confirmation
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .operatorActionRequired:
            self = .operatorActionRequired(kind: try c.decode(FleetRecipeOperatorActionKind.self, forKey: .operatorKind))
        case .unrecoverableFailure:
            self = .unrecoverableFailure(kind: try c.decode(FleetRecipeUnrecoverableFailureKind.self, forKey: .failureKind))
        case .confirmation:
            self = .confirmation(kind: try c.decode(FleetRecipeConfirmationKind.self, forKey: .confirmationKind))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .operatorActionRequired(let kind):
            try c.encode(Kind.operatorActionRequired, forKey: .kind)
            try c.encode(kind, forKey: .operatorKind)
        case .unrecoverableFailure(let kind):
            try c.encode(Kind.unrecoverableFailure, forKey: .kind)
            try c.encode(kind, forKey: .failureKind)
        case .confirmation(let kind):
            try c.encode(Kind.confirmation, forKey: .kind)
            try c.encode(kind, forKey: .confirmationKind)
        }
    }
}
