import Foundation

enum PaladinVehicleHealthStatus: String, Equatable {
    case green
    case amber
    case red
    case unknown
}

enum PaladinPreflightStatus: String, Equatable {
    case notRun
    case running
    case passed
    case failed
}

enum PaladinCalibrationStatus: String, Equatable {
    case unknown
    case required
    case inProgress
    case passed
    case failed
}

enum PaladinAutonomyEligibility: String, Equatable {
    case eligible
    case eligibleWithRisk
    case ineligible
}

struct PaladinFleetReadinessBlocker: Equatable, Identifiable {
    let id: UUID
    let code: String
    let detail: String

    init(id: UUID = UUID(), code: String, detail: String) {
        self.id = id
        self.code = code
        self.detail = detail
    }
}

struct PaladinFleetVehicleReadiness: Equatable, Identifiable {
    let id: String
    var healthStatus: PaladinVehicleHealthStatus
    var preflightStatus: PaladinPreflightStatus
    var calibrationStatus: PaladinCalibrationStatus
    var autonomyEligibility: PaladinAutonomyEligibility
    var blockers: [PaladinFleetReadinessBlocker]
    var remediationAdvice: PreflightFailureRemediationAdvice?
    var lastUpdatedAt: Date

    init(
        id: String,
        healthStatus: PaladinVehicleHealthStatus = .unknown,
        preflightStatus: PaladinPreflightStatus = .notRun,
        calibrationStatus: PaladinCalibrationStatus = .unknown,
        autonomyEligibility: PaladinAutonomyEligibility = .ineligible,
        blockers: [PaladinFleetReadinessBlocker] = [],
        remediationAdvice: PreflightFailureRemediationAdvice? = nil,
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.healthStatus = healthStatus
        self.preflightStatus = preflightStatus
        self.calibrationStatus = calibrationStatus
        self.autonomyEligibility = autonomyEligibility
        self.blockers = blockers
        self.remediationAdvice = remediationAdvice
        self.lastUpdatedAt = lastUpdatedAt
    }
}
