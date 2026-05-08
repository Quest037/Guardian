import Foundation

enum PaladinFleetPreflightBridge {
    /// Maps existing Fleet preflight probe output into Paladin normalized readiness.
    @MainActor
    static func readinessFromPreflightProbe(
        vehicleID: String,
        probe: SingleVehiclePreflightProbeResult,
        calibrationStatus: PaladinCalibrationStatus = .unknown
    ) -> PaladinFleetVehicleReadiness {
        if probe.passed {
            return PaladinFleetVehicleReadiness(
                id: vehicleID,
                healthStatus: calibrationStatus == .failed ? .amber : .green,
                preflightStatus: .passed,
                calibrationStatus: calibrationStatus,
                autonomyEligibility: calibrationStatus == .failed ? .eligibleWithRisk : .eligible,
                blockers: [],
                remediationAdvice: nil
            )
        }

        let blockerCode = probe.remediationAdvice?.patternId ?? "preflight.probe_failed"
        let blocker = PaladinFleetReadinessBlocker(code: blockerCode, detail: probe.detail)
        return PaladinFleetVehicleReadiness(
            id: vehicleID,
            healthStatus: .red,
            preflightStatus: .failed,
            calibrationStatus: calibrationStatus,
            autonomyEligibility: .ineligible,
            blockers: [blocker],
            remediationAdvice: probe.remediationAdvice
        )
    }
}
