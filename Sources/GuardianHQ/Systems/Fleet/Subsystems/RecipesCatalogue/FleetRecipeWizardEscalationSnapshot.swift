import Foundation

/// Inline operator escalation for Stage E wizard chrome (Vehicle Inspector, future surfaces).
///
/// Built from ``FleetRecipeEscalationEvent`` so the UI can render human copy and
/// ``allowedVerbs`` without re-deriving from raw recipe DSL.
struct FleetRecipeWizardEscalationSnapshot: Equatable, Sendable {

    let runID: FleetRecipeRunID
    let stepID: FleetRecipeStepID
    let headline: String
    let detail: String
    let allowedVerbs: [FleetRecipeResumptionVerb]

    /// Tints the strip border / icon row alongside ``GuardianSemanticColors``.
    let feedbackSeverity: GuardianFeedbackSeverity

    static func from(event: FleetRecipeEscalationEvent) -> FleetRecipeWizardEscalationSnapshot {
        let copy = event.reason.wizardInlineCopy()
        return FleetRecipeWizardEscalationSnapshot(
            runID: event.runID,
            stepID: event.stepID,
            headline: copy.headline,
            detail: copy.detail,
            allowedVerbs: event.allowedVerbs,
            feedbackSeverity: copy.severity
        )
    }
}

extension FleetRecipeEscalationReason {

    /// Operator-facing headline, supporting detail, and severity for compact inline banners.
    func wizardInlineCopy() -> (headline: String, detail: String, severity: GuardianFeedbackSeverity) {
        switch self {
        case .operatorActionRequired(let kind):
            return (Self.headline(for: kind), Self.detail(for: kind), .warning)
        case .unrecoverableFailure(let kind):
            return (
                "Cannot continue",
                "Reason: \(Self.displayName(forUnrecoverable: kind)).",
                .error
            )
        case .confirmation(let kind):
            return (
                "Confirmation needed",
                Self.detail(for: kind),
                .info
            )
        }
    }

    private static func headline(for kind: FleetRecipeOperatorActionKind) -> String {
        if kind == .rotateDrone { return "Rotate the vehicle" }
        if kind == .holdStill { return "Hold still" }
        if kind == .placeOnLevelSurface { return "Place on a level surface" }
        if kind == .pointNorth { return "Point north" }
        if kind == .connectExternalSensor { return "Connect external sensor" }
        if kind == .removeMagneticInterference { return "Reduce magnetic interference" }
        if kind == .restartVehicle { return "Restart the vehicle" }
        if kind == .moveOutdoors { return "Move outdoors" }
        return "Operator action required"
    }

    private static func detail(for kind: FleetRecipeOperatorActionKind) -> String {
        if kind == .rotateDrone {
            return "Slowly rotate the vehicle on each axis as the procedure indicates, then choose how to continue."
        }
        if kind == .holdStill {
            return "Keep the vehicle steady until the step finishes, then choose how to continue."
        }
        if kind == .placeOnLevelSurface {
            return "Set the vehicle on a level surface before continuing."
        }
        if kind == .pointNorth {
            return "Orient the vehicle so the front faces north, then continue."
        }
        if kind == .connectExternalSensor {
            return "Attach or power the external sensor the procedure expects, then continue."
        }
        if kind == .removeMagneticInterference {
            return "Move away from metal, magnets, or strong currents, then continue."
        }
        if kind == .restartVehicle {
            return "Power-cycle the vehicle if it is safe to do so, then continue."
        }
        if kind == .moveOutdoors {
            return "Move to an open outdoor area with good sky view, then continue."
        }
        return "The recipe is waiting for action: \(kind.rawValue)."
    }

    private static func detail(for kind: FleetRecipeConfirmationKind) -> String {
        if kind == .confirmGroundOnlyAction {
            return "Confirm this ground-only action before the recipe continues."
        }
        if kind == .confirmIrreversibleAction {
            return "Confirm this irreversible action before the recipe continues."
        }
        if kind == .confirmInLiveMission {
            return "Confirm you want to proceed while this vehicle is in a live mission."
        }
        if kind == .confirmAcceptCalibrationResult {
            return "Confirm you accept the calibration result before the recipe continues."
        }
        return "Confirmation: \(kind.rawValue)."
    }

    private static func displayName(forUnrecoverable kind: FleetRecipeUnrecoverableFailureKind) -> String {
        if kind == .calibrationDidNotConverge { return "calibration did not converge" }
        if kind == .preflightHardFailure { return "preflight hard failure" }
        if kind == .vehicleOffline { return "vehicle offline" }
        if kind == .persistentAutopilotError { return "persistent autopilot error" }
        if kind == .configurationMismatch { return "configuration mismatch" }
        return kind.rawValue
    }
}

extension FleetRecipeResumptionVerb {

    /// Short label for inline wizard buttons (aligned with ``OperatorPromptOption`` defaults).
    var wizardButtonTitle: String {
        switch self {
        case .acknowledge: return "Acknowledge"
        case .retry: return "Retry"
        case .skip: return "Skip"
        case .abort: return "Abort"
        }
    }
}
