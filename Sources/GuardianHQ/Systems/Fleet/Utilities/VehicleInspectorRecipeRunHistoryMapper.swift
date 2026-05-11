import Foundation

/// Maps Vehicle Inspector catalogue recipe outcomes into ``SingleVehiclePreflightProbeResult`` (v1 outcome
/// envelope) so ``FleetLinkService/recordRecipeRun(vehicleID:source:kind:outcome:)`` can append with
/// ``RecipeRunHistoryKind/vehicleInspectorCatalogueRecipe`` to the unified ``FleetVehicleModel/Functions/recipeRunHistory`` ring.
enum VehicleInspectorRecipeRunHistoryMapper {

    /// Stable prefix for ``PreflightFailureRemediationAdvice/patternId`` on failed calibration runs;
    /// ``FleetCalibrationCollection`` maps `wizard.cal.<FleetCalibrationSystemID.rawValue>` to the canvas marker.
    static let wizardCalibrationFailurePatternPrefix = "wizard.cal."

    static func preflightShapedResult(
        outcome: FleetRecipeOutcome,
        recipeHumanLabel: String,
        calibrationSystemID: FleetCalibrationSystemID
    ) -> SingleVehiclePreflightProbeResult {
        switch outcome {
        case .succeeded(let detail, _, _):
            let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let body: String
            if trimmed.isEmpty {
                body = "\(recipeHumanLabel) finished."
            } else {
                body = trimmed
            }
            return SingleVehiclePreflightProbeResult(
                passed: true,
                armedDuringProbe: false,
                detail: body,
                remediationAdvice: nil
            )
        case .failed(_, _, let detail, _):
            let msg: String = {
                if let d = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { return d }
                return outcome.loggable
            }()
            let patternId = wizardCalibrationFailurePatternPrefix + calibrationSystemID.rawValue
            let advice = PreflightFailureRemediationAdvice(
                patternId: patternId,
                summary: "\(recipeHumanLabel) did not complete.",
                steps: [
                    "Read the failure detail on this vehicle card, fix any autopilot-side issue, then retry the procedure.",
                    "Use the remediation block below or the Fix recipes when the catalogue lists them for this system.",
                ]
            )
            return SingleVehiclePreflightProbeResult(
                passed: false,
                armedDuringProbe: false,
                detail: msg,
                remediationAdvice: advice
            )
        }
    }
}
