import Foundation

// MARK: - Recipe outcome → preflight UI

/// Maps ``FleetRecipeRunner`` outcomes for diagnose arm recipes into
/// ``SingleVehiclePreflightProbeResult`` (legacy preflight probe shape).
enum MissionControlPreflightRecipeOutcomeMapper {

    private static let armStepID = FleetRecipeStepID.literal("arm")
    private static let disarmStepID = FleetRecipeStepID.literal("disarm")

    static func singleVehiclePreflightProbeResult(
        recipeOutcome: FleetRecipeOutcome,
        hub: FleetHubVehicleTelemetry?,
        isSimulation: Bool
    ) -> SingleVehiclePreflightProbeResult {
        switch recipeOutcome {
        case .succeeded(_, _, let trace):
            return SingleVehiclePreflightProbeResult(
                passed: true,
                armedDuringProbe: armedDuringSuccessfulProbe(trace: trace),
                detail: "Arm succeeded.",
                remediationAdvice: nil
            )
        case .failed(let path, let lastResponse, let detail, _):
            let raw = rawFailureDetailForAdvisor(
                recipeDetail: detail,
                lastResponse: lastResponse
            )
            let advice = PreflightFailureAdvisor.advice(
                for: PreflightFailureRemediationContext(
                    autopilotStack: hub?.autopilotStack ?? .unknown,
                    rawFailureDetail: raw,
                    hubSnapshot: hub,
                    isSimulation: isSimulation
                )
            )
            let uiDetail = operatorFacingProbeFailureDetail(
                failingCommandPath: path,
                recipeDetail: detail,
                lastResponse: lastResponse,
                hub: hub
            )
            return SingleVehiclePreflightProbeResult(
                passed: false,
                armedDuringProbe: false,
                detail: uiDetail,
                remediationAdvice: advice
            )
        }
    }

    /// After a **succeeded** arm (or arm-hold) recipe run, whether the arm step
    /// actually transitioned to armed (`alreadyArmed` counts as false).
    static func armedDuringSuccessfulProbe(trace: FleetRecipeAuditTrace) -> Bool {
        guard let armEntry = trace.entries.first(where: { $0.stepID == armStepID }) else {
            return false
        }
        switch armEntry.response.outcome {
        case .succeeded:
            return true
        case .error(let kind) where kind == .alreadyArmed:
            return false
        case .error, .cancelled, .timeout:
            return false
        }
    }

    static func rawFailureDetailForAdvisor(
        recipeDetail: String?,
        lastResponse: FleetCommandResponse?
    ) -> String {
        if let d = recipeDetail?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            return d
        }
        if let lr = lastResponse {
            switch lr.outcome {
            case .succeeded:
                return "Recipe reported failure after a successful command outcome (unexpected)."
            case .error(let kind):
                return lr.detail ?? "Error: \(kind.rawValue)"
            case .cancelled:
                return lr.detail ?? "Command cancelled."
            case .timeout:
                return lr.detail ?? "Command timed out."
            }
        }
        return "Preflight recipe failed."
    }

    static func operatorFacingProbeFailureDetail(
        failingCommandPath: [FleetRecipeStepID],
        recipeDetail: String?,
        lastResponse: FleetCommandResponse?,
        hub: FleetHubVehicleTelemetry?
    ) -> String {
        if failingCommandPath.contains(disarmStepID) {
            if let d = recipeDetail?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                return d
            }
            return "Disarm step failed during preflight."
        }
        let raw = rawFailureDetailForAdvisor(recipeDetail: recipeDetail, lastResponse: lastResponse)
        return preflightArmFailureDetail(hub: hub, reason: raw)
    }

    static func preflightArmFailureDetail(hub: FleetHubVehicleTelemetry?, reason: String) -> String {
        if hub?.healthArmable == false {
            return "Arm failed: \(reason) (telemetry: not armable — resolve pre-arm / health on the vehicle.)"
        }
        if hub?.healthArmable == nil {
            return "Arm failed: \(reason) (armable health not yet reported — check link and autopilot messages.)"
        }
        return "Arm failed: \(reason)"
    }
}
