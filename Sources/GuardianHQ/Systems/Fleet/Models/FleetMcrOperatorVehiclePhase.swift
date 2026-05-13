import Foundation

/// Mission Control live roster triage hint for a fleet vehicle (keyed by ``FleetLinkService`` vehicle id).
enum FleetMcrOperatorVehiclePhase: Equatable, Sendable {
    case unknown
    /// Armed and hub telemetry suggests the vehicle is executing a loaded mission.
    case onMission
    /// PX4 UGV **Park** finished via the offboard zero-velocity path; operator may run **Continue mission**.
    case operatorParkAwaitingContinue

    /// Short operator copy for Mission Control assignment triage (badge).
    var missionControlAssignmentTriageBadgeTitle: String {
        switch self {
        case .unknown:
            return "Standby"
        case .onMission:
            return "On mission"
        case .operatorParkAwaitingContinue:
            return "Parked — continue available"
        }
    }
}
